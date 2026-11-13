defmodule TcgCheap.Sealed.Shops do
  @moduledoc """
  The shops whose product feeds the buying guide reads, fixed in code (Polish
  shops, and shops abroad compared with their delivery to Poland, see
  `TcgCheap.Sealed.Shop`):
  where and how to read each feed (see `TcgCheap.Sealed.Shop`) and the
  delivery facts shown next to its offers. The owner agreed recurring
  fetching from these shops.

  Delivery prices, free-delivery thresholds and pickup cities were checked on
  the shops' own pages on 2026-10-31; nil means the shop does not publish it.
  Card Gallery and PokeCoffee delivery pages were checked on 2026-11-03.
  Card Gallery publishes pickup in Kraków; PokeCoffee publishes no pickup or free threshold.
  Smyk and Empik delivery pages were checked on 2026-11-10; both chains also
  deliver to their own stores for free, which a single pickup city cannot show,
  so their delivery facts are the cheapest delivery to a parcel point.
  Pickup store coordinates were geocoded from the store addresses with
  OpenStreetMap Nominatim on 2026-11-01.

  singleTCG and PokeKarty ask crawlers in their robots.txt not to read the
  endpoints used here (`/api`, and the Store API with its `per_page` and
  `stock_status` parameters); the owner decided on 2026-11-07 to read them
  anyway, for the public prices only, at the usual pace and with the guide's
  own user agent.

  Logos are the shops' own, taken from their sites on 2026-11-01 and
  normalised to a 240×80 WebP on a white chip (dark for light logos) in
  `priv/static/images/shops/<key>.webp`; a shop without a file shows none.
  Morion Games and Hearts Pub have only their favicons (taken 2026-11-02):
  Morion's header image is a banner and Hearts Pub sits behind a bot check.
  The logos of the shops added for singles, and of those that had none, were
  taken on 2026-11-07, the same way; Smyk's, Empik's and Bangerpack's on
  2026-11-10.
  """

  alias TcgCheap.Pricing.ExchangeRate

  alias TcgCheap.Sealed.{
    Am76,
    CeneoFeed,
    Chasedex,
    Collectify,
    Empik,
    GildiaGrodzisk,
    GoogleFeed,
    Guildmage,
    IdoSell,
    MagicznyRynek,
    NopCommerce,
    Pasaz24,
    Planszomania,
    Pokemonki,
    PrestaShop,
    Sellingo,
    Selly,
    Shop,
    ShoperListing,
    ShopGold,
    Shopify,
    Shoptet,
    SingleTcg,
    SkyShop,
    Smajk,
    Smyk,
    Sote,
    WooCommerce
  }

  @produkt ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @produkt_no_slash ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*\z|
  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @sklep ~r|\A/sklep/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @sklep_nested ~r|\A/sklep/(?:[a-z0-9]+(?:-[a-z0-9]+)*/){1,5}\z|
  @tcg_nested ~r|\A/tcg/(?:[a-z0-9]+(?:-[a-z0-9]+)*/){1,5}\z|

  # Shoper's whole-shop exports; a shop enables one or the other integration.
  @shoper_google "/console/integration/execute/name/GoogleProductSearch"
  @shoper_ceneo "/console/integration/execute/name/CeneoV2"

  @shops [
    %Shop{
      key: "cardgallery",
      name: "Card Gallery",
      host: "cardgallery.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      singles_categories: ["Single Angielskie", "Karty ocenione (PSA/CGC)"],
      shipping_from: Decimal.new("13.99"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: "Kraków"
    },
    %Shop{
      key: "pokecoffee",
      name: "PokeCoffee",
      host: "pokecoffee.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      singles_categories: ["Pojedyncze Karty > Pojedyncze Karty Pokemon"],
      shipping_from: Decimal.new("11.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "alpakagra",
      singles_categories: [
        "Artykuły kolekcjonerskie > Pojedyncze karty kolekcjonerskie > Karty Single Pokemon"
      ],
      name: "AlpakaGra",
      host: "alpakagra.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "atneles",
      name: "Atneles",
      host: "atneles.pl",
      source: WooCommerce,
      category: "22",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("12"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "boosterland",
      name: "Boosterland",
      host: "boosterland.pl",
      source: WooCommerce,
      category: "40",
      sealed_categories: ["pokemon"],
      product_path: @sklep_nested,
      max_pages: 3,
      shipping_from: Decimal.new("12.99"),
      free_shipping_from: nil,
      pickup_city: "Żukowo",
      pickup_location: {54.3424, 18.3645}
    },
    %Shop{
      key: "boostermania",
      name: "Boostermania",
      host: "boostermania.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("16"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "boosterpoint",
      name: "BoosterPoint",
      host: "boosterpoint.pl",
      source: WooCommerce,
      category: "61",
      sealed_categories: [
        "boostery",
        "booster-box",
        "blistry",
        "boostery-i-blistry",
        "puszki-tins",
        "boxy-vmax-vstar-ex",
        "gotowe-talie-deck",
        "puszki-decki-box-tcg",
        "elite-trainer-boxy",
        "zestawy-kolekcjonerskie"
      ],
      product_path: @produkt,
      max_pages: 10,
      shipping_from: Decimal.new("13.95"),
      free_shipping_from: Decimal.new("499"),
      pickup_city: nil
    },
    %Shop{
      key: "carddojo",
      name: "Card Dojo",
      host: "carddojo.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("19.99"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "cardfan",
      singles_categories: ["Gry Karciane > Pokemon > Single"],
      name: "CardFan",
      host: "www.cardfan.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("16.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "cardwolf",
      name: "Cardwolf",
      host: "cardwolf.pl",
      source: WooCommerce,
      category: "20,28,38,39",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "cardzhouse",
      name: "CardzHouse",
      host: "cardzhouse.pl",
      source: WooCommerce,
      category: "742",
      sealed_categories: [
        "boostery",
        "3-packi-blistry",
        "booster-bundle",
        "booster-boxy",
        "elite-trainer-boxy",
        "kolekcjonerskie",
        "premium-boxy",
        "puszki",
        "theme-decki"
      ],
      product_path: @product,
      max_pages: 10,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: "Gdynia",
      pickup_location: {54.5200, 18.5332}
    },
    %Shop{
      key: "colligere",
      name: "Colligere",
      host: "colligere.pl",
      source: WooCommerce,
      category: "23",
      sealed_categories: ["pokemon-tcg"],
      product_path: @sklep,
      max_pages: 3,
      shipping_from: Decimal.new("10.99"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "diablestcg",
      name: "Diables TCG",
      host: "diablestcg.pl",
      source: WooCommerce,
      category: "202",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: Decimal.new("399.99"),
      pickup_city: nil
    },
    %Shop{
      key: "epiccard",
      name: "EpicCard",
      host: "epiccard.pl",
      source: IdoSell,
      feed_path: "/search.php?text=pokemon",
      max_pages: 15,
      shipping_from: Decimal.new("15.26"),
      free_shipping_from: Decimal.new("450"),
      pickup_city: "Żory",
      pickup_location: {50.0434, 18.6860}
    },
    %Shop{
      key: "flamberg",
      name: "Flamberg",
      host: "flamberg.com.pl",
      source: IdoSell,
      feed_path: "/pl/menu/pokemon-687",
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: Decimal.new("400"),
      pickup_city: "Katowice",
      pickup_location: {50.2605, 19.0208}
    },
    %Shop{
      key: "gnom",
      name: "Gnom",
      host: "gnom-sklep.pl",
      source: IdoSell,
      feed_path: "/pl/menu/pokemon-tcg-449",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("450"),
      pickup_city: nil
    },
    %Shop{
      key: "graal",
      name: "Graal",
      host: "sklep-graal.pl",
      source: CeneoFeed,
      feed_path: @shoper_ceneo,
      max_pages: 1,
      shipping_from: Decimal.new("19"),
      free_shipping_from: nil,
      pickup_city: "Warszawa",
      pickup_location: {52.2129, 20.9558}
    },
    %Shop{
      key: "gralnia",
      name: "Gralnia",
      host: "gralnia.org",
      source: WooCommerce,
      category: "229",
      product_path: @produkt,
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "grovetcg",
      name: "Grove TCG",
      host: "grovetcg.pl",
      source: WooCommerce,
      category: "19",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("13.99"),
      free_shipping_from: Decimal.new("499"),
      pickup_city: "Tarnowskie Góry",
      pickup_location: {50.4489, 18.8627}
    },
    %Shop{
      key: "grybezpradu",
      name: "Gry Bez Prądu",
      host: "grybezpradu.eu",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("14.99"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: "Poznań",
      pickup_location: {52.4137, 16.8951}
    },
    %Shop{
      key: "gryujanusza",
      name: "Gry u Janusza",
      host: "gryujanusza.pl",
      source: Shopify,
      collection: "tcg-pokemon",
      max_pages: 3,
      shipping_from: Decimal.new("18"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "hejmistrzu",
      name: "Hej Mistrzu",
      host: "hejmistrzu.pl",
      source: WooCommerce,
      category: "25",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Rumia",
      pickup_location: {54.5565, 18.4092}
    },
    %Shop{
      key: "jigglypack",
      name: "Jigglypack",
      host: "www.jigglypack.pl",
      source: WooCommerce,
      category: "191",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "kantodrop",
      singles_categories: ["KARTY SV", "KARTY ME", "KARTY SWSH"],
      name: "KantoDrop",
      host: "kantodrop.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("14.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "karciarz",
      name: "Karciarz",
      host: "karciarz.com",
      source: WooCommerce,
      category: "15",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("16"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "kartomaniak",
      singles_categories: ["Karty - Single > Pokémon"],
      name: "Kartomaniak",
      host: "kartomaniak.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "kartonada",
      name: "Kartonada",
      host: "kartonada.pl",
      source: WooCommerce,
      category: "16",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("14.99"),
      free_shipping_from: Decimal.new("399"),
      pickup_city: "Suwałki",
      pickup_location: {54.0991, 22.9304}
    },
    %Shop{
      key: "kartoteka",
      name: "Kartoteka",
      host: "sklepkartoteka.pl",
      source: WooCommerce,
      category: "78,80",
      # English singles only; Japanese, Korean and Chinese ones have their own.
      singles_categories: ["79"],
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("16.99"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "kartsy",
      name: "Kartsy",
      host: "kartsy.pl",
      source: IdoSell,
      feed_path: "/search.php?text=pokemon",
      max_pages: 3,
      shipping_from: Decimal.new("9.9"),
      free_shipping_from: nil,
      pickup_city: "Kraków",
      pickup_location: {50.0177, 19.9060}
    },
    %Shop{
      key: "kegami",
      name: "Kegami",
      host: "kegami.pl",
      source: CeneoFeed,
      feed_path: @shoper_ceneo,
      max_pages: 1,
      shipping_from: Decimal.new("12.5"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "krainagoblinow",
      name: "Kraina Goblinów",
      host: "krainagoblinow.pl",
      source: WooCommerce,
      category: "92",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "krajen",
      name: "Krajen",
      host: "krajen.pl",
      source: WooCommerce,
      category: "113",
      product_path: @tcg_nested,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "kupteraz",
      name: "Kup Teraz",
      host: "kupteraz.com.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("18"),
      free_shipping_from: Decimal.new("499"),
      pickup_city: nil
    },
    %Shop{
      key: "lootquest",
      name: "LootQuest",
      host: "lootquest.pl",
      source: WooCommerce,
      category: "55",
      sealed_categories: [
        "pokemon-boostery",
        "pokemon-blistry",
        "pokemon-zestawy",
        "pokemon-talie"
      ],
      product_path: @produkt,
      max_pages: 10,
      shipping_from: Decimal.new("14"),
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "luznepaczki",
      singles_categories: ["Single > Pokemon"],
      name: "Luźne Paczki",
      host: "luznepaczki.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "magiccafe",
      name: "Magic Cafe",
      host: "magiccafe.eu",
      source: WooCommerce,
      category: "257",
      product_path: @product,
      max_pages: 10,
      shipping_from: Decimal.new("12.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "mepel",
      name: "Mepel",
      host: "mepel.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("7"),
      free_shipping_from: Decimal.new("70"),
      pickup_city: "Katowice",
      # The store address is unpublished: the company's registered address.
      pickup_location: {50.2320, 18.9633}
    },
    %Shop{
      key: "mrpuggy",
      singles_categories: ["Karty Kolekcjonerskie > Karty Pokemon > Single Pokemon"],
      name: "Mr. Puggy",
      host: "mrpuggy.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: Decimal.new("300"),
      pickup_city: "Kraków",
      pickup_location: {50.0208, 20.0498}
    },
    %Shop{
      key: "nearmint",
      name: "Nearmint",
      host: "nearmint.pl",
      source: WooCommerce,
      category: "32",
      product_path: @produkt_no_slash,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "oscg",
      name: "OSCG",
      host: "oscg.pl",
      source: WooCommerce,
      category: "44",
      product_path: @produkt,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "paladynat",
      name: "Paladynat",
      host: "paladynat.pl",
      source: WooCommerce,
      category: "4500",
      product_path: @sklep_nested,
      max_pages: 3,
      shipping_from: Decimal.new("13.5"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "panmysza",
      name: "Pan Mysza",
      host: "panmysza.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("600"),
      pickup_city: nil
    },
    %Shop{
      key: "pika",
      name: "pi-ka.space",
      host: "pi-ka.space",
      source: WooCommerce,
      category: "587",
      singles_categories: ["123"],
      product_path: @product,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pikatube",
      singles_categories: ["Single/Slaby/Akcesoria"],
      name: "PikaTube",
      host: "pikatube.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "planszolek",
      name: "Planszołek",
      host: "www.planszolek.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("11.99"),
      free_shipping_from: Decimal.new("450"),
      pickup_city: "Brzesko",
      pickup_location: {49.9670, 20.6073}
    },
    %Shop{
      key: "pokebeast",
      name: "PokeBeast",
      host: "pokebeast.pl",
      source: WooCommerce,
      category: "16,17",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("11.99"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "pokebooster",
      name: "PokeBooster",
      host: "pokebooster.pl",
      source: WooCommerce,
      category: "26,27,42,57",
      sealed_categories: ["booster", "elite-trainer-box", "premium-collection", "puszki"],
      product_path: @produkt,
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokecollect",
      name: "PokeCollect",
      host: "pokecollect.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("12.9"),
      free_shipping_from: Decimal.new("400"),
      pickup_city: "Lublin",
      pickup_location: {51.2516, 22.5437}
    },
    %Shop{
      key: "pokegemcollector",
      singles_categories: ["Single TCG > Pokemon TCG > Angielskie"],
      name: "PokeGemCollector",
      host: "www.pokegemcollector.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("16.95"),
      free_shipping_from: Decimal.new("600"),
      pickup_city: nil
    },
    %Shop{
      key: "pokelab",
      name: "Poke-Lab",
      host: "poke-lab.pl",
      source: Shopify,
      singles_categories: ["pojedyncze-karty"],
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "pokemaniak",
      name: "Pokemaniak",
      host: "pokemaniak.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "pokenest",
      name: "PokeNest",
      host: "pokenest.pl",
      source: WooCommerce,
      category: "70,76,77,90,91,92",
      singles_categories: ["99"],
      product_path: @produkt,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("299"),
      pickup_city: nil
    },
    %Shop{
      key: "pokespot",
      name: "PokeSpot",
      host: "pokespot.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("13.49"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: "Luboń",
      # The street is unpublished: the centre of Luboń.
      pickup_location: {52.3367, 16.8718}
    },
    %Shop{
      key: "pokeverse",
      name: "PokeVerse",
      host: "www.pokeverse.pl",
      source: WooCommerce,
      category: "71",
      product_path: @produkt,
      max_pages: 5,
      shipping_from: Decimal.new("10.97"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "razorcards",
      name: "Razor Cards",
      host: "razorcards.pl",
      source: WooCommerce,
      category: "35,108,112,114,119",
      singles_categories: ["105"],
      product_path: @produkt,
      max_pages: 12,
      shipping_from: nil,
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "redraft",
      name: "Redraft",
      host: "redraft.pl",
      source: IdoSell,
      feed_path: "/pl/menu/pokemon-tcg-176.html",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("400"),
      pickup_city: "Katowice",
      pickup_location: {50.2572, 19.0122}
    },
    %Shop{
      key: "skarbieckart",
      name: "SkarbiecKart",
      host: "skarbieckart.pl",
      source: Shopify,
      max_pages: 3,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "skladgier",
      name: "Skład Gier",
      host: "skladgier.pl",
      source: Shopify,
      collection: "pokemon-tcg",
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "straganogra",
      name: "Stragan Ogra",
      host: "straganogra.pl",
      source: WooCommerce,
      category: "30",
      product_path: @produkt,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Chrzanów",
      pickup_location: {50.1423, 19.4082}
    },
    %Shop{
      key: "strefakart",
      name: "Strefa Kart",
      host: "strefakart.pl",
      source: WooCommerce,
      category: "17",
      singles_categories: ["51"],
      product_path: @product,
      max_pages: 8,
      shipping_from: Decimal.new("10"),
      free_shipping_from: Decimal.new("299"),
      pickup_city: nil
    },
    %Shop{
      key: "strefamarzen",
      name: "Strefa Marzeń",
      host: "strefamarzen.pl",
      source: IdoSell,
      feed_path: "/search.php?text=pokemon+tcg",
      max_pages: 12,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: Decimal.new("350"),
      pickup_city: "Bielsko-Biała",
      pickup_location: {49.8283, 19.0479}
    },
    %Shop{
      key: "strefatcg",
      singles_categories: ["Pokemon TCG > single"],
      name: "Strefa TCG",
      host: "strefa-tcg.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("12"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "swiatkart",
      # The feed files every single under plain "Single", other games too.
      singles_categories: ["Single"],
      name: "Świat Kart",
      host: "swiatkart.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: Decimal.new("599"),
      pickup_city: nil
    },
    %Shop{
      key: "tcghobby",
      name: "TCGHobby",
      host: "tcghobby.pl",
      source: WooCommerce,
      category: "199",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "tcghub",
      name: "TCG Hub",
      host: "tcghub.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("12"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "tcglove",
      name: "TCGLove",
      host: "www.tcglove.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgtrener",
      name: "TCG Trener",
      host: "tcgtrener.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("18"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgzielona",
      name: "TCG Zielona",
      host: "tcg-zielona.pl",
      source: WooCommerce,
      category: "122",
      product_path: @product,
      max_pages: 3,
      shipping_from: Decimal.new("16.99"),
      free_shipping_from: Decimal.new("800"),
      pickup_city: nil
    },
    %Shop{
      key: "time4magic",
      name: "Time4Magic",
      host: "time4magic.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("12.99"),
      free_shipping_from: Decimal.new("349"),
      pickup_city: "Wrocław",
      pickup_location: {51.1223, 16.9932}
    },
    %Shop{
      key: "tubacards",
      name: "TubaCards",
      host: "tubacards.pl",
      source: WooCommerce,
      category: "26",
      product_path: @sklep_nested,
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "zagrajnik",
      name: "Zagrajnik",
      host: "zagrajnik.shop",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("349"),
      pickup_city: "Izabelin C",
      pickup_location: {52.2944, 20.8131}
    },
    %Shop{
      key: "zarc",
      name: "Zarc",
      host: "zarc.pl",
      source: GoogleFeed,
      feed_path: @shoper_google,
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: Decimal.new("600"),
      pickup_city: "Jaworzno",
      pickup_location: {50.2022, 19.2741}
    },
    %Shop{
      key: "zgrani",
      name: "Zgrani",
      host: "zgrani.pl",
      source: IdoSell,
      feed_path: "/pl/menu/pokemon-208",
      max_pages: 5,
      shipping_from: Decimal.new("11.99"),
      free_shipping_from: Decimal.new("199"),
      pickup_city: nil
    },
    %Shop{
      key: "3trolle",
      name: "Trzy Trolle",
      host: "3trolle.pl",
      source: PrestaShop,
      listing_paths: ["/833-pokemon"],
      max_pages: 12,
      shipping_from: Decimal.new("9.99"),
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "arenasklep",
      singles_categories: ["/13-pokemon-tcg-single"],
      name: "Arena Centrum Gier",
      host: "arena-sklep.pl",
      source: PrestaShop,
      listing_paths: ["/15-pokemon-tcg"],
      max_pages: 3,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: Decimal.new("199"),
      pickup_city: nil
    },
    %Shop{
      key: "grymel",
      name: "Grymel",
      host: "grymel.pl",
      source: PrestaShop,
      listing_paths: ["/204-karty-pokemon-trading-card-game"],
      max_pages: 2,
      shipping_from: Decimal.new("13.9"),
      free_shipping_from: Decimal.new("149.9"),
      pickup_city: nil
    },
    %Shop{
      key: "heartspub",
      name: "Hearts Pub",
      host: "hearts.pub",
      source: PrestaShop,
      images: false,
      listing_paths: ["/sklep/pokemon-tcg"],
      max_pages: 16,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Gliwice",
      pickup_location: {50.2882, 18.6713}
    },
    %Shop{
      key: "hobbity",
      name: "Hobbity",
      host: "hobbity.pl",
      source: PrestaShop,
      listing_paths: ["/gry-karciane-kolekcjonerskie/pokemon-tcg"],
      max_pages: 12,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("289"),
      pickup_city: "Nowy Sącz",
      pickup_location: {49.6188, 20.6944}
    },
    %Shop{
      key: "monsteriada",
      name: "Monsteriada",
      host: "monsteriada.pl",
      source: PrestaShop,
      listing_paths: ["/93-pokemon-tcg-karty-kolekjonerskie"],
      max_pages: 8,
      shipping_from: Decimal.new("12"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "pegazgry",
      name: "Centrum Gier Pegaz",
      host: "pegaz-gry.pl",
      source: PrestaShop,
      listing_paths: ["/22-pokemon-tcg-gra-karciana-sklep-bydgoszcz"],
      max_pages: 10,
      shipping_from: Decimal.new("10"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: "Bydgoszcz",
      pickup_location: {53.1209, 17.9978}
    },
    %Shop{
      key: "basanti",
      name: "Basanti Pokemon",
      host: "poke.basanti.pl",
      source: PrestaShop,
      listing_paths: ["/71-rodzaje"],
      max_pages: 8,
      shipping_from: Decimal.new("17.9"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "poketeka",
      name: "Poketeka",
      host: "www.poketeka.pl",
      source: PrestaShop,
      listing_paths: ["/56-pokemon-tcg"],
      max_pages: 10,
      shipping_from: Decimal.new("10"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "rgfk",
      name: "RGFK",
      host: "rgfk.pl",
      source: PrestaShop,
      listing_paths: ["/k/51874/pokemon-tcg"],
      max_pages: 12,
      shipping_from: Decimal.new("10"),
      free_shipping_from: Decimal.new("200"),
      pickup_city: nil
    },
    %Shop{
      key: "stajniagier",
      name: "Stajnia Gier",
      host: "stajnia-gier.pl",
      source: PrestaShop,
      listing_paths: ["/178-pokemon-tcg"],
      max_pages: 4,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("350"),
      pickup_city: nil
    },
    %Shop{
      key: "strefamtg",
      name: "Strefa MTG",
      host: "strefamtg.pl",
      source: PrestaShop,
      listing_paths: ["/2837-boostery-i-boxy-pokemon", "/2838-talie-i-zestawy-kart-pokemon"],
      max_pages: 6,
      shipping_from: Decimal.new("16"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "vanaheim",
      name: "Vanaheim",
      host: "vanaheim.pl",
      source: PrestaShop,
      listing_paths: ["/pl/2095-pokemon-tcg"],
      max_pages: 3,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("400"),
      pickup_city: "Kraków",
      pickup_location: {50.0655, 19.9527}
    },
    %Shop{
      key: "wgre",
      name: "wGRE",
      host: "wgre.pl",
      source: PrestaShop,
      listing_paths: ["/257-tcg"],
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "planszomania",
      name: "Planszomania",
      host: "www.planszomania.pl",
      source: Planszomania,
      feed_path: "/szukaj/pokemon",
      max_pages: 1,
      shipping_from: Decimal.new("16"),
      free_shipping_from: Decimal.new("350"),
      pickup_city: "Warszawa",
      pickup_location: {52.2603, 20.9208}
    },
    %Shop{
      key: "merfolk",
      name: "Merfolk",
      host: "sklep.merfolk.pl",
      source: Pasaz24,
      feed_path: "/category/POKEMON-TCG-345476",
      max_pages: 12,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Pruszków",
      pickup_location: {52.1669, 20.8029}
    },
    %Shop{
      key: "sidequest",
      name: "Side Quest",
      host: "www.sklep.sidequest.pl",
      source: Pasaz24,
      feed_path: "/category/Pokemon-TCG-445952",
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Gdańsk",
      pickup_location: {54.3782, 18.6041}
    },
    %Shop{
      key: "am76",
      name: "AM76",
      host: "am76.pl",
      source: Am76,
      feed_path: "/pokemon",
      max_pages: 6,
      shipping_from: Decimal.new("12.99"),
      free_shipping_from: Decimal.new("390"),
      pickup_city: "Warszawa",
      pickup_location: {52.1407, 21.0596}
    },
    %Shop{
      key: "gildiagrodzisk",
      name: "Gildia Grodzisk",
      host: "gildiagrodzisk.pl",
      source: GildiaGrodzisk,
      feed_path: "/category/pokemon-tcg",
      max_pages: 6,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Grodzisk Mazowiecki",
      pickup_location: {52.1084, 20.6226}
    },
    %Shop{
      key: "magicznyrynek",
      name: "Magiczny Rynek",
      host: "magicznyrynek.pl",
      source: MagicznyRynek,
      feed_path: "/collections/pokemon/",
      max_pages: 10,
      shipping_from: Decimal.new("16"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "guildmage",
      name: "Guildmage",
      host: "guildmage.pl",
      source: Guildmage,
      feed_path: "/pokemon",
      max_pages: 4,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "collectify",
      name: "Collectify",
      host: "collectify.pl",
      source: Collectify,
      feed_path: "/sealed-products",
      max_pages: 5,
      shipping_from: Decimal.new("18.99"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "smajk",
      name: "Smajk",
      host: "smajk.pl",
      source: Smajk,
      feed_path: "/c/pokemon-tcg",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "smyk",
      name: "Smyk",
      host: "www.smyk.com",
      source: Smyk,
      feed_path: "/pl/pl/zabawki-gry/pokemon-tcg.html",
      max_pages: 1,
      shipping_from: Decimal.new("8.99"),
      free_shipping_from: Decimal.new("199"),
      pickup_city: nil
    },
    %Shop{
      key: "empik",
      name: "Empik",
      host: "www.empik.com",
      source: Empik,
      feed_path: "/zabawki/karty-kolekcjonerskie,3777,s",
      max_pages: 10,
      shipping_from: Decimal.new("10.99"),
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
    },
    %Shop{
      key: "elfiagrota",
      name: "Elfia Grota",
      host: "elfiagrota.pl",
      source: ShopGold,
      listing_paths: ["/pokmon-c-43.html"],
      max_pages: 12,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "karcianybunkier",
      name: "Karciany Bunkier",
      host: "karcianybunkier.pl",
      source: ShopGold,
      listing_paths: ["/httpspokevcrpl-c-16.html"],
      max_pages: 12,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "lochyikoty",
      name: "Lochy i Koty",
      host: "www.lochyikoty.pl",
      source: ShopGold,
      listing_paths: ["/pokemon-produkty-c-10.html"],
      max_pages: 12,
      shipping_from: Decimal.new("10"),
      free_shipping_from: Decimal.new("1000"),
      pickup_city: nil
    },
    %Shop{
      key: "moriongames",
      name: "Morion Games",
      host: "www.moriongames.pl",
      source: ShopGold,
      listing_paths: ["/httpswwwmoriongamesplpokemon-c-6-13-131html-c-6_13_131.html"],
      max_pages: 30,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("600"),
      pickup_city: "Warszawa",
      pickup_location: {52.2744, 20.9378}
    },
    %Shop{
      key: "pokapoke",
      name: "PokaPoke",
      host: "pokapoke.pl",
      source: ShopGold,
      listing_paths: ["/pokemon-tcg-c-1.html"],
      max_pages: 6,
      shipping_from: Decimal.new("14.99"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "poketrader",
      name: "PokeTrader",
      host: "poketrader.eu",
      source: ShopGold,
      listing_paths: [
        "/booster-c-1.html",
        "/booster-box-c-3.html",
        "/elite-trainer-box-etb-c-4.html",
        "/blistry-checklane-c-5.html",
        "/boxy-upc-c-6.html",
        "/puszki-c-7.html",
        "/decki-produkty-dla-graczy-c-9.html",
        "/3-pack-tech-sticker-c-192.html",
        "/japonskie-karty-pokemon-c-130.html",
        "/chinskie-karty-pokemon-c-196.html"
      ],
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "truecollector",
      name: "True Collector",
      host: "www.truecollector.pl",
      source: ShopGold,
      listing_paths: ["/pokmon-tcg-c-1.html"],
      max_pages: 12,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "twojekarty",
      name: "TwojeKarty.pl",
      host: "twojekarty.pl",
      source: ShopGold,
      listing_paths: [
        "/boostery-c-59.html",
        "/booster-boxy-c-60.html",
        "/elite-trainer-boxy-c-61.html",
        "/blistry-3-packi-mini-albumy-c-62.html",
        "/puszki-boxy-c-63.html",
        "/decki-i-produkty-dla-graczy-c-65.html",
        "/japonskie-karty-pokemon-c-112.html",
        "/chinskie-karty-pokemon-c-146.html",
        "/koreanskie-karty-pokemon-c-140.html"
      ],
      max_pages: 20,
      shipping_from: Decimal.new("13"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "nora",
      name: "Nora",
      host: "nora.sklep.pl",
      source: Sellingo,
      listing_paths: ["/pokemon-tcg"],
      max_pages: 1,
      shipping_from: Decimal.new("11.90"),
      free_shipping_from: Decimal.new("399"),
      pickup_city: nil
    },
    %Shop{
      key: "plastiq",
      name: "Plastiq",
      host: "plastiq.pl",
      source: Selly,
      listing_paths: ["/karty-pokemon,c127.html"],
      max_pages: 8,
      shipping_from: Decimal.new("18"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: "Warszawa",
      pickup_location: {52.1677, 21.0048}
    },
    %Shop{
      key: "wilczek",
      name: "Wilczek Poznań",
      host: "wilczek.poznan.pl",
      source: Sote,
      listing_paths: ["/category/pokemon"],
      max_pages: 12,
      shipping_from: Decimal.new("17"),
      free_shipping_from: nil,
      pickup_city: "Poznań",
      pickup_location: {52.4082, 16.9385}
    },
    %Shop{
      key: "bastiontcg",
      name: "Bastion TCG",
      host: "bastiontcg.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Pokemon/38",
      max_pages: 4,
      shipping_from: Decimal.new("17"),
      free_shipping_from: Decimal.new("999"),
      pickup_city: nil
    },
    %Shop{
      key: "dragonus",
      name: "Dragonus",
      host: "dragonus.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Pokemon/315",
      mixed_listing: true,
      max_pages: 8,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: "Kraków",
      pickup_location: {50.0669, 19.9566}
    },
    %Shop{
      key: "kartexpol",
      singles_categories: ["/pl/c/Angielskie/216"],
      name: "Kartexpol",
      host: "www.kartexpol.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Pokemon-TCG/38",
      max_pages: 8,
      shipping_from: Decimal.new("16"),
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "lukillo",
      name: "Lukillo",
      host: "lukillo.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Pokemon-TCG/46",
      max_pages: 4,
      shipping_from: Decimal.new("12.99"),
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "magplanszowy",
      name: "Mag Planszowy",
      host: "magplanszowy.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Pokemon-TCG/52",
      max_pages: 6,
      shipping_from: Decimal.new("15.99"),
      free_shipping_from: nil,
      pickup_city: "Wrocław",
      pickup_location: {51.1120, 17.0356}
    },
    %Shop{
      key: "mycards",
      singles_categories: ["/pl/c/Single-Angielskie/26"],
      name: "MyCards.pl",
      host: "mycards.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Pokemon-TCG/1",
      max_pages: 6,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokesmart",
      singles_categories: [
        "/pl/c/Era-Mega-Evolution/273",
        "/pl/c/Era-Scarlet-Violet/79",
        "/pl/c/Era-Sword-Shield/78",
        "/pl/c/Karty-Promo/261"
      ],
      name: "PokeSmart",
      host: "pokesmart.pl",
      source: ShoperListing,
      feed_path: "/pl/c/Produkty-Pokemon/232",
      preorder_path: "/pl/c/Produkty-Pokemon/232/1/default/1/f_collection_21/1",
      max_pages: 3,
      shipping_from: Decimal.new("11.95"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "raventcg",
      singles_categories: ["/pl/collection/Karty-Single/13"],
      name: "RavenTCG",
      host: "raventcg.pl",
      source: ShoperListing,
      feed_path: "/pokemon-tcg",
      max_pages: 3,
      shipping_from: Decimal.new("14.99"),
      free_shipping_from: Decimal.new("299"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgheaven",
      name: "TCG Heaven",
      host: "tcgheaven.eu",
      source: ShoperListing,
      feed_path: "/pokemon-tcg",
      max_pages: 6,
      shipping_from: Decimal.new("16"),
      free_shipping_from: Decimal.new("350"),
      pickup_city: nil
    },
    %Shop{
      key: "canislupus",
      name: "Canis Lupus",
      host: "www.canislupus.com.pl",
      source: SkyShop,
      feed_path: "/Pokemon-c713",
      max_pages: 14,
      shipping_from: Decimal.new("9.99"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: "Poznań",
      pickup_location: {52.3735, 16.9807}
    },
    %Shop{
      key: "chaosgames",
      name: "Chaos Games",
      host: "chaos-games.pl",
      source: SkyShop,
      feed_path: "/Pokemon-c212",
      max_pages: 4,
      shipping_from: Decimal.new("9.99"),
      free_shipping_from: Decimal.new("450"),
      pickup_city: "Piła",
      pickup_location: {53.1498, 16.7350}
    },
    %Shop{
      key: "japancollectibles",
      name: "Japan Collectibles",
      host: "japancollectibles.shop",
      source: SkyShop,
      feed_path: "/Karty-Pokemon",
      max_pages: 25,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Elbląg",
      pickup_location: {54.1590, 19.3949}
    },
    %Shop{
      key: "jaskiniatrolla",
      name: "Jaskinia Trolla",
      host: "jaskiniatrolla.pl",
      source: SkyShop,
      feed_path: "/Pokemon-c564",
      max_pages: 4,
      shipping_from: Decimal.new("16"),
      free_shipping_from: Decimal.new("600"),
      pickup_city: nil
    },
    %Shop{
      key: "krakenshop",
      name: "KrakenShop",
      host: "krakenshop.pl",
      source: SkyShop,
      feed_path: "/karty-pokemon",
      max_pages: 2,
      shipping_from: Decimal.new("9.99"),
      free_shipping_from: Decimal.new("299"),
      pickup_city: nil
    },
    %Shop{
      key: "loficards",
      name: "LofiCards",
      host: "loficards.pl",
      source: SkyShop,
      feed_path: "/pokemon",
      max_pages: 16,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("399"),
      pickup_city: "Poznań",
      pickup_location: {52.3918, 16.8958}
    },
    %Shop{
      key: "planszon",
      name: "Planszon",
      host: "planszon.pl",
      source: SkyShop,
      feed_path: "/Pokemon-TCG-c32",
      max_pages: 5,
      shipping_from: Decimal.new("10.99"),
      free_shipping_from: Decimal.new("500"),
      pickup_city: "Warszawa",
      pickup_location: {52.2606, 21.0426}
    },
    %Shop{
      key: "pokecentrum",
      name: "PokeCentrum",
      host: "pokecentrum.pl",
      source: SkyShop,
      feed_path: "/Angielskie-c30",
      max_pages: 4,
      shipping_from: Decimal.new("15"),
      free_shipping_from: Decimal.new("499"),
      pickup_city: nil
    },
    %Shop{
      key: "pokemoon",
      singles_categories: ["Single angielskie"],
      name: "PokeMoon",
      host: "pokemoon.pl",
      source: CeneoFeed,
      feed_path: @shoper_ceneo,
      max_pages: 1,
      shipping_from: Decimal.new("13.90"),
      free_shipping_from: Decimal.new("290"),
      pickup_city: "Warszawa"
    },
    %Shop{
      key: "letsgotry",
      name: "LetsGoTry",
      host: "letsgotry.pl",
      source: PrestaShop,
      listing_paths: ["/pl/37-angielskie", "/pl/33-japonskie"],
      # English singles only; "/pl/850-pokemon-tcg" lists Japanese ones too.
      singles_categories: ["/pl/777-pojedyncze-single"],
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: Decimal.new("500"),
      pickup_city: nil
    },
    %Shop{
      key: "pokemonki",
      name: "Pokémonki",
      host: "pokemonki.pl",
      source: Pokemonki,
      # Not read (the set index decides); nil would disable singles.
      singles_categories: ["all"],
      max_pages: 40,
      shipping_from: Decimal.new("13.99"),
      free_shipping_from: Decimal.new("300"),
      pickup_city: nil
    },
    %Shop{
      key: "singletcg",
      name: "single TCG",
      host: "singletcg.pl",
      source: SingleTcg,
      # Not read (the shop's two listings decide); nil would disable singles.
      singles_categories: ["all"],
      max_pages: 40,
      # InPost parcel locker 15.28 zł (up to 200 zł), no free delivery.
      shipping_from: Decimal.new("15.28"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokekarty",
      name: "PokeKarty",
      host: "www.pokekarty.pl",
      source: WooCommerce,
      # The versioned path answers with a bot check; this one is the same API.
      feed_path: "/wp-json/wc/store/products",
      category: "80,81,82,83,84,89",
      singles_categories: ["1431"],
      product_path: ~r{\A/product/[a-z0-9-]+\z},
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: Decimal.new("300"),
      pickup_city: "Warszawa"
    },
    # Stragan Ogra's singles shop.
    %Shop{
      key: "kolekcjonerkart",
      name: "Kolekcjoner Kart",
      host: "kolekcjonerkart.pl",
      source: WooCommerce,
      singles_categories: ["19"],
      product_path: @produkt,
      # No sealed category; singles have their own page limit.
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Chrzanów",
      pickup_location: {50.1423, 19.4082}
    },
    # Shops abroad: priced in their currency, mostly for their singles, and
    # compared at their price with delivery to Poland converted to PLN (NBP,
    # 6 November 2026: EUR 4.39, GBP 5.26, SEK 0.40, CZK 0.18, DKK 0.59); one
    # without a known delivery price is only listed (`compared_price/2`).
    #
    # Bangerpack (White Tree AB, Helsingborg) asked to be listed and gave its
    # Google Shopping export, served from its CDN in euros; it holds sealed
    # products only. Its FAQ (2026-11-10) says it ships to Poland at a price
    # shown only in the checkout and has no free delivery.
    %Shop{
      key: "bangerpack",
      name: "Bangerpack",
      host: "bangerpack.com",
      source: GoogleFeed,
      feed_host: "cdn.bangerpack.com",
      feed_path: "/shopping-pl.xml",
      currency: "EUR",
      country: "SE",
      max_pages: 1,
      # €10.99 to Poland in its checkout for a €1.99 cart (2026-11-10): a lower
      # bound, a heavier parcel (a booster box) may cost more.
      shipping_from: Decimal.new("48.25"),
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
      # €7.95, free from €250.
      shipping_from: Decimal.new("34.92"),
      free_shipping_from: Decimal.new("1098"),
      pickup_city: nil
    },
    %Shop{
      key: "tcgking",
      name: "TCG King",
      host: "tcgking.nl",
      source: Shopify,
      # "all" also lists One Piece and Lorcana cards and sealed products;
      # this collection holds exactly its Pokémon singles (November 2026).
      singles_categories: ["pokemon-all-singles"],
      currency: "EUR",
      singles_only: true,
      country: "NL",
      max_pages: 20,
      # €10.95, free from €100.
      shipping_from: Decimal.new("48.10"),
      free_shipping_from: Decimal.new("439"),
      pickup_city: nil
    },
    %Shop{
      key: "gemipulls",
      name: "GemiPulls",
      host: "gemipulls.com",
      source: Shopify,
      singles_categories: ["singles"],
      currency: "DKK",
      singles_only: true,
      country: "DK",
      max_pages: 5,
      # 109 DKK standard to Poland in its cart, also for 699 DKK (2026-11-10).
      shipping_from: Decimal.new("64.31"),
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
      # €13.95 to Poland, also for an order of €270.
      shipping_from: Decimal.new("61.28"),
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
      # 99 SEK tracked letter to the EU, free from 799 SEK (319.60 zł, rounded
      # up so no order is shown with free delivery it does not get).
      shipping_from: Decimal.new("39.40"),
      free_shipping_from: Decimal.new("320"),
      pickup_city: nil
    },
    %Shop{
      key: "unicorncards",
      name: "Unicorn Cards",
      host: "unicorncards.co.uk",
      source: NopCommerce,
      singles_categories: ["1:1"],
      currency: "GBP",
      singles_only: true,
      country: "GB",
      max_pages: 40,
      # £5.90 for any number of singles, duties paid (IOSS), free from £100.
      shipping_from: Decimal.new("31.05"),
      free_shipping_from: Decimal.new("526.30"),
      pickup_city: nil
    },
    %Shop{
      key: "bulbazard",
      name: "Bulbazard",
      host: "www.bulbazard.cz",
      source: Shoptet,
      singles_categories: ["/kusove-karty-pokemon/"],
      currency: "CZK",
      singles_only: true,
      country: "CZ",
      max_pages: 40,
      # Zásilkovna (Packeta) to Poland 149 Kč.
      shipping_from: Decimal.new("26.89"),
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @keys Enum.map(@shops, & &1.key)

  # A shop abroad is read through a client that checks the currency of its
  # prices, in a currency with a daily NBP rate, from a country the offer list
  # can name (`GuideComponents`).
  @abroad_sources [Shopify, WooCommerce, Chasedex, NopCommerce, Shoptet, GoogleFeed]
  @countries ~w(NL DE BE GB SE DK CZ)

  for shop <- @shops, shop.currency != "PLN" or shop.country != nil do
    unless shop.source in @abroad_sources and
             shop.currency in ExchangeRate.currencies() and
             shop.country in @countries,
           do: raise(ArgumentError, "shop abroad #{shop.key} is misconfigured")
  end

  @doc """
  The price an offer is compared at with other shops' offers (verdicts,
  lowest prices, history): a Polish shop's item price; a shop abroad's with
  its cheapest delivery to Poland, none from its free-delivery threshold.
  Nil for a shop abroad whose delivery price is unknown: it is only listed.
  """
  @spec compared_price(String.t(), Decimal.t()) :: Decimal.t() | nil
  def compared_price(key, price), do: shop_price(fetch(key), price)

  defp shop_price(
         {:ok, %Shop{country: country, shipping_from: shipping, free_shipping_from: free_from}},
         price
       )
       when country != nil do
    cond do
      shipping == nil -> nil
      free_from && not Decimal.lt?(price, free_from) -> price
      true -> Decimal.add(price, shipping)
    end
  end

  # A Polish shop, or one no longer configured.
  defp shop_price(_polish, price), do: price

  @doc "The offers that count in prices, each at its `compared_price/2`."
  @spec compared([offer]) :: [offer] when offer: %{shop: String.t(), price: Decimal.t()}
  def compared(offers) do
    # Each shop is looked up once, not once per offer: the singles banner
    # prices every card offer in stock.
    shops = offers |> Enum.map(& &1.shop) |> Enum.uniq() |> Map.new(&{&1, fetch(&1)})

    for offer <- offers,
        price = shop_price(Map.fetch!(shops, offer.shop), offer.price),
        price != nil,
        do: %{offer | price: price}
  end

  @doc """
  An offer's place in an offer list, as a float: its `compared_price/2`, or
  its item price for a shop that is only listed.
  """
  @spec listing_price(%{shop: String.t(), price: Decimal.t()}) :: float()
  def listing_price(offer),
    do: Decimal.to_float(compared_price(offer.shop, offer.price) || offer.price)

  @doc "Shops abroad compared with their delivery: `{shipping, free from}` by key."
  @spec delivered() :: %{String.t() => {Decimal.t(), Decimal.t() | nil}}
  def delivered do
    for %Shop{country: country, shipping_from: shipping} = shop <- @shops,
        country != nil and shipping != nil,
        into: %{},
        do: {shop.key, {shipping, shop.free_shipping_from}}
  end

  @doc "Shops abroad without a known delivery price: listed, never compared."
  @spec listed_only_keys() :: [String.t()]
  def listed_only_keys do
    for %Shop{country: country, shipping_from: nil} = shop <- @shops, country != nil, do: shop.key
  end

  @spec all() :: [Shop.t()]
  def all, do: @shops

  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Every host a shop's product images may be shown from."
  @spec image_hosts() :: [String.t()]
  def image_hosts, do: @shops |> Enum.flat_map(& &1.source.image_hosts(&1)) |> Enum.uniq()

  @spec fetch(term()) :: {:ok, Shop.t()} | :error
  def fetch(key) when key in @keys, do: {:ok, Enum.find(@shops, &(&1.key == key))}
  def fetch(_key), do: :error

  @doc "The shop's display name, or the raw key for a shop no longer configured."
  @spec name(String.t()) :: String.t()
  def name(key) do
    case fetch(key) do
      {:ok, shop} -> shop.name
      :error -> key
    end
  end

  @logo_dir Path.expand("../../../priv/static/images/shops", __DIR__)
  @logos for file <- File.ls!(@logo_dir), Path.extname(file) == ".webp", do: Path.rootname(file)
  for logo <- @logos, do: @external_resource(Path.join(@logo_dir, logo <> ".webp"))

  # A newly added logo file is not an external resource yet; recompile when the set changes.
  @doc false
  def __mix_recompile__? do
    logos =
      for file <- File.ls!(@logo_dir), Path.extname(file) == ".webp", do: Path.rootname(file)

    MapSet.new(logos) != MapSet.new(@logos)
  end

  @doc "Whether the shop has a logo in `priv/static/images/shops`."
  @spec logo?(String.t()) :: boolean()
  def logo?(key), do: key in @logos
end
