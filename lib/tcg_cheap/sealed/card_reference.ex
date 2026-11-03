defmodule TcgCheap.Sealed.CardReference do
  @moduledoc """
  Single-card reference: Cardmarket trend (trend_holo for reverse), delivered
  to Poland. Up to and including €25 a German letter costs €1.55; above it
  a registered letter from Poland costs €2.80. Special patterns are separate
  products without a reference here. Missing or zero prices stay unknown.
  """
  alias TcgCheap.Sealed.Guide

  @spec delivered_eur(Decimal.t() | nil) :: Decimal.t() | nil
  def delivered_eur(%Decimal{} = trend) do
    if Decimal.gt?(trend, 0) do
      shipping = if Decimal.gt?(trend, 25), do: "2.80", else: "1.55"
      Decimal.add(trend, Decimal.new(shipping))
    end
  end

  def delivered_eur(nil), do: nil

  @spec pln(map() | nil, atom(), map() | nil) :: Decimal.t() | nil
  def pln(_price, :special, _rate), do: nil
  def pln(nil, _variant, _rate), do: nil

  def pln(price, variant, rate) do
    trend = if variant == :reverse, do: price.trend_holo, else: price.trend
    trend |> delivered_eur() |> Guide.to_pln(rate)
  end
end
