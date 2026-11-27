defmodule TcgCheap.Sealed.Shops.Sweden do
  @moduledoc """
  Shops in Sweden, and the deliveries to Sweden of shops abroad
  (`TcgCheap.Sealed.Shops`), in the shops' own currencies.

  The Shopify shops' Pokémon collections were read from their public
  `/collections.json` on 2026-11-14; a shop without a collection that holds
  all its Pokémon products is read whole (its titles must say Pokémon).
  Their singles are not read: singles have no market in Sweden yet.

  Delivery within Sweden and to Sweden from abroad: the shops' delivery
  pages, or their anonymous cart's shipping estimate (Shopify), on
  2026-11-14; nil where neither states a price. Unknown terms stay nil.
  """

  alias TcgCheap.Sealed.Shop

  alias TcgCheap.Sealed.ShopFeed.{
    BangerpackSe,
    Chasedex,
    GoogleFeed,
    Shopify,
    Storeborn,
    WooCommerce
  }

  @shops [
    # Bangerpack (White Tree AB, Helsingborg) runs two shops. bangerpack.com
    # sells abroad in euros and does not ship to Sweden (its FAQ sends Swedish
    # buyers to bangerpack.se), so it is outside the Swedish market. It
    # publishes a Google Shopping export per language on its CDN, sealed
    # products only; the Polish one links to its Polish pages.
    %Shop{
      key: "bangerpack",
      name: "Bangerpack",
      host: "bangerpack.com",
      source: GoogleFeed,
      feed_host: "cdn.bangerpack.com",
      feed_path: "/shopping-pl.xml",
      currency: "EUR",
      country: "SE",
      home_market: false,
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # bangerpack.se sells in Sweden in kronor, at its own prices. Its FAQ
    # (2026-11-16): 29 kr as a letter to the mailbox, 59 kr as a parcel to a
    # pickup point, no free delivery and no pickup at the warehouse.
    %Shop{
      key: "bangerpackse",
      name: "Bangerpack",
      host: "bangerpack.se",
      source: BangerpackSe,
      feed_path: "/pokemon",
      currency: "SEK",
      country: "SE",
      max_pages: 1,
      shipping_from: Decimal.new("29"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "chasedex",
      name: "Chasedex",
      host: "chasedex.se",
      source: Chasedex,
      # Not read (the sitemaps decide); nil would disable singles.
      singles_categories: ["all"],
      currency: "SEK",
      singles_only: true,
      country: "SE",
      max_pages: 80,
      shipping_from: Decimal.new("29"),
      free_shipping_from: Decimal.new("499"),
      pickup_city: nil
    },
    %Shop{
      key: "hobbykort",
      name: "Hobbykort",
      host: "hobbykort.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      max_pages: 5,
      shipping_from: Decimal.new("69"),
      free_shipping_from: Decimal.new("2000"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgstore",
      name: "TCGstore",
      host: "tcgstore.se",
      source: Shopify,
      # Its vendor for discontinued products.
      excluded_markers: ["Utgått ur sortiment"],
      currency: "SEK",
      country: "SE",
      # 13 pages in November 2026.
      max_pages: 16,
      shipping_from: Decimal.new("39"),
      free_shipping_from: Decimal.new("2999"),
      pickup_city: nil
    },
    %Shop{
      key: "samlarhobby",
      name: "Samlarhobby",
      host: "www.samlarhobby.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      # 6 pages in November 2026.
      max_pages: 8,
      shipping_from: Decimal.new("89"),
      free_shipping_from: Decimal.new("2000"),
      pickup_city: nil
    },
    %Shop{
      key: "poketalk",
      name: "PokeTalk",
      host: "www.poketalk.se",
      source: Shopify,
      # Its RareFinds singles are tagged by format.
      excluded_markers: ["format:raw", "format:graded"],
      currency: "SEK",
      country: "SE",
      # 3 pages in November 2026.
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "speltrollet",
      name: "Speltrollet",
      host: "speltrollet.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      max_pages: 25,
      shipping_from: Decimal.new("59"),
      free_shipping_from: Decimal.new("2000"),
      pickup_city: nil
    },
    %Shop{
      key: "dragonslair",
      name: "Dragon's Lair",
      host: "dragonslair.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      # 38 pages in November 2026: the shop sells many board games.
      max_pages: 45,
      shipping_from: Decimal.new("49"),
      free_shipping_from: nil,
      pickup_city: "Stockholm"
    },
    %Shop{
      key: "kortarkivet",
      name: "Kortarkivet",
      host: "kortarkivet.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      # 3 pages in November 2026.
      max_pages: 5,
      shipping_from: Decimal.new("59"),
      free_shipping_from: Decimal.new("1500"),
      pickup_city: nil
    },
    %Shop{
      key: "auroradex",
      name: "Auroradex",
      host: "auroradex.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      # 3 pages in November 2026.
      max_pages: 5,
      shipping_from: Decimal.new("59"),
      free_shipping_from: Decimal.new("2499"),
      pickup_city: nil
    },
    %Shop{
      key: "kantovault",
      name: "Kantovault",
      host: "kantovault.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      max_pages: 3,
      shipping_from: Decimal.new("49"),
      free_shipping_from: Decimal.new("2999"),
      pickup_city: nil
    },
    %Shop{
      key: "rahtech",
      name: "Rahtech",
      host: "rahtech.se",
      source: Shopify,
      # It sells only Pokémon: its titles seldom say so.
      mixed_listing: false,
      excluded_markers: ["format:raw", "format:graded"],
      currency: "SEK",
      country: "SE",
      # 1 page in November 2026.
      max_pages: 3,
      shipping_from: Decimal.new("69"),
      free_shipping_from: nil,
      pickup_city: "Malmö"
    },
    %Shop{
      key: "cardshopsweden",
      name: "Cardshop Sweden",
      host: "cardshopsweden.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      # 1 page in November 2026.
      max_pages: 3,
      shipping_from: Decimal.new("65"),
      free_shipping_from: Decimal.new("2999"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgvault",
      name: "TCGVAULT",
      host: "tcgvault.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      max_pages: 2,
      shipping_from: Decimal.new("49"),
      free_shipping_from: Decimal.new("1500"),
      pickup_city: nil
    },
    %Shop{
      key: "cardvalley",
      name: "CardValley",
      host: "www.cardvalley.se",
      source: Storeborn,
      # A Storeborn storefront since 2026-11-26 (it left Shopify). Its parent
      # category "pokemon-sealed-produkter" lacked three products that its
      # collection category lists, so the subcategories are read instead; the
      # sleeved packs are in two of them, and the boxes and vintage ones are
      # empty today. It also sells One Piece and Lorcana (other categories),
      # and packs opened live on stream (marked "öppnas live" in the title or
      # the slug) that are not shipped sealed.
      listing_paths: [
        "/kategorier/collection-boxar",
        "/kategorier/pokemon-booster-box",
        "/kategorier/pokemon-booster-bundle",
        "/kategorier/pokemon-elite-trainer-box-etb",
        "/kategorier/pokemon-blister-packs",
        "/kategorier/pokemon-tins",
        "/kategorier/sleeved-booster-packs",
        "/kategorier/engelska-pokemon-booster-packs",
        "/kategorier/vintage-pokemon"
      ],
      excluded_title_phrases: [
        "one piece",
        "lorcana",
        "match attax",
        "oppnas live",
        "live oppning",
        "liveoppning",
        "mystery box"
      ],
      currency: "SEK",
      country: "SE",
      max_pages: 3,
      # Its shipping policy (updated 2026-09-25) delivers within Sweden only,
      # with PostNord, and shows the price at checkout: none is published.
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "cardclub",
      name: "Card Club",
      host: "cardclub.se",
      source: Shopify,
      currency: "SEK",
      country: "SE",
      # 6 pages in November 2026.
      max_pages: 8,
      shipping_from: Decimal.new("89"),
      free_shipping_from: Decimal.new("3000"),
      pickup_city: nil
    },
    # Its Pokémon category (WooCommerce Store API, allowed in its robots.txt,
    # checked 2026-11-24); the title decides what is sealed. Delivery:
    # https://theswedishfish.se/shipping/ (2026-11-24), a flat 99 kr by
    # PostNord, free from 3 000 kr.
    %Shop{
      key: "theswedishfish",
      name: "The Swedish Fish",
      host: "theswedishfish.se",
      source: WooCommerce,
      category: "83",
      product_path: ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      currency: "SEK",
      country: "SE",
      max_pages: 3,
      shipping_from: Decimal.new("99"),
      free_shipping_from: Decimal.new("3000"),
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "SE"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Sweden of shops abroad, by shop key; one with no published
  price is only listed.
  """
  def deliveries do
    %{
      # Its cart for buyers in Sweden, in their currency (2026-11-16).
      "beamcardshop" => %{
        shipping_from: Decimal.new("340"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "SEK"
      },
      # Its cart for buyers in Sweden, in their currency (2026-11-16).
      "bescards" => %{
        shipping_from: Decimal.new("95"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "SEK"
      },
      # Its cart to Stockholm, VAT included (2026-11-16).
      "cardverse" => %{
        shipping_from: Decimal.new("3750"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its delivery page says €19.99 to Sweden; the cart asked €29.99.
      "cardcosmos" => %{
        shipping_from: Decimal.new("29.99"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "SEK"
      },
      # Delivers to Sweden; the price is shown only in the checkout.
      "gemipulls" => %{
        shipping_from: nil,
        free_shipping_from: nil,
        currency: "DKK",
        price_currency: "SEK"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("8.55"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "SEK"
      },
      # Its cart for buyers in Sweden, in their currency (2026-11-16).
      "pkmwinkel" => %{
        shipping_from: Decimal.new("227"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "SEK"
      },
      # Its cart for buyers in Sweden, in their currency (2026-11-16).
      "pokefamily" => %{
        shipping_from: Decimal.new("147"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "SEK"
      },
      # Its cart to Stockholm (2026-11-16).
      "pokemagic" => %{
        shipping_from: Decimal.new("29.95"),
        free_shipping_from: nil,
        currency: "EUR"
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
        price_currency: "SEK"
      },
      "rarecards" => %{
        shipping_from: Decimal.new("11.95"),
        free_shipping_from: Decimal.new("350"),
        currency: "EUR"
      },
      "tcgking" => %{
        shipping_from: Decimal.new("10.95"),
        free_shipping_from: Decimal.new("100"),
        currency: "EUR",
        price_currency: "SEK"
      },
      # https://reflexshop.hu/szallitasi-informaciok: GLS home delivery, zone 4 for orders under 7 000 Ft;
      # the rate falls with the order value, and the page names no free delivery (2026-11-26).
      "reflexshop" => %{
        shipping_from: Decimal.new("7190"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart to Stockholm, VAT included (2026-11-16).
      "tcgwebshop" => %{
        shipping_from: Decimal.new("10160"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # https://unicorncards.co.uk/international_shipping (2026-11-17): £5.90
      # for any number of singles, free from £100, VAT and duties prepaid
      # (IOSS). It prices singles only; the shop is read for its singles alone.
      "unicorncards" => %{
        shipping_from: Decimal.new("5.90"),
        free_shipping_from: Decimal.new("100"),
        currency: "GBP"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-25).
      "kartonada" => %{
        shipping_from: Decimal.new("69.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its cart to Stockholm (2026-11-17): DPD 78.06 zł and 23% VAT.
      "paladynat" => %{
        shipping_from: Decimal.new("96.01"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://rgfk.pl/content/1-koszty-dostawy: DHL (2026-11-17).
      "rgfk" => %{
        shipping_from: Decimal.new("54"),
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
