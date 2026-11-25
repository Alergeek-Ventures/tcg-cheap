defmodule TcgCheap.Sealed.Shops.Netherlands do
  @moduledoc """
  Shops in the Netherlands, the guide's region `/nl/` in euro, and the
  deliveries to the Netherlands of shops abroad (`TcgCheap.Sealed.Shops`).

  The Shopify shops are read whole, as their collections answer only
  signed requests with 429 (`TcgCheap.Sealed.ShopFeed.Shopify`); a product
  counts when its title says Pokémon. The WooCommerce shops are read through
  their Store API categories, checked on 2026-11-15 (`wp-json` is allowed in
  their robots.txt; a shop that disallows it is left out). Delivery within
  the Netherlands is each shop's cheapest standard parcel and its free-delivery
  threshold as the shop states them in November 2026; nil where it states
  none. Singles have no market here yet: RareCards, TCG King and PokeMagic
  are read for the Polish singles prices.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{PrestaShop, Shopify, WooCommerce}

  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @root_product ~r|\A/[a-z0-9]+(?:-[a-z0-9]+)*/\z|

  @shops [
    # Sells Japanese-language products only, whose titles never say so; its
    # category of booster boxes also holds Pokémon Center boxes and decks. Its
    # singles are not read.
    %Shop{
      key: "tcgjapan",
      name: "TCGjapan",
      host: "tcgjapan.nl",
      source: PrestaShop,
      listing_paths: ["/nl/20-booster-boxen"],
      edition: :ja,
      currency: "EUR",
      country: "NL",
      # 5 pages in November 2026.
      max_pages: 8,
      # https://tcgjapan.nl/nl/content/1-levering-verzending (2026-11-24):
      # "Booster Boxen kunnen alleen verzonden worden via PostNL pakket Track &
      # Trace": €5.99, not the €1.95 and €4 letterbox options, which are for
      # packs and single cards; it states no free-delivery threshold.
      shipping_from: Decimal.new("5.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
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
      shipping_from: Decimal.new("7.95"),
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
      shipping_from: Decimal.new("4.95"),
      free_shipping_from: Decimal.new("75"),
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
      shipping_from: Decimal.new("4.99"),
      free_shipping_from: Decimal.new("250"),
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
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "tcgreus",
      name: "TcgReus",
      # The shop answers on www only: the bare domain redirects there.
      host: "www.tcgreus.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.25"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "embertcg",
      name: "Ember TCG",
      host: "embertcg.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("275"),
      pickup_city: nil
    },
    %Shop{
      key: "brothersincards",
      name: "Brothers in Cards",
      host: "brothersincards.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.95"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "thetcgplug",
      name: "The TCG Plug",
      host: "www.thetcgplug.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.19"),
      free_shipping_from: Decimal.new("299"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgworld",
      name: "TCG World",
      host: "tcgworld.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.99"),
      free_shipping_from: Decimal.new("200"),
      pickup_city: nil
    },
    %Shop{
      key: "debroergrot",
      name: "De Broergrot",
      host: "debroergrot.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "nosticcards",
      name: "Nostic Cards",
      host: "www.nostic-cards.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "collectorsgarden",
      name: "Collectors Garden",
      host: "collectorsgarden.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "vividnerd",
      name: "VividNerd",
      host: "vividnerd.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      # A whole list of other games too: more than 10 pages in November 2026.
      max_pages: 20,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "kingcards",
      name: "King Cards",
      host: "www.kingcards.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "collectibleshop",
      name: "Collectible Shop",
      host: "collectibleshop.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "cardbinder",
      name: "Card-Binder.com",
      host: "card-binder.com",
      source: Shopify,
      # Every product is listed twice: sealed, and a twin marked "[Live]",
      # "(Live-stream)" or "(Lives-stream)" in the title (and "-live" or
      # "-live-stream" in the handle) that the shop opens on a live stream
      # instead of shipping sealed. Only the title and handle are searched:
      # ordinary sealed descriptions also say "live".
      excluded_title_phrases: ["live", "live stream", "lives stream"],
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "pokeyume",
      name: "PokéYume",
      host: "www.pokeyume.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("5.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "gamerzparadize",
      name: "GamerzParadize",
      host: "gamerzparadize.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.99"),
      free_shipping_from: Decimal.new("80"),
      pickup_city: nil
    },
    %Shop{
      key: "mistcards",
      name: "MIST Cards",
      host: "mistcards.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("5.95"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgmaniacs",
      name: "TCG Maniacs",
      host: "tcgmaniacs.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("175"),
      pickup_city: nil
    },
    %Shop{
      key: "elveecollectibles",
      name: "Elvee Collectibles",
      host: "elveecollectibles.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "collgamers",
      name: "CollGamers",
      host: "collgamers.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.49"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "deckkingdom",
      name: "Deck Kingdom",
      host: "deckkingdom.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("4.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "tcgtogether",
      name: "TCG Together",
      host: "tcgtogether.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("275"),
      pickup_city: nil
    },
    %Shop{
      key: "miraicards",
      name: "Mirai Cards",
      host: "www.miraicards.com",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.45"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "evocollects",
      name: "Evocollects",
      host: "evocollects.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("5.95"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "pokeca",
      name: "Pokeca",
      host: "pokeca.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("175"),
      pickup_city: nil
    },
    %Shop{
      key: "bkcards",
      name: "BK Cards",
      host: "bkcards.nl",
      source: Shopify,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.95"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "oppacards",
      name: "Oppa Cards",
      host: "oppacards.com",
      source: WooCommerce,
      category: "46,47,63,48,104",
      sealed_categories: [
        "pokemon-booster-box",
        "pokemon-booster-pack",
        "pokemon-collection-box",
        "pokemon-elite-trainer-boxen",
        "pokemon-tin"
      ],
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("6.95"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgcompany",
      name: "TCG Company",
      host: "tcgcompany.nl",
      source: WooCommerce,
      category: "72,71,70,38,36,37,40,35",
      sealed_categories: [
        "1-pack-blister-pokemon",
        "2-pack-blister-pokemon",
        "3-pack-blister-pokemon",
        "pokemon-blisters",
        "pokemon-booster-box",
        "pokemon-booster-packs",
        "pokemon-collection-box",
        "pokemon-elite-trainer-box"
      ],
      product_path: @root_product,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: Decimal.new("7.95"),
      free_shipping_from: Decimal.new("175"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgtriarch",
      name: "TCGTriarch",
      host: "www.tcgtriarch.com",
      source: WooCommerce,
      category: "35",
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 6,
      shipping_from: Decimal.new("6.96"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "monkeltcg",
      name: "MonkelTCG",
      host: "monkeltcg.nl",
      source: WooCommerce,
      category: "107,53,54,66,56,55,57",
      sealed_categories: [
        "pokemon_blisters",
        "pokemon_boosterboxen",
        "pokemon_boosterpacks",
        "pokemon_elite-trainer-box",
        "pokemon_tins",
        "pokemon_v-boxen",
        "pokemon_thema-decks"
      ],
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 9,
      shipping_from: Decimal.new("5.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "gamecardscentral",
      name: "GameCardsCentral",
      host: "gamecardscentral.nl",
      source: WooCommerce,
      category: "76",
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 2,
      shipping_from: Decimal.new("9.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "braadscardshop",
      name: "Braad's Card Shop",
      host: "braadscardshop.nl",
      source: WooCommerce,
      category: "82",
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 3,
      shipping_from: Decimal.new("5.00"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "zaptoys",
      name: "Zaptoys",
      host: "zaptoys.nl",
      source: WooCommerce,
      category: "1881",
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 3,
      shipping_from: Decimal.new("6.95"),
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
      shipping_from: Decimal.new("5.95"),
      free_shipping_from: Decimal.new("200"),
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
      shipping_from: Decimal.new("5.95"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    # The four shops below are read through their Store API categories
    # (2026-11-24). DavidPTCG, PackEmAll and TCG Experts state a free-delivery
    # threshold and no price under it (it appears in the cart), so that price
    # stays nil. Boxes sold with an acrylic case are not the plain product:
    # DavidPTCG and DiddoDeals drop them by their "acryl" title word.
    # https://davidptcg.nl/verzending/: free from 250 € in the Netherlands.
    %Shop{
      key: "davidptcg",
      name: "DavidPTCG",
      host: "davidptcg.nl",
      source: WooCommerce,
      category: "19,23,24,63",
      product_path: @product,
      excluded_title_phrases: ["acryl"],
      currency: "EUR",
      country: "NL",
      max_pages: 4,
      shipping_from: nil,
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    # https://packemall.nl/algemene-voorwaarden/: free from 250 €.
    %Shop{
      key: "packemall",
      name: "PackEmAll",
      host: "packemall.nl",
      source: WooCommerce,
      # Its sealed categories, Chinese sets included.
      category: "304,381",
      # A flag or other emoji opening a slug is percent-encoded.
      product_path: ~r"\A/product/(?:[a-z0-9]|%[0-9a-f]{2})+(?:-(?:[a-z0-9]|%[0-9a-f]{2})+)*/\z"i,
      currency: "EUR",
      country: "NL",
      max_pages: 4,
      shipping_from: nil,
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    # Its product pages (https://diddodeals.nl/product/pokemon-surging-sparks-booster-box/,
    # 2026-11-24): "Verzending € 7,20 in Nederland", free from 500 €.
    %Shop{
      key: "diddodeals",
      name: "DiddoDeals",
      host: "diddodeals.nl",
      source: WooCommerce,
      category: "22,99,23,26,49,21,24,95,89",
      product_path: @product,
      excluded_title_phrases: ["acryl"],
      currency: "EUR",
      country: "NL",
      max_pages: 3,
      shipping_from: Decimal.new("7.20"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    # https://tcgexperts.nl/algemene-voorwaarden/: free from 175 € to the
    # Netherlands and Belgium. Its bundles of loose cards are not read.
    %Shop{
      key: "tcgexperts",
      name: "TCG Experts",
      host: "www.tcgexperts.nl",
      source: WooCommerce,
      category: "4192,4189,4202,4195,4196,4212,4211",
      product_path: @product,
      currency: "EUR",
      country: "NL",
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: Decimal.new("175"),
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "NL"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to the Netherlands of shops abroad, by shop key: the cheapest
  delivery of a small parcel to an Amsterdam address, in the currency the shop
  quoted it, read from the shops' carts or delivery pages on 2026-11-16. Only
  Collecthors publishes a free-delivery threshold for the Netherlands. Shops abroad
  without a known price for the Netherlands are left out. The Shopify shops
  whose cart answered Dutch buyers in euro charge them prices of their own
  (`price_currency`): the German and Portuguese ones as for Croatia, the
  Swedish and Polish ones in euro instead of their kronor or złoty.
  """
  def deliveries do
    %{
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      # 3,000 Ft and 21% VAT, as its cart adds the buyer's country's VAT.
      "cardverse" => %{
        shipping_from: Decimal.new("3630"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      "carddojo" => %{
        shipping_from: Decimal.new("80"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://www.collecthors.eu/ banner (2026-11-23): "Verzendkosten (BE/NL)
      # €8,40 | Gratis vanaf €100 (BE) €150 (NL)". Its prices are the same for
      # buyers in the Netherlands.
      "collecthors" => %{
        shipping_from: Decimal.new("8.40"),
        free_shipping_from: Decimal.new("150"),
        currency: "EUR"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("6.90"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "hobbykort" => %{
        shipping_from: Decimal.new("12.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-25).
      "kartonada" => %{
        shipping_from: Decimal.new("36.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # DPD 32.52 zł and 23% VAT, as its cart splits every rate.
      "paladynat" => %{
        shipping_from: Decimal.new("40"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      "pokebros" => %{
        shipping_from: Decimal.new("36"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "pokespot" => %{
        shipping_from: Decimal.new("150"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      "poketalk" => %{
        shipping_from: Decimal.new("14.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
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
        price_currency: "EUR"
      },
      "rahtech" => %{
        shipping_from: Decimal.new("18.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "rgfk" => %{
        shipping_from: Decimal.new("34"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its list for buyers in the Netherlands is in euro (`?country=NL`, 2026-11-18).
      "samlarhobby" => %{
        shipping_from: Decimal.new("299"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "EUR"
      },
      "skarbieckart" => %{
        shipping_from: Decimal.new("5.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "skladgier" => %{
        shipping_from: Decimal.new("16.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "tcgwebshop" => %{
        shipping_from: Decimal.new("8000"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      "vanaheim" => %{
        shipping_from: Decimal.new("90"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://chasedex.se/villkor (2026-11-17): a PostNord tracked letter to
      # the EU for 99 SEK, charged in the buyer's currency, free from 799 SEK.
      "chasedex" => %{
        shipping_from: Decimal.new("99"),
        free_shipping_from: Decimal.new("799"),
        currency: "SEK",
        price_currency: "EUR"
      },
      # https://unicorncards.co.uk/international_shipping (2026-11-17): £5.90
      # for any number of singles, free from £100, VAT and duties prepaid
      # (IOSS). It prices singles only; the shop is read for its singles alone.
      "unicorncards" => %{
        shipping_from: Decimal.new("5.90"),
        free_shipping_from: Decimal.new("100"),
        currency: "GBP"
      }
    }
  end
end
