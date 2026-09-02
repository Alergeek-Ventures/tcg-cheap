defmodule TcgCheap.Pricing.HomepageSealedPriceChangesTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core
  alias TcgCheap.Repo

  @as_of ~U[2026-08-10 12:00:00.000000Z]

  test "balances six qualified risers and fallers and orders deterministic identities" do
    risers = Enum.map(1..6, &product("riser-#{&1}"))
    fallers = Enum.map(1..6, &product("faller-#{&1}"))

    Enum.each(Enum.with_index(risers), fn {product, index} ->
      points(product, "#{10 + index}", "#{20 + index}")
    end)

    Enum.each(Enum.with_index(fallers), fn {product, index} ->
      points(product, "#{20 + index}", "#{10 + index}")
    end)

    assert {:ok, changes} = Core.list_homepage_sealed_price_changes(@as_of, 10)
    assert length(changes) == 10
    assert Enum.count(changes, &(Decimal.compare(&1.change_percent, Decimal.new(0)) == :gt)) == 5
    assert Enum.count(changes, &(Decimal.compare(&1.change_percent, Decimal.new(0)) == :lt)) == 5

    expected_ids =
      Enum.take(Enum.map(risers, & &1.id), 5) ++ Enum.take(Enum.map(fallers, & &1.id), 5)

    assert Enum.map(changes, & &1.sealed_product_id) == expected_ids

    [first | _] = changes
    assert first.slug == hd(risers).slug
    assert first.name == hd(risers).name
    assert first.product_type == "tin"
    assert first.series_name == "Homepage Series"
    assert first.set_name == "Homepage Set"
    assert first.release_date == ~D[2026-08-01]
    assert first.distribution_status == "current"
    assert first.current_checked_at == @as_of
    assert first.current_calculated_at == @as_of
  end

  test "does not publish movers for an approved product missing factual metadata" do
    product = product("incomplete-mover")
    points(product, "10", "20")

    Repo.query!(
      "UPDATE sealed_products SET image_url = NULL, image_source = NULL, image_source_url = NULL WHERE id = $1",
      [Ecto.UUID.dump!(product.id)]
    )

    assert {:ok, changes} = Core.list_homepage_sealed_price_changes(@as_of, 10)
    refute Enum.any?(changes, &(&1.sealed_product_id == product.id))
  end

  test "excludes insufficient, out-of-window, stale, future, non-public, and unconfident evidence" do
    fewer = product("fewer")
    aggregate(fewer, ~D[2026-08-10], "20", current?: true)

    short = product("short")
    aggregate(short, ~D[2026-08-10], "20", current?: true)

    outside = product("outside")
    points(outside, "10", "20", dates: [~D[2026-07-10], ~D[2026-07-11], ~D[2026-08-10]])

    stale = product("stale")
    points(stale, "10", "20", current_checked_at: ~U[2026-08-02 12:00:00Z])

    future_calculated = product("future-calculated")
    points(future_calculated, "10", "20", current_calculated_at: ~U[2026-08-10 12:00:01Z])

    future_checked = product("future-checked")

    points(future_checked, "10", "20",
      current_checked_at: ~U[2026-08-10 12:00:01Z],
      current_calculated_at: ~U[2026-08-10 12:00:01Z]
    )

    unconfident = product("unconfident")
    points(unconfident, "10", "20", source_mapping_confident: false)

    draft = product("draft", approved?: false)
    points(draft, "10", "20")

    archived = product("archived")

    Core.archive_sealed_product!(archived, %{expected_updated_at: archived.updated_at},
      authorize?: false
    )

    points(archived, "10", "20")

    assert {:ok, []} = Core.list_homepage_sealed_price_changes(@as_of, 10)
  end

  test "a newest limited aggregate suppresses older ready evidence" do
    limited = product("limited")
    points(limited, "10", "20")

    Repo.query!(
      """
      UPDATE sealed_daily_aggregates
      SET status = 'limited', limited_reason = 'no_fresh_current_offers', benchmark_pln = NULL,
        typical_low_pln = NULL, typical_high_pln = NULL, fresh_regular_retailer_count = 0,
        latest_nonfuture_checked_at = NULL, source_mapping_confident = FALSE
      WHERE sealed_product_id = $1 AND aggregate_date = $2
      """,
      [Ecto.UUID.dump!(limited.id), ~D[2026-08-10]]
    )

    assert {:ok, []} = Core.list_homepage_sealed_price_changes(@as_of, 10)
  end

  defp product(label, opts \\ []) do
    suffix = System.unique_integer([:positive])

    draft =
      Core.create_sealed_product_draft!(%{
        slug: "homepage-#{label}-#{suffix}",
        name: "Homepage #{label} #{suffix}",
        product_type: "tin",
        series_name: "Homepage Series",
        set_name: "Homepage Set",
        description: "A complete sealed product for homepage tests.",
        contents: ["Tin", "Booster packs"],
        pack_count: 4,
        cards_per_pack: 10,
        official_url: "https://example.com/products/homepage",
        details_source: "Official product page",
        details_source_url: "https://example.com/products/homepage/details",
        image_url: "https://assets.tcgdex.net/en/sealed/homepage.jpg",
        image_source: "Official product page",
        image_source_url: "https://example.com/products/homepage/image",
        officially_distributed: Keyword.get(opts, :officially_distributed, true),
        release_date: ~D[2026-08-01]
      })

    if Keyword.get(opts, :approved?, true) do
      Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
        authorize?: false
      )
    else
      draft
    end
  end

  defp points(product, start_value, current_value, opts \\ []) do
    dates = Keyword.get(opts, :dates, [~D[2026-08-01], ~D[2026-08-05], ~D[2026-08-10]])
    [first, middle, current] = dates
    aggregate(product, first, start_value, opts)

    aggregate(
      product,
      middle,
      Decimal.to_string(
        Decimal.div(
          Decimal.add(Decimal.new(start_value), Decimal.new(current_value)),
          Decimal.new(2)
        )
      ),
      opts
    )

    aggregate(product, current, current_value, Keyword.put(opts, :current?, true))
  end

  defp aggregate(product, date, value, opts) do
    status = Keyword.get(opts, :status, "ready")

    calculated_at =
      Keyword.get(opts, :calculated_at, DateTime.new!(date, ~T[12:00:00], "Etc/UTC"))

    checked_at = Keyword.get(opts, :checked_at, calculated_at)

    checked_at =
      if Keyword.get(opts, :current?, false),
        do: Keyword.get(opts, :current_checked_at, @as_of),
        else: checked_at

    calculated_at =
      if Keyword.get(opts, :current?, false),
        do: Keyword.get(opts, :current_calculated_at, @as_of),
        else: calculated_at

    attrs = %{
      sealed_product_id: Ecto.UUID.dump!(product.id),
      aggregate_date: date,
      status: status,
      limited_reason: if(status == "limited", do: "no_fresh_current_offers"),
      benchmark_pln: if(value, do: Decimal.new(value)),
      typical_low_pln: if(value, do: Decimal.new(value)),
      typical_high_pln: if(value, do: Decimal.new(value)),
      fresh_regular_retailer_count: if(value, do: 5, else: 0),
      fresh_lgs_count: 0,
      recent_sold_out_0_14_day_count: 0,
      sold_out_15_30_day_count: 0,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: if(value, do: 5, else: 0),
      latest_nonfuture_checked_at: checked_at,
      calculated_at: calculated_at,
      source_mapping_confident: Keyword.get(opts, :source_mapping_confident, true)
    }

    Repo.insert_all("sealed_daily_aggregates", [attrs])
  end
end
