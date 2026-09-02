defmodule TcgCheap.Catalogue.SealedRetailerListingTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Catalogue.{SealedListingMatcher, SealedRetailerAdapter}
  alias TcgCheap.Core
  alias TcgCheap.Repo

  defp retailer_attrs(overrides) do
    Map.merge(
      %{
        slug: "retailer-#{System.unique_integer([:positive])}",
        source_key: "source-#{System.unique_integer([:positive])}",
        name: "Example Shop",
        category: "regular_retailer",
        homepage_url: "https://shop.example"
      },
      overrides
    )
  end

  defp retailer(overrides \\ %{}), do: Core.register_retailer!(retailer_attrs(overrides))

  defp listing_attrs(retailer_id, overrides \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Map.merge(
      %{
        retailer_id: retailer_id,
        source_listing_id: "listing-#{System.unique_integer([:positive])}",
        source_title: "  Booster   Box ",
        direct_url: "https://shop.example/items/1",
        gtin: "4006381333931",
        current_price_pln: Decimal.new("12.50"),
        stock_status: "in_stock",
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now
      },
      overrides
    )
  end

  defp listing(retailer_id, overrides \\ %{}),
    do: Core.ingest_retailer_listing!(listing_attrs(retailer_id, overrides))

  defp product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          slug: "product-#{System.unique_integer([:positive])}",
          name: "Example Sealed Product",
          product_type: "booster_box",
          officially_distributed: true,
          release_date: Date.utc_today(),
          description: "A complete sealed product.",
          contents: ["36 booster packs"],
          pack_count: 36,
          cards_per_pack: 10,
          official_url: "https://example.com/product",
          details_source: "Publisher",
          details_source_url: "https://example.com/details",
          image_url: "https://assets.pokemon.com/image.jpg",
          image_source: "Publisher",
          image_source_url: "https://example.com/image-source"
        },
        overrides
      )

    draft = Core.create_sealed_product_draft!(attrs)

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  test "retailer registration normalizes identity and protects disabled rows" do
    attrs = retailer_attrs(%{slug: "  My-Shop ", source_key: " stable-source ", name: " Shop "})
    registered = Core.register_retailer!(attrs)

    assert {registered.slug, registered.source_key, registered.name} ==
             {"my-shop", "stable-source", "Shop"}

    disabled = Core.disable_retailer!(registered)
    assert disabled.status == "disabled"
    Core.register_retailer!(Map.merge(attrs, %{name: "Updated Shop"}))
    assert Core.get_retailer_by_source_key!("stable-source").status == "disabled"
    assert Core.enable_retailer!(disabled).status == "active"
    assert Enum.map(Core.list_active_retailers!(), & &1.id) |> Enum.member?(registered.id)
  end

  test "retailer rejects unsupported category and malformed homepage" do
    assert_raise Ash.Error.Invalid, fn -> retailer(%{category: "marketplace"}) end
    assert_raise Ash.Error.Invalid, fn -> retailer(%{homepage_url: "https://"}) end
    assert_raise Ash.Error.Invalid, fn -> retailer(%{homepage_url: "http://shop.example"}) end
    assert_raise Ash.Error.Invalid, fn -> retailer(%{name: "   "}) end
  end

  test "listing normalizes projection and preserves first_seen on idempotent ingest" do
    shop = retailer()
    first = DateTime.add(DateTime.utc_now() |> DateTime.truncate(:microsecond), -100, :second)
    row = listing(shop.id, %{first_seen_at: first, last_seen_at: first, last_checked_at: first})

    updated =
      listing(shop.id, %{
        source_listing_id: row.source_listing_id,
        source_title: " New   Title ",
        current_price_pln: "20.25",
        first_seen_at: row.first_seen_at,
        last_seen_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        last_checked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })

    reloaded = Core.get_retailer_listing!(shop.id, row.source_listing_id)
    assert reloaded.id == row.id
    assert reloaded.first_seen_at == first
    assert reloaded.normalized_title == "new title"
    assert updated.current_price_pln == Decimal.new("20.25")
  end

  test "listing image URL is persisted and updated by a newer observation" do
    shop = retailer()
    first = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    row = listing(shop.id, %{first_seen_at: first, last_seen_at: first, last_checked_at: first})

    newer = DateTime.add(first, 60, :second)

    Core.ingest_retailer_listing!(
      listing_attrs(shop.id, %{
        source_listing_id: row.source_listing_id,
        image_url: "https://lootquest.pl/wp-content/uploads/new.jpg",
        last_seen_at: newer,
        last_checked_at: newer
      })
    )

    assert Core.get_retailer_listing!(shop.id, row.source_listing_id).image_url ==
             "https://lootquest.pl/wp-content/uploads/new.jpg"
  end

  test "listing validates HTTPS, source identity, GTIN, price and time ordering" do
    shop = retailer()
    base = listing_attrs(shop.id)

    for invalid <- [
          %{source_listing_id: "   "},
          %{direct_url: "https://"},
          %{direct_url: "http://shop.example"},
          %{gtin: "4006381333932"},
          %{current_price_pln: Decimal.new("0")},
          %{stock_status: "in_stock", current_price_pln: nil},
          %{last_seen_at: DateTime.add(base.first_seen_at, -1, :second)}
        ] do
      assert_raise Ash.Error.Invalid, fn ->
        Core.ingest_retailer_listing!(Map.merge(base, invalid))
      end
    end

    for status <- ["sold_out", "unknown"] do
      assert %Decimal{} =
               listing(shop.id, %{stock_status: status, current_price_pln: Decimal.new("1")}).current_price_pln
    end
  end

  test "database rejects an alphabetic listing URL port" do
    shop = retailer()
    row = listing(shop.id)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE retailer_listings SET direct_url = 'https://shop.example:bad/path' WHERE id = $1",
               [Ecto.UUID.dump!(row.id)]
             )
  end

  test "database rejects an alphabetic retailer homepage port" do
    shop = retailer()

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE retailers SET homepage_url = 'https://shop.example:bad/path' WHERE id = $1",
               [Ecto.UUID.dump!(shop.id)]
             )
  end

  test "disabled listing is not silently re-enabled by ingest" do
    shop = retailer()
    row = listing(shop.id)
    Core.disable_retailer_listing!(row)

    Core.ingest_retailer_listing!(
      listing_attrs(shop.id, %{source_listing_id: row.source_listing_id, source_title: "Changed"})
    )

    assert Core.get_retailer_listing!(shop.id, row.source_listing_id).status == "disabled"
  end

  test "adapter returns normalized fields and Decimal price" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, result} =
             SealedRetailerAdapter.new(%{
               source_listing_id: " id ",
               source_title: "  A   Box ",
               direct_url: " https://shop.example/a ",
               gtin: "4006 3813 3393 1",
               current_price_pln: "3.50",
               stock_status: "in_stock",
               first_seen_at: now,
               last_seen_at: now,
               last_checked_at: now
             })

    assert result.source_listing_id == "id"
    assert result.source_title == "A   Box"
    assert result.normalized_title == "a box"
    assert result.direct_url == "https://shop.example/a"
    assert result.gtin == "4006381333931"
    assert result.current_price_pln == Decimal.new("3.50")
  end

  test "adapter rejects malformed matrix without HTTP" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    base = %{
      source_listing_id: "id",
      source_title: "Title",
      direct_url: "https://shop.example/a",
      stock_status: "unknown",
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now
    }

    for invalid <- [
          %{direct_url: "https://"},
          %{direct_url: "http://shop.example"},
          %{gtin: "4006381333932"},
          %{current_price_pln: 1.5},
          %{current_price_pln: "NaN"},
          %{current_price_pln: "Infinity"},
          %{current_price_pln: "0"},
          %{stock_status: "in_stock", current_price_pln: nil},
          %{last_seen_at: DateTime.add(now, -1, :second)},
          %{source_payload: "not a JSON map"}
        ] do
      assert {:error, :malformed_listing} = SealedRetailerAdapter.new(Map.merge(base, invalid))
    end

    assert {:error, :malformed_listing} =
             SealedRetailerAdapter.new(
               Map.put(base, :image_url, "https://user:pass@example.com/image")
             )
  end

  test "matcher only matches one eligible approved alias" do
    product_id = Ecto.UUID.generate()

    product = %{
      publication_status: "approved",
      officially_distributed: true,
      market: "PL",
      language: "en",
      release_date: Date.utc_today()
    }

    alias_row = %{
      kind: "ean",
      review_status: "approved",
      normalized_value: "4006381333931",
      sealed_product_id: product_id,
      sealed_product: product
    }

    assert {:matched, %{confirmed_product_id: ^product_id}} =
             SealedListingMatcher.match(%{gtin: "4006381333931"}, [alias_row])

    for aliases <- [
          [],
          [Map.put(alias_row, :review_status, "pending")],
          [Map.put(alias_row, :sealed_product, %{product | publication_status: "draft"})],
          [alias_row, alias_row]
        ] do
      assert {:review, %{reason: reason}} =
               SealedListingMatcher.match(%{gtin: "4006381333931"}, aliases)

      assert is_binary(reason)
    end

    assert {:review, _} = SealedListingMatcher.match(%{gtin: "bad"}, [alias_row])
    assert {:review, _} = SealedListingMatcher.match(%{source_title: "same name"}, [alias_row])
  end

  test "mapping state transitions and import protection" do
    shop = retailer()
    row = listing(shop.id)
    product = product()
    pending = Core.create_pending_listing_mapping!(%{retailer_listing_id: row.id})
    assert pending.status == "pending"

    queued_pending = hd(Core.list_listing_mapping_review_queue!(authorize?: false))
    assert queued_pending.retailer_listing.id == row.id
    assert queued_pending.retailer_listing.retailer.id == shop.id

    review =
      Core.import_listing_mapping!(%{
        retailer_listing_id: row.id,
        candidate_product_id: product.id,
        confidence: Decimal.new("0.8"),
        evidence: %{source: "matcher"},
        reason: "review needed"
      })

    assert Core.get_matched_listing_mapping(row.id) == {:ok, nil}
    queued_review = hd(Core.list_listing_mapping_review_queue!(authorize?: false))
    assert queued_review.status == "review"
    assert queued_review.candidate_product.id == product.id
    assert queued_review.retailer_listing.id == row.id
    assert queued_review.retailer_listing.retailer.id == shop.id

    approved_mapping =
      Core.approve_listing_mapping!(
        review,
        %{
          confirmed_product_id: product.id,
          confidence: Decimal.new("0.9"),
          evidence: %{source: "human"},
          expected_updated_at: review.updated_at
        },
        authorize?: false
      )

    assert approved_mapping.status == "matched"

    Core.import_listing_mapping!(%{
      retailer_listing_id: row.id,
      candidate_product_id: nil,
      confidence: nil,
      evidence: nil,
      reason: "overwrite"
    })

    assert Core.get_matched_listing_mapping!(row.id).status == "matched"
  end

  test "mapping rejects draft targets and clears review state" do
    shop = retailer()
    row = listing(shop.id)

    draft =
      Core.create_sealed_product_draft!(%{
        slug: "draft-#{System.unique_integer([:positive])}",
        name: "Draft",
        product_type: "booster_box"
      })

    assert_raise Ash.Error.Invalid, fn ->
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: row.id,
        confirmed_product_id: draft.id,
        confidence: Decimal.new("1"),
        evidence: %{method: "test"}
      })
    end

    review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: row.id,
        candidate_product_id: draft.id,
        confidence: Decimal.new("0.5"),
        evidence: %{method: "test"},
        reason: "check"
      })

    rejected =
      Core.reject_listing_mapping!(
        review,
        %{reason: "not this product", expected_updated_at: review.updated_at},
        authorize?: false
      )

    assert {rejected.status, rejected.candidate_product_id, rejected.confidence,
            rejected.evidence} == {"rejected", nil, nil, nil}
  end

  test "direct SQL rejects malformed listing URL" do
    shop = retailer()
    row = listing(shop.id)
    id = Ecto.UUID.dump!(row.id)

    assert {:error, _} =
             Repo.query("UPDATE retailer_listings SET direct_url = 'https://' WHERE id = $1", [
               id
             ])
  end

  test "direct SQL rejects invalid listing GTIN checksum" do
    shop = retailer()
    row = listing(shop.id)
    id = Ecto.UUID.dump!(row.id)

    assert {:error, _} =
             Repo.query("UPDATE retailer_listings SET gtin = '4006381333932' WHERE id = $1", [
               id
             ])
  end

  test "direct SQL rejects nonfinite listing price" do
    shop = retailer()
    row = listing(shop.id)
    id = Ecto.UUID.dump!(row.id)

    assert {:error, _} =
             Repo.query("UPDATE retailer_listings SET current_price_pln = 'NaN' WHERE id = $1", [
               id
             ])
  end

  test "direct SQL rejects unordered listing timestamps" do
    shop = retailer()
    row = listing(shop.id)
    id = Ecto.UUID.dump!(row.id)

    assert {:error, _} =
             Repo.query(
               "UPDATE retailer_listings SET last_seen_at = first_seen_at - interval '1 second' WHERE id = $1",
               [id]
             )
  end

  test "direct SQL rejects in-stock listing without price" do
    shop = retailer()
    row = listing(shop.id)
    id = Ecto.UUID.dump!(row.id)

    assert {:error, _} =
             Repo.query(
               "UPDATE retailer_listings SET stock_status = 'in_stock', current_price_pln = NULL WHERE id = $1",
               [id]
             )
  end

  test "direct SQL rejects an incomplete matched mapping state" do
    shop = retailer()
    row = listing(shop.id)
    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: row.id})
    id = Ecto.UUID.dump!(mapping.id)

    assert {:error, _} =
             Repo.query("UPDATE listing_product_mappings SET status = 'matched' WHERE id = $1", [
               id
             ])
  end

  test "direct SQL rejects a rejected mapping with retained product fields" do
    shop = retailer()
    row = listing(shop.id)
    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: row.id})
    id = Ecto.UUID.dump!(mapping.id)
    product_id = Ecto.UUID.dump!(product().id)

    assert {:error, _} =
             Repo.query(
               "UPDATE listing_product_mappings SET status = 'rejected', confirmed_product_id = $2, reason = 'bad', rejected_at = now() WHERE id = $1",
               [id, product_id]
             )
  end
end
