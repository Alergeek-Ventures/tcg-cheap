defmodule TcgCheap.Sealed.Shops.Netherlands do
  @moduledoc """
  Shops in the Netherlands, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{Shopify, WooCommerce}

  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|

  @shops [
    %Shop{
      key: "pokefamily",
      name: "PokeFamily",
      host: "pokefamily.nl",
      source: Shopify,
      # Its Rip & Ship products are packs opened live for the buyer.
      excluded_markers: ["Pokémon R&S"],
      currency: "EUR",
      country: "NL",
      # 4 pages in November 2026.
      max_pages: 6,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pkmwinkel",
      name: "PKMWinkel",
      host: "www.pkmwinkel.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "bescards",
      name: "Bescards",
      host: "www.bescards.com",
      source: Shopify,
      excluded_markers: ["product:single"],
      currency: "EUR",
      country: "NL",
      # 14 pages in November 2026.
      max_pages: 18,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "beamcardshop",
      name: "Beam Card Shop",
      host: "beamcardshop.com",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      # 3 pages in November 2026.
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "rarecards",
      name: "RareCards",
      host: "rarecards.nl",
      source: Shopify,
      singles_categories: ["losse-pokemon-kaarten"],
      currency: "EUR",
      singles_only: true,
      country: "NL",
      max_pages: 30,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "tcgking",
      name: "TCG King",
      host: "tcgking.nl",
      source: Shopify,
      # Its list also holds other games' cards and sealed products: a single
      # here is a Pokémon product of the "Single Card" type.
      singles_markers: ["Single Card"],
      currency: "EUR",
      singles_only: true,
      country: "NL",
      # 16 pages in November 2026.
      max_pages: 20,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokemagic",
      name: "PokeMagic",
      host: "pokemagic.nl",
      source: WooCommerce,
      # The Scarlet & Violet, Mega Evolution and Sword & Shield series (about
      # 47 pages in November 2026). Pages take about 2.8 s, so the whole
      # singles category (85 pages) and even Sun & Moon on top (61 pages,
      # 173 s before matching) leave too little of the 5-minute job. English
      # cards only: the shop also sells Japanese ones, its language attribute
      # tells them apart.
      singles_categories: ["8871", "8872", "8873"],
      singles_attribute: {"pa_taal", 219},
      product_path: @product,
      currency: "EUR",
      singles_only: true,
      country: "NL",
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "NL"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to the Netherlands of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
