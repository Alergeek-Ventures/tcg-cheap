defmodule TcgCheap.Sealed.Shops.Slovenia do
  @moduledoc """
  Shops in Slovenia. Their public listings and published delivery terms were
  checked on 2026-11-15; unknown terms stay `nil`. Shops behind bot protection
  are not read.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{RajZaIgrace, TcgPark, ZberiVse}

  @shops [
    %Shop{
      key: "zberivse",
      name: "Zberi vse",
      host: "www.zberivse.si",
      source: ZberiVse,
      currency: "EUR",
      country: "SI",
      max_pages: 1,
      # Tracked delivery by product weight, published in the shop's settings.
      shipping_from: Decimal.new("3.90"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "tcgpark",
      name: "TCG Park",
      host: "www.tcgpark.com",
      source: TcgPark,
      feed_path: "/si/kategorija/pokemon-karte",
      currency: "EUR",
      country: "SI",
      max_pages: 60,
      shipping_from: Decimal.new("2.38"),
      free_shipping_from: Decimal.new("99"),
      pickup_city: "Ljubljana"
    },
    %Shop{
      key: "rajzaigrace",
      name: "Raj za igrače",
      host: "www.rajzaigrace.si",
      source: RajZaIgrace,
      feed_path: "/pokemon-c23238",
      currency: "EUR",
      country: "SI",
      max_pages: 1,
      # Parcel point or locker; home delivery is €5.99.
      shipping_from: Decimal.new("4.99"),
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "SI"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Slovenia of shops abroad, by shop key: the cheapest rate each
  shop's own anonymous cart quoted for one sealed product to a Ljubljana
  postcode on 2026-11-16, VAT included (a WooCommerce cart's shipping tax
  added), or what its delivery page says. Beamcardshop's cart offers no
  delivery to Slovenia; Poky Box, PokePower, PokéCARTA, Igabiba and TCG STAR
  answer bot checks and are not read.
  """
  def deliveries do
    %{
      # https://dabas.hr/placanje-dostava/ and its cart: a fixed €9; the €70
      # free-delivery threshold applies only within Croatia.
      "dabas" => %{shipping_from: Decimal.new("9"), free_shipping_from: nil, currency: "EUR"},
      "bescards" => %{
        shipping_from: Decimal.new("8.38"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      # 3,000 Ft and 22% VAT.
      "cardverse" => %{
        shipping_from: Decimal.new("3660"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart for buyers in Slovenia (2026-11-16), in kroner.
      "gemipulls" => %{
        shipping_from: Decimal.new("229"),
        free_shipping_from: nil,
        currency: "DKK"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("10.90"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      "pkmwinkel" => %{shipping_from: Decimal.new("20"), free_shipping_from: nil, currency: "EUR"},
      # Quoted by weight; €18 for a Build & Battle Box, the lightest product in stock.
      "pokebros" => %{shipping_from: Decimal.new("18"), free_shipping_from: nil, currency: "EUR"},
      "pokefamily" => %{
        shipping_from: Decimal.new("12.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # CTT tracked; DPD tracked is €20.
      "psydeck" => %{
        shipping_from: Decimal.new("15"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      # GLS to an address: €6.80 and 25% VAT.
      "pullz" => %{shipping_from: Decimal.new("8.50"), free_shipping_from: nil, currency: "EUR"},
      # Its delivery page's table of countries.
      "rarecards" => %{
        shipping_from: Decimal.new("9.95"),
        free_shipping_from: Decimal.new("300"),
        currency: "EUR"
      },
      # Its delivery page: a flat €10.95, free from €100 to every destination it lists.
      "tcgking" => %{
        shipping_from: Decimal.new("10.95"),
        free_shipping_from: Decimal.new("100"),
        currency: "EUR"
      },
      # 8,000 Ft and 27% VAT.
      "tcgwebshop" => %{
        shipping_from: Decimal.new("10160"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart to Ljubljana (2026-11-17), as the cart totals it.
      "pokemagic" => %{
        shipping_from: Decimal.new("29.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-17).
      "kartonada" => %{
        shipping_from: Decimal.new("34.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its cart to Ljubljana (2026-11-17): DPD 41.46 zł and 23% VAT.
      "paladynat" => %{
        shipping_from: Decimal.new("51"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://rgfk.pl/content/1-koszty-dostawy: DHL (2026-11-17).
      "rgfk" => %{
        shipping_from: Decimal.new("35"),
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
        currency: "SEK"
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
