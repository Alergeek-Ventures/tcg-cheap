defmodule TcgCheap.Pricing.SealedMarketHistoryTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.{SealedDailyAggregateCalculator, SealedMarketHistory}

  @now ~U[2026-08-09 12:00:00Z]
  @product_id "11111111-1111-1111-1111-111111111111"

  test "empty and malformed input produces no points" do
    assert SealedMarketHistory.build([], @product_id, @now).points == []

    result =
      SealedMarketHistory.build([nil, %{}, %{aggregate_date: "not a date"}], @product_id, @now)

    assert result.points == []
    assert result.benchmark_paths == []
    assert result.range_paths == []
    assert SealedMarketHistory.build([], "not-an-id", @now).points == []
  end

  test "rejects rows belonging to another product" do
    assert SealedMarketHistory.build(
             [row(~D[2026-08-09], 10, 8, 12)],
             "22222222-2222-2222-2222-222222222222",
             @now
           ).points == []
  end

  test "rejects invalid version, currency, missing checked timestamp, and incoherent counts" do
    valid = row(~D[2026-08-09], 10, 8, 12)

    invalid = [
      %{valid | calculation_version: "old"},
      %{valid | currency: "EUR"},
      %{valid | latest_nonfuture_checked_at: nil},
      %{valid | fresh_regular_retailer_count: 4},
      %{valid | unique_source_retailer_count: 4},
      %{valid | recent_sold_out_0_14_day_count: 4, sold_out_15_30_day_count: 2}
    ]

    assert SealedMarketHistory.build(invalid, @product_id, @now).points == []
  end

  test "rejects invalid price ordering and nonfinite prices" do
    valid = row(~D[2026-08-09], 10, 8, 12)

    invalid = [
      %{valid | typical_low_pln: Decimal.new("11")},
      %{valid | typical_high_pln: Decimal.new("9")},
      %{valid | benchmark_pln: Decimal.new("NaN")},
      %{valid | typical_high_pln: Decimal.new("Inf")}
    ]

    assert SealedMarketHistory.build(invalid, @product_id, @now).points == []
  end

  test "keeps exact origin and today boundaries, excludes outside and future dates" do
    origin = row(~D[2026-07-11], 10, 8, 12)
    today = row(~D[2026-08-09], 20, 18, 22)
    outside = row(~D[2026-07-10], 30, 28, 32)
    future = %{today | aggregate_date: ~D[2026-08-10], calculated_at: @now}

    result = SealedMarketHistory.build([outside, origin, today, future], @product_id, @now)

    assert Enum.map(result.points, & &1.date) == [~D[2026-07-11], ~D[2026-08-09]]
    assert Enum.map(result.plot_points, & &1.x) == [5, 295]
  end

  test "chooses latest calculated row and breaks equal timestamps by greatest id" do
    old = row(~D[2026-08-01], 10, 8, 12) |> Map.put(:id, "a")

    newer = %{
      old
      | calculated_at: ~U[2026-08-01 13:00:00Z],
        latest_nonfuture_checked_at: ~U[2026-08-01 13:00:00Z],
        benchmark_pln: Decimal.new("11")
    }

    tie_low = %{
      newer
      | id: "b",
        benchmark_pln: Decimal.new("12"),
        typical_high_pln: Decimal.new("20")
    }

    tie_high = %{
      newer
      | id: "c",
        benchmark_pln: Decimal.new("13"),
        typical_high_pln: Decimal.new("20")
    }

    result = SealedMarketHistory.build([old, newer, tie_low, tie_high], @product_id, @now)

    assert [%{benchmark_pln: benchmark}] = result.points
    assert Decimal.equal?(benchmark, Decimal.new("13"))
  end

  test "splits paths at every missing day" do
    rows = [row(~D[2026-08-01], 10, 8, 12), row(~D[2026-08-03], 20, 18, 22)]
    result = SealedMarketHistory.build(rows, @product_id, @now)

    assert length(result.benchmark_paths) == 2
    assert length(result.range_paths) == 2
  end

  test "equal-valued one-point geometry uses the midpoint" do
    result = SealedMarketHistory.build([row(~D[2026-08-08], 5, 5, 5)], @product_id, @now)

    assert [%{benchmark_y: 60, low_y: 60, high_y: 60}] = result.plot_points
  end

  defp row(date, benchmark, low, high) do
    calculated_at = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

    %{
      id: Ecto.UUID.generate(),
      sealed_product_id: @product_id,
      aggregate_date: date,
      calculation_version: SealedDailyAggregateCalculator.version(),
      currency: "PLN",
      status: "ready",
      limited_reason: nil,
      benchmark_pln: Decimal.new(benchmark),
      typical_low_pln: Decimal.new(low),
      typical_high_pln: Decimal.new(high),
      fresh_regular_retailer_count: 5,
      fresh_lgs_count: 0,
      recent_sold_out_0_14_day_count: 0,
      sold_out_15_30_day_count: 0,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: 5,
      calculated_at: calculated_at,
      latest_nonfuture_checked_at: calculated_at
    }
  end
end
