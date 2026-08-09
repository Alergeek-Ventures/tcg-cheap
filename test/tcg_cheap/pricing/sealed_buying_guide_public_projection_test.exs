defmodule TcgCheap.Pricing.SealedBuyingGuidePublicProjectionTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.{
    SealedBuyingGuidePublicProjection,
    SealedBuyingModel,
    SealedDailyAggregateCalculator,
    SealedDailyAggregateRevision
  }

  test "classifies ready, stale, limited, and cached-ready projections" do
    now = ~U[2026-08-09 12:00:00Z]
    source = aggregate(now, "ready")
    history = []
    guide = guide(source, now, history, "ready")
    readers = [latest_reader: latest_reader(guide), history_reader: history_reader(history)]

    assert {:ready, ^guide} =
             SealedBuyingGuidePublicProjection.load("product-1", :ready, source, now, readers)

    stale = %{
      source
      | aggregate_date: Date.add(source.aggregate_date, -2),
        calculated_at: ~U[2026-08-07 12:00:00Z],
        latest_nonfuture_checked_at: ~U[2026-08-07 12:00:00Z]
    }

    stale_guide = guide(stale, now, history, "ready")

    assert {:stale_ready, _} =
             SealedBuyingGuidePublicProjection.load("product-1", :ready, stale, now,
               latest_reader: fn _, _, _ -> {:ok, stale_guide} end,
               history_reader: history_reader(history)
             )

    limited = aggregate(now, "limited")
    limited_guide = guide(limited, now, history, "limited")

    assert {:limited, ^limited_guide} =
             SealedBuyingGuidePublicProjection.load("product-1", :limited, limited, now,
               latest_reader: latest_reader(limited_guide),
               history_reader: history_reader(history)
             )

    assert {:cached_ready, _} =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :limited_cached,
               %{limited: limited, snapshot: source},
               now,
               latest_reader: latest_reader(limited_guide),
               ready_reader: latest_reader(guide),
               history_reader: history_reader(history)
             )

    refute match?(
             {:cached_ready, _},
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :limited_cached,
               %{limited: limited, snapshot: %{source | sealed_product_id: "product-2"}},
               now,
               latest_reader: latest_reader(limited_guide),
               ready_reader: latest_reader(guide),
               history_reader: history_reader(history)
             )
           )
  end

  test "reader errors, mismatches, fingerprints, and malformed guides fail closed" do
    now = ~U[2026-08-09 12:00:00Z]
    source = aggregate(now, "ready")
    guide = guide(source, now, [], "ready")
    opts = [history_reader: history_reader([])]

    assert :read_error =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               source,
               now,
               Keyword.put(opts, :latest_reader, fn _, _, _ -> {:error, :boom} end)
             )

    assert :invalid =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               source,
               now,
               Keyword.put(opts, :latest_reader, fn _, _, _ ->
                 {:ok, %{guide | source_aggregate_fingerprint: "bad"}}
               end)
             )

    assert :read_error =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               source,
               now,
               Keyword.merge(opts,
                 latest_reader: latest_reader(guide),
                 history_reader: fn _, _, _, _, _ -> {:error, :boom} end
               )
             )

    assert :invalid =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               source,
               now,
               Keyword.put(opts, :latest_reader, fn _, _, _ ->
                 {:ok, %{guide | explanation_factors: ["msrp", "msrp"]}}
               end)
             )

    assert :invalid =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               source,
               now,
               Keyword.put(opts, :latest_reader, fn _, _, _ ->
                 {:ok, %{guide | trend: "rising", trend_change: nil}}
               end)
             )

    assert :invalid =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               source,
               now,
               Keyword.put(opts, :latest_reader, fn _, _, _ ->
                 {:ok, %{guide | great_price_max_pln: Decimal.new("NaN")}}
               end)
             )
  end

  test "a missing guide is missing without an aggregate, while an existing guide is invalid" do
    now = ~U[2026-08-09 12:00:00Z]
    source = aggregate(now, "ready")
    guide = guide(source, now, [], "ready")

    assert :missing =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               nil,
               now,
               latest_reader: latest_reader(nil)
             )

    assert :invalid =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :ready,
               nil,
               now,
               latest_reader: latest_reader(guide)
             )
  end

  test "cached-ready reader errors fail closed" do
    now = ~U[2026-08-09 12:00:00Z]
    limited = aggregate(now, "limited")
    source = aggregate(now, "ready")
    limited_guide = guide(limited, now, [], "limited")

    opts = [
      latest_reader: latest_reader(limited_guide),
      history_reader: history_reader([]),
      ready_reader: fn _, _, _ -> {:error, :boom} end
    ]

    assert :read_error =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :limited_cached,
               %{limited: limited, snapshot: source},
               now,
               opts
             )

    assert :read_error =
             SealedBuyingGuidePublicProjection.load(
               "product-1",
               :limited_cached,
               %{limited: limited, snapshot: source},
               now,
               Keyword.put(opts, :ready_reader, fn _, _, _ -> raise "boom" end)
             )
  end

  defp aggregate(now, status) do
    limited = status == "limited"

    %{
      id: "aggregate-#{status}",
      sealed_product_id: "product-1",
      aggregate_date: DateTime.to_date(now),
      calculation_version: SealedDailyAggregateCalculator.version(),
      currency: "PLN",
      status: status,
      limited_reason: if(limited, do: "too_few_regular_retailers", else: nil),
      benchmark_pln: if(limited, do: nil, else: Decimal.new("100")),
      typical_low_pln: if(limited, do: nil, else: Decimal.new("90")),
      typical_high_pln: if(limited, do: nil, else: Decimal.new("110")),
      fresh_regular_retailer_count: if(limited, do: 2, else: 5),
      fresh_lgs_count: 1,
      recent_sold_out_0_14_day_count: 0,
      sold_out_15_30_day_count: 0,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: 6,
      source_mapping_confident: true,
      source_msrp_pln: nil,
      latest_nonfuture_checked_at: if(limited, do: nil, else: now),
      calculated_at: now,
      source_evidence: []
    }
  end

  defp guide(source, now, history, status) do
    {:ok, fingerprint} = SealedDailyAggregateRevision.fingerprint(source)
    {:ok, history_fingerprint} = SealedDailyAggregateRevision.history_fingerprint(history)

    %{
      sealed_product_id: "product-1",
      model_version: SealedBuyingModel.version(),
      currency: "PLN",
      status: status,
      limited_reason: if(status == "limited", do: "limited_market_aggregate", else: nil),
      guide_date: source.aggregate_date,
      source_aggregate_id: source.id,
      source_aggregate_calculated_at: source.calculated_at,
      source_aggregate_fingerprint: fingerprint,
      source_history_fingerprint: history_fingerprint,
      calculated_at: now,
      confidence: Decimal.new("0"),
      reference_price_pln: if(status == "limited", do: nil, else: Decimal.new("100")),
      great_price_max_pln: if(status == "limited", do: nil, else: Decimal.new("90")),
      fair_price_max_pln: if(status == "limited", do: nil, else: Decimal.new("100")),
      expensive_price_max_pln: if(status == "limited", do: nil, else: Decimal.new("110")),
      regular_benchmark_pln: Decimal.new("100"),
      msrp_pln: nil,
      lgs_median_pln: nil,
      sold_out_center_pln: nil,
      explanation_factors: ["market_benchmark"],
      trend: "insufficient_history",
      trend_change: nil,
      availability: "balanced",
      availability_trend: "insufficient_history"
    }
  end

  defp latest_reader(value), do: fn _, _, _ -> {:ok, value} end
  defp history_reader(value), do: fn _, _, _, _, _ -> {:ok, value} end
end
