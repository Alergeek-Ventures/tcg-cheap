defmodule TcgCheap.Cards.Reference do
  @moduledoc """
  Single-card reference: Cardmarket trend (trend_holo for reverse) with the
  market's realistic delivery: the cheaper domestic/German method whose
  published maximum covers the trend. Special patterns are separate products
  without a reference here. Missing or zero prices, and trends above the
  published shipping ladder, have no delivered reference.
  """
  alias TcgCheap.Sealed.Market

  @type method ::
          :letter
          | :tracked_letter
          | :insured_letter
          | :tracked_parcel
          | :insured_parcel
          | :insured_courier_estimate
  @type tier :: {Decimal.t(), Decimal.t(), method()}

  @doc "The first published shipping tier whose maximum covers the trend."
  @spec shipping_tier(Decimal.t(), Market.t()) :: tier() | nil
  def shipping_tier(trend, %Market{} = market) do
    Enum.find(market.cardmarket_letter_tiers, fn {limit, _cost, _method} ->
      Decimal.lte?(trend, limit)
    end)
  end

  @doc "The selected tier's method class."
  @spec shipping_method(Decimal.t(), Market.t()) :: method() | nil
  def shipping_method(trend, %Market{} = market) do
    with {_limit, _cost, method} <- shipping_tier(trend, market), do: method
  end

  @doc "The selected tier's total Cardmarket Price, including packaging."
  @spec shipping_eur(Decimal.t(), Market.t()) :: Decimal.t() | nil
  def shipping_eur(trend, %Market{} = market) do
    with {_limit, cost, _method} <- shipping_tier(trend, market), do: cost
  end

  @spec delivered_eur(Decimal.t() | nil, Market.t()) :: Decimal.t() | nil
  def delivered_eur(%Decimal{} = trend, %Market{} = market) do
    with true <- Decimal.gt?(trend, 0),
         %Decimal{} = shipping <- shipping_eur(trend, market) do
      Decimal.add(trend, shipping)
    else
      _unknown -> nil
    end
  end

  def delivered_eur(nil, _market), do: nil

  @spec pln(map() | nil, atom(), map() | nil) :: Decimal.t() | nil
  def pln(price, variant, rate), do: in_market(price, variant, rate, Market.poland())

  @doc "The reference in the market's currency, at the euro's `rate` there (`Market.cardmarket_rate/2`)."
  @spec in_market(map() | nil, atom(), map() | nil, Market.t()) :: Decimal.t() | nil
  def in_market(_price, :special, _rate, _market), do: nil
  def in_market(nil, _variant, _rate, _market), do: nil

  def in_market(price, variant, rate, market) do
    trend = if variant == :reverse, do: price.trend_holo, else: price.trend
    trend |> delivered_eur(market) |> Market.in_market(rate, market)
  end

  @doc """
  The reference without delivery, for a market whose card prices have none
  either (`Shops.own_singles?/1`) or whose trend exceeds the published
  shipping ladder: the bare trend in the market's currency.
  """
  @spec bare_in_market(map() | nil, atom(), map() | nil, Market.t()) :: Decimal.t() | nil
  def bare_in_market(_price, :special, _rate, _market), do: nil
  def bare_in_market(nil, _variant, _rate, _market), do: nil

  def bare_in_market(price, variant, rate, market) do
    trend = if variant == :reverse, do: price.trend_holo, else: price.trend
    if trend && Decimal.positive?(trend), do: Market.in_market(trend, rate, market)
  end
end
