defmodule TcgCheap.Cards.Reference do
  @moduledoc """
  Single-card reference: Cardmarket trend (trend_holo for reverse) with the
  market's realistic letter delivery: the cheaper domestic/German untracked
  letter through €25, then its cheapest domestic tracked letter. Special
  patterns are separate products without a reference here. Missing or zero
  prices stay unknown.
  """
  alias TcgCheap.Sealed.Market

  @tracked_from Decimal.new("25")

  @doc "Whether Cardmarket's order-value rule requires tracked shipping."
  @spec tracking_required?(Decimal.t()) :: boolean()
  def tracking_required?(trend), do: Decimal.gt?(trend, @tracked_from)

  @doc "The market's letter Price, including Cardmarket's packaging fee."
  @spec shipping_eur(Decimal.t(), Market.t()) :: Decimal.t()
  def shipping_eur(trend, %Market{} = market) do
    if tracking_required?(trend),
      do: market.cardmarket_tracked_letter_eur,
      else: market.cardmarket_untracked_letter_eur
  end

  @spec delivered_eur(Decimal.t() | nil, Market.t()) :: Decimal.t() | nil
  def delivered_eur(%Decimal{} = trend, %Market{} = market) do
    if Decimal.gt?(trend, 0), do: Decimal.add(trend, shipping_eur(trend, market))
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
  either (`Shops.own_singles?/1`): the bare trend in the market's currency.
  """
  @spec bare_in_market(map() | nil, atom(), map() | nil, Market.t()) :: Decimal.t() | nil
  def bare_in_market(_price, :special, _rate, _market), do: nil
  def bare_in_market(nil, _variant, _rate, _market), do: nil

  def bare_in_market(price, variant, rate, market) do
    trend = if variant == :reverse, do: price.trend_holo, else: price.trend
    if trend && Decimal.positive?(trend), do: Market.in_market(trend, rate, market)
  end
end
