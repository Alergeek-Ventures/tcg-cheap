defmodule TcgCheap.Sealed.PriceGuide do
  @moduledoc """
  Judges the cheapest price you can buy a product at right now.

  The typical price is the median of the daily lowest in-stock price in
  Polish shops over the last 30 days, counting only days when some shop had
  stock, when there are at least 7 such days. A price is good up to 95% of
  it, normal up to 110%, and expensive above that. Both limits are rounded
  down to whole złoty, so a price seen in a physical shop can be judged
  against the shown limits directly and no price above 95%/110% of the
  typical one is rated better than it is.

  Before that the price is only compared with the Cardmarket trend converted
  to PLN with the latest NBP rate (`:cardmarket`, no limits): a European
  price without shipping would make almost every Polish price look
  expensive. Without either there is not enough data. The verdict is never
  anchored on an official (MSRP) price: only prices you can actually buy at
  count.
  """

  @window_days 30
  @min_days_with_stock 7
  @good_factor Decimal.new("0.95")
  @normal_factor Decimal.new("1.10")

  @type status ::
          :good | :normal | :expensive | :cardmarket | :insufficient_data | :out_of_stock
  @type day :: %{required(:date) => Date.t(), required(:lowest_price) => Decimal.t() | nil}
  @type offer :: %{required(:price) => Decimal.t(), optional(atom()) => term()}
  @type t :: %{
          status: status(),
          cheapest: offer() | nil,
          typical: Decimal.t() | nil,
          typical_source: :shops | :cardmarket | nil,
          days_with_stock: non_neg_integer(),
          good_max: integer() | nil,
          normal_max: integer() | nil,
          last_known: %{price: Decimal.t(), date: Date.t()} | nil
        }

  def window_days, do: @window_days
  def min_days_with_stock, do: @min_days_with_stock

  @doc """
  The verdict for a product given its daily history, its current in-stock
  offers on `today`, and the Cardmarket trend in PLN used as a fallback.
  """
  @spec verdict([day()], [offer()], Date.t(), Decimal.t() | nil) :: t()
  def verdict(history, in_stock_offers, %Date{} = today, cardmarket_pln \\ nil) do
    window_start = Date.add(today, -(@window_days - 1))

    prices =
      for %{date: date, lowest_price: %Decimal{} = price} <- history,
          Date.compare(date, window_start) != :lt and Date.compare(date, today) != :gt,
          do: price

    {typical, source} =
      cond do
        length(prices) >= @min_days_with_stock -> {median(prices), :shops}
        match?(%Decimal{}, cardmarket_pln) -> {cardmarket_pln, :cardmarket}
        true -> {nil, nil}
      end

    cheapest = Enum.min_by(in_stock_offers, & &1.price, Decimal, fn -> nil end)

    base = %{
      status: nil,
      cheapest: cheapest,
      typical: typical,
      typical_source: source,
      days_with_stock: length(prices),
      good_max: if(source == :shops, do: whole_zloty(Decimal.mult(typical, @good_factor))),
      normal_max: if(source == :shops, do: whole_zloty(Decimal.mult(typical, @normal_factor))),
      last_known: last_known(history)
    }

    %{base | status: status(cheapest, base)}
  end

  defp status(nil, _base), do: :out_of_stock
  defp status(_cheapest, %{typical: nil}), do: :insufficient_data
  defp status(_cheapest, %{typical_source: :cardmarket}), do: :cardmarket

  defp status(%{price: price}, %{good_max: good_max, normal_max: normal_max}) do
    cond do
      Decimal.compare(price, good_max) != :gt -> :good
      Decimal.compare(price, normal_max) != :gt -> :normal
      true -> :expensive
    end
  end

  defp median(prices) do
    sorted = Enum.sort(prices, Decimal)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle)
    else
      sorted |> Enum.slice(middle - 1, 2) |> Enum.reduce(&Decimal.add/2) |> Decimal.div(2)
    end
  end

  defp whole_zloty(value), do: value |> Decimal.round(0, :floor) |> Decimal.to_integer()

  defp last_known(history) do
    history
    |> Enum.filter(&match?(%{lowest_price: %Decimal{}}, &1))
    |> Enum.max_by(& &1.date, Date, fn -> nil end)
    |> case do
      nil -> nil
      day -> %{price: day.lowest_price, date: day.date}
    end
  end
end
