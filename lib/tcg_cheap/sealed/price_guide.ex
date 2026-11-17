defmodule TcgCheap.Sealed.PriceGuide do
  alias TcgCheap.Sealed.Market

  @moduledoc """
  Judges the cheapest price you can buy a product at right now, twice.

  `verdict/4` is the guide's answer: is it a good price today? The typical
  price is the median of today's shops' item prices, one per shop (its lowest
  in-stock item price, the product alone, without delivery), when at least 3
  shops have the product. The cheapest offer is the lowest compared price: a
  shop abroad's with delivery. A price
  is good up to 95% of it, normal up to 110%, and expensive above that, so
  the cheapest offer is good when it clearly undercuts the typical shop.
  A good price must also be at most 95% of each known reference: the usual
  price of the last 30 days (see `past/3`) and the Cardmarket trend with
  shipping to Poland, in PLN. The good limit is the lowest of these
  (`good_limits` has each). Both limits are rounded down to the market's
  step, so a price seen in a physical shop can be judged against the shown
  limits directly and no price above 95%/110% of the typical one is rated
  better than it is.

  Prices and references are in one market's currency (`TcgCheap.Sealed.Market`;
  złoty and PLN above are Poland's): the limits are whole units where a unit
  is small (złoty, forints, kronor), and 0.10 euro in a euro market.

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
  @deal_min_ratio Decimal.new("0.6")

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
          good_max: integer() | Decimal.t() | nil,
          good_limits: %{optional(:shops | :past | :cardmarket) => integer() | Decimal.t()},
          normal_max: integer() | Decimal.t() | nil
        }
  @type past :: %{
          status: past_status(),
          typical: Decimal.t() | nil,
          days_with_stock: non_neg_integer(),
          good_max: integer() | Decimal.t() | nil,
          normal_max: integer() | Decimal.t() | nil,
          last_known: %{price: Decimal.t(), date: Date.t()} | nil
        }

  def min_shops, do: @min_shops
  def window_days, do: @window_days
  def min_days_with_stock, do: @min_days_with_stock

  @doc """
  Today's verdict for a product given its current in-stock offers (each
  `price` its compared price; an offer that carries an `item_price`, as
  `Market.compared/3` makes it, has the typical price taken from that, else
  from `price`), the
  Cardmarket trend in PLN (the comparison with fewer shops) and the
  references a good price must also undercut: `past:` the usual price
  (`usual/2`) and `cardmarket:` the Cardmarket trend with shipping in PLN,
  each nil when unknown.
  """
  @spec verdict(
          [offer()],
          Decimal.t() | nil,
          [{:past | :cardmarket, Decimal.t() | nil}],
          Market.t()
        ) ::
          t()
  def verdict(in_stock_offers, cardmarket_price, references, market \\ Market.poland()) do
    shop_prices =
      in_stock_offers
      |> Enum.group_by(& &1.shop, & &1.price)
      |> Enum.map(fn {shop, prices} -> %{shop: shop, price: Enum.min(prices, Decimal)} end)
      |> Enum.sort_by(& &1.price, Decimal)

    # A shop's lowest item price, as `shop_prices` has its lowest compared
    # one. They are the same offer unless free delivery from some order value
    # makes a dearer offer the cheaper one delivered.
    item_prices =
      in_stock_offers
      |> Enum.group_by(& &1.shop, &Map.get(&1, :item_price, &1.price))
      |> Enum.map(fn {_shop, prices} -> Enum.min(prices, Decimal) end)

    {typical, source} =
      cond do
        length(shop_prices) >= @min_shops -> {median(item_prices), :shops}
        match?(%Decimal{}, cardmarket_price) -> {cardmarket_price, :cardmarket}
        true -> {nil, nil}
      end

    cheapest = Enum.min_by(in_stock_offers, & &1.price, Decimal, fn -> nil end)

    limits =
      if source == :shops,
        do: typical |> limits(market) |> with_good_limits(references, market),
        else: Map.put(limits(nil, market), :good_limits, %{})

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
  @spec past([day()], offer() | nil, Date.t(), Market.t()) :: past()
  def past(history, cheapest, %Date{} = today, market \\ Market.poland()) do
    prices = window_prices(history, today)
    typical = usual_of(prices)
    limits = limits(typical, market)

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

  @doc """
  How many whole percent `price` is under `reference`; `nil` when it is not
  under it or rounds to 0 %, so that no "-0%" is shown.
  """
  @spec discount_percent(Decimal.t(), Decimal.t()) :: pos_integer() | nil
  def discount_percent(price, reference) do
    if Decimal.lt?(price, reference) do
      percent =
        Decimal.new(1)
        |> Decimal.sub(Decimal.div(price, reference))
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      if percent > 0, do: percent
    end
  end

  @doc """
  The least a deal's price may be of its reference: more than 40% under it, an
  offer is more often matched to the wrong product (half a booster box, a
  promo's other print) than a real deal.
  """
  @spec deal_min_ratio() :: Decimal.t()
  def deal_min_ratio, do: @deal_min_ratio

  defp window_prices(history, today) do
    window_start = Date.add(today, -(@window_days - 1))

    for %{date: date, lowest_price: %Decimal{} = price} <- history,
        Date.compare(date, window_start) != :lt and Date.compare(date, today) != :gt,
        do: price
  end

  defp usual_of(prices), do: if(length(prices) >= @min_days_with_stock, do: median(prices))

  # A good price is good against every known reference.
  defp with_good_limits(limits, references, market) do
    good_limits =
      for {source, %Decimal{} = price} <- references,
          into: %{shops: limits.good_max},
          do: {source, good_max(price, market)}

    Map.merge(limits, %{
      good_max: good_limits |> Map.values() |> Enum.min(Decimal),
      good_limits: good_limits
    })
  end

  defp limits(nil, _market), do: %{good_max: nil, normal_max: nil}

  defp limits(typical, market),
    do: %{
      good_max: good_max(typical, market),
      normal_max: floor_limit(Decimal.mult(typical, @normal_factor), market)
    }

  defp good_max(typical, market), do: floor_limit(Decimal.mult(typical, @good_factor), market)

  defp floor_limit(value, market) do
    case Market.limit_step(market) do
      1 ->
        whole_zloty(value)

      %Decimal{} = step ->
        value |> Decimal.div(step) |> Decimal.round(0, :floor) |> Decimal.mult(step)
    end
  end

  @doc "Rates a price against a verdict's (or past's) limits, naming the three outcomes."
  def rate(price, %{good_max: good_max, normal_max: normal_max}, {good, normal, expensive}) do
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
