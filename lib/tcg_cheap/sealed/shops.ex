defmodule TcgCheap.Sealed.Shops do
  @moduledoc """
  The Polish shops whose WooCommerce Store API feeds the buying guide.

  Each shop is fixed in code: the API host, the product categories requested,
  the category slugs that count as sealed Pokémon products, and the path shape
  of a product permalink. The owner agreed recurring fetching from these shops.
  """

  alias TcgCheap.Sealed.Shop

  @shops [
    %Shop{
      key: "lootquest",
      name: "LootQuest",
      host: "lootquest.pl",
      category: "55",
      sealed_categories: [
        "pokemon-boostery",
        "pokemon-blistry",
        "pokemon-zestawy",
        "pokemon-talie"
      ],
      product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      max_pages: 10
    },
    %Shop{
      key: "cardzhouse",
      name: "CardzHouse",
      host: "cardzhouse.pl",
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
      product_path: ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      max_pages: 10
    },
    %Shop{
      key: "boosterpoint",
      name: "BoosterPoint",
      host: "boosterpoint.pl",
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
      product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      max_pages: 10
    },
    %Shop{
      key: "pokebooster",
      name: "PokeBooster",
      host: "pokebooster.pl",
      category: "26,27,42,57",
      sealed_categories: ["booster", "elite-trainer-box", "premium-collection", "puszki"],
      product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      max_pages: 10
    },
    %Shop{
      key: "boosterland",
      name: "Boosterland",
      host: "boosterland.pl",
      category: "40",
      sealed_categories: ["pokemon"],
      product_path: ~r|\A/sklep/(?:[a-z0-9]+(?:-[a-z0-9]+)*/){1,5}\z|,
      max_pages: 3
    },
    %Shop{
      key: "colligere",
      name: "Colligere",
      host: "colligere.pl",
      category: "23",
      sealed_categories: ["pokemon-tcg"],
      product_path: ~r|\A/sklep/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      max_pages: 3
    }
  ]

  @keys Enum.map(@shops, & &1.key)

  @spec all() :: [Shop.t()]
  def all, do: @shops

  @spec keys() :: [String.t()]
  def keys, do: @keys

  @spec hosts() :: [String.t()]
  def hosts, do: Enum.map(@shops, & &1.host)

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
