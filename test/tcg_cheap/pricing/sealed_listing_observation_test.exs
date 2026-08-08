defmodule TcgCheap.Pricing.SealedListingObservationTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Repo

  defp shop do
    Core.register_retailer!(%{
      slug: "observation-shop-#{System.unique_integer([:positive])}",
      source_key: "observation-source-#{System.unique_integer([:positive])}",
      name: "Observation Shop",
      category: "regular_retailer"
    })
  end

  defp attrs(retailer_id, overrides) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Map.merge(
      %{
        retailer_id: retailer_id,
        source_listing_id: "observation-listing-#{System.unique_integer([:positive])}",
        source_title: "  Booster   Box ",
        direct_url: "https://shop.example/items/1",
        gtin: "4006381333931",
        current_price_pln: Decimal.new("12.50"),
        currency: "PLN",
        stock_status: "in_stock",
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now,
        source_payload: %{provider: "fixture"}
      },
      overrides
    )
  end

  defp ingest(retailer_id, overrides \\ %{}) do
    Core.ingest_retailer_listing!(attrs(retailer_id, overrides))
  end

  defp later(time, seconds), do: DateTime.add(time, seconds, :second)

  defp observation_attrs(listing, overrides) do
    Map.merge(
      %{
        retailer_listing_id: listing.id,
        source_title: "Title",
        normalized_title: "title",
        direct_url: "https://shop.example/item",
        gtin: "4006381333931",
        price_pln: Decimal.new("1.00"),
        currency: "PLN",
        stock_status: "in_stock",
        observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        source_payload: %{fixture: true}
      },
      overrides
    )
  end

  test "first observation, latest and ordered history are exposed" do
    retailer = shop()
    listing = ingest(retailer.id)

    assert [observation] = Core.list_sealed_listing_observation_history!(listing.id)
    assert observation.source_title == "Booster   Box"
    assert observation.normalized_title == "booster box"
    assert {:ok, latest} = Core.get_latest_sealed_listing_observation(listing.id)
    assert latest.id == observation.id
  end

  test "unchanged content deduplicates while check times advance and Decimal scale is ignored" do
    retailer = shop()
    listing = ingest(retailer.id)
    checked = later(listing.last_checked_at, 1)

    ingest(retailer.id, %{
      source_listing_id: listing.source_listing_id,
      current_price_pln: Decimal.new("12.500"),
      first_seen_at: listing.first_seen_at,
      last_seen_at: checked,
      last_checked_at: checked
    })

    projection = Core.get_retailer_listing!(retailer.id, listing.source_listing_id)
    assert projection.last_checked_at == checked
    assert length(Core.list_sealed_listing_observation_history!(listing.id)) == 1
  end

  test "price, metadata, payload and stock transitions append observations" do
    retailer = shop()
    listing = ingest(retailer.id)
    t1 = later(listing.last_checked_at, 1)

    ingest(retailer.id, %{
      source_listing_id: listing.source_listing_id,
      source_title: "Different Box",
      direct_url: "https://shop.example/items/2",
      gtin: nil,
      current_price_pln: Decimal.new("13.00"),
      source_payload: %{provider: "changed"},
      first_seen_at: listing.first_seen_at,
      last_seen_at: t1,
      last_checked_at: t1
    })

    sold_out_at = later(t1, 1)

    ingest(retailer.id, %{
      source_listing_id: listing.source_listing_id,
      stock_status: "sold_out",
      current_price_pln: nil,
      first_seen_at: listing.first_seen_at,
      last_seen_at: sold_out_at,
      last_checked_at: sold_out_at
    })

    in_stock_at = later(sold_out_at, 1)

    ingest(retailer.id, %{
      source_listing_id: listing.source_listing_id,
      stock_status: "in_stock",
      current_price_pln: Decimal.new("13.00"),
      first_seen_at: listing.first_seen_at,
      last_seen_at: in_stock_at,
      last_checked_at: in_stock_at
    })

    history = Core.list_sealed_listing_observation_history!(listing.id)

    assert Enum.map(history, & &1.stock_status) == [
             "in_stock",
             "in_stock",
             "sold_out",
             "in_stock"
           ]

    assert Enum.at(history, 1).source_title == "Different Box"
    assert Enum.at(history, 1).normalized_title == "different box"
    assert Enum.at(history, 1).gtin == nil
    assert Enum.at(history, 1).source_payload == %{"provider" => "changed"}
    assert Enum.at(history, 2).price_pln == nil
  end

  test "stale and invalid ingests preserve the projection and observation history" do
    retailer = shop()

    listing =
      ingest(retailer.id, %{
        first_seen_at: DateTime.add(DateTime.utc_now(), -10, :second)
      })

    before = Core.get_retailer_listing!(retailer.id, listing.source_listing_id)
    history_before = Core.list_sealed_listing_observation_history!(listing.id)
    stale = DateTime.add(before.last_checked_at, -1, :second)

    ingest(retailer.id, %{
      source_listing_id: listing.source_listing_id,
      source_title: "Stale Change",
      current_price_pln: Decimal.new("99"),
      first_seen_at: before.first_seen_at,
      last_seen_at: stale,
      last_checked_at: stale
    })

    assert Core.get_retailer_listing!(retailer.id, listing.source_listing_id) == before
    assert Core.list_sealed_listing_observation_history!(listing.id) == history_before

    assert_raise Ash.Error.Invalid, fn ->
      ingest(retailer.id, %{
        source_listing_id: listing.source_listing_id,
        direct_url: "http://invalid.example",
        first_seen_at: before.first_seen_at,
        last_seen_at: later(before.last_seen_at, 1),
        last_checked_at: later(before.last_checked_at, 1)
      })
    end

    assert Core.get_retailer_listing!(retailer.id, listing.source_listing_id) == before
    assert Core.list_sealed_listing_observation_history!(listing.id) == history_before
  end

  test "changed content at the same observed timestamp rolls back the ingest" do
    retailer = shop()
    listing = ingest(retailer.id)
    before = Core.get_retailer_listing!(retailer.id, listing.source_listing_id)
    history_before = Core.list_sealed_listing_observation_history!(listing.id)

    assert_raise Ash.Error.Invalid, fn ->
      ingest(retailer.id, %{
        source_listing_id: listing.source_listing_id,
        source_title: "Same Time Change",
        current_price_pln: Decimal.new("99"),
        first_seen_at: before.first_seen_at,
        last_seen_at: before.last_seen_at,
        last_checked_at: before.last_checked_at
      })
    end

    assert Core.get_retailer_listing!(retailer.id, listing.source_listing_id) == before
    assert Core.list_sealed_listing_observation_history!(listing.id) == history_before
  end

  test "direct observation preserves trimmed title and validates its normalized identity" do
    retailer = shop()
    listing = ingest(retailer.id)

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{source_title: "Title", normalized_title: "wrong"})
      )
    end

    observation =
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{source_title: "  Title "})
      )

    assert observation.source_title == "Title"
  end

  test "direct observation rejects malformed HTTPS URLs" do
    listing = ingest(shop().id)

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{direct_url: "http://invalid.example"})
      )
    end
  end

  test "direct observation rejects blank normalized titles" do
    listing = ingest(shop().id)

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{normalized_title: "  "})
      )
    end
  end

  test "direct observation rejects invalid GTINs" do
    listing = ingest(shop().id)

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{gtin: "4006381333932"})
      )
    end
  end

  test "direct observation rejects invalid stock and currency" do
    listing = ingest(shop().id)

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{stock_status: "maybe"})
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(observation_attrs(listing, %{currency: "EUR"}))
    end
  end

  test "direct observation rejects invalid prices independently" do
    listing = ingest(shop().id)

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(observation_attrs(listing, %{price_pln: nil}))
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{stock_status: "sold_out", price_pln: Decimal.new("0")})
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{stock_status: "unknown", price_pln: "NaN"})
      )
    end

    assert_raise Ash.Error.Invalid, fn ->
      Core.record_sealed_listing_observation!(
        observation_attrs(listing, %{stock_status: "unknown", price_pln: "Infinity"})
      )
    end
  end

  test "database constraint rejects malformed observation URL" do
    listing = ingest(shop().id)
    id = Ecto.UUID.dump!(listing.id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:error,
            %Postgrex.Error{
              postgres: %{
                code: :check_violation,
                constraint: "sealed_listing_observations_identity_invariant"
              }
            }} =
             Repo.query(
               "INSERT INTO sealed_listing_observations (id, source_title, normalized_title, direct_url, price_pln, currency, stock_status, observed_at, retailer_listing_id) VALUES ($1, $2, $3, 'http://invalid.example', 1, 'PLN', 'in_stock', $4, $5)",
               [Ecto.UUID.dump!(Ecto.UUID.generate()), "Title", "title", now, id]
             )
  end

  test "database constraint rejects in-stock observation without price" do
    listing = ingest(shop().id)
    id = Ecto.UUID.dump!(listing.id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:error,
            %Postgrex.Error{
              postgres: %{
                code: :check_violation,
                constraint: "sealed_listing_observations_stock_price_invariant"
              }
            }} =
             Repo.query(
               "INSERT INTO sealed_listing_observations (id, source_title, normalized_title, direct_url, price_pln, currency, stock_status, observed_at, retailer_listing_id) VALUES ($1, $2, $3, $4, NULL, 'PLN', 'in_stock', $5, $6)",
               [
                 Ecto.UUID.dump!(Ecto.UUID.generate()),
                 "Title",
                 "title",
                 "https://shop.example/item",
                 now,
                 id
               ]
             )
  end

  test "database constraint rejects nonfinite observation price" do
    listing = ingest(shop().id)
    id = Ecto.UUID.dump!(listing.id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:error,
            %Postgrex.Error{
              postgres: %{
                code: :check_violation,
                constraint: "sealed_listing_observations_price_finite_invariant"
              }
            }} =
             Repo.query(
               "INSERT INTO sealed_listing_observations (id, source_title, normalized_title, direct_url, price_pln, currency, stock_status, observed_at, retailer_listing_id) VALUES ($1, $2, $3, $4, 'NaN', 'PLN', 'unknown', $5, $6)",
               [
                 Ecto.UUID.dump!(Ecto.UUID.generate()),
                 "Title",
                 "title",
                 "https://shop.example/item",
                 now,
                 id
               ]
             )
  end

  test "database identity rejects duplicate listing observation timestamps" do
    listing = ingest(shop().id)
    id = Ecto.UUID.dump!(listing.id)
    duplicate_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    observed_at = listing.last_checked_at

    assert {:error,
            %Postgrex.Error{
              postgres: %{
                code: :unique_violation,
                constraint: "sealed_listing_observations_listing_observed_index"
              }
            }} =
             Repo.query(
               "INSERT INTO sealed_listing_observations (id, source_title, normalized_title, direct_url, price_pln, currency, stock_status, observed_at, retailer_listing_id) VALUES ($1, 'Title', 'title', 'https://shop.example/item', 1, 'PLN', 'in_stock', $2, $3)",
               [duplicate_id, observed_at, id]
             )
  end
end
