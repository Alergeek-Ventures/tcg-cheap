defmodule TcgCheap.Sealed.AgentTools.Json do
  @moduledoc "Plain JSON-ready maps of offers, products, contents, suggested prices and sets for the agent tools."

  alias TcgCheap.Sealed.{
    CardReference,
    Offer,
    Product,
    ProductContents,
    PullRates,
    Shops,
    SuggestedPrice,
    TcgdexSet
  }

  @product_fields [
    :id,
    :slug,
    :name,
    :kind,
    :set_name,
    :cardmarket_id,
    :cardmarket_expansion_id,
    :eans
  ]

  @spec offer(Offer.t()) :: map()
  def offer(%Offer{} = offer) do
    %{
      id: offer.id,
      shop: offer.shop,
      shop_name: Shops.name(offer.shop),
      title: offer.title,
      price: offer.price,
      in_stock: offer.in_stock,
      preorder: offer.preorder,
      ean: offer.ean,
      url: offer.url,
      manual: offer.manual?,
      product_id: offer.product_id,
      last_seen_at: offer.last_seen_at
    }
    |> put_product(offer.product)
  end

  @doc "The product fields `product/1` reads."
  @spec product_fields() :: [atom()]
  def product_fields, do: @product_fields

  @spec product(Product.t() | nil) :: map() | nil
  def product(nil), do: nil
  def product(%Product{} = product), do: Map.take(product, @product_fields)

  @spec contents(ProductContents.t() | nil) :: map() | nil
  def contents(nil), do: nil

  def contents(%ProductContents{} = contents) do
    %{
      items: Enum.map(contents.items, &item/1),
      sources: contents.sources,
      checked_on: contents.checked_on
    }
  end

  defp item(item) do
    item
    |> Map.take([
      :quantity,
      :type,
      :name,
      :tcgdex_id,
      :set,
      :number,
      :cardmarket_id,
      :image,
      :photo
    ])
    |> Map.put(:cards, item.cards && Enum.map(item.cards, &deck_card/1))
    |> Map.put(:variants, item.variants && Enum.map(item.variants, &deck_variant/1))
  end

  defp deck_variant(variant) do
    %{name: variant.name, cards: Enum.map(variant.cards, &deck_card/1)}
  end

  defp deck_card(card) do
    Map.take(card, [
      :quantity,
      :name,
      :tcgdex_id,
      :category,
      :set,
      :number,
      :cardmarket_id,
      :image,
      :photo
    ])
  end

  @spec suggested_price(SuggestedPrice.t() | nil) :: map() | nil
  def suggested_price(nil), do: nil

  def suggested_price(%SuggestedPrice{} = item) do
    item
    |> Map.take([:id, :rebel_id, :title, :url, :ean, :price, :product_id, :last_seen_at])
    |> Map.put(:manual, item.manual?)
    |> put_product(item.product)
  end

  @spec tcgdex_set(TcgdexSet.t()) :: map()
  def tcgdex_set(%TcgdexSet{} = set) do
    set
    |> Map.take([:tcgdex_id, :name, :released_on, :cardmarket_expansion_id, :cards_source_url])
    |> Map.put(:pull_rates, pull_rates(set.pull_rates))
  end

  defp pull_rates(nil), do: nil

  defp pull_rates(%PullRates{} = pull_rates) do
    %{
      cards_per_pack: pull_rates.cards_per_pack,
      rates: Enum.map(pull_rates.rates, &Map.take(&1, [:rarity, :per_pack, :percent, :card])),
      sources: Enum.map(pull_rates.sources, &Map.take(&1, [:url, :sample_packs, :data_from])),
      borrowed_from: pull_rates.borrowed_from,
      checked_on: pull_rates.checked_on
    }
  end

  @doc "A single-card offer, including the shop's parsed copy attributes."
  def card_offer(offer) do
    offer
    |> Map.take([
      :id,
      :shop,
      :shop_product_id,
      :title,
      :category,
      :url,
      :price,
      :in_stock,
      :card_id,
      :variant,
      :language,
      :condition,
      :grading,
      :match_note,
      :last_seen_at
    ])
    |> Map.put(:manual, offer.manual?)
  end

  @doc "A synced card and its normal/reverse delivered reference at the NBP rate."
  def card(card, rate) do
    price = card.cardmarket_price

    card
    |> Map.take([:id, :tcgdex_id, :name, :number, :rarity, :variants, :cardmarket_id])
    |> Map.merge(%{
      set: Map.take(card.tcgdex_set, [:tcgdex_id, :name, :abbreviation]),
      trend_eur: price && price.trend,
      trend_holo_eur: price && price.trend_holo,
      reference_pln: CardReference.pln(price, :normal, rate),
      reverse_reference_pln: CardReference.pln(price, :reverse, rate)
    })
  end

  defp put_product(map, %Product{} = product), do: Map.put(map, :product, product(product))
  defp put_product(map, _not_loaded), do: map
end
