defmodule TcgCheap.Sealed.Shops.Hungary do
  @moduledoc """
  Shops in Hungary. Their listings and delivery terms were checked on the
  shops' public pages and anonymous carts on 2026-11-14; unknown terms stay
  `nil`.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{Shopify, Shoptet, WooCommerce}

  @termek ~r|\A/termek/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @bolt ~r|\A/bolt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|

  @shops [
    %Shop{
      key: "cardempire",
      name: "Card Empire",
      host: "www.cardempire.hu",
      source: Shoptet,
      listing_paths: [
        "/pokemon-booster-box/",
        "/pokemon-booster-pack/",
        "/pokemon-elite-trainer-box/",
        "/pokemon-blister/",
        "/pokemon-tin/",
        "/pokemon-premium-box/",
        "/pokemon-booster-bundle/",
        "/pokemon-build-and-battle-box/",
        "/pokemon-build-and-battle-stadium/",
        "/pokemon-sleeved-booster-pack/",
        "/pokemon-sealed-case/"
      ],
      currency: "HUF",
      country: "HU",
      max_pages: 20,
      shipping_from: Decimal.new("1690"),
      free_shipping_from: Decimal.new("80000"),
      pickup_city: nil
    },
    %Shop{
      key: "rjmods",
      name: "RJ Mods",
      host: "www.rjmods.hu",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      # Foxpost rate in the product's schema.org shippingDetails.
      shipping_from: Decimal.new("1200"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "tcgbolt",
      name: "TCGbolt",
      host: "tcgbolt.hu",
      source: WooCommerce,
      category: "19",
      product_path: @bolt,
      sealed_categories: [
        "booster-pokemon",
        "booster-display",
        "elite-trainer-box",
        "ex-box",
        "premium-collection",
        "battle-deck",
        "tin"
      ],
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("1400"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "cobracard",
      name: "CobraCard",
      host: "cobracard.hu",
      source: WooCommerce,
      category: "69",
      product_path: @termek,
      mixed_listing: true,
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("1650"),
      free_shipping_from: nil,
      pickup_city: "Halásztelek"
    },
    %Shop{
      key: "tcgwebshop",
      name: "TCG Webshop",
      host: "tcgwebshop.hu",
      source: WooCommerce,
      category: "5564",
      product_path: @termek,
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("1350"),
      free_shipping_from: Decimal.new("30000"),
      pickup_city: nil
    },
    %Shop{
      key: "cardverse",
      name: "Cardverse",
      host: "www.cardverse.hu",
      source: WooCommerce,
      category: "131",
      product_path: @termek,
      mixed_listing: true,
      currency: "HUF",
      country: "HU",
      max_pages: 10,
      # The parcel-point plugin quotes its price only after selecting a point.
      shipping_from: Decimal.new("2000"),
      free_shipping_from: nil,
      pickup_city: "Szombathely"
    },
    %Shop{
      key: "geekempire",
      name: "Geek Empire",
      host: "geekempire.hu",
      source: WooCommerce,
      category: "1512",
      product_path: @termek,
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("1200"),
      free_shipping_from: nil,
      pickup_city: "Nyíregyháza"
    },
    %Shop{
      key: "holozone",
      name: "Holo Zone",
      host: "holozone.hu",
      source: Shopify,
      collection: "minden-pokemon-termek",
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("2500"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "mythgames",
      name: "Myth Games",
      host: "mythgames.eu",
      source: Shopify,
      collection: "pokemon-kartyak-booster-boxok-es-gyujtoi-termekek",
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("1990"),
      free_shipping_from: nil,
      pickup_city: "Budapest"
    }
  ]

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops
end
