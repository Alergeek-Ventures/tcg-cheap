defmodule TcgCheap.Sealed.Shops.Croatia do
  @moduledoc """
  Shops in Croatia. Their listings and delivery terms were checked on the
  shops' public pages and anonymous Store API carts to a Zagreb address on
  2026-11-14, prices with VAT; unknown terms stay `nil`.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.WooCommerce

  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|

  @shops [
    %Shop{
      key: "pullz",
      name: "Pullz",
      host: "pullz.shop",
      source: WooCommerce,
      # Its sealed kinds; the German edition has a category of its own,
      # left out, and Japanese, Korean and Chinese products say so in
      # their titles.
      category: "87,88,89,90,93,95,96",
      sealed_categories: [
        "blister",
        "booster-box",
        "booster-pack",
        "collection-box",
        "deck-build-and-battle",
        "elite-trainer-box",
        "tin"
      ],
      product_path: ~r|\A/shop/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      currency: "EUR",
      country: "HR",
      max_pages: 5,
      # BOX NOW parcel locker; free from an order between 98.98 € and
      # 99.98 € in the cart.
      shipping_from: Decimal.new("3.00"),
      free_shipping_from: Decimal.new("99"),
      pickup_city: nil
    },
    %Shop{
      key: "pokebros",
      name: "PokéBros",
      host: "pokebros.com.hr",
      source: WooCommerce,
      category: "92",
      product_path: @product,
      currency: "EUR",
      country: "HR",
      max_pages: 5,
      # By weight, quoted only at checkout.
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "dabas",
      name: "Dabas",
      host: "dabas.hr",
      source: WooCommerce,
      category: "372",
      product_path: @product,
      currency: "EUR",
      country: "HR",
      max_pages: 2,
      # Some islands pay extra and get no free delivery.
      shipping_from: Decimal.new("5"),
      free_shipping_from: Decimal.new("70"),
      pickup_city: "Zaprešić"
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "HR"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Croatia of shops abroad, by shop key: the cheapest rate each
  shop's own anonymous cart quoted for one sealed product to Zagreb on
  2026-11-14, VAT included. Bescards and Beam Card Shop quoted in złoty.
  Shops whose carts offer no delivery to Croatia (TCGbolt, CobraCard, Geek
  Empire, Holo Zone, Myth Games) or quote no price (Bangerpack, Card
  Empire, RJ Mods) are not here.
  """
  def deliveries do
    %{
      "beamcardshop" => %{
        shipping_from: Decimal.new("135"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      "bescards" => %{
        shipping_from: Decimal.new("38"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "cardverse" => %{
        shipping_from: Decimal.new("3750"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("11.90"),
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
        shipping_from: Decimal.new("20"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "tcgwebshop" => %{
        shipping_from: Decimal.new("10160"),
        free_shipping_from: nil,
        currency: "HUF"
      }
    }
  end
end
