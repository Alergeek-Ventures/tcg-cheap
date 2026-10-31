defmodule TcgCheap.Sealed.Shops do
  @moduledoc """
  The Polish shops whose product feeds the buying guide reads, fixed in code:
  where and how to read each feed (see `TcgCheap.Sealed.Shop`) and the
  delivery facts shown next to its offers. The owner agreed recurring
  fetching from these shops.

  Delivery prices, free-delivery thresholds and pickup cities were checked on
  the shops' own pages on 2026-10-31; nil means the shop does not publish it.
  """

  alias TcgCheap.Sealed.{Shop, Shopify, WooCommerce}

  @produkt ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @produkt_no_slash ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*\z|
  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @sklep ~r|\A/sklep/[a-z0-9]+(?:-[a-z0-9]+)*/\z|
  @sklep_nested ~r|\A/sklep/(?:[a-z0-9]+(?:-[a-z0-9]+)*/){1,5}\z|
  @tcg_nested ~r|\A/tcg/(?:[a-z0-9]+(?:-[a-z0-9]+)*/){1,5}\z|

  @shops [
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
      pickup_city: "Żukowo"
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
      pickup_city: "Gdynia"
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
      pickup_city: "Tarnowskie Góry"
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
      pickup_city: "Rumia"
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
      key: "kartonada",
      name: "Kartonada",
      host: "kartonada.pl",
      source: WooCommerce,
      category: "16",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("14.99"),
      free_shipping_from: Decimal.new("399"),
      pickup_city: "Suwałki"
    },
    %Shop{
      key: "kartoteka",
      name: "Kartoteka",
      host: "sklepkartoteka.pl",
      source: WooCommerce,
      category: "78,80",
      product_path: @produkt,
      max_pages: 3,
      shipping_from: Decimal.new("16.99"),
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
      key: "pika",
      name: "pi-ka.space",
      host: "pi-ka.space",
      source: WooCommerce,
      category: "587",
      product_path: @product,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
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
      key: "pokelab",
      name: "Poke-Lab",
      host: "poke-lab.pl",
      source: Shopify,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("400"),
      pickup_city: nil
    },
    %Shop{
      key: "pokenest",
      name: "PokeNest",
      host: "pokenest.pl",
      source: WooCommerce,
      category: "70,76,77,90,91,92",
      product_path: @produkt,
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("299"),
      pickup_city: nil
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
      product_path: @produkt,
      max_pages: 12,
      shipping_from: nil,
      free_shipping_from: Decimal.new("250"),
      pickup_city: nil
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
      pickup_city: "Chrzanów"
    },
    %Shop{
      key: "strefakart",
      name: "Strefa Kart",
      host: "strefakart.pl",
      source: WooCommerce,
      category: "17",
      product_path: @product,
      max_pages: 8,
      shipping_from: Decimal.new("10"),
      free_shipping_from: Decimal.new("299"),
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
    }
  ]

  @keys Enum.map(@shops, & &1.key)

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
end
