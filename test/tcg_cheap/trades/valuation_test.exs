defmodule TcgCheap.Trades.ValuationTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot
  alias TcgCheap.Trades.{Composition, Valuation}

  @now ~U[2026-01-08 12:00:00Z]

  test "multiplies Decimal unit values by quantities without floats" do
    evaluation = evaluate([{"a", 3}], [{"a", "1.25"}])
    row = evaluation.left.rows |> hd()

    assert row.unit_value == Decimal.new("1.25")
    assert row.row_value == Decimal.new("3.75")
    assert evaluation.left.known_total == Decimal.new("3.75")
  end

  test "compares equal totals with different Decimal exponents" do
    evaluation = evaluate([{"a", 1}], [{"a", "1.0"}], [{"b", 1}], [{"b", "1.00"}])
    assert evaluation.comparison == :equal
  end

  test "reports the higher side and absolute Decimal difference" do
    evaluation = evaluate([{"a", 2}], [{"a", "2.50"}], [{"b", 1}], [{"b", "3.00"}])
    assert evaluation.comparison == {:higher, :left, Decimal.new("2.00")}
  end

  test "empty or incomplete sides cannot be compared" do
    assert evaluate([], []).comparison == :incomplete
    assert evaluate([{"unknown", 1}], []).comparison == :incomplete
  end

  test "counts every unvalued copy, including unknown identifiers" do
    evaluation = evaluate([{"unknown", 2}, {"missing-price", 3}], [])
    assert evaluation.left.unvalued_quantity == 5
    assert evaluation.left.complete? == false
    assert evaluation.left.known_total == Decimal.new(0)
  end

  test "stale valuations remain included in arithmetic" do
    stale = valuation("4.20", DateTime.add(@now, -8, :day))
    evaluation = evaluate([{"a", 2}], [{"a", stale}])
    row = hd(evaluation.left.rows)

    assert row.status == :stale
    assert row.row_value == Decimal.new("8.40")
    assert evaluation.left.known_total == Decimal.new("8.40")
    assert evaluation.left.complete?
  end

  defp evaluate(left, left_cards, right \\ [], right_cards \\ []) do
    cards = Map.new(left_cards ++ right_cards, fn {id, value} -> {id, card(value)} end)
    Valuation.evaluate(%Composition{left: left, right: right}, cards, @now)
  end

  defp card(%SingleValuationSnapshot{} = valuation),
    do: %{tcgdex_cardmarket_v1_current_valuation: valuation}

  defp card(value), do: card(valuation(value, DateTime.add(@now, -1, :hour)))

  defp valuation(value, fetched_at),
    do: struct!(SingleValuationSnapshot, value_eur: Decimal.new(value), fetched_at: fetched_at)
end
