defmodule TcgCheap.Sealed.PriceGuideTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Sealed.PriceGuide

  @today ~D[2026-10-30]

  defp days(prices, today \\ @today) do
    prices
    |> Enum.with_index()
    |> Enum.map(fn {price, index} ->
      %{date: Date.add(today, -index), lowest_price: price && Decimal.new(price)}
    end)
  end

  defp offer(price), do: %{price: Decimal.new(price), shop: "colligere"}

  # Seven stocked days with a median of exactly 640.
  @history ~w(620 630 640 640 640 650 660)

  test "good up to 95% of the typical price, in whole złoty" do
    verdict = PriceGuide.verdict(days(@history), [offer("608.99"), offer("700")], @today)

    assert verdict.status == :good
    assert Decimal.equal?(verdict.typical, 640)
    assert verdict.good_max == 608
    assert verdict.normal_max == 704
    assert verdict.days_with_stock == 7
    assert Decimal.equal?(verdict.cheapest.price, "608.99")
  end

  test "normal from the first złoty above the good limit up to 110%" do
    assert PriceGuide.verdict(days(@history), [offer("609")], @today).status == :normal
    assert PriceGuide.verdict(days(@history), [offer("704.99")], @today).status == :normal
  end

  test "expensive above 110%" do
    assert PriceGuide.verdict(days(@history), [offer("705")], @today).status == :expensive
  end

  test "the median of an even number of days averages the middle two" do
    verdict =
      PriceGuide.verdict(days(~w(100 100 100 100 200 200 200 200)), [offer("150")], @today)

    assert Decimal.equal?(verdict.typical, 150)
  end

  test "insufficient data with fewer than 7 stocked days, still showing the cheapest offer" do
    verdict = PriceGuide.verdict(days(~w(620 630 640 650 660 670)), [offer("600")], @today)

    assert verdict.status == :insufficient_data
    assert verdict.typical == nil
    assert verdict.good_max == nil
    assert verdict.days_with_stock == 6
    assert Decimal.equal?(verdict.cheapest.price, 600)
  end

  test "days without stock do not count towards the typical price" do
    history = days([nil, nil, "640", nil, "640", "640", "640", "640", "640"])
    assert PriceGuide.verdict(history, [offer("640")], @today).status == :insufficient_data

    history = days(["640" | List.duplicate(nil, 5)] ++ List.duplicate("640", 6))
    assert PriceGuide.verdict(history, [offer("640")], @today).status == :normal
  end

  test "only the last 30 days count" do
    old = Enum.map(30..40, &%{date: Date.add(@today, -&1), lowest_price: Decimal.new(100)})
    verdict = PriceGuide.verdict(days(~w(640 640 640)) ++ old, [offer("640")], @today)

    assert verdict.status == :insufficient_data
    assert verdict.days_with_stock == 3

    edge = %{date: Date.add(@today, -29), lowest_price: Decimal.new(640)}

    assert PriceGuide.verdict([edge | days(~w(640 640 640 640 640 640))], [offer("1")], @today).days_with_stock ==
             7
  end

  test "future days are ignored" do
    future = days(@history, Date.add(@today, 10))
    assert PriceGuide.verdict(future, [offer("640")], @today).days_with_stock == 0
  end

  test "out of stock reports the last known lowest price and its date" do
    history = days([nil, nil, "512.50", "500"])
    verdict = PriceGuide.verdict(history, [], @today)

    assert verdict.status == :out_of_stock
    assert verdict.cheapest == nil
    assert Decimal.equal?(verdict.last_known.price, "512.50")
    assert verdict.last_known.date == Date.add(@today, -2)
  end

  test "out of stock keeps the thresholds when the history is long enough" do
    verdict = PriceGuide.verdict(days([nil | @history]), [], @today)
    assert verdict.status == :out_of_stock
    assert verdict.good_max == 608
  end

  test "out of stock with no history at all" do
    assert %{status: :out_of_stock, last_known: nil, typical: nil} =
             PriceGuide.verdict([], [], @today)
  end
end
