defmodule TcgCheap.Pricing.Singles.ValuationHistoryTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.{SingleValuationSnapshot, ValuationHistory}

  @now ~U[2026-08-07 12:00:00Z]

  test "projects exactly the current date and preceding 29 UTC dates" do
    snapshots = [
      snapshot_at(~U[2026-07-08 23:59:59Z], "1.00"),
      snapshot_at(~U[2026-07-09 00:00:00Z], "2.00"),
      snapshot_at(~U[2026-08-07 12:00:00Z], "3.00"),
      snapshot_at(~U[2026-08-07 12:00:01Z], "4.00")
    ]

    assert ValuationHistory.window_start(@now) == ~U[2026-07-09 00:00:00Z]

    assert ValuationHistory.daily_points(snapshots, @now) == [
             %ValuationHistory.Point{
               date: ~D[2026-07-09],
               fetched_at: ~U[2026-07-09 00:00:00Z],
               value_eur: Decimal.new("2.00")
             },
             %ValuationHistory.Point{
               date: ~D[2026-08-07],
               fetched_at: ~U[2026-08-07 12:00:00Z],
               value_eur: Decimal.new("3.00")
             }
           ]
  end

  test "chooses the latest snapshot in each day, preserves gaps, and keeps decimals" do
    snapshots = [
      snapshot_at(~U[2026-07-11 08:00:00Z], "10.10"),
      snapshot_at(~U[2026-07-11 19:00:00Z], "20.20"),
      snapshot_at(~U[2026-07-13 09:00:00Z], "30.30")
    ]

    assert [first, second] = ValuationHistory.daily_points(snapshots, @now)
    assert first.date == ~D[2026-07-11]
    assert first.fetched_at == ~U[2026-07-11 19:00:00Z]
    assert Decimal.equal?(first.value_eur, Decimal.new("20.20"))
    assert second.date == ~D[2026-07-13]
    assert Decimal.equal?(second.value_eur, Decimal.new("30.30"))
  end

  test "uses later created_at when fetched_at timestamps are equal" do
    fetched_at = ~U[2026-07-15 12:00:00Z]

    snapshots = [
      snapshot_at(fetched_at, "10.10", created_at: ~U[2026-07-15 12:00:01Z], id: "older"),
      snapshot_at(fetched_at, "20.20", created_at: ~U[2026-07-15 12:00:02Z], id: "newer")
    ]

    assert [%ValuationHistory.Point{value_eur: value}] =
             ValuationHistory.daily_points(snapshots, @now)

    assert Decimal.equal?(value, Decimal.new("20.20"))
  end

  test "uses stable id when fetched_at and created_at timestamps are equal" do
    fetched_at = ~U[2026-07-16 12:00:00Z]
    created_at = ~U[2026-07-16 12:00:01Z]

    snapshots = [
      snapshot_at(fetched_at, "10.10", created_at: created_at, id: "id-a"),
      snapshot_at(fetched_at, "20.20", created_at: created_at, id: "id-b")
    ]

    reversed = Enum.reverse(snapshots)

    assert [%ValuationHistory.Point{value_eur: first_value}] =
             ValuationHistory.daily_points(snapshots, @now)

    assert [%ValuationHistory.Point{value_eur: second_value}] =
             ValuationHistory.daily_points(reversed, @now)

    assert Decimal.equal?(first_value, Decimal.new("20.20"))
    assert Decimal.equal?(second_value, Decimal.new("20.20"))
  end

  defp snapshot_at(fetched_at, value, attrs \\ []) do
    struct(
      %SingleValuationSnapshot{fetched_at: fetched_at, value_eur: Decimal.new(value)},
      attrs
    )
  end
end
