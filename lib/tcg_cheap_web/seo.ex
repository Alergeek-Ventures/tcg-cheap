defmodule TcgCheapWeb.SEO do
  @moduledoc "Search metadata for the buying guide, derived from the same data as its visible pages."

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{CardGuide, CardImage, Catalogue, Kinds, Shops}
  alias TcgCheapWeb.{GuideComponents, PageMarkdown, Polish, SocialImage}

  def home(params) do
    metadata(
      gettext("Pokémon TCG – ceny kart, boosterów i boxów"),
      gettext(
        "Porównaj ceny Pokémon TCG w sklepach wysyłających do Polski. Sprawdź oferty boosterów, ETB, boxów i angielskich kart, historię cen i czy warto kupić teraz."
      ),
      url(~p"/"),
      social_image: home_image(),
      social_image_alt: home_image_alt(),
      robots:
        if(Enum.any?(~w(q rodzaj wersja rozszerzenie), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" => [
          %{"@type" => "WebSite", "name" => "TCG Cheap", "url" => url(~p"/")},
          %{
            "@type" => "Organization",
            "name" => "TCG Cheap",
            "url" => url(~p"/"),
            "logo" => static_url(TcgCheapWeb.Endpoint, ~p"/apple-touch-icon.png")
          }
        ]
      }
    )
  end

  # The card list stands beside the products list as its equal: people search
  # for card prices as much as for boosters. Narrowed by a search or an
  # expansion it stays out of search, as the products list does.
  def cards(params, market) do
    canonical = url(~p"/karty")

    metadata(
      gettext("Ceny kart Pokémon TCG w Polsce"),
      fit_description(card_list_answer(market)),
      canonical,
      social_image:
        if(market,
          do: url(~p"/og/karty?#{[v: SocialImage.cards_version(market)]}"),
          else: home_image()
        ),
      social_image_alt:
        if(market, do: gettext("Ceny kart Pokémon w polskich sklepach"), else: home_image_alt()),
      robots:
        if(Enum.any?(~w(q rozszerzenie), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data: %{
        "@context" => "https://schema.org",
        "@type" => "CollectionPage",
        "name" => gettext("Ceny kart Pokémon TCG w Polsce"),
        "url" => canonical
      }
    )
  end

  # A chosen expansion's list has no market of its own; it is not indexed.
  defp card_list_answer(nil),
    do: [gettext("Angielskie karty Pokémon TCG w sklepach wysyłających do Polski.")]

  defp card_list_answer(market) do
    [
      gettext(
        "Angielskie karty Pokémon TCG w sklepach wysyłających do Polski: %{cards} na stanie.",
        cards: Polish.plural(market.in_stock, "karta", "karty", "kart")
      ),
      market.cheaper > 0 &&
        gettext("%{count} z nich taniej niż na Cardmarket z przesyłką.",
          count: Polish.number(market.cheaper)
        ),
      gettext("Najniższa cena i ocena każdej karty.")
    ]
    |> Enum.filter(&is_binary/1)
  end

  # People ask what a booster costs, also in the chains ("ile kosztuje booster
  # pokemon w żabce"): the answer is today's cheapest English booster.
  def booster_prices(page) do
    canonical = url(~p"/ile-kosztuje-booster-pokemon")

    metadata(
      gettext("Ile kosztuje booster Pokémon? Ceny w Polsce"),
      fit_description(
        List.insert_at(
          booster_answer(page),
          1,
          gettext("Co jest w ETB, blistrach i puszkach i ile dopłacasz za dodatki.")
        )
      ),
      canonical,
      social_image:
        url(~p"/og/ile-kosztuje-booster-pokemon?#{[v: SocialImage.boosters_version(page)]}"),
      social_image_alt: gettext("Ile kosztuje booster Pokémon: najtańsze boostery w sklepach"),
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" => [
          %{
            "@type" => "Article",
            "headline" => gettext("Ile kosztuje booster Pokémon?"),
            "inLanguage" => Gettext.get_locale(TcgCheapWeb.Gettext),
            "dateModified" => Date.to_iso8601(page.today),
            "author" => %{"@type" => "Organization", "name" => "TCG Cheap", "url" => url(~p"/")},
            "mainEntityOfPage" => canonical
          },
          %{
            "@type" => "BreadcrumbList",
            "itemListElement" => [
              %{
                "@type" => "ListItem",
                "position" => 1,
                "name" => gettext("Wszystkie produkty"),
                "item" => url(~p"/")
              },
              %{
                "@type" => "ListItem",
                "position" => 2,
                "name" => gettext("Ile kosztuje booster"),
                "item" => canonical
              }
            ]
          }
        ]
      }
    )
  end

  # "najdroższe karty pokemon" is asked about the records and about what
  # costs most today: the description answers both. A filtered ranking is
  # the same article: canonical to it and not indexed on its own.
  def expensive_cards(overview, records, filters) do
    canonical = url(~p"/najdrozsze-karty-pokemon")
    filtered? = filters != %{set: nil, stock: :all}
    title = gettext("Najdroższe karty Pokémon – rekordy i ceny dziś")

    metadata(
      title,
      fit_description(expensive_cards_answer(overview, hd(records))),
      canonical,
      robots: if(filtered?, do: "noindex, follow", else: "index, follow"),
      social_image:
        url(
          ~p"/og/najdrozsze-karty-pokemon?#{[v: SocialImage.expensive_cards_version(overview)]}"
        ),
      social_image_alt: gettext("Najdroższe karty Pokémon: rekordy aukcji i ceny dziś"),
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" => [
          %{
            "@type" => "Article",
            "headline" => gettext("Najdroższe karty Pokémon"),
            "inLanguage" => Gettext.get_locale(TcgCheapWeb.Gettext),
            "dateModified" => overview.priced_on && Date.to_iso8601(overview.priced_on),
            "author" => %{"@type" => "Organization", "name" => "TCG Cheap", "url" => url(~p"/")},
            "mainEntityOfPage" => canonical
          },
          %{
            "@type" => "BreadcrumbList",
            "itemListElement" => [
              %{
                "@type" => "ListItem",
                "position" => 1,
                "name" => gettext("Karty"),
                "item" => url(~p"/karty")
              },
              %{
                "@type" => "ListItem",
                "position" => 2,
                "name" => gettext("Najdroższe karty Pokémon"),
                "item" => canonical
              }
            ]
          }
        ]
      }
    )
  end

  defp expensive_cards_answer(overview, record) do
    [
      gettext("Najdroższa karta Pokémon w historii to %{card}: %{price} (%{grade}, %{year}).",
        card: record.name,
        price: TcgCheapWeb.CardRecords.usd(record.usd),
        grade: record.grade,
        year: elem(record.sold, 0)
      ),
      case overview.highlights do
        [top | _] ->
          gettext("Najdroższa karta dziś na Cardmarket: %{card}, %{value}.",
            card: top.card.name,
            value: Polish.zloty(top.value)
          )

        [] ->
          nil
      end,
      gettext("Rekordy aukcji i ceny w polskich sklepach.")
    ]
    |> Enum.filter(&is_binary/1)
  end

  def card_value(%{spread: spread} = guide) do
    canonical = url(~p"/jak-sprawdzic-wartosc-karty-pokemon")
    title = gettext("Jak sprawdzić wartość karty Pokémon")

    metadata(
      gettext("Jak sprawdzić wartość karty Pokémon – ile jest warta twoja karta"),
      fit_description(
        [
          gettext(
            "Wpisz nazwę albo numer z dołu karty Pokémon i sprawdź, ile kosztuje w sklepach."
          ),
          spread &&
            gettext("Połowa kart kosztuje do %{median} – sprawdź, czy twoja jest wyjątkiem.",
              median: Polish.zloty_ceiling(spread.median)
            ),
          gettext("Do tego grading: kiedy się opłaca.")
        ]
        |> Enum.filter(&is_binary/1)
      ),
      canonical,
      social_image:
        url(
          ~p"/og/jak-sprawdzic-wartosc-karty-pokemon?#{[v: SocialImage.card_value_version(guide)]}"
        ),
      social_image_alt:
        gettext("Ile jest warta twoja karta Pokémon: ceny kart w polskich sklepach"),
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" => [
          %{
            "@type" => "Article",
            "headline" => title,
            "inLanguage" => Gettext.get_locale(TcgCheapWeb.Gettext),
            "dateModified" => spread && Date.to_iso8601(spread.on),
            "author" => %{"@type" => "Organization", "name" => "TCG Cheap", "url" => url(~p"/")},
            "mainEntityOfPage" => canonical
          },
          %{
            "@type" => "BreadcrumbList",
            "itemListElement" => [
              %{
                "@type" => "ListItem",
                "position" => 1,
                "name" => gettext("Karty"),
                "item" => url(~p"/karty")
              },
              %{"@type" => "ListItem", "position" => 2, "name" => title, "item" => canonical}
            ]
          }
        ]
      }
    )
  end

  # For shop owners and the bot registries that link to it; it has no
  # markdown version.
  def bot do
    canonical = url(~p"/bot")

    metadata(
      gettext("Bot TCG Cheap – informacje dla sklepów"),
      gettext(
        "Jak bot TCG Cheap czyta publiczne listy produktów sklepów, jak go rozpoznać i jak poprosić, żeby przestał."
      ),
      canonical,
      markdown: nil,
      social_image: home_image(),
      social_image_alt: home_image_alt(),
      structured_data: %{
        "@context" => "https://schema.org",
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{
            "@type" => "ListItem",
            "position" => 1,
            "name" => gettext("Wszystkie produkty"),
            "item" => url(~p"/")
          },
          %{
            "@type" => "ListItem",
            "position" => 2,
            "name" => gettext("Bot TCG Cheap"),
            "item" => canonical
          }
        ]
      }
    )
  end

  @doc """
  The booster price page's answer, in sentences: the cheapest booster of the
  recent English sets in a Polish shop today and the newest set's booster.
  The chains' prices stay in their own list: they are not all boosters.
  """
  @spec booster_answer(%{
          :boosters => list(),
          :cheapest => map() | nil,
          optional(atom()) => any()
        }) :: [String.t()]
  def booster_answer(%{cheapest: nil}),
    do: [gettext("Teraz żaden polski sklep nie ma angielskiego boostera na stanie.")]

  def booster_answer(%{boosters: [newest | _], cheapest: cheapest}) do
    [
      gettext(
        "Booster z ostatnich angielskich setów kosztuje dziś od %{price} (%{product}, %{shop}).",
        price: Polish.price(cheapest.verdict.cheapest.price),
        product: cheapest.product.name,
        shop: GuideComponents.priced_shop_name(cheapest.verdict.cheapest)
      ),
      gettext("Najnowszy set w sklepach, %{set}: od %{price}.",
        set: newest.product.set_name,
        price: Polish.price(newest.verdict.cheapest.price)
      )
    ]
  end

  @doc "The set page's path: the expansion's name plus its Cardmarket id, like a product's."
  @spec expansion_path(integer(), String.t()) :: String.t()
  def expansion_path(id, name), do: ~p"/rozszerzenia/#{Catalogue.slug(name, id)}"

  @doc "The set page's full URL."
  @spec expansion_url(integer(), String.t()) :: String.t()
  def expansion_url(id, name), do: url(~p"/rozszerzenia/#{Catalogue.slug(name, id)}")

  # A set's page is what people search for by name: "<set> cena", "<set>
  # drop rate", "<set> lista kart". Its list narrowed by a search or a
  # filter stays out of search.
  def expansion(params, %{id: id, name: name}, page) do
    canonical = expansion_url(id, name)

    metadata(
      fit_title(expansion_titles(name, page)),
      fit_description(expansion_answer(name, page)),
      canonical,
      social_image:
        unverified_url(TcgCheapWeb.Endpoint, "/og" <> expansion_path(id, name),
          v: SocialImage.expansion_version(name, page)
        ),
      social_image_alt: gettext("%{expansion}: najcenniejsze karty i ceny", expansion: name),
      robots:
        if(Enum.any?(~w(q rodzaj wersja), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data: %{
        "@context" => "https://schema.org",
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{
            "@type" => "ListItem",
            "position" => 1,
            "name" => gettext("Wszystkie produkty"),
            "item" => url(~p"/")
          },
          %{"@type" => "ListItem", "position" => 2, "name" => name, "item" => canonical}
        ]
      }
    )
  end

  # A set whose cards Polish shops sell is searched for its card prices too,
  # and for its boosters' when it has one.
  defp expansion_titles(name, %{set: %{singles: %{in_stock: in_stock}} = set, booster: nil})
       when in_stock > 0,
       do:
         Enum.filter(
           [
             set.pull_rates && gettext("%{expansion} – ceny kart i drop rate", expansion: name),
             gettext("%{expansion} – ceny kart Pokémon TCG", expansion: name),
             gettext("%{expansion} – ceny kart", expansion: name),
             name
           ],
           &is_binary/1
         )

  defp expansion_titles(name, %{set: %{singles: %{in_stock: in_stock}} = set})
       when in_stock > 0,
       do:
         Enum.filter(
           [
             set.pull_rates &&
               gettext("%{expansion} – ceny kart i boosterów, drop rate", expansion: name),
             gettext("%{expansion} – ceny kart i boosterów Pokémon TCG", expansion: name),
             gettext("%{expansion} – ceny kart i boosterów", expansion: name),
             gettext("%{expansion} – ceny kart", expansion: name),
             name
           ],
           &is_binary/1
         )

  defp expansion_titles(name, %{set: %{pull_rates: %{}}}),
    do: [
      gettext("%{expansion} – ceny, drop rate i lista kart Pokémon TCG", expansion: name),
      gettext("%{expansion} – ceny, drop rate i lista kart", expansion: name),
      name
    ]

  defp expansion_titles(name, %{set: %{rarities: [_ | _]}}),
    do: [
      gettext("%{expansion} – ceny i lista kart Pokémon TCG", expansion: name),
      gettext("%{expansion} – ceny i lista kart", expansion: name),
      name
    ]

  defp expansion_titles(name, _page),
    do: [
      gettext("%{expansion} – ceny boosterów, ETB i boxów Pokémon TCG", expansion: name),
      gettext("%{expansion} – ceny boosterów, ETB i boxów", expansion: name),
      name
    ]

  @doc """
  The set page's answer, in sentences, for its top and its search snippet:
  the single booster's cheapest price, the rarest pull rates, the number of
  cards and the dearest one.
  """
  @spec expansion_answer(String.t(), %{
          :set => map() | nil,
          :booster => map() | nil,
          optional(atom()) => any()
        }) :: [String.t()]
  def expansion_answer(name, %{set: set, booster: booster}) do
    [
      booster_answer(name, booster),
      set && pull_rates_summary(set.pull_rates),
      set && cards_answer(set)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        [
          gettext(
            "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w sklepach wysyłających do Polski.",
            expansion: name
          )
        ]

      sentences ->
        sentences
    end
  end

  defp booster_answer(_name, nil), do: nil

  defp booster_answer(name, %{verdict: %{cheapest: nil}}),
    do:
      gettext("Boostera %{expansion} żaden polski sklep nie ma teraz na stanie.",
        expansion: name
      )

  defp booster_answer(name, %{verdict: %{cheapest: cheapest}, preorder?: true}),
    do:
      gettext("Booster %{expansion}: przedsprzedaż od %{price} w %{shop}.",
        expansion: name,
        price: Polish.price(cheapest.price),
        shop: GuideComponents.priced_shop_name(cheapest)
      )

  defp booster_answer(name, %{verdict: %{cheapest: cheapest}}),
    do:
      gettext("Booster %{expansion}: najtaniej teraz %{price} w %{shop}.",
        expansion: name,
        price: Polish.price(cheapest.price),
        shop: GuideComponents.priced_shop_name(cheapest)
      )

  defp cards_answer(%{card_count: 0}), do: nil

  defp cards_answer(%{card_count: count, top_cards: []}),
    do: gettext("Set liczy %{cards}.", cards: Polish.plural(count, "karta", "karty", "kart"))

  defp cards_answer(%{card_count: count, top_cards: [top | _]}),
    do:
      gettext("Set liczy %{cards}, najdroższa to %{card} (%{price}, bez dostawy).",
        cards: Polish.plural(count, "karta", "karty", "kart"),
        card: top.card.name,
        price: Polish.price(top.price)
      )

  defp home_image, do: url(~p"/og?#{[v: SocialImage.home_version()]}")

  defp home_image_alt,
    do:
      "TCG Cheap. " <>
        gettext("Sprawdź, czy cena jest dobra") <> ". " <> SocialImage.home_promise()

  def product(page) do
    product = page.product
    canonical = url(~p"/produkty/#{product.slug}")

    description = product_description(page)

    product_data = %{
      "@type" => "Product",
      "name" => product.name,
      "description" => description,
      "url" => canonical,
      "category" => Kinds.label(product.kind)
    }

    product_data =
      if image = image(product),
        do: Map.put(product_data, "image", image),
        else: product_data

    # Only current, in-stock offers count, at their compared price (a shop abroad's
    # with delivery), never MSRP, Cardmarket or a last-known price. Google requires
    # offers on a Product, so without one there's no Product block.
    product_data =
      case page.offers |> Enum.filter(& &1.in_stock) |> Shops.compared() do
        [] ->
          nil

        offers ->
          {low, high} = Enum.min_max_by(offers, & &1.price, Decimal)

          Map.put(product_data, "offers", %{
            "@type" => "AggregateOffer",
            "url" => canonical,
            "priceCurrency" => "PLN",
            "lowPrice" => Decimal.to_string(low.price, :normal),
            "highPrice" => Decimal.to_string(high.price, :normal),
            "offerCount" => length(offers)
          })
      end

    metadata(
      fit_title(product_titles(page)),
      description,
      canonical,
      social_image:
        url(~p"/og/produkty/#{product.slug}?#{[v: SocialImage.product_version(page)]}"),
      social_image_alt: product.name <> ". " <> answer(page.verdict),
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" =>
          List.wrap(product_data) ++
            [
              %{
                "@type" => "BreadcrumbList",
                "itemListElement" =>
                  [
                    %{
                      "@type" => "ListItem",
                      "position" => 1,
                      "name" => gettext("Wszystkie produkty"),
                      "item" => url(~p"/")
                    },
                    %{
                      "@type" => "ListItem",
                      "position" => 2,
                      "name" => product.name,
                      "item" => canonical
                    }
                  ]
                  |> with_expansion_crumb(product)
              }
            ]
      }
    )
  end

  # The expansion's list sits between all products and the product.
  defp with_expansion_crumb([all, item], %{cardmarket_expansion_id: id, set_name: name})
       when is_integer(id) and is_binary(name) do
    [
      all,
      %{
        "@type" => "ListItem",
        "position" => 2,
        "name" => name,
        "item" => expansion_url(id, name)
      },
      %{item | "position" => 3}
    ]
  end

  defp with_expansion_crumb(items, _product), do: items

  # The answer first, as search results and AI assistants quote it: today's
  # cheapest price, where, and how it compares with the other Polish shops.
  defp product_description(%{product: product, verdict: verdict} = page) do
    lead =
      case {verdict.cheapest, page.preorder?} do
        {nil, _preorder?} ->
          gettext("%{name}: teraz żaden polski sklep nie ma tego produktu na stanie.",
            name: product.name
          )

        {cheapest, true} ->
          gettext("%{name}: przedsprzedaż od %{price} w %{shop}.",
            name: product.name,
            price: Polish.price(cheapest.price),
            shop: GuideComponents.priced_shop_name(cheapest)
          )

        {cheapest, false} ->
          gettext("%{name}: najtaniej teraz %{price} w %{shop}.",
            name: product.name,
            price: Polish.price(cheapest.price),
            shop: GuideComponents.priced_shop_name(cheapest)
          )
      end

    [lead, comparison(verdict) | set_content(page)]
    |> Enum.reject(&is_nil/1)
    |> fit_description()
  end

  # A single booster's page also holds its set's pull rates and cards, which
  # people search for by name ("<set> drop rate", "<set> lista kart").
  defp product_titles(%{booster_set: %{pull_rates: %{}}, product: product}),
    do: [
      gettext("%{name} – cena, drop rate i lista kart", name: product.name),
      gettext("%{name} – cena", name: product.name),
      product.name
    ]

  defp product_titles(%{booster_set: %{rarities: [_ | _]}, product: product}),
    do: [
      gettext("%{name} – cena i lista kart", name: product.name),
      gettext("%{name} – cena", name: product.name),
      product.name
    ]

  defp product_titles(%{product: product}),
    do: [
      gettext("%{name} – ceny i oferty Pokémon TCG", name: product.name),
      gettext("%{name} – ceny i oferty", name: product.name),
      product.name
    ]

  defp set_content(%{booster_set: %{rarities: [_ | _] = rarities} = set}) do
    cards = Enum.sum_by(rarities, &length(&1.cards))

    [
      pull_rates_summary(set.pull_rates),
      # "Lista 22 kart": the genitive after "lista", whatever the count.
      gettext("Lista %{count} kart z cenami.", count: Polish.number(cards))
    ]
  end

  defp set_content(_page), do: [gettext("Porównanie cen w sklepach i historia cen.")]

  # The two rarest rates, as the page's table states them.
  defp pull_rates_summary(%{rates: [_ | _] = rates}) do
    odds = Enum.map_join(Enum.take(rates, 2), ", ", &"#{&1.rarity} #{Polish.odds(&1.rate)}")
    gettext("Szansa na drop (pull rates): %{odds}.", odds: odds)
  end

  defp pull_rates_summary(_pull_rates), do: nil

  defp comparison(%{status: status, typical: typical, typical_source: :shops} = verdict)
       when status in [:good, :normal, :expensive],
       do:
         gettext("%{verdict} – typowa cena w %{shops} sklepach to %{typical}.",
           verdict: GuideComponents.verdict_label(verdict),
           typical: Polish.zloty(typical),
           shops: length(verdict.shop_prices)
         )

  defp comparison(_verdict), do: nil

  # The answer the product's card shows, for its alt text.
  defp answer(%{cheapest: %{price: price} = cheapest} = verdict),
    do:
      gettext("%{verdict}: najtaniej teraz %{price} w %{shop}.",
        verdict: GuideComponents.verdict_label(verdict),
        price: Polish.price(price),
        shop: GuideComponents.priced_shop_name(cheapest)
      )

  defp answer(_verdict), do: gettext("Teraz żaden sklep nie ma tego produktu na stanie.")

  # `social_image` is the designed link-preview card (TcgCheapWeb.SocialImage),
  # not the product photo, which stays in the structured data.
  def single(page) do
    card = page.card
    number = CardGuide.printed_number(card)
    canonical = unverified_url(TcgCheapWeb.Endpoint, page.path)
    answer = Enum.find(page.answers, & &1.cheapest)

    description =
      if answer do
        fit_description([
          gettext("%{name} %{number}: od %{price} w sklepach wysyłających do Polski.",
            name: card.name,
            number: number,
            price: Polish.price(answer.cheapest.price)
          ),
          GuideComponents.single_verdict_label(answer.verdict) <> ".",
          gettext("Ceny, stan i warianty karty.")
        ])
      else
        gettext(
          "%{name} %{number}: brak ofert bez gradingu na stanie w sklepach. Sprawdź referencję Cardmarket i pozostałe oferty.",
          name: card.name,
          number: number
        )
      end

    card_name = "#{card.name} #{number} #{page.expansion_name}"

    metadata(
      fit_title([
        gettext("%{card} – cena karty Pokémon w Polsce", card: card_name),
        gettext("%{card} – cena karty Pokémon", card: card_name),
        card_name
      ]),
      description,
      canonical,
      # Matches CardGuide.sitemap_cards/0: a card without an offer leaves the index until one returns.
      robots: if(answer, do: "index, follow", else: "noindex, follow"),
      social_image:
        unverified_url(TcgCheapWeb.Endpoint, "/og" <> page.path,
          v: SocialImage.card_version(page)
        ),
      social_image_alt: card_name,
      structured_data: %{
        "@context" => "https://schema.org",
        "@graph" =>
          List.wrap(single_product(page, answer, description, canonical)) ++
            [
              %{
                "@type" => "BreadcrumbList",
                "itemListElement" => [
                  %{
                    "@type" => "ListItem",
                    "position" => 1,
                    "name" => gettext("Wszystkie produkty"),
                    "item" => url(~p"/")
                  },
                  %{
                    "@type" => "ListItem",
                    "position" => 2,
                    "name" => page.expansion_name,
                    "item" =>
                      expansion_url(card.tcgdex_set.cardmarket_expansion_id, page.expansion_name)
                  },
                  %{
                    "@type" => "ListItem",
                    "position" => 3,
                    "name" => card.name,
                    "item" => canonical
                  }
                ]
              }
            ]
      }
    )
  end

  # Like a sealed product's: only current, in-stock, ungraded offers at their
  # compared price, and only the answer's variant, so the price range starts at the "od"
  # price the description and the page's answer state. Without an answer there's no
  # Product block, as Google requires offers on one.
  defp single_product(_page, nil, _description, _canonical), do: nil

  defp single_product(page, answer, description, canonical) do
    offers =
      page.offers
      |> Enum.filter(&(&1.in_stock and is_nil(&1.grading) and &1.variant == answer.variant))
      |> Shops.compared()

    {low, high} = Enum.min_max_by(offers, & &1.price, Decimal)

    product = %{
      "@type" => "Product",
      "name" => "#{page.card.name} #{CardGuide.printed_number(page.card)} #{page.expansion_name}",
      "description" => description,
      "url" => canonical,
      "category" => gettext("Karta Pokémon TCG"),
      "offers" => %{
        "@type" => "AggregateOffer",
        "url" => canonical,
        "priceCurrency" => "PLN",
        "lowPrice" => Decimal.to_string(low.price, :normal),
        "highPrice" => Decimal.to_string(high.price, :normal),
        "offerCount" => length(offers)
      }
    }

    # The card picture the page shows, from our own mirror.
    if page.image,
      do:
        Map.put(
          product,
          "image",
          unverified_url(TcgCheapWeb.Endpoint, CardImage.detail_url(page.image))
        ),
      else: product
  end

  # Search results show about 60 characters of a title and 160 of a
  # description and cut the rest. A page lists its title from the fullest to
  # the shortest form; the description keeps the first sentences that fit, so
  # the answer always stays.
  @title_limit 60
  @description_limit 160
  @brand " · TCG Cheap"

  defp fit_title(titles),
    do: Enum.find(titles, List.last(titles), &(String.length(&1) <= @title_limit))

  defp fit_description([first | rest]) do
    Enum.reduce_while(rest, first, fn sentence, description ->
      longer = description <> " " <> sentence

      if String.length(longer) <= @description_limit,
        do: {:cont, longer},
        else: {:halt, description}
    end)
  end

  # The browser tab's and the search result's title, with our name when it fits.
  defp page_title(title) do
    branded = title <> @brand
    if String.length(branded) <= @title_limit, do: branded, else: title
  end

  defp metadata(title, description, canonical, opts) do
    %{
      title: title,
      page_title: page_title(title),
      description: description,
      canonical: canonical,
      # nil leaves the alternate link without an href.
      markdown: Keyword.get_lazy(opts, :markdown, fn -> PageMarkdown.url_for(canonical) end),
      robots: Keyword.get(opts, :robots, "index, follow"),
      social_image: Keyword.fetch!(opts, :social_image),
      social_image_alt: Keyword.fetch!(opts, :social_image_alt),
      structured_data: Keyword.fetch!(opts, :structured_data)
    }
  end

  attr :seo, :map, required: true

  def head(assigns) do
    ~H"""
    <meta id="seo-description" name="description" content={@seo.description} />
    <meta id="seo-robots" name="robots" content={@seo.robots} />
    <link id="seo-canonical" rel="canonical" href={@seo.canonical} />
    <link id="seo-markdown" rel="alternate" type="text/markdown" href={@seo.markdown} />
    <meta id="seo-og-title" property="og:title" content={@seo.title <> " · TCG Cheap"} />
    <meta id="seo-og-description" property="og:description" content={@seo.description} />
    <meta id="seo-og-url" property="og:url" content={@seo.canonical} />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="TCG Cheap" />
    <meta id="seo-og-image" property="og:image" content={@seo.social_image} />
    <meta property="og:image:type" content="image/jpeg" />
    <meta property="og:image:width" content={SocialImage.width()} />
    <meta property="og:image:height" content={SocialImage.height()} />
    <meta id="seo-og-image-alt" property="og:image:alt" content={@seo.social_image_alt} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta id="seo-twitter-image-alt" name="twitter:image:alt" content={@seo.social_image_alt} />
    <script id="seo-structured-data" type="application/ld+json">
      <%= raw(Jason.encode!(@seo.structured_data, escape: :html_safe)) %>
    </script>
    """
  end

  attr :seo, :map, required: true

  # Root layouts render only on HTTP requests. Keep their metadata current on live navigation too.
  def sync(assigns) do
    ~H"""
    <div
      id="guide-seo"
      hidden
      phx-hook=".SearchMetadata"
      phx-update="ignore"
      data-seo={Jason.encode!(@seo)}
    />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SearchMetadata">
      export default {
        mounted() { this.sync() },
        updated() { this.sync() },
        sync() {
          const seo = JSON.parse(this.el.dataset.seo)
          const values = {
            "seo-description": seo.description,
            "seo-robots": seo.robots,
            "seo-og-title": `${seo.title} · TCG Cheap`,
            "seo-og-description": seo.description,
            "seo-og-url": seo.canonical,
            "seo-og-image": seo.social_image,
            "seo-og-image-alt": seo.social_image_alt,
            "seo-twitter-image-alt": seo.social_image_alt,
          }
          for (const [id, value] of Object.entries(values)) {
            const element = document.getElementById(id)
            if (value) element.setAttribute("content", value)
            else element.removeAttribute("content")
          }
          document.getElementById("seo-canonical").setAttribute("href", seo.canonical)
          const markdown = document.getElementById("seo-markdown")
          if (seo.markdown) markdown.setAttribute("href", seo.markdown)
          else markdown.removeAttribute("href")
          document.getElementById("seo-structured-data").textContent = JSON.stringify(seo.structured_data)
        },
      }
    </script>
    """
  end

  # Our stored copy of the packaging photo when there is one, else the shop's.
  defp image(%{stored_photo_page_url: url}) when is_binary(url), do: url
  defp image(_product), do: nil
end
