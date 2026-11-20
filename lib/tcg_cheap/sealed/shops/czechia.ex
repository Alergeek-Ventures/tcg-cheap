defmodule TcgCheap.Sealed.Shops.Czechia do
  @moduledoc """
  Shops in Czechia, the guide's region `/cz/` in koruna, and the deliveries to
  Czechia of shops abroad (`TcgCheap.Sealed.Shops`). The Shoptet and
  WooCommerce shops are read from their public Pokémon listings. Delivery
  within Czechia is each shop's cheapest standard parcel and its free-delivery
  threshold as the shop states them in November 2026; nil where it states none.
  Singles have no market here yet.
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{Shoptet, WooCommerce}

  @shops [
    %Shop{
      key: "azgarra",
      name: "Azgarra",
      host: "www.azgarra.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-produkty/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.chaotit.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "chaotit",
      name: "Chaotit",
      host: "www.chaotit.cz",
      source: Shoptet,
      listing_paths: [
        "/pokemon-boostery/",
        "/pokemon-hotove-balicky/",
        "/pokemon-specialni-sety/",
        "/elite-trainer-box/"
      ],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("79"),
      free_shipping_from: Decimal.new("2500"),
      pickup_city: "České Budějovice"
    },
    %Shop{
      key: "alola",
      name: "Alola",
      host: "www.alola.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.blacklotus.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "blacklotus",
      name: "BlackLotus",
      host: "www.blacklotus.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-produkty/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("89"),
      free_shipping_from: Decimal.new("3000"),
      pickup_city: "Ostrava"
    },
    %Shop{
      key: "pokeone",
      name: "Pokeone",
      host: "www.pokeone.cz",
      source: Shoptet,
      listing_paths: [
        "/boostery-pokemon/",
        "/booster-boxy-pokemon/",
        "/booster-bundle/",
        "/elite-trainer-boxy/",
        "/pokemon-plechovky-tin/"
      ],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokesov",
      name: "Pokešov",
      host: "www.pokesov.cz",
      source: Shoptet,
      listing_paths: ["/elite-trainer-boxy/", "/boostery-2/", "/blistery/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.bulbazard.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "bulbazard",
      name: "Bulbazard",
      host: "www.bulbazard.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-sealed-produkty/"],
      singles_categories: ["/kusove-karty-pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("64"),
      free_shipping_from: Decimal.new("3799"),
      pickup_city: nil
    },
    # Delivery terms: https://www.professoronyx.com/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "professoronyx",
      name: "Professor Onyx",
      host: "www.professoronyx.com",
      source: Shoptet,
      listing_paths: ["/pokemon-produkty/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("99"),
      free_shipping_from: nil,
      pickup_city: "Praha"
    },
    %Shop{
      key: "cardstore",
      name: "Cardstore",
      host: "www.cardstore.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-produkty/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokefun",
      name: "PokéFun",
      host: "www.pokefun.cz",
      source: Shoptet,
      listing_paths: [
        "/category-sealed-pokemon-boxy-/",
        "/booster-balicky/",
        "/japonske-korejske-boostery/",
        "/japonske-korejske-booster-boxy/"
      ],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.kouzelnehry.cz/ceny_dopravy/ (checked 2026-11-15).
    %Shop{
      key: "kouzelnehry",
      name: "Kouzelné hry",
      host: "www.kouzelnehry.cz",
      source: Shoptet,
      listing_paths: [
        "/pokemon-booster-boxy/",
        "/pokemon-booster-balicky/",
        "/pokemon-specialni-produkty/"
      ],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("89"),
      free_shipping_from: Decimal.new("3900"),
      pickup_city: "Kadaň"
    },
    %Shop{
      key: "realmerch",
      name: "RealMerch",
      host: "www.realmerch.store",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.pokemall.cz/clanky/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "pokemall",
      name: "Pokemall",
      host: "www.pokemall.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("79"),
      free_shipping_from: Decimal.new("3999"),
      pickup_city: "Braškov",
      # A village of fewer than 1,000 inhabitants: not in the towns list.
      pickup_location: {50.0986, 14.0896}
    },
    # Delivery terms: https://www.pokemagic.cz/dopravaplatba/ (checked 2026-11-15).
    %Shop{
      key: "pokemagiccz",
      name: "PokeMagic",
      host: "www.pokemagic.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("79"),
      free_shipping_from: Decimal.new("3500"),
      pickup_city: nil
    },
    %Shop{
      key: "chytjevsechnypoke",
      name: "Chyť je všechny!",
      host: "www.chytjevsechny-poke.cz",
      source: Shoptet,
      listing_paths: [
        "/boostery/",
        "/booster-boxy/",
        "/japonske-booster-boxy/",
        "/ostatni-pokemon-produkty/"
      ],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "bubuobchod",
      name: "Bubuobchod",
      host: "www.bubuobchod.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-produkty/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.mysidoupe.eu/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "mysidoupe",
      name: "Myší doupě",
      host: "www.mysidoupe.eu",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg-booster/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("69"),
      free_shipping_from: Decimal.new("2000"),
      pickup_city: "Praha"
    },
    %Shop{
      key: "pokeshop",
      name: "Pokéshop",
      host: "www.pokeshop.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "sragicards",
      name: "SragiCards",
      host: "www.sragicards.cz",
      source: Shoptet,
      listing_paths: ["/boxy/", "/boostery/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "planetaher",
      name: "Planeta Her",
      host: "www.planetaher.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.pokemon4u.cz/doprava-a-platby/ (checked 2026-11-15).
    %Shop{
      key: "pokemon4u",
      name: "Pokemon4U",
      host: "www.pokemon4u.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-karticky/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("70"),
      free_shipping_from: nil,
      pickup_city: "Mladá Boleslav"
    },
    %Shop{
      key: "cardcave",
      name: "CardCave",
      host: "www.cardcave.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "meowtcg",
      name: "Meow TCG",
      host: "www.meowtcg.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "svetkaret",
      name: "Světkaret",
      host: "www.svetkaret.eu",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "herocomics",
      name: "HERO Comics",
      host: "www.herocomics.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-tcg/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "pokepop",
      name: "Poképop",
      host: "www.pokepop.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.cdmc.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "cdmc",
      name: "CDMC",
      host: "www.cdmc.cz",
      source: Shoptet,
      listing_paths: ["/pokemon-karty/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("69"),
      free_shipping_from: nil,
      pickup_city: "Ústí nad Labem"
    },
    # Delivery terms: https://www.fyft.cz/doprava/ (checked 2026-11-15).
    %Shop{
      key: "fyft",
      name: "FYFT",
      host: "www.fyft.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("69"),
      free_shipping_from: nil,
      pickup_city: "Praha"
    },
    # Delivery terms: https://www.konzoliste.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "konzoliste",
      name: "Konzoliště",
      host: "www.konzoliste.cz",
      source: Shoptet,
      listing_paths: [
        "/pokemon-boostery/",
        "/pokemon-booster-boxy/",
        "/pokemon-tin-plechovky/",
        "/pokemon-elite-trainer-boxy/"
      ],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("58"),
      free_shipping_from: Decimal.new("2500"),
      pickup_city: "Brno"
    },
    # Delivery terms: https://www.hras.cz/jak-nakupovat/ (checked 2026-11-15).
    %Shop{
      key: "hras",
      name: "HRAS",
      host: "www.hras.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("49"),
      free_shipping_from: nil,
      pickup_city: "Praha"
    },
    # Delivery terms: https://www.magule.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "magule",
      name: "Magule",
      host: "www.magule.cz",
      source: Shoptet,
      listing_paths: ["/sberatelske-karty-tcg-pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("75"),
      free_shipping_from: Decimal.new("1500"),
      pickup_city: "Hrušovany u Brna"
    },
    %Shop{
      key: "spellbound",
      name: "Spellbound",
      host: "www.spellbound.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "wombatgamesshop",
      name: "Wombat Games",
      host: "www.wombatgames-shop.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "obchodjotunheim",
      name: "Jotunheim",
      host: "www.obchodjotunheim.cz",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://www.tlamagames.com/doprava_platba/ (checked 2026-11-15).
    %Shop{
      key: "tlamagames",
      name: "TLAMA games",
      host: "www.tlamagames.com",
      source: Shoptet,
      listing_paths: ["/pokemon/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("54"),
      free_shipping_from: Decimal.new("2000"),
      pickup_city: "Praha"
    },
    # Delivery terms: https://www.toredo.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "toredo",
      name: "Toredo",
      host: "www.toredo.cz",
      source: Shoptet,
      listing_paths: ["/boostery/", "/booster-boxy/", "/elite-trainer-boxy/"],
      currency: "CZK",
      country: "CZ",
      max_pages: 40,
      shipping_from: Decimal.new("69"),
      free_shipping_from: Decimal.new("2000"),
      pickup_city: nil
    },
    %Shop{
      key: "pokemonkarty",
      name: "Pokémon-karty.cz",
      host: "pokemon-karty.cz",
      source: WooCommerce,
      category: "151,150,160,153,159,158,148,180",
      product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      currency: "CZK",
      country: "CZ",
      max_pages: 15,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "geekhall",
      name: "GeekHall",
      host: "geekhall.cz",
      source: WooCommerce,
      category: "26",
      product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      currency: "CZK",
      country: "CZ",
      max_pages: 15,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    # Delivery terms: https://epicdecks.cz/doprava-a-reklamace/ (checked 2026-11-15).
    %Shop{
      key: "epicdecks",
      name: "Epic Decks",
      host: "epicdecks.cz",
      source: WooCommerce,
      category: "34",
      product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      currency: "CZK",
      country: "CZ",
      max_pages: 15,
      shipping_from: Decimal.new("69"),
      free_shipping_from: Decimal.new("5000"),
      pickup_city: "Praha"
    },
    # Delivery terms: https://bhakti.cz/doprava-a-platba/ (checked 2026-11-15).
    %Shop{
      key: "bhakti",
      name: "BHAKTI.CZ",
      host: "bhakti.cz",
      source: WooCommerce,
      category: "228",
      product_path: ~r|\A/obchod/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
      currency: "CZK",
      country: "CZ",
      max_pages: 15,
      shipping_from: Decimal.new("89"),
      free_shipping_from: nil,
      pickup_city: "Uherské Hradiště"
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "CZ"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc """
  Deliveries to Czechia of shops abroad, by shop key: the cheapest rate each
  shop's own anonymous cart quoted for one sealed product to a Prague address
  on 2026-11-16 with Czechia chosen in the shop's country selector, in the
  currency the cart quoted, VAT included. A shop with a `price_currency` charges
  Czech buyers prices of its own in koruna. A shop whose cart quoted no
  delivery to Czechia is not here.
  """
  def deliveries do
    %{
      "beamcardshop" => %{
        shipping_from: Decimal.new("747"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      "bescards" => %{
        shipping_from: Decimal.new("209"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      "cardcosmos" => %{
        shipping_from: Decimal.new("24.99"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "CZK"
      },
      "godofcards" => %{
        shipping_from: Decimal.new("11.68"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "CZK"
      },
      "hobbykort" => %{
        shipping_from: Decimal.new("139"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "CZK"
      },
      "pkmwinkel" => %{
        shipping_from: Decimal.new("499"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      "pokefamily" => %{
        shipping_from: Decimal.new("323"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      "poketalk" => %{
        shipping_from: Decimal.new("358"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      "psydeck" => %{
        shipping_from: Decimal.new("15"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "CZK"
      },
      "rahtech" => %{
        shipping_from: Decimal.new("447"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      "samlarhobby" => %{
        shipping_from: Decimal.new("299"),
        free_shipping_from: nil,
        currency: "SEK",
        price_currency: "CZK"
      },
      "skarbieckart" => %{
        shipping_from: Decimal.new("142"),
        free_shipping_from: nil,
        currency: "CZK",
        price_currency: "CZK"
      },
      # Its list for buyers in Czechia is in euro (`?country=CZ`, 2026-11-18).
      "skladgier" => %{
        shipping_from: Decimal.new("11.95"),
        free_shipping_from: nil,
        currency: "EUR",
        price_currency: "EUR"
      },
      # Its cart to Prague (2026-11-17): 8,000 Ft and 27% VAT.
      "tcgwebshop" => %{
        shipping_from: Decimal.new("10160"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart to Prague (2026-11-17): 3,000 Ft and 21% VAT.
      "cardverse" => %{
        shipping_from: Decimal.new("3630"),
        free_shipping_from: nil,
        currency: "HUF"
      },
      # Its cart to Prague (2026-11-17), as the cart totals it.
      "pokemagic" => %{
        shipping_from: Decimal.new("29.95"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # Its cart to Prague (2026-11-17), as the cart totals it.
      "pokebros" => %{
        shipping_from: Decimal.new("28"),
        free_shipping_from: nil,
        currency: "EUR"
      },
      # https://kartonada.pl/dostawa/: DPD Classic up to 1 kg, gross (2026-11-17).
      "kartonada" => %{
        shipping_from: Decimal.new("26.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # Its cart to Prague (2026-11-17): DPD 39.02 zł and 23% VAT.
      "paladynat" => %{
        shipping_from: Decimal.new("47.99"),
        free_shipping_from: nil,
        currency: "PLN"
      },
      # https://rgfk.pl/content/1-koszty-dostawy: DHL (2026-11-17).
      "rgfk" => %{
        shipping_from: Decimal.new("23"),
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
