defmodule TcgCheap.Sealed.Shops.Portugal do
  @moduledoc """
  Shops in Portugal. Their public listings, robots.txt and published delivery
  terms were checked on 2026-11-15 and 2026-11-16. Delivery is for mainland
  Portugal where a shop says so; an unknown price stays `nil`.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{Jumpseller, Shopify, WooCommerce}

  @product ~r/\A\/produto\/[a-z0-9]+(?:-[a-z0-9]+)*\/\z/

  @shops [
    %Shop{
      key: "lotusvalley",
      name: "Lotus Valley",
      host: "lotusvalley.pt",
      source: WooCommerce,
      # The Pokémon category also contains a few miscatalogued products of
      # other games; those cannot match the Pokémon catalogue.
      category: "59",
      product_path: @product,
      currency: "EUR",
      country: "PT",
      max_pages: 5,
      # GLS, free to mainland Portugal from this order value.
      shipping_from: Decimal.new("5"),
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "mercadiagames",
      name: "Mercadia Games",
      host: "mercadiagames.pt",
      source: WooCommerce,
      category: "69",
      product_path: @product,
      currency: "EUR",
      country: "PT",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("150"),
      pickup_city: "Lisboa"
    },
    %Shop{
      key: "tcghaven",
      name: "TCG Haven",
      host: "www.tcghaven.pt",
      source: Jumpseller,
      # Only the English-edition listings; JP, KR and CH have their own.
      listing_paths: [
        "/pokemon-en/por-categoria/booster-boxes",
        "/pokemon-en/por-categoria/booster-packs",
        "/pokemon-en/por-categoria/boxes-sets",
        "/pokemon-en/por-categoria/elite-trainer-boxes"
      ],
      currency: "EUR",
      country: "PT",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("100"),
      pickup_city: nil
    },
    %Shop{
      key: "playerspot",
      name: "Playerspot",
      host: "www.playerspot.pt",
      source: Jumpseller,
      listing_paths: ["/trading-card-games/pokemon-tcg"],
      mixed_listing: true,
      currency: "EUR",
      country: "PT",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Barreiro"
    },
    %Shop{
      key: "triplacegames",
      name: "Triplace Games",
      host: "www.triplacegames.com",
      source: Jumpseller,
      listing_paths: ["/pokemon"],
      mixed_listing: true,
      currency: "EUR",
      country: "PT",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: "Setúbal"
    },
    %Shop{
      key: "mytcgacademia",
      name: "MyTCG Academia",
      host: "www.mytcgacademia.com",
      source: Jumpseller,
      listing_paths: [
        "/tcg/pokemon/boosters",
        "/tcg/pokemon/boxs",
        "/tcg/pokemon/binder-collection"
      ],
      mixed_listing: true,
      currency: "EUR",
      country: "PT",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: Decimal.new("150"),
      pickup_city: nil
    },
    %Shop{
      key: "duocollectibles",
      name: "Duo Collectibles",
      host: "duocollectibles.com",
      source: Shopify,
      mixed_listing: false,
      excluded_markers: [
        "LEGO",
        "funko",
        "Lorcana",
        "One Piece",
        "One Piece Inglês",
        "One Piece Japonês",
        "MTG",
        "Magic The Gathering",
        "Dragon Ball",
        "Dragon Ball Inglês",
        "riftbound",
        "riftbound inglês",
        "riftbound chinês",
        "Radiance riftbound",
        "acessórios",
        "proteção",
        "proteções",
        "singles"
      ],
      currency: "EUR",
      country: "PT",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "templarsarena",
      name: "Templars Arena",
      host: "templarsarena.com",
      source: Shopify,
      excluded_markers: [
        "Funko",
        "Ultra PRO",
        "Ultra Pro",
        "Sleeves",
        "Playmat",
        "Vinyl Figure",
        "Plush",
        "Plush Blindbox",
        "Acrylic Display Case",
        "The Acrylic Box",
        "Jazwares",
        "Ravensburger"
      ],
      currency: "EUR",
      country: "PT",
      max_pages: 15,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokelotas",
      name: "Pokelotas",
      host: "pokelotas.com",
      source: Shopify,
      excluded_markers: [
        "Singles",
        "Slab",
        "Acessórios",
        "Funko",
        "One Piece",
        "Magic",
        "Lorcana",
        "Sleeves",
        "TopLoaders",
        "Palworld",
        "gundam",
        "naruto",
        "merch",
        "Suporte"
      ],
      currency: "EUR",
      country: "PT",
      max_pages: 10,
      shipping_from: Decimal.new("6"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "brokards",
      name: "Brokards",
      host: "brokards.com",
      source: Shopify,
      currency: "EUR",
      country: "PT",
      max_pages: 10,
      shipping_from: Decimal.new("3.50"),
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "geekhaven",
      name: "Geek Haven",
      host: "geekhaven.pt",
      source: Shopify,
      currency: "EUR",
      country: "PT",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "psydeck",
      name: "Psydeck",
      host: "psydeck.com",
      source: Shopify,
      # PSA is the vendor of its graded cards; "danificado" marks damaged products.
      excluded_markers: ["PSA", "danificado"],
      currency: "EUR",
      country: "PT",
      max_pages: 10,
      # CTT and DPD pick-up points; free from the shop's banner threshold.
      shipping_from: Decimal.new("3.99"),
      free_shipping_from: Decimal.new("120"),
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "PT"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Portugal of shops abroad, by shop key: the cheapest rate each
  shop's own anonymous cart quoted for one sealed product to a Lisbon address
  on 2026-11-16 with the shop's Portugal market selected, VAT included, all in
  euro. A shop whose cart offers no delivery to Portugal is
  not here.
  """
  def deliveries do
    %{
      "beamcardshop" => %{
        shipping_from: Decimal.new("29.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
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
      "rarecards" => %{
        shipping_from: Decimal.new("9.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      "tcgking" => %{
        shipping_from: Decimal.new("10.95"),
        free_shipping_from: Decimal.new("100"),
        currency: "EUR"
      },
      # Its cart to Lisbon (2026-11-17): 8,000 Ft and 27% VAT.
      "tcgwebshop" => %{
        shipping_from: Decimal.new("10160"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart to Lisbon (2026-11-17): 3,000 Ft and 23% VAT.
      "cardverse" => %{
        shipping_from: Decimal.new("3690"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-17).
      "kartonada" => %{
        shipping_from: Decimal.new("47.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its cart to Lisbon (2026-11-17): InPost International parcel locker 36.59
      # zł and 23% VAT; DPD to an address is 49.50 zł.
      "paladynat" => %{
        shipping_from: Decimal.new("45.01"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://rgfk.pl/content/1-koszty-dostawy: DHL (2026-11-17).
      "rgfk" => %{
        shipping_from: Decimal.new("36"),
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
