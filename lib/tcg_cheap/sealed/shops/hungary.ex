defmodule TcgCheap.Sealed.Shops.Hungary do
  @moduledoc """
  Shops in Hungary. Their listings and delivery terms were checked on the
  shops' public pages and anonymous carts on 2026-11-14; unknown terms stay
  `nil`.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{Shopify, ShopRenter, Shoptet, WooCommerce}

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
    },
    %Shop{
      key: "gamerunner",
      name: "Gamerunner",
      host: "gamerunner.hu",
      source: ShopRenter,
      listing_paths: ["/gyujtogetos-kartyajatekok/pokemon-tcg"],
      currency: "HUF",
      country: "HU",
      max_pages: 15,
      # https://gamerunner.hu/fizetes-szallitas: GLS parcel locker or
      # collection point, gross (2026-11-25).
      shipping_from: Decimal.new("1190"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "gemklub",
      name: "Gémklub",
      host: "www.gemklub.hu",
      source: ShopRenter,
      listing_paths: [
        "/tarsasjatekok-felnotteknek/gyujtogetos-kartyajatekok-1107/pokemon-tcg-1109"
      ],
      currency: "HUF",
      country: "HU",
      max_pages: 4,
      # https://www.gemklub.hu/szallitas: parcel locker up to 20 000 Ft, free
      # above, gross (2026-11-25).
      shipping_from: Decimal.new("990"),
      free_shipping_from: Decimal.new("20000"),
      pickup_city: "Budapest"
    },
    %Shop{
      key: "drawspot",
      name: "DrawSpot",
      host: "www.drawspot.hu",
      source: ShopRenter,
      listing_paths: [
        "/tcg-kartyak/pokemon/pokemon-booster-box",
        "/tcg-kartyak/pokemon/pokemon-booster-pack",
        "/tcg-kartyak/pokemon/pokemon-elite-trainer-box",
        "/tcg-kartyak/pokemon/pokemon-collection-box-tin-blister-es-special-box"
      ],
      currency: "HUF",
      country: "HU",
      max_pages: 4,
      # https://www.drawspot.hu/fizetes-szallitas-34: Foxpost parcel locker,
      # free to a locker from 20 000 Ft, gross (2026-11-25).
      shipping_from: Decimal.new("1290"),
      free_shipping_from: Decimal.new("20000"),
      pickup_city: nil
    },
    %Shop{
      key: "revoshop",
      name: "Revo Shop",
      host: "revoshop.hu",
      source: ShopRenter,
      listing_paths: [
        "/pokemon-tcg/japan-269/pokemon-japan-booster-box",
        "/pokemon-tcg/kinai-275/booster-pack-437",
        "/pokemon-tcg/kinai-275/egyeb",
        "/pokemon-tcg/kinai-275/pokemon-kinai-booster-box",
        "/pokemon-tcg/koreai-272/pokemon-koreai-booster-box",
        "/pokemon-tcg/koreai-272/pokemon-koreai-booster-pack"
      ],
      # "[Kína]" (without the "i") marks Chinese products the matcher would read
      # as the Japanese set of the same name; a "FAT" box is six boxes and a
      # "LIVE" pack one opened on a stream; plush toys are no cards.
      excluded_title_phrases: ["Kína", "FAT", "LIVE", "Plush"],
      currency: "HUF",
      country: "HU",
      max_pages: 4,
      # https://revoshop.hu/szallitasi-informaciok: Foxpost parcel locker,
      # per parcel (2026-11-25).
      shipping_from: Decimal.new("1240"),
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "HU"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Hungary of shops abroad, by shop key (`TcgCheap.Sealed.Shops`),
  in the shops' own currencies, or in forints where a shop's cart quotes
  buyers in Hungary in them.
  """
  def deliveries do
    %{
      # Its cart for buyers in Hungary, in their currency (2026-11-16).
      "beamcardshop" => %{
        shipping_from: Decimal.new("11200"),
        free_shipping_from: nil,
        currency: "HUF",
        price_currency: "HUF"
      },
      # Its cart for buyers in Hungary, in their currency (2026-11-16).
      "bescards" => %{
        shipping_from: Decimal.new("3200"),
        free_shipping_from: nil,
        currency: "HUF",
        price_currency: "HUF"
      },
      "bulbazard" => %{
        shipping_from: Decimal.new("149"),
        free_shipping_from: nil,
        currency: "CZK"
      },
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "HUF"
      },
      "chasedex" => %{
        shipping_from: Decimal.new("99"),
        free_shipping_from: Decimal.new("799"),
        currency: "SEK",
        price_currency: "EUR"
      },
      "gemipulls" => %{
        shipping_from: Decimal.new("229"),
        free_shipping_from: nil,
        currency: "DKK",
        price_currency: "HUF"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("11.45"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "HUF"
      },
      # Its cart for buyers in Hungary, in their currency (2026-11-16).
      "pkmwinkel" => %{
        shipping_from: Decimal.new("7500"),
        free_shipping_from: nil,
        currency: "HUF",
        price_currency: "HUF"
      },
      # Its cart for buyers in Hungary, in their currency (2026-11-16).
      "pokefamily" => %{
        shipping_from: Decimal.new("4900"),
        free_shipping_from: nil,
        currency: "HUF",
        price_currency: "HUF"
      },
      # https://www.pressstart.pt/pt/content/entregas.html (2026-11-25), its table
      # of countries: the rate for orders up to €35; free above €35.
      "pressstart" => %{
        shipping_from: Decimal.new("4.49"),
        free_shipping_from: Decimal.new("35"),
        currency: "EUR"
      },
      "psydeck" => %{
        shipping_from: Decimal.new("15"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "HUF"
      },
      "rarecards" => %{
        shipping_from: Decimal.new("8.95"),
        free_shipping_from: Decimal.new("300"),
        currency: "EUR"
      },
      # Its delivery page: free from €100 to every country it lists (2026-11-16).
      "tcgking" => %{
        shipping_from: Decimal.new("10.95"),
        free_shipping_from: Decimal.new("100"),
        currency: "EUR",
        price_currency: "HUF"
      },
      "unicorncards" => %{
        shipping_from: Decimal.new("5.90"),
        free_shipping_from: Decimal.new("100"),
        currency: "GBP"
      },
      # Its cart to Budapest (2026-11-17): GLS to an address, €10 and 25% VAT.
      "pullz" => %{
        shipping_from: Decimal.new("12.50"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # Its cart to Budapest (2026-11-17), as the cart totals it.
      "pokebros" => %{
        shipping_from: Decimal.new("28"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-25).
      "kartonada" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its cart to Budapest (2026-11-17): DPD 38.21 zł and 23% VAT.
      "paladynat" => %{
        shipping_from: Decimal.new("47"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://rgfk.pl/content/1-koszty-dostawy: DHL (2026-11-17).
      "rgfk" => %{
        shipping_from: Decimal.new("23"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://pokespot.pl/pl/i/Czas-i-koszty-dostawy/1: one rate to the EU
      # (2026-11-17).
      "pokespot" => %{
        shipping_from: Decimal.new("150"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://carddojo.pl/pl/i/Czas-i-koszty-dostawy/4: InPost courier to the EU
      # (2026-11-17).
      "carddojo" => %{
        shipping_from: Decimal.new("80"),
        free_shipping_from: nil,
        currency: "PLN"
      }
    }
  end
end
