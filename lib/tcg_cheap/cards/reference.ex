defmodule TcgCheap.Cards.Reference do
  @moduledoc """
  Single-card reference: Cardmarket trend (trend_holo for reverse) with
  delivery, one rule for every market. Up to and including €25 a German
  letter costs €1.55; above it a registered letter from Poland costs €2.80.
  Special patterns are separate products without a reference here. Missing
  or zero prices stay unknown.
  """
  alias TcgCheap.Sealed.Market

  @spec delivered_eur(Decimal.t() | nil) :: Decimal.t() | nil
  def delivered_eur(%Decimal{} = trend) do
    if Decimal.gt?(trend, 0) do
      shipping = if Decimal.gt?(trend, 25), do: "2.80", else: "1.55"
      Decimal.add(trend, Decimal.new(shipping))
    end
  end

  def delivered_eur(nil), do: nil

  @spec pln(map() | nil, atom(), map() | nil) :: Decimal.t() | nil
  def pln(price, variant, rate), do: in_market(price, variant, rate, Market.poland())

  @doc "The reference in the market's currency, at the euro's `rate` there (`Market.cardmarket_rate/2`)."
  @spec in_market(map() | nil, atom(), map() | nil, Market.t()) :: Decimal.t() | nil
  def in_market(_price, :special, _rate, _market), do: nil
  def in_market(nil, _variant, _rate, _market), do: nil

  def in_market(price, variant, rate, market) do
    trend = if variant == :reverse, do: price.trend_holo, else: price.trend
    trend |> delivered_eur() |> Market.in_market(rate, market)
  end
end
