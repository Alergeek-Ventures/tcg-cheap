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
    },
    # Its Pokémon category (Store API, 2026-11-24). Its pages state no
    # delivery terms.
    %Shop{
      key: "igrackehrvatska",
      name: "Igračke Hrvatska",
      host: "igrackehrvatska.com",
      source: WooCommerce,
      category: "16",
      product_path: @product,
      currency: "EUR",
      country: "HR",
      max_pages: 3,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
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
  2026-11-14, VAT included. Bescards quoted in złoty.
  Shops whose carts offer no delivery to Croatia (TCGbolt, CobraCard, Geek
  Empire, Holo Zone, Myth Games) or quote no price (Bangerpack, Card
  Empire, RJ Mods) are not here.
  """
  def deliveries do
    %{
      # Its cart for buyers in Croatia (2026-11-16).
      "beamcardshop" => %{
        shipping_from: Decimal.new("29.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "bescards" => %{
        shipping_from: Decimal.new("38"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "cardverse" => %{
        shipping_from: Decimal.new("3750"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("11.90"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
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
      # https://www.pressstart.pt/pt/content/entregas.html (2026-11-25), its table
      # of countries: the rate for orders up to €35; a middle band up to €200
      # costs less and is not recorded, free above €200.
      "pressstart" => %{
        shipping_from: Decimal.new("6.99"),
        free_shipping_from: Decimal.new("200"),
        currency: "EUR"
      },
      "psydeck" => %{
        shipping_from: Decimal.new("20"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      # Its delivery page's table of countries (2026-11-16): free from €300.
      "rarecards" => %{
        shipping_from: Decimal.new("9.95"),
        free_shipping_from: Decimal.new("300"),
        currency: "EUR"
      },
      # Its delivery page (2026-11-16): free from €100.
      "tcgking" => %{
        shipping_from: Decimal.new("10.95"),
        free_shipping_from: Decimal.new("100"),
        currency: "EUR"
      },
      "tcgwebshop" => %{
        shipping_from: Decimal.new("10160"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart to Zagreb (2026-11-17), as the cart totals it.
      "pokemagic" => %{
        shipping_from: Decimal.new("39.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-17).
      "kartonada" => %{
        shipping_from: Decimal.new("41.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its cart to Zagreb (2026-11-17): DPD 41.46 zł and 23% VAT.
      "paladynat" => %{
        shipping_from: Decimal.new("51"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://rgfk.pl/content/1-koszty-dostawy: DHL (2026-11-17).
      "rgfk" => %{
        shipping_from: Decimal.new("32"),
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
