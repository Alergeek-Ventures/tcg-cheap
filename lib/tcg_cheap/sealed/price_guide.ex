defmodule TcgCheap.Sealed.PriceGuide do
  @moduledoc """
  Judges the cheapest price you can buy a product at right now, twice.

  `verdict/3` is the guide's answer: is it a good price today? The typical
  price is the median of today's shop prices, one per shop (its lowest
  in-stock offer, a shop abroad's with delivery), when at least 3 shops have the product. A price
  is good up to 95% of it, normal up to 110%, and expensive above that, so
  the cheapest offer is good when it clearly undercuts the typical shop.
  A good price must also be at most 95% of each known reference: the usual
  price of the last 30 days (see `past/3`) and the Cardmarket trend with
  shipping to Poland, in PLN. The good limit is the lowest of these
  (`good_limits` has each). Both limits are rounded down to whole złoty, so
  a price seen in a physical shop can be judged against the shown limits
  directly and no price above 95%/110% of the typical one is rated better
  than it is.

  With fewer shops the price is only compared with the Cardmarket trend
  converted to PLN with the latest NBP rate (`:cardmarket`, no limits): a
  European price without shipping would make almost every Polish price look
  expensive. Without either there is not enough data. The verdict is never
  anchored on an official (MSRP) price: only prices you can actually buy at
  count.

  `past/3` shows the history, as on flight price graphs: is it a good price
  for this product historically? The usual price (`usual/2`) is the median
  of the daily lowest in-stock price over the last 30 days, counting only
  days when some shop had stock, when there are at least 7 such days; the
  same 95%/110% limits make it `:low`, `:usual` or `:high`. Beyond the good
  limit above it does not change the verdict.
  """

  @min_shops 3
  @window_days 30
  @min_days_with_stock 7
  @good_factor Decimal.new("0.95")
  @normal_factor Decimal.new("1.10")

  @type status ::
          :good | :normal | :expensive | :cardmarket | :insufficient_data | :out_of_stock
  @type past_status :: :low | :usual | :high | :insufficient_data | :out_of_stock
  @type day :: %{required(:date) => Date.t(), required(:lowest_price) => Decimal.t() | nil}
  @type offer :: %{
          required(:price) => Decimal.t(),
          required(:shop) => String.t(),
          optional(atom()) => term()
        }
  @type t :: %{
          status: status(),
          cheapest: offer() | nil,
          shop_prices: [%{shop: String.t(), price: Decimal.t()}],
          typical: Decimal.t() | nil,
          typical_source: :shops | :cardmarket | nil,
          good_max: integer() | nil,
          good_limits: %{optional(:shops | :past | :cardmarket) => integer()},
          normal_max: integer() | nil
        }
  @type past :: %{
          status: past_status(),
          typical: Decimal.t() | nil,
          days_with_stock: non_neg_integer(),
          good_max: integer() | nil,
          normal_max: integer() | nil,
          last_known: %{price: Decimal.t(), date: Date.t()} | nil
        }

  def min_shops, do: @min_shops
  def window_days, do: @window_days
  def min_days_with_stock, do: @min_days_with_stock

  @doc """
  Today's verdict for a product given its current in-stock offers, the
  Cardmarket trend in PLN (the comparison with fewer shops) and the
  references a good price must also undercut: `past:` the usual price
  (`usual/2`) and `cardmarket:` the Cardmarket trend with shipping in PLN,
  each nil when unknown.
  """
  @spec verdict([offer()], Decimal.t() | nil, [{:past | :cardmarket, Decimal.t() | nil}]) :: t()
  def verdict(in_stock_offers, cardmarket_pln, references) do
    shop_prices =
      in_stock_offers
      |> Enum.group_by(& &1.shop, & &1.price)
      |> Enum.map(fn {shop, prices} -> %{shop: shop, price: Enum.min(prices, Decimal)} end)
      |> Enum.sort_by(& &1.price, Decimal)

    {typical, source} =
      cond do
        length(shop_prices) >= @min_shops -> {median(Enum.map(shop_prices, & &1.price)), :shops}
        match?(%Decimal{}, cardmarket_pln) -> {cardmarket_pln, :cardmarket}
        true -> {nil, nil}
      end

    cheapest = Enum.min_by(in_stock_offers, & &1.price, Decimal, fn -> nil end)

    limits =
      if source == :shops,
        do: typical |> limits() |> with_good_limits(references),
        else: Map.put(limits(nil), :good_limits, %{})

    status =
      cond do
        cheapest == nil -> :out_of_stock
        typical == nil -> :insufficient_data
        source == :cardmarket -> :cardmarket
        true -> rate(cheapest.price, limits, {:good, :normal, :expensive})
      end

    Map.merge(limits, %{
      status: status,
      cheapest: cheapest,
      shop_prices: shop_prices,
      typical: typical,
      typical_source: source
    })
  end

  @doc """
  How the cheapest current offer (nil when out of stock) compares with the
  product's daily history up to `today`.
  """
  @spec past([day()], offer() | nil, Date.t()) :: past()
  def past(history, cheapest, %Date{} = today) do
    prices = window_prices(history, today)
    typical = usual_of(prices)
    limits = limits(typical)

    status =
      cond do
        cheapest == nil -> :out_of_stock
        typical == nil -> :insufficient_data
        true -> rate(cheapest.price, limits, {:low, :usual, :high})
      end

    Map.merge(limits, %{
      status: status,
      typical: typical,
      days_with_stock: length(prices),
      last_known: last_known(history)
    })
  end

  @doc """
  The usual price up to `today`: the median daily lowest in-stock price of
  the last 30 days, or nil with fewer than 7 days with stock.
  """
  @spec usual([day()], Date.t()) :: Decimal.t() | nil
  def usual(history, %Date{} = today), do: history |> window_prices(today) |> usual_of()

  defp window_prices(history, today) do
    window_start = Date.add(today, -(@window_days - 1))

    for %{date: date, lowest_price: %Decimal{} = price} <- history,
        Date.compare(date, window_start) != :lt and Date.compare(date, today) != :gt,
        do: price
  end

  defp usual_of(prices), do: if(length(prices) >= @min_days_with_stock, do: median(prices))

  # A good price is good against every known reference.
  defp with_good_limits(limits, references) do
    good_limits =
      for {source, %Decimal{} = price} <- references,
          into: %{shops: limits.good_max},
          do: {source, good_max(price)}

    Map.merge(limits, %{
      good_max: good_limits |> Map.values() |> Enum.min(),
      good_limits: good_limits
    })
  end

  defp limits(nil), do: %{good_max: nil, normal_max: nil}

  defp limits(typical),
    do: %{
      good_max: good_max(typical),
      normal_max: whole_zloty(Decimal.mult(typical, @normal_factor))
    }

  defp good_max(typical), do: whole_zloty(Decimal.mult(typical, @good_factor))

  defp rate(price, %{good_max: good_max, normal_max: normal_max}, {good, normal, expensive}) do
    cond do
      Decimal.compare(price, good_max) != :gt -> good
      Decimal.compare(price, normal_max) != :gt -> normal
      true -> expensive
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
