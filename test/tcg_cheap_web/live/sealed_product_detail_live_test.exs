defmodule TcgCheapWeb.SealedProductDetailLiveTest do
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedBuyingModel
  alias TcgCheap.Pricing.SealedDailyAggregateCalculator
  alias TcgCheap.Pricing.SealedDailyAggregateRevision
  alias TcgCheapWeb.SealedProductDetailLive

  test "renders an exact persisted ready guide without explanations", %{conn: conn} do
    product = product()
    today = Date.utc_today()

    for date <- [Date.add(today, -14), Date.add(today, -7)] do
      record_aggregate!(product, date)
    end

    source = record_aggregate!(product, today)

    record_guide!(source, %{
      great_price_max_pln: Decimal.new("90"),
      fair_price_max_pln: Decimal.new("105"),
      expensive_price_max_pln: Decimal.new("120"),
      trend: "rising",
      trend_change: Decimal.new("0.12"),
      availability: "scarce",
      availability_trend: "tightening",
      msrp_pln: Decimal.new("129.99"),
      explanation_factors: ["trend_rising", "availability_scarce", "msrp"]
    })

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    for band <- ~w(great fair expensive avoid) do
      assert has_element?(view, "#sealed-detail-buying-band-#{band}")
    end

    assert has_element?(view, "#sealed-detail-buying-band-great", "90.00 PLN")
    assert has_element?(view, "#sealed-detail-buying-band-fair", "105.00 PLN")
    assert has_element?(view, "#sealed-detail-buying-band-expensive", "120.00 PLN")
    assert has_element?(view, "#sealed-detail-buying-band-avoid", "120.00 PLN")
    refute has_element?(view, "#sealed-detail-guide-reasons")
    assert has_element?(view, "#sealed-market-history-ledger.sr-only")

    assert has_element?(
             view,
             "#sealed-market-history-ledger",
             Calendar.strftime(today, "%b %-d, %Y")
           )

    assert has_element?(view, "#sealed-market-history-ledger", "benchmark 12.00 PLN")
    assert has_element?(view, "#sealed-market-history-ledger", "typical range 10.00–15.00 PLN")
    assert has_element?(view, "#sealed-market-history-benchmark-0")
    assert has_element?(view, "#sealed-market-history-benchmark-1")
    refute has_element?(view, "button", "Buy")
    refute has_element?(view, "sealed_buying_model_v1")
    refute has_element?(view, "trend_rising")
  end

  test "renders an exact stale ready guide as previous guidance", %{conn: conn} do
    product = product()
    today = Date.utc_today()
    stale_date = Date.add(today, -2)

    source = record_aggregate!(product, stale_date)
    record_guide!(source, %{})

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-detail-guide-stale", "May be outdated")
    refute has_element?(view, "#sealed-detail-guide-stale", "snapshot")

    for band <- ~w(great fair expensive avoid) do
      assert has_element?(view, "#sealed-detail-buying-band-#{band}")
    end

    refute has_element?(view, "#sealed-detail-guide-ready")
  end

  test "renders a limited persisted guide without buying bands", %{conn: conn} do
    product = product()

    source =
      record_aggregate!(product, Date.utc_today(), %{
        status: "limited",
        limited_reason: "too_few_regular_retailers",
        fresh_regular_retailer_count: 4,
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil
      })

    record_guide!(source, %{
      status: "limited",
      limited_reason: "low_confidence",
      reference_price_pln: Decimal.new("100"),
      regular_benchmark_pln: Decimal.new("100"),
      great_price_max_pln: nil,
      fair_price_max_pln: nil,
      expensive_price_max_pln: nil,
      explanation_factors: [
        "market_data_limited",
        "trend_insufficient_history",
        "availability_trend_insufficient_history"
      ],
      trend: "insufficient_history",
      trend_change: nil
    })

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    refute has_element?(view, "#sealed-detail-buying-guide")
    refute has_element?(view, "#sealed-detail-buying-bands")
  end

  test "renders current limited guide with cached exact ready guidance", %{conn: conn} do
    product = product()
    today = Date.utc_today()
    older = record_aggregate!(product, Date.add(today, -10))
    record_guide!(older, %{})

    limited =
      record_aggregate!(product, today, %{
        status: "limited",
        limited_reason: "too_few_regular_retailers",
        fresh_regular_retailer_count: 4,
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil
      })

    record_guide!(limited, %{
      status: "limited",
      limited_reason: "low_confidence",
      great_price_max_pln: nil,
      fair_price_max_pln: nil,
      expensive_price_max_pln: nil
    })

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-detail-buying-guide")
    assert has_element?(view, "#sealed-detail-guide-cached")
    assert has_element?(view, "#sealed-detail-guide-limited", "Limited data")

    for band <- ~w(great fair expensive avoid) do
      assert has_element?(view, "#sealed-detail-buying-band-#{band}")
    end
  end

  test "fails closed when the newest ready aggregate has no guide", %{conn: conn} do
    product = product()
    today = Date.utc_today()
    older = record_aggregate!(product, Date.add(today, -10))
    record_guide!(older, %{})

    record_aggregate!(product, today, %{
      benchmark_pln: Decimal.new("13.00"),
      typical_low_pln: Decimal.new("11.00"),
      typical_high_pln: Decimal.new("16.00")
    })

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    refute has_element?(view, "#sealed-detail-buying-guide")
    refute has_element?(view, "#sealed-detail-buying-bands")
  end

  test "renders public identity, optional MSRP, and the price guide state", %{conn: conn} do
    product = product(%{msrp_pln: Decimal.new("129.99"), msrp_source: "official product sheet"})

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, ".sealed-detail-world")
    assert has_element?(view, "#decision-header")
    assert has_element?(view, "#decision-wordmark")
    assert has_element?(view, "#decision-wordmark .fluent-icon")
    assert has_element?(view, "#sealed-detail-title", product.name)
    assert has_element?(view, "#sealed-detail-type", "Booster Box")
    assert has_element?(view, "#sealed-detail-msrp", "129.99 PLN")
    refute has_element?(view, "#sealed-detail-msrp-provenance")
    refute has_element?(view, "#sealed-detail-release", "Release date:")
    refute has_element?(view, "#sealed-detail-status", "Status:")
    assert has_element?(view, "#sealed-detail-market-snapshot")
    assert has_element?(view, "#sealed-detail-market-snapshot-title", "Price guide")
    refute has_element?(view, "#sealed-market-history-section")
    refute has_element?(view, "#sealed-market-history-empty")
    refute has_element?(view, "#sealed-detail-buying-guide")
    refute has_element?(view, "#sealed-detail-guide-missing")

    assert has_element?(
             view,
             "#sealed-detail-aggregate-empty",
             "Limited data."
           )

    refute has_element?(view, "#sealed-detail-benchmark")
    refute has_element?(view, "#sealed-detail-market-snapshot", "graph")
    assert has_element?(view, "#sealed-current-empty", "No current local offers yet")
    refute has_element?(view, "#sealed-sold-out-section")
    refute has_element?(view, "#sealed-sold-out-empty")
  end

  test "renders a concise fallback when MSRP is absent", %{conn: conn} do
    product = product(%{msrp_pln: nil, msrp_source: nil})

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-detail-msrp", "MSRP unavailable")
    refute has_element?(view, "#sealed-detail-msrp", "unavailable from local records")
  end

  test "renders a graph ledger with a genuine missing-day gap", %{conn: conn} do
    product = product()
    today = Date.utc_today()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    for date <- [Date.add(today, -2), today] do
      calculated_at =
        if date == today, do: now, else: DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

      assert {:ok, _} =
               Core.record_sealed_daily_aggregate(
                 aggregate_attrs(product, %{
                   aggregate_date: date,
                   calculated_at: calculated_at,
                   latest_nonfuture_checked_at: calculated_at
                 })
               )
    end

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-market-history-chart")
    assert has_element?(view, "#sealed-market-history-ledger.sr-only")
    assert has_element?(view, "#sealed-market-history-ledger", "benchmark 12.00 PLN")
    assert has_element?(view, "#sealed-market-history-ledger", "typical range 10.00–15.00 PLN")

    assert has_element?(view, "#sealed-market-history-benchmark-0")
    assert has_element?(view, "#sealed-market-history-benchmark-1")
    refute has_element?(view, "button", "Buy")
    refute has_element?(view, "sealed_buying_model_v1")
  end

  test "keeps current and sold-out evidence separate with safe direct links", %{conn: conn} do
    product = product()
    retailer = Core.register_retailer!(retailer_attrs())
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    current =
      listing(retailer.id, now, %{
        stock_status: "in_stock",
        current_price_pln: Decimal.new("99.90")
      })

    sold_out =
      listing(retailer.id, DateTime.add(now, -3600, :second), %{
        stock_status: "sold_out",
        current_price_pln: nil
      })

    map_listing(product.id, current)
    map_listing(product.id, sold_out)

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-current-offers #sealed-current-offer-#{current.id}")
    assert has_element?(view, "#sealed-sold-out-offers #sealed-sold-out-offer-#{sold_out.id}")
    assert has_element?(view, "details#sealed-sold-out-section > summary#sealed-sold-out-title")
    assert has_element?(view, "#sealed-current-price-#{current.id}", "99.90 PLN")
    assert has_element?(view, "#sealed-sold-out-price-#{sold_out.id}", "unavailable")
    refute has_element?(view, "#sealed-sold-out-price-#{sold_out.id}", "Price at last check:")
    assert has_element?(view, "#sealed-current-price-#{current.id}.sealed-offer-price")

    assert has_element?(
             view,
             "#sealed-current-stock-#{current.id}.sealed-offer-stock",
             "In stock"
           )

    assert has_element?(
             view,
             "#sealed-current-checked-#{current.id}.sealed-offer-checked",
             "Checked today"
           )

    refute has_element?(view, ".sealed-offer-category")
    refute has_element?(view, "#sealed-current-offer-#{current.id}", "Category:")

    assert has_element?(
             view,
             "#sealed-current-direct-link-#{current.id}[target='_blank'][rel='noopener noreferrer']"
           )

    assert has_element?(view, "#sealed-sold-out-checked-#{sold_out.id}", "Checked today")

    assert has_element?(
             view,
             "#sealed-current-direct-link-#{current.id}[aria-label*='#{retailer.name}'][aria-label*='In stock']"
           )

    refute has_element?(view, "#sealed-current-empty")
    refute has_element?(view, "#sealed-sold-out-empty")
  end

  test "renders a ready local aggregate alongside offers without inventing buying bands", %{
    conn: conn
  } do
    product = product()
    retailer = Core.register_retailer!(retailer_attrs())
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    current = listing(retailer.id, now, %{current_price_pln: Decimal.new("11.50")})
    map_listing(product.id, current)

    assert {:ok, _aggregate} =
             Core.record_sealed_daily_aggregate(
               aggregate_attrs(product, %{
                 benchmark_pln: Decimal.new("12.50"),
                 typical_low_pln: Decimal.new("10.00"),
                 typical_high_pln: Decimal.new("15.00")
               })
             )

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-detail-benchmark", "12.50 PLN")
    assert has_element?(view, "#sealed-current-offer-#{current.id}")
    assert has_element?(view, "#sealed-detail-range", "10.00–15.00 PLN")
    refute has_element?(view, "#sealed-detail-fresh-regular-count")
    refute has_element?(view, "#sealed-detail-fresh-lgs-count")
    refute has_element?(view, "#sealed-detail-sold-out-evidence-count")
    refute has_element?(view, "#sealed-detail-aggregate-date")
    refute has_element?(view, "#sealed-detail-methodology")
    refute has_element?(view, "#sealed-detail-evidence-checked-at")
    refute has_element?(view, "#sealed-detail-buying-bands")
    refute has_element?(view, "button", "Buy")
  end

  test "labels an older ready aggregate as cached and possibly outdated", %{conn: conn} do
    product = product()

    assert {:ok, _aggregate} =
             Core.record_sealed_daily_aggregate(
               aggregate_attrs(product, %{aggregate_date: Date.add(Date.utc_today(), -2)})
             )

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")
    assert has_element?(view, "#sealed-detail-aggregate-stale", "May be outdated")

    assert has_element?(view, "#sealed-detail-market-snapshot", "Market price")
    assert has_element?(view, "#sealed-detail-market-snapshot", "Typical range")
    refute has_element?(view, "#sealed-detail-aggregate-date")
    refute has_element?(view, "#sealed-detail-evidence-checked-at")
    refute has_element?(view, "#sealed-detail-market-snapshot", "Latest stored benchmark")
    refute has_element?(view, "#sealed-detail-market-snapshot", "Current market benchmark")
  end

  test "renders canonical limited aggregate reasons as plain copy", %{conn: conn} do
    for {reason, counts} <- [
          {"no_fresh_current_offers", %{fresh_regular_retailer_count: 0, fresh_lgs_count: 0}},
          {"too_few_regular_retailers", %{fresh_regular_retailer_count: 4}},
          {"insufficient_inliers", %{fresh_regular_retailer_count: 5}}
        ] do
      product = product()

      assert {:ok, _aggregate} =
               Core.record_sealed_daily_aggregate(
                 aggregate_attrs(
                   product,
                   Map.merge(counts, %{
                     status: "limited",
                     limited_reason: reason,
                     benchmark_pln: nil,
                     typical_low_pln: nil,
                     typical_high_pln: nil
                   })
                 )
               )

      {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")
      assert has_element?(view, "#sealed-detail-aggregate-limited", "Limited data.")
      refute has_element?(view, "regular retailer")
      refute has_element?(view, "outlier")
      refute has_element?(view, "sealed_market_daily_v1")
      refute has_element?(view, "#sealed-detail-benchmark")
    end
  end

  test "uses an older cached ready snapshot when the newest aggregate is limited", %{conn: conn} do
    product = product()
    snapshot_date = Date.add(Date.utc_today(), -45)
    snapshot_time = DateTime.new!(snapshot_date, ~T[12:00:00], "Etc/UTC")

    assert {:ok, _aggregate} =
             Core.record_sealed_daily_aggregate(
               aggregate_attrs(product, %{
                 aggregate_date: snapshot_date,
                 latest_nonfuture_checked_at: snapshot_time,
                 calculated_at: snapshot_time
               })
             )

    assert {:ok, _aggregate} =
             Core.record_sealed_daily_aggregate(
               aggregate_attrs(product, %{
                 status: "limited",
                 limited_reason: "too_few_regular_retailers",
                 fresh_regular_retailer_count: 4,
                 benchmark_pln: nil,
                 typical_low_pln: nil,
                 typical_high_pln: nil
               })
             )

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-detail-aggregate-cached", "May be outdated")
    assert has_element?(view, "#sealed-detail-aggregate-limited", "Limited data.")
    assert has_element?(view, "#sealed-detail-benchmark", "12.00 PLN")
    refute has_element?(view, "#sealed-detail-aggregate-ready")
  end

  test "does not label ready evidence current when its evidence is stale", %{conn: conn} do
    product = product()
    stale = DateTime.add(DateTime.utc_now(), -8 * 86_400, :second)

    assert {:ok, _aggregate} =
             Core.record_sealed_daily_aggregate(
               aggregate_attrs(product, %{latest_nonfuture_checked_at: stale})
             )

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-detail-aggregate-stale", "May be outdated")
    assert has_element?(view, "#sealed-detail-market-snapshot", "Market price")
    refute has_element?(view, "#sealed-detail-market-snapshot", "Latest stored benchmark")
    refute has_element?(view, "#sealed-detail-market-snapshot", "Current market benchmark")
  end

  test "does not expose draft or nonexistent products", %{conn: conn} do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "hidden-#{suffix()}",
        name: "Hidden Draft",
        product_type: "tin"
      })

    {:ok, draft_view, _html} = live(conn, ~p"/sealed/#{draft.slug}")
    assert has_element?(draft_view, "#sealed-detail-not-found")
    refute has_element?(draft_view, "#sealed-detail-title", draft.name)

    {:ok, missing_view, _html} = live(conn, "/sealed/not-a-real-product-#{suffix()}")
    assert has_element?(missing_view, "#sealed-detail-not-found")
    refute has_element?(missing_view, "#sealed-current-offers")
  end

  test "data-read error component distinguishes an outage from not found" do
    html = render_component(&SealedProductDetailLive.data_error/1, flash: %{})
    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#sealed-detail-data-error")
           |> LazyHTML.to_tree() != []

    assert document
           |> LazyHTML.query("#sealed-detail-data-error-back")
           |> LazyHTML.to_tree() != []

    assert document
           |> LazyHTML.query("#sealed-detail-not-found")
           |> LazyHTML.to_tree() == []
  end

  defp product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          slug: "detail-product-#{suffix()}",
          name: "Detail Booster Box",
          product_type: "booster_box",
          officially_distributed: true,
          release_date: Date.utc_today()
        },
        overrides
      )

    draft = Core.create_sealed_product_draft!(attrs)

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp retailer_attrs do
    %{
      slug: "detail-retailer-#{suffix()}",
      source_key: "detail-source-#{suffix()}",
      name: "Detail Shop",
      category: "regular_retailer",
      homepage_url: "https://shop.example"
    }
  end

  defp listing(retailer_id, checked_at, overrides) do
    Core.ingest_retailer_listing!(
      Map.merge(
        %{
          retailer_id: retailer_id,
          source_listing_id: "detail-listing-#{suffix()}",
          source_title: "Detail product",
          direct_url: "https://shop.example/product",
          current_price_pln: Decimal.new("10.00"),
          stock_status: "in_stock",
          first_seen_at: checked_at,
          last_seen_at: checked_at,
          last_checked_at: checked_at
        },
        overrides
      )
    )
  end

  defp map_listing(product_id, listing) do
    review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: listing.id,
        confidence: Decimal.new("1"),
        evidence: %{"source" => "test"},
        reason: "test"
      })

    Core.approve_listing_mapping!(
      review,
      %{
        confirmed_product_id: product_id,
        confidence: Decimal.new("1"),
        evidence: %{"source" => "test"},
        expected_updated_at: review.updated_at
      },
      authorize?: false
    )
  end

  defp record_aggregate!(product, date, overrides \\ %{}) do
    calculated_at =
      if date == Date.utc_today() do
        DateTime.utc_now() |> DateTime.truncate(:microsecond)
      else
        DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
      end

    Core.record_sealed_daily_aggregate!(
      aggregate_attrs(product, %{
        aggregate_date: date,
        latest_nonfuture_checked_at: calculated_at,
        calculated_at: calculated_at
      })
      |> Map.merge(overrides)
    )
  end

  defp record_guide!(aggregate, overrides) do
    {:ok, history} =
      Core.list_sealed_daily_aggregate_history(
        aggregate.sealed_product_id,
        aggregate.calculation_version,
        Date.add(aggregate.aggregate_date, -30),
        Date.add(aggregate.aggregate_date, -1)
      )

    {:ok, aggregate_fingerprint} = SealedDailyAggregateRevision.fingerprint(aggregate)
    {:ok, history_fingerprint} = SealedDailyAggregateRevision.history_fingerprint(history)

    attrs =
      %{
        source_aggregate_id: aggregate.id,
        expected_source_aggregate_date: aggregate.aggregate_date,
        expected_source_aggregate_calculated_at: aggregate.calculated_at,
        expected_source_aggregate_fingerprint: aggregate_fingerprint,
        expected_source_history_fingerprint: history_fingerprint,
        model_version: SealedBuyingModel.version(),
        currency: "PLN",
        status: "ready",
        limited_reason: nil,
        reference_price_pln: Decimal.new("100"),
        great_price_max_pln: Decimal.new("90"),
        fair_price_max_pln: Decimal.new("105"),
        expensive_price_max_pln: Decimal.new("120"),
        confidence: Decimal.new("0.8"),
        trend: "stable",
        trend_change: Decimal.new("0"),
        availability: "abundant",
        availability_trend: "stable",
        regular_benchmark_pln: Decimal.new("100"),
        msrp_pln: nil,
        lgs_median_pln: nil,
        sold_out_center_pln: nil,
        explanation_factors: [
          "market_benchmark",
          "trend_stable",
          "availability_abundant",
          "availability_trend_stable"
        ],
        calculated_at: aggregate.calculated_at
      }

    Core.record_sealed_buying_guide_snapshot!(Map.merge(attrs, overrides))
  end

  defp aggregate_attrs(product, overrides) do
    Map.merge(
      %{
        sealed_product_id: product.id,
        aggregate_date: Date.utc_today(),
        calculation_version: SealedDailyAggregateCalculator.version(),
        currency: "PLN",
        status: "ready",
        limited_reason: nil,
        benchmark_pln: Decimal.new("12.00"),
        typical_low_pln: Decimal.new("10.00"),
        typical_high_pln: Decimal.new("15.00"),
        fresh_regular_retailer_count: 5,
        fresh_lgs_count: 1,
        recent_sold_out_0_14_day_count: 2,
        sold_out_15_30_day_count: 1,
        stale_or_future_current_offer_count: 0,
        unique_source_retailer_count: 6,
        latest_nonfuture_checked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        calculated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      },
      overrides
    )
  end

  defp suffix, do: System.unique_integer([:positive])
end
