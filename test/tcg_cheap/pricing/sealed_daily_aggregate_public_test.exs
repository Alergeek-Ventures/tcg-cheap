defmodule TcgCheap.Pricing.SealedDailyAggregatePublicTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.{SealedDailyAggregateCalculator, SealedDailyAggregatePublic}

  test "accepts current ready aggregates and rejects stale or malformed values" do
    now = ~U[2026-08-09 12:00:00Z]
    aggregate = ready(now)

    assert SealedDailyAggregatePublic.ready?(aggregate, now)
    assert SealedDailyAggregatePublic.ready?(aggregate, now, sealed_product_id: "product-1")
    refute SealedDailyAggregatePublic.ready?(aggregate, now, sealed_product_id: "product-2")
    assert SealedDailyAggregatePublic.current_ready?(aggregate, now)

    assert SealedDailyAggregatePublic.current_ready?(aggregate, now,
             sealed_product_id: "product-1"
           )

    refute SealedDailyAggregatePublic.current_ready?(aggregate, now,
             sealed_product_id: "product-2"
           )

    refute SealedDailyAggregatePublic.current_ready?(
             %{aggregate | latest_nonfuture_checked_at: ~U[2026-07-31 12:00:00Z]},
             now
           )

    refute SealedDailyAggregatePublic.ready?(%{aggregate | calculation_version: "old"}, now)
    refute SealedDailyAggregatePublic.ready?(%{aggregate | currency: "EUR"}, now)
    refute SealedDailyAggregatePublic.ready?(%{aggregate | fresh_regular_retailer_count: 4}, now)
    refute SealedDailyAggregatePublic.ready?(%{aggregate | latest_nonfuture_checked_at: nil}, now)

    refute SealedDailyAggregatePublic.ready?(
             %{aggregate | benchmark_pln: Decimal.new("NaN")},
             now
           )

    refute SealedDailyAggregatePublic.ready?(
             %{aggregate | calculated_at: ~U[2026-08-10 00:00:00Z]},
             now
           )
  end

  test "limited state has canonical reason/counts and optional checked time" do
    now = ~U[2026-08-09 12:00:00Z]

    aggregate =
      ready(now)
      |> Map.merge(%{
        status: "limited",
        limited_reason: "too_few_regular_retailers",
        fresh_regular_retailer_count: 2,
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil,
        latest_nonfuture_checked_at: nil
      })

    assert SealedDailyAggregatePublic.limited?(aggregate, now)
    assert SealedDailyAggregatePublic.limited?(aggregate, now, sealed_product_id: "product-1")
    refute SealedDailyAggregatePublic.limited?(aggregate, now, sealed_product_id: "product-2")

    refute SealedDailyAggregatePublic.limited?(
             %{aggregate | fresh_regular_retailer_count: 0, fresh_lgs_count: 0},
             now
           )

    refute SealedDailyAggregatePublic.limited?(%{aggregate | limited_reason: "bad"}, now)
    refute SealedDailyAggregatePublic.limited?(%{aggregate | sold_out_15_30_day_count: 99}, now)
  end

  defp ready(now) do
    %{
      id: "aggregate-1",
      sealed_product_id: "product-1",
      aggregate_date: DateTime.to_date(now),
      calculation_version: SealedDailyAggregateCalculator.version(),
      currency: "PLN",
      status: "ready",
      limited_reason: nil,
      benchmark_pln: Decimal.new("100"),
      typical_low_pln: Decimal.new("90"),
      typical_high_pln: Decimal.new("110"),
      fresh_regular_retailer_count: 5,
      fresh_lgs_count: 1,
      recent_sold_out_0_14_day_count: 1,
      sold_out_15_30_day_count: 1,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: 7,
      latest_nonfuture_checked_at: DateTime.add(now, -3600),
      calculated_at: now,
      source_mapping_confident: true,
      source_msrp_pln: nil,
      source_evidence: []
    }
  end
end
