defmodule TcgCheap.Pricing.SealedDailyAggregateCalculatorTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @as_of ~U[2026-08-09 12:00:00Z]

  test "publishes the calculation policy used by the aggregate" do
    assert SealedDailyAggregateCalculator.minimum_fresh_regular_retailers() == 5
    policy = SealedDailyAggregateCalculator.policy()
    assert policy.minimum_regular_prices == 5
    assert policy.minimum_inliers == 3
    assert policy.freshness_days == 7
    assert policy.outlier_policy == %{method: :tukey_iqr, iqr_multiplier: Decimal.new("1.5")}
    assert policy.center == :median
    assert policy.range == :inlier_min_max
    assert policy.rounding == %{scale: 2, mode: :half_up}
    assert policy.freshness == %{max_age_days: 7, future_checked_at?: false, boundary: :inclusive}
  end

  test "requires five fresh regular-retailer prices" do
    assert {:ok, result} = calculate(["1", "2", "3", "4"])
    assert result.status == "limited"
    assert result.limited_reason == "too_few_regular_retailers"

    assert {:ok, ready} = calculate(["1", "2", "3", "4", "5"])
    assert ready.status == "ready"
    assert Decimal.equal?(ready.benchmark_pln, Decimal.new("3.00"))
  end

  test "rounds benchmark and range half up" do
    assert {:ok, result} = calculate(["1.005", "1.005", "1.005", "1.005", "1.005"])
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("1.01"))
    assert Decimal.equal?(result.typical_low_pln, Decimal.new("1.01"))
    assert Decimal.equal?(result.typical_high_pln, Decimal.new("1.01"))
  end

  test "equal prices and category separation work" do
    offers = Enum.map(1..5, &offer("r#{&1}", "10")) ++ [offer("lgs", "1", "lgs")]
    assert {:ok, result} = calculate_offers(offers)
    assert result.fresh_regular_retailer_count == 5
    assert result.fresh_lgs_count == 1
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("10.00"))
  end

  test "counts each fresh retailer once and uses its cheapest listing" do
    offers =
      [offer("duplicate", "9.5"), offer("duplicate", "9")] ++
        [offer("r1", "9.5")] ++ Enum.map(2..4, &offer("r#{&1}", "10"))

    assert {:ok, result} = calculate_offers(offers)
    assert result.fresh_regular_retailer_count == 5
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("10.00"))
    assert Decimal.equal?(result.typical_low_pln, Decimal.new("9.00"))
  end

  test "a stale cheap duplicate cannot hide a fresh listing" do
    offers =
      [offer("duplicate", "1", "regular_retailer", days_ago: 8), offer("duplicate", "10")] ++
        Enum.map(1..4, &offer("r#{&1}", "10"))

    assert {:ok, result} = calculate_offers(offers)
    assert result.fresh_regular_retailer_count == 5
    assert result.stale_or_future_current_offer_count == 1
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("10.00"))
  end

  test "removes Tukey outliers before calculating the range" do
    assert {:ok, result} = calculate(["10", "10", "10", "10", "1000", "10"])
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("10.00"))
    assert Decimal.equal?(result.typical_low_pln, Decimal.new("10.00"))
    assert Decimal.equal?(result.typical_high_pln, Decimal.new("10.00"))
  end

  test "removes a cheap Tukey outlier as well as an expensive one" do
    assert {:ok, result} = calculate(["1", "10", "10", "10", "10", "10"])
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("10.00"))
    assert Decimal.equal?(result.typical_low_pln, Decimal.new("10.00"))
    assert Decimal.equal?(result.typical_high_pln, Decimal.new("10.00"))
  end

  test "deduplicates a retailer across current and sold-out evidence" do
    current = Enum.map(1..5, &offer("r#{&1}", "10"))
    current = [offer("same-retailer", "10") | tl(current)]
    sold_out = [sold_out_offer("same-retailer", 86_400)]

    assert {:ok, result} = calculate_offers(current, sold_out)
    assert result.unique_source_retailer_count == 5
    assert result.latest_nonfuture_checked_at == @as_of
  end

  test "counts sold-out evidence at inclusive 14 and 30 day boundaries" do
    sold_out = [
      sold_out_offer("recent", 0),
      sold_out_offer("boundary-recent", 14 * 86_400),
      sold_out_offer("older", 14 * 86_400 + 1),
      sold_out_offer("boundary-older", 30 * 86_400),
      sold_out_offer("too-old", 30 * 86_400 + 1),
      sold_out_offer("future", -1)
    ]

    assert {:ok, result} = calculate_offers(Enum.map(1..5, &offer("r#{&1}", "10")), sold_out)
    assert result.recent_sold_out_0_14_day_count == 2
    assert result.sold_out_15_30_day_count == 2
  end

  test "counts only the latest sold-out listing for each retailer" do
    sold_out = [
      sold_out_offer("same-retailer", 20 * 86_400),
      sold_out_offer("same-retailer", 2 * 86_400),
      sold_out_offer("another-retailer", 16 * 86_400)
    ]

    assert {:ok, result} =
             calculate_offers(Enum.map(1..5, &offer("r#{&1}", "10")), sold_out)

    assert result.recent_sold_out_0_14_day_count == 1
    assert result.sold_out_15_30_day_count == 1
    assert result.unique_source_retailer_count == 7
  end

  test "counts stale and future current offers but excludes them from prices" do
    stale = offer("stale", "1", "regular_retailer", days_ago: 8)
    future = offer("future", "2", "regular_retailer", offset: 60)
    fresh = Enum.map(1..5, &offer("r#{&1}", "10"))
    assert {:ok, result} = calculate_offers(fresh ++ [stale, future])
    assert result.fresh_regular_retailer_count == 5
    assert result.stale_or_future_current_offer_count == 2
    assert Decimal.equal?(result.benchmark_pln, Decimal.new("10.00"))
  end

  test "rejects malformed categories, statuses, prices, and projections" do
    assert {:error, :malformed_current_offer} = calculate_offers([offer("r", "1", "unknown")])
    assert {:error, :malformed_current_offer} = calculate_offers([offer("r", "NaN")])
    assert {:error, :malformed_current_offer} = calculate_offers([offer("r", "0")])
    assert {:error, :malformed_projection} = SealedDailyAggregateCalculator.calculate(%{}, @as_of)
  end

  test "rejects contradictory categories for one retailer across evidence" do
    current = [offer("same-retailer", "10", "regular_retailer")]
    sold_out = [sold_out_offer("same-retailer", 86_400, "lgs")]

    assert {:error, :conflicting_retailer_categories} = calculate_offers(current, sold_out)
  end

  defp calculate(prices),
    do:
      calculate_offers(
        Enum.with_index(prices)
        |> Enum.map(fn {price, index} -> offer("r#{index}", price) end)
      )

  defp calculate_offers(current, sold_out \\ []),
    do: SealedDailyAggregateCalculator.calculate(%{current: current, sold_out: sold_out}, @as_of)

  defp offer(id, price, category \\ "regular_retailer", opts \\ []) do
    checked =
      @as_of
      |> DateTime.add(Keyword.get(opts, :offset, 0), :second)
      |> DateTime.add(-Keyword.get(opts, :days_ago, 0), :day)

    %{
      listing: %{
        stock_status: "in_stock",
        current_price_pln: Decimal.new(price),
        last_checked_at: checked
      },
      retailer: %{id: id, category: category}
    }
  end

  defp sold_out_offer(id, age, category \\ "regular_retailer"),
    do: %{
      listing: %{
        stock_status: "sold_out",
        current_price_pln: nil,
        last_checked_at: DateTime.add(@as_of, -age, :second)
      },
      retailer: %{id: id, category: category}
    }
end
