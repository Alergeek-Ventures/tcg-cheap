defmodule TcgCheap.Pricing.SealedBuyingModelTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.SealedBuyingModel
  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @as_of ~U[2026-01-31 12:00:00Z]

  test "publishes version, fixed weights, confidence targets, and rounding policy" do
    policy = SealedBuyingModel.policy()

    assert SealedBuyingModel.version() == "sealed_buying_model_v1"
    assert policy.version == SealedBuyingModel.version()
    assert policy.component_weights.regular_benchmark == Decimal.new("0.55")
    assert policy.confidence.regular_coverage_target == 8
    assert policy.confidence.history_points_target == 3
    assert policy.confidence.history_span_days_target == 7
    assert policy.confidence.lgs_support_target == 2
    assert policy.confidence.sold_out_support_target == 2
    assert policy.confidence.ready_threshold == Decimal.new("0.65")
    assert policy.rounding == %{scale: 2, mode: :half_up}
    assert :low_confidence in SealedBuyingModel.limited_reasons()
    assert policy.arithmetic_context.precision == 34
    assert policy.arithmetic_context.rounding == :half_up
    assert policy.arithmetic_context.emax == 6144
    assert policy.arithmetic_context.emin == -6143
  end

  test "calculation uses fixed Decimal arithmetic and restores the caller context" do
    input = %{
      current_aggregate: ready(fresh_lgs_count: 2, recent_sold_out_0_14_day_count: 2),
      msrp_pln: d("120"),
      lgs_price_evidence: [lgs("shop-b", "101"), lgs("shop-a", "99")],
      sold_out_price_evidence: [
        sold("sold-b", "95", @as_of),
        sold("sold-a", "97", @as_of)
      ]
    }

    baseline = calculate(input)
    original = Decimal.Context.get()
    low_precision = %{original | precision: 6, rounding: :down}
    high_precision = %{original | precision: 50, rounding: :half_even}

    for context <- [low_precision, high_precision] do
      Decimal.Context.with(context, fn ->
        assert calculate(input) == baseline
        assert Decimal.Context.get() == context
      end)
    end

    assert Decimal.Context.get() == original
  end

  test "band intervals state their inclusive ceilings and exclusive floors" do
    assert {:ok, %{buying_bands: [great, fair, expensive, avoid]}} =
             calculate(%{current_aggregate: ready(), history: history()})

    assert great.min_price_pln == nil
    assert great.max_inclusive? and not great.min_inclusive?
    assert fair.min_price_pln == great.max_price_pln
    assert fair.max_price_pln != nil
    assert fair.max_inclusive? and not fair.min_inclusive?
    assert expensive.min_price_pln == fair.max_price_pln
    assert expensive.max_inclusive? and not expensive.min_inclusive?
    assert avoid.min_price_pln == expensive.max_price_pln
    assert avoid.max_price_pln == nil
    assert not avoid.min_inclusive?
  end

  test "rejects malformed, wrong-version, nonfinite, and future aggregate data" do
    assert {:error, :malformed_aggregate} = calculate(%{current_aggregate: %{}})

    assert {:error, :malformed_aggregate} =
             calculate(%{current_aggregate: ready(calculation_version: "wrong")})

    assert {:error, :malformed_aggregate} =
             calculate(%{current_aggregate: ready(benchmark_pln: Decimal.new("NaN"))})

    assert {:error, :malformed_aggregate} =
             calculate(%{current_aggregate: ready(aggregate_date: ~D[2026-02-01])})

    assert {:error, :malformed_aggregate} =
             calculate(%{
               current_aggregate: ready(latest_nonfuture_checked_at: ~U[2026-02-01 00:00:00Z])
             })

    assert {:error, :malformed_aggregate} =
             calculate(%{
               current_aggregate: ready(calculated_at: DateTime.add(@as_of, 1, :second))
             })

    assert {:error, :malformed_aggregate} =
             calculate(%{
               current_aggregate: ready(calculated_at: ~U[2026-01-30 12:00:00Z])
             })
  end

  test "requires coherent ready and limited aggregate state" do
    assert {:error, :malformed_aggregate} =
             calculate(%{current_aggregate: ready(fresh_regular_retailer_count: 4)})

    assert {:error, :malformed_aggregate} =
             calculate(%{current_aggregate: limited(benchmark_pln: d("100"))})

    assert {:ok,
            %{
              status: "limited",
              limited_reason: :limited_market_aggregate,
              great_price_max_pln: nil
            }} = calculate(%{current_aggregate: limited()})
  end

  test "uses exact hard limited-reason precedence" do
    assert {:ok,
            %{status: "limited", limited_reason: :uncertain_mapping, great_price_max_pln: nil}} =
             calculate(%{
               current_aggregate: limited(latest_nonfuture_checked_at: ~U[2026-01-01 00:00:00Z]),
               mapping_confident?: false,
               history: []
             })

    assert {:ok, %{limited_reason: :limited_market_aggregate}} =
             calculate(%{
               current_aggregate: limited(latest_nonfuture_checked_at: ~U[2026-01-01 00:00:00Z]),
               history: []
             })

    assert {:ok, %{limited_reason: :stale_market_evidence}} =
             calculate(%{
               current_aggregate: ready(latest_nonfuture_checked_at: ~U[2026-01-01 00:00:00Z]),
               history: []
             })

    assert {:ok, %{limited_reason: :insufficient_history}} =
             calculate(%{
               current_aggregate: ready(fresh_regular_retailer_count: 5),
               history: []
             })

    assert {:ok, %{limited_reason: :low_confidence}} =
             calculate(%{
               current_aggregate: ready(fresh_regular_retailer_count: 5),
               history: history()
             })
  end

  test "accepts aggregate evidence exactly seven days old but not one second older" do
    exact = DateTime.add(@as_of, -7 * 86_400, :second)
    stale = DateTime.add(@as_of, -(7 * 86_400 + 1), :second)

    assert {:ok, %{status: "ready"}} =
             calculate(%{
               current_aggregate: ready(latest_nonfuture_checked_at: exact),
               history: history()
             })

    assert {:ok, %{status: "limited", limited_reason: :stale_market_evidence}} =
             calculate(%{
               current_aggregate: ready(latest_nonfuture_checked_at: stale),
               history: history()
             })
  end

  test "uncertain mapping wins over limited, stale, history, and confidence reasons" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate: limited(latest_nonfuture_checked_at: ~U[2025-01-01 00:00:00Z]),
               mapping_confident?: false,
               history: []
             })

    assert result.status == "limited"
    assert result.limited_reason == :uncertain_mapping
  end

  test "limited no-evidence aggregate accepts nil timestamp and reports limited market data" do
    assert {:ok, result} =
             calculate(%{current_aggregate: limited(latest_nonfuture_checked_at: nil)})

    assert result.limited_reason == :limited_market_aggregate

    assert result.explanation_factors == [
             "market_data_limited",
             "trend_insufficient_history",
             "availability_balanced",
             "availability_trend_insufficient_history"
           ]
  end

  test "accepts exact history duplicates and rejects conflicts with the current date" do
    duplicate = ready()

    input = %{
      current_aggregate: ready(),
      history: [
        duplicate,
        ready(aggregate_date: ~D[2026-01-24], benchmark_pln: d("90")),
        ready(aggregate_date: ~D[2026-01-17], benchmark_pln: d("95"))
      ]
    }

    assert {:ok, result} = calculate(input)
    assert result.status == "ready"
    assert Decimal.compare(result.trend_change, d("0.05")) == :gt

    assert {:error, :conflicting_history_projection} =
             calculate(%{
               current_aggregate: ready(),
               history: [ready(aggregate_date: ~D[2026-01-31], benchmark_pln: d("99"))]
             })
  end

  test "uses insufficient-history trend and nil change below hard history requirements" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate: ready(benchmark_pln: d("105")),
               history: [ready(aggregate_date: ~D[2026-01-24])]
             })

    assert result.status == "limited"
    assert result.limited_reason == :insufficient_history
    assert result.trend == "insufficient_history"
    assert is_nil(result.trend_change)
  end

  test "classifies exact plus and minus five percent trend thresholds" do
    rising =
      calculate(%{
        current_aggregate: ready(benchmark_pln: d("105")),
        history: [
          ready(aggregate_date: ~D[2026-01-24], benchmark_pln: d("100")),
          ready(aggregate_date: ~D[2026-01-17], benchmark_pln: d("100"))
        ]
      })

    falling =
      calculate(%{
        current_aggregate: ready(benchmark_pln: d("95")),
        history: [
          ready(aggregate_date: ~D[2026-01-24], benchmark_pln: d("100")),
          ready(aggregate_date: ~D[2026-01-17], benchmark_pln: d("100"))
        ]
      })

    assert {:ok, %{trend: "rising"}} = rising
    assert {:ok, %{trend: "falling"}} = falling
  end

  test "rejects future history dates rather than silently dropping them" do
    assert {:error, :malformed_aggregate} =
             calculate(%{
               current_aggregate: ready(),
               history: [ready(aggregate_date: ~D[2026-02-01])]
             })
  end

  test "rejects future sold-out evidence" do
    assert {:error, :future_evidence} =
             calculate(%{
               current_aggregate: ready(),
               sold_out_price_evidence: [sold("future", "90", DateTime.add(@as_of, 1, :second))]
             })
  end

  test "rejects contradictory same-time sold-out retailer evidence" do
    rows = [
      sold("ambiguous", "90", DateTime.add(@as_of, -86_400, :second)),
      sold("ambiguous", "91", DateTime.add(@as_of, -86_400, :second))
    ]

    assert {:error, :ambiguous_sold_out_evidence} =
             calculate(%{
               current_aggregate: ready(recent_sold_out_0_14_day_count: 1),
               sold_out_price_evidence: rows
             })
  end

  test "duplicate and older sold-out evidence do not inflate confidence support" do
    evidence = [
      sold("same", "90", DateTime.add(@as_of, -86_400, :second)),
      sold("same", "90", DateTime.add(@as_of, -86_400, :second)),
      sold("old", "80", DateTime.add(@as_of, -31 * 86_400, :second))
    ]

    assert {:ok, result} =
             calculate(%{
               current_aggregate: ready(recent_sold_out_0_14_day_count: 1),
               history: history(),
               sold_out_price_evidence: evidence
             })

    assert result.confidence == d("0.75")
  end

  test "weights sold-out prices at inclusive 14 and 30 day boundaries and deduplicates retailers" do
    evidence = [
      sold("r1", "80", @as_of |> DateTime.add(-14 * 86_400, :second)),
      sold("r2", "100", @as_of |> DateTime.add(-(14 * 86_400 + 1), :second)),
      sold("r3", "120", @as_of |> DateTime.add(-30 * 86_400, :second)),
      sold("r4", "200", @as_of |> DateTime.add(-(30 * 86_400 + 1), :second)),
      sold("r1", "90", @as_of |> DateTime.add(-(14 * 86_400 - 1), :second))
    ]

    assert {:ok, result} =
             calculate(%{
               current_aggregate:
                 ready(
                   recent_sold_out_0_14_day_count: 1,
                   sold_out_15_30_day_count: 2
                 ),
               sold_out_price_evidence: evidence
             })

    assert result.component_centers.sold_out_center == d("98.24")
  end

  test "retains snapshot sold-out evidence when the model runs days after aggregation" do
    current =
      ready(
        aggregate_date: ~D[2026-01-25],
        sold_out_15_30_day_count: 1
      )

    input = %{
      current_aggregate: current,
      history: [
        ready(aggregate_date: ~D[2026-01-18]),
        ready(aggregate_date: ~D[2026-01-11])
      ],
      msrp_pln: nil,
      lgs_price_evidence: [],
      sold_out_price_evidence: [
        sold("thirty-day", "80", DateTime.add(current.calculated_at, -30 * 86_400, :second))
      ],
      mapping_confident?: true
    }

    assert {:ok, result} = SealedBuyingModel.calculate(input, @as_of)
    assert result.status == "ready"
    assert result.component_centers.sold_out_center == d("80.00")
  end

  test "ignores nil-price sold-out support in the center but retains valid support" do
    evidence = [
      sold("nil", nil, DateTime.add(@as_of, -86_400, :second)),
      sold("valid", "80", DateTime.add(@as_of, -86_400, :second))
    ]

    assert {:ok, result} =
             calculate(%{
               current_aggregate: ready(recent_sold_out_0_14_day_count: 2),
               sold_out_price_evidence: evidence
             })

    assert result.component_centers.sold_out_center == d("80.00")
  end

  test "renormalizes reference weights when optional components are absent" do
    assert {:ok, result} = calculate(%{current_aggregate: ready(), history: history()})
    assert result.reference_price_pln == d("100.00")
    refute Map.has_key?(result.component_centers, :msrp)
  end

  test "rejects excessive LGS evidence and nonfinite optional prices" do
    assert {:error, :invalid_lgs_evidence} =
             calculate(%{
               current_aggregate: ready(fresh_lgs_count: 1),
               lgs_price_evidence: [lgs("a", "10"), lgs("b", "11")]
             })

    assert {:error, :invalid_price} =
             calculate(%{current_aggregate: ready(), msrp_pln: Decimal.new("Infinity")})

    assert {:error, :invalid_lgs_evidence} =
             calculate(%{current_aggregate: ready(fresh_lgs_count: 1), lgs_price_evidence: []})

    assert {:error, :sold_out_count_mismatch} =
             calculate(%{
               current_aggregate: ready(recent_sold_out_0_14_day_count: 1),
               sold_out_price_evidence: []
             })
  end

  test "validates LGS evidence against the aggregate snapshot" do
    current = ready(fresh_lgs_count: 1)

    assert {:error, :invalid_lgs_evidence} =
             calculate(%{
               current_aggregate: ready(fresh_lgs_count: 2),
               lgs_price_evidence: [lgs("same", "10"), lgs("same", "11")]
             })

    for evidence <- [
          [%{retailer_id: "", price_pln: d("10"), checked_at: current.calculated_at}],
          [
            %{
              retailer_id: "extra",
              price_pln: d("10"),
              checked_at: current.calculated_at,
              source: "unexpected"
            }
          ],
          [lgs("future", "10", DateTime.add(current.calculated_at, 1, :second))],
          [lgs("stale", "10", DateTime.add(current.calculated_at, -(7 * 86_400 + 1), :second))],
          [lgs("one", "10"), lgs("two", "11")]
        ] do
      assert {:error, :invalid_lgs_evidence} =
               calculate(%{current_aggregate: current, lgs_price_evidence: evidence})
    end

    assert {:ok, result} =
             calculate(%{
               current_aggregate: current,
               lgs_price_evidence: [
                 lgs("exact", "10", DateTime.add(current.calculated_at, -7 * 86_400, :second))
               ]
             })

    assert Decimal.equal?(result.component_centers.lgs_median, d("10.00"))
  end

  test "publishes four explicit buying bands and fails closed after rounding collisions" do
    assert {:ok, ready_result} = calculate(%{current_aggregate: ready(), history: history()})
    assert Enum.map(ready_result.buying_bands, & &1.key) == [:great, :fair, :expensive, :avoid]
    assert Enum.at(ready_result.buying_bands, 0).min_price_pln == nil
    assert Enum.at(ready_result.buying_bands, 3).max_price_pln == nil

    low_input = %{
      current_aggregate:
        ready(
          benchmark_pln: d("0.01"),
          typical_low_pln: d("0.01"),
          typical_high_pln: d("0.01")
        ),
      history: history(benchmark: "0.01", typical_low: "0.01", typical_high: "0.01")
    }

    assert {:ok, limited_result} = calculate(low_input)

    assert limited_result.status == "limited"
    assert limited_result.limited_reason == :invalid_band_boundaries

    assert Enum.all?(
             [:great_price_max_pln, :fair_price_max_pln, :expensive_price_max_pln],
             &is_nil(Map.get(limited_result, &1))
           )

    assert limited_result.buying_bands == []
  end

  test "complete ready scenario includes every optional center" do
    current = ready(fresh_lgs_count: 2, recent_sold_out_0_14_day_count: 2)

    assert {:ok, result} =
             calculate(%{
               current_aggregate: current,
               msrp_pln: d("120"),
               lgs_price_evidence: [lgs("shop-b", "101"), lgs("shop-a", "99")],
               sold_out_price_evidence: [
                 sold("sold-b", "95", current.calculated_at),
                 sold("sold-a", "97", current.calculated_at)
               ]
             })

    assert result.status == "ready"
    assert Map.has_key?(result.component_centers, :regular_benchmark)
    assert Map.has_key?(result.component_centers, :msrp)
    assert Map.has_key?(result.component_centers, :lgs_median)
    assert Map.has_key?(result.component_centers, :sold_out_center)
  end

  test "accepts history through 30 days but excludes 30 days plus one calendar day" do
    assert {:ok, included} =
             calculate(%{
               current_aggregate: ready(),
               history: [
                 ready(aggregate_date: ~D[2026-01-24]),
                 ready(aggregate_date: ~D[2026-01-01])
               ]
             })

    assert included.trend == "stable"

    assert {:ok, excluded} =
             calculate(%{
               current_aggregate: ready(),
               history: [
                 ready(aggregate_date: ~D[2026-01-24]),
                 ready(aggregate_date: ~D[2025-12-31])
               ]
             })

    assert excluded.limited_reason == :insufficient_history
  end

  test "deduplicated sold-out buckets cannot exceed unique source retailers" do
    assert {:error, :malformed_aggregate} =
             calculate(%{
               current_aggregate:
                 ready(unique_source_retailer_count: 8, recent_sold_out_0_14_day_count: 9)
             })

    assert {:error, :malformed_aggregate} =
             calculate(%{
               current_aggregate:
                 ready(
                   unique_source_retailer_count: 8,
                   recent_sold_out_0_14_day_count: 5,
                   sold_out_15_30_day_count: 5
                 )
             })
  end

  test "history and evidence permutations produce identical results" do
    sold_out = [
      sold("second", "90", DateTime.add(@as_of, -2 * 86_400, :second)),
      sold("first", "80", DateTime.add(@as_of, -86_400, :second))
    ]

    input = %{
      current_aggregate: ready(recent_sold_out_0_14_day_count: 2),
      history: history(),
      sold_out_price_evidence: sold_out
    }

    assert {:ok, result} = calculate(input)

    assert {:ok, ^result} =
             calculate(%{
               input
               | history: Enum.reverse(input.history),
                 sold_out_price_evidence: Enum.reverse(sold_out)
             })
  end

  test "rounds Decimal reference and produces strict ordered boundaries" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate:
                 ready(typical_low_pln: d("90.01"), typical_high_pln: d("110.01")),
               history: history(),
               msrp_pln: d("101.01")
             })

    assert result.reference_price_pln == d("100.32")
    assert Decimal.compare(result.great_price_max_pln, result.fair_price_max_pln) == :lt
    assert Decimal.compare(result.fair_price_max_pln, result.expensive_price_max_pln) == :lt
  end

  test "synthetic policy fixture: widely available below MSRP" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate: ready(fresh_regular_retailer_count: 10),
               msrp_pln: d("130"),
               history: history()
             })

    assert result.status == "ready"
    assert Decimal.equal?(result.confidence, d("0.80"))
    assert Decimal.equal?(result.reference_price_pln, d("109.38"))
    assert Decimal.equal?(result.great_price_max_pln, d("90.00"))
    assert Decimal.equal?(result.fair_price_max_pln, d("111.57"))
    assert Decimal.equal?(result.expensive_price_max_pln, d("127.97"))
    assert result.availability == "abundant"
    assert Decimal.compare(result.reference_price_pln, d("130")) == :lt

    assert result.explanation_factors == [
             "market_benchmark",
             "msrp",
             "trend_stable",
             "availability_abundant",
             "availability_trend_improving"
           ]
  end

  test "synthetic policy fixture: widely available around MSRP" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate: ready(benchmark_pln: d("100")),
               msrp_pln: d("100"),
               history: history()
             })

    assert result.status == "ready"
    assert Decimal.equal?(result.confidence, d("0.80"))
    assert Decimal.equal?(result.reference_price_pln, d("100.00"))
    assert Decimal.equal?(result.great_price_max_pln, d("88.00"))
    assert Decimal.equal?(result.fair_price_max_pln, d("103.00"))
    assert Decimal.equal?(result.expensive_price_max_pln, d("118.00"))

    assert result.explanation_factors == [
             "market_benchmark",
             "msrp",
             "trend_stable",
             "availability_abundant",
             "availability_trend_stable"
           ]
  end

  test "synthetic policy fixture: scarce and rising after lower offers sold out" do
    current =
      ready(
        fresh_regular_retailer_count: 5,
        recent_sold_out_0_14_day_count: 4,
        benchmark_pln: d("110")
      )

    assert {:ok, result} =
             calculate(%{
               current_aggregate: current,
               history: history(benchmark: "100"),
               msrp_pln: d("120"),
               sold_out_price_evidence: [
                 sold("s1", "90", @as_of),
                 sold("s2", "92", @as_of),
                 sold("s3", "94", @as_of),
                 sold("s4", "96", @as_of)
               ]
             })

    assert result.status == "ready"
    assert Decimal.equal?(result.confidence, d("0.79"))
    assert Decimal.equal?(result.reference_price_pln, d("110.89"))
    assert Decimal.equal?(result.great_price_max_pln, d("90.00"))
    assert Decimal.equal?(result.fair_price_max_pln, d("121.98"))
    assert Decimal.equal?(result.expensive_price_max_pln, d("138.61"))
    assert result.availability == "scarce"
    assert result.availability_trend == "tightening"
    assert result.trend == "rising"
    assert "sold_out" in result.explanation_factors
    assert result.component_centers.sold_out_center == d("93.00")
  end

  test "synthetic policy fixture: one cheap regular-retailer outlier is removed upstream" do
    current = aggregate_from_regular_prices(["1", "100", "100", "100", "100", "100"])

    assert {:ok, result} = calculate(%{current_aggregate: current, msrp_pln: d("100")})
    assert result.reference_price_pln == d("100.00")
    assert result.component_centers.regular_benchmark == d("100.00")
    assert result.status == "ready"
  end

  test "synthetic policy fixture: one expensive regular-retailer outlier is removed upstream" do
    current = aggregate_from_regular_prices(["100", "100", "100", "100", "100", "1000"])

    assert {:ok, result} = calculate(%{current_aggregate: current, msrp_pln: d("100")})
    assert result.reference_price_pln == d("100.00")
    assert result.component_centers.regular_benchmark == d("100.00")
    assert result.status == "ready"
  end

  test "synthetic policy fixture: falling reprint remains ready with falling trend" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate: ready(benchmark_pln: d("95")),
               history: history(benchmark: "100"),
               msrp_pln: d("120")
             })

    assert result.status == "ready"
    assert Decimal.equal?(result.confidence, d("0.80"))
    assert Decimal.equal?(result.reference_price_pln, d("102.81"))
    assert Decimal.equal?(result.great_price_max_pln, d("88.42"))
    assert Decimal.equal?(result.fair_price_max_pln, d("103.84"))
    assert Decimal.equal?(result.expensive_price_max_pln, d("119.26"))
    assert result.trend == "falling"
  end

  test "synthetic policy fixture: new release with little history is limited" do
    assert {:ok, result} =
             calculate(%{current_aggregate: ready(), history: [], msrp_pln: d("100")})

    assert result.status == "limited"
    assert result.limited_reason == :insufficient_history
  end

  test "synthetic policy fixture: one active shop is limited by the aggregate" do
    assert {:ok, result} =
             calculate(%{
               current_aggregate:
                 limited(
                   fresh_regular_retailer_count: 1,
                   limited_reason: "too_few_regular_retailers"
                 ),
               history: history()
             })

    assert result.status == "limited"
    assert result.limited_reason == :limited_market_aggregate

    assert Enum.all?(
             [
               result.great_price_max_pln,
               result.fair_price_max_pln,
               result.expensive_price_max_pln
             ],
             &is_nil/1
           )
  end

  test "synthetic policy fixture: discontinued or sporadic weak stock is low confidence" do
    current = ready(fresh_regular_retailer_count: 5, fresh_lgs_count: 0)

    assert {:ok, result} =
             calculate(%{current_aggregate: current, history: history(), msrp_pln: nil})

    assert result.status == "limited"
    assert result.limited_reason == :low_confidence
  end

  defp calculate(overrides) do
    input = %{
      current_aggregate: ready(),
      history: history(),
      msrp_pln: nil,
      lgs_price_evidence: [],
      sold_out_price_evidence: [],
      mapping_confident?: true
    }

    SealedBuyingModel.calculate(Map.merge(input, overrides), @as_of)
  end

  defp history(opts \\ []) do
    benchmark = Keyword.get(opts, :benchmark, "100")
    typical_low = Keyword.get(opts, :typical_low, "90")
    typical_high = Keyword.get(opts, :typical_high, "110")

    [
      ready(
        aggregate_date: ~D[2026-01-24],
        benchmark_pln: d(benchmark),
        typical_low_pln: d(typical_low),
        typical_high_pln: d(typical_high)
      ),
      ready(
        aggregate_date: ~D[2026-01-17],
        benchmark_pln: d(benchmark),
        typical_low_pln: d(typical_low),
        typical_high_pln: d(typical_high)
      )
    ]
  end

  defp ready(overrides \\ []) do
    date = Keyword.get(overrides, :aggregate_date, ~D[2026-01-31])

    merged =
      Map.merge(
        %{
          status: "ready",
          calculation_version: "sealed_market_daily_v1",
          currency: "PLN",
          limited_reason: nil,
          aggregate_date: ~D[2026-01-31],
          benchmark_pln: d("100"),
          typical_low_pln: d("90"),
          typical_high_pln: d("110"),
          fresh_regular_retailer_count: 8,
          fresh_lgs_count: 0,
          recent_sold_out_0_14_day_count: 0,
          sold_out_15_30_day_count: 0,
          stale_or_future_current_offer_count: 0,
          unique_source_retailer_count: 8,
          calculated_at: DateTime.new!(date, ~T[12:00:00]),
          latest_nonfuture_checked_at: DateTime.new!(date, ~T[12:00:00])
        },
        Map.new(overrides)
      )

    calculated_at = Keyword.get(overrides, :calculated_at, DateTime.new!(date, ~T[12:00:00]))

    merged
    |> Map.put(
      :unique_source_retailer_count,
      max(
        merged.fresh_regular_retailer_count + merged.fresh_lgs_count,
        merged.unique_source_retailer_count
      )
    )
    |> Map.put(:calculated_at, calculated_at)
  end

  defp limited(overrides \\ []) do
    Map.merge(
      ready(
        status: "limited",
        limited_reason: "no_fresh_current_offers",
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil,
        fresh_regular_retailer_count: 0
      ),
      Map.new(overrides)
    )
  end

  defp sold(retailer, price, checked_at),
    do: %{
      retailer_id: retailer,
      price_pln: if(is_nil(price), do: nil, else: d(price)),
      checked_at: checked_at
    }

  defp lgs(retailer, price, checked_at \\ @as_of),
    do: %{retailer_id: retailer, price_pln: d(price), checked_at: checked_at}

  defp aggregate_from_regular_prices(prices) do
    offers =
      prices
      |> Enum.with_index()
      |> Enum.map(fn {price, index} ->
        %{
          listing: %{
            stock_status: "in_stock",
            current_price_pln: d(price),
            last_checked_at: @as_of
          },
          retailer: %{id: "regular-#{index}", category: "regular_retailer"}
        }
      end)

    {:ok, aggregate} =
      SealedDailyAggregateCalculator.calculate(%{current: offers, sold_out: []}, @as_of)

    aggregate
  end

  defp d(value), do: Decimal.new(to_string(value))
end
