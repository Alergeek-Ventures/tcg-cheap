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
      currency: "HUF",
      country: "HU",
      max_pages: 5,
      shipping_from: Decimal.new("1990"),
      free_shipping_from: nil,
      pickup_city: "Budapest"
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "HU"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Hungary of shops abroad, by shop key (`TcgCheap.Sealed.Shops`),
  in the shops' own currencies.
  """
  def deliveries do
    %{
      "beamcardshop" => %{
        shipping_from: Decimal.new("29.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "bescards" => %{
        shipping_from: Decimal.new("8.38"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "bulbazard" => %{
        shipping_from: Decimal.new("149"),
        free_shipping_from: nil,
        currency: "CZK"
      },
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "chasedex" => %{
        shipping_from: Decimal.new("99"),
        free_shipping_from: Decimal.new("799"),
        currency: "SEK"
      },
      "gemipulls" => %{
        shipping_from: Decimal.new("229"),
        free_shipping_from: nil,
        currency: "DKK"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("11.44"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "pkmwinkel" => %{
        shipping_from: Decimal.new("20"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "pokefamily" => %{
        shipping_from: Decimal.new("12.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "psydeck" => %{
        shipping_from: Decimal.new("15"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "rarecards" => %{
        shipping_from: Decimal.new("8.95"),
        free_shipping_from: Decimal.new("300"),
        currency: "EUR"
      },
      "tcgking" => %{
        shipping_from: Decimal.new("10.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "unicorncards" => %{
        shipping_from: Decimal.new("5.90"),
        free_shipping_from: Decimal.new("100"),
        currency: "GBP"
      }
    }
  end
end
