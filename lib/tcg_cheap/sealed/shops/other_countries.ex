defmodule TcgCheap.Sealed.Shops.OtherCountries do
  @moduledoc """
  Shops outside Poland and Hungary, priced in their own currency, mostly for
  their singles. They are compared at their price with delivery to Poland
  (`deliveries`), given in PLN converted at the NBP rates of 6 November 2026
  (EUR 4.39, GBP 5.26, SEK 0.40, CZK 0.18, DKK 0.59); a shop without a known
  delivery price is only listed (`TcgCheap.Sealed.Market`). Delivery within a
  shop's own country is not recorded: the guide has no market there.
  """

  alias TcgCheap.Sealed.Shop

  alias TcgCheap.Sealed.ShopFeed.{
    Chasedex,
    GoogleFeed,
    NopCommerce,
    Shopify,
    Shoptet,
    WooCommerce
  }

  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|

  @shops [
    %Shop{
      key: "godofcards",
      name: "God of Cards",
      host: "godofcards.com",
      source: Shopify,
      collection: "pokemon-tcg",
      currency: "EUR",
      country: "DE",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("11.44"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €8.38, converted to PLN and rounded up.
          shipping_from: Decimal.new("36.94"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    %Shop{
      key: "psydeck",
      name: "Psydeck",
      host: "psydeck.com",
      source: Shopify,
      collection: "pokemon",
      currency: "EUR",
      country: "PT",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("15"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €15, converted to PLN and rounded up.
          shipping_from: Decimal.new("66.11"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    %Shop{
      key: "pokefamily",
      name: "PokeFamily",
      host: "pokefamily.nl",
      source: Shopify,
      collection: "pokemon",
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("12.95"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €12.95, converted to PLN and rounded up.
          shipping_from: Decimal.new("57.08"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    %Shop{
      key: "pkmwinkel",
      name: "PKMWinkel",
      host: "www.pkmwinkel.nl",
      source: Shopify,
      collection: "all",
      mixed_listing: true,
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("20"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €20, converted to PLN and rounded up.
          shipping_from: Decimal.new("88.14"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    %Shop{
      key: "cardcosmos",
      name: "CardCosmos",
      host: "cardcosmos.de",
      source: Shopify,
      collection: "pokemon-karten-kaufen",
      currency: "EUR",
      country: "DE",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("24.99"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €24.99, converted to PLN and rounded up.
          shipping_from: Decimal.new("110.14"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    %Shop{
      key: "bescards",
      name: "Bescards",
      host: "www.bescards.com",
      source: Shopify,
      collection: "pokemon-sealed",
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("8.38"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €8.38, converted to PLN and rounded up.
          shipping_from: Decimal.new("36.94"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    %Shop{
      key: "beamcardshop",
      name: "Beam Card Shop",
      host: "beamcardshop.com",
      source: Shopify,
      collection: "all-pokemon",
      currency: "EUR",
      country: "NL",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("29.95"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €29.95, converted to PLN and rounded up.
          shipping_from: Decimal.new("131.99"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    },
    # Bangerpack (White Tree AB, Helsingborg) publishes a Google Shopping
    # export, served from its CDN in euros; it holds sealed products only. Its
    # FAQ (2026-11-10) says it ships to Poland at a price shown only in the
    # checkout and has no free delivery.
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "PL" => %{
          # €10.99 to Poland in its checkout for a €1.99 cart (2026-11-10): a lower
          # bound, a heavier parcel (a booster box) may cost more.
          shipping_from: Decimal.new("48.25"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("8.95"),
          free_shipping_from: Decimal.new("300"),
          currency: "EUR"
        },
        "PL" => %{
          # €7.95, free from €250.
          shipping_from: Decimal.new("34.92"),
          free_shipping_from: Decimal.new("1098"),
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("10.95"),
          free_shipping_from: nil,
          currency: "EUR"
        },
        "PL" => %{
          # €10.95, free from €100.
          shipping_from: Decimal.new("48.10"),
          free_shipping_from: Decimal.new("439"),
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("229"),
          free_shipping_from: nil,
          currency: "DKK"
        },
        "PL" => %{
          # 109 DKK standard to Poland in its cart, also for 699 DKK (2026-11-10).
          shipping_from: Decimal.new("64.31"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "PL" => %{
          # €13.95 to Poland, also for an order of €270.
          shipping_from: Decimal.new("61.28"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("99"),
          free_shipping_from: Decimal.new("799"),
          currency: "SEK"
        },
        "PL" => %{
          # 99 SEK tracked letter to the EU, free from 799 SEK (319.60 zł, rounded
          # up so no order is shown with free delivery it does not get).
          shipping_from: Decimal.new("39.40"),
          free_shipping_from: Decimal.new("320"),
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("5.90"),
          free_shipping_from: Decimal.new("100"),
          currency: "GBP"
        },
        "PL" => %{
          # £5.90 for any number of singles, duties paid (IOSS), free from £100.
          shipping_from: Decimal.new("31.05"),
          free_shipping_from: Decimal.new("526.30"),
          currency: "PLN"
        }
      }
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
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil,
      deliveries: %{
        "HU" => %{
          shipping_from: Decimal.new("149"),
          free_shipping_from: nil,
          currency: "CZK"
        },
        "PL" => %{
          # Zásilkovna (Packeta) to Poland 149 Kč.
          shipping_from: Decimal.new("26.89"),
          free_shipping_from: nil,
          currency: "PLN"
        }
      }
    }
  ]

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops
end
