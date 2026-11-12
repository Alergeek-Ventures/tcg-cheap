defmodule TcgCheap.Sealed.CheckedCardmarketIds do
  @moduledoc """
  Cardmarket product ids checked by hand for cards TCGdex links wrongly,
  from `priv/cardmarket/card_ids.tsv`: a TCGdex card id, the Cardmarket
  product it is (empty when no product can be told apart) and the evidence.

  TCGdex gives some printings of a set one id (a common and its secret rare,
  a holo and non-holo rare, two trainer kit halves) and points some sets at
  another set's products, which showed one card another's price. The list
  was checked on 2026-11-12 against Cardmarket's singles catalogue (a
  product's name carries the card's attacks), the Cardmarket link and price
  Limitless TCG shows for each card number, and pokemontcg.io's Cardmarket
  prices. `TcgCheap.Sealed.CardSync` applies it over TCGdex's answers.
  """

  @path Path.expand("../../../priv/cardmarket/card_ids.tsv", __DIR__)
  @external_resource @path

  @ids @path
       |> File.read!()
       |> String.split("\n", trim: true)
       |> Enum.reject(&String.starts_with?(&1, "#"))
       |> Map.new(fn line ->
         [card, product | _evidence] = String.split(line, "\t")
         {card, if(product == "", do: nil, else: String.to_integer(product))}
       end)

  @doc "The checked product id of a TCGdex card (nil: none), or :error when it was not checked."
  @spec fetch(String.t()) :: {:ok, pos_integer() | nil} | :error
  def fetch(tcgdex_id), do: Map.fetch(@ids, tcgdex_id)

  @doc "Every checked TCGdex card id with its product id."
  @spec all() :: %{String.t() => pos_integer() | nil}
  def all, do: @ids
end
