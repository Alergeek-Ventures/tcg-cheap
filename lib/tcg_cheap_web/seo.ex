defmodule TcgCheapWeb.SEO do
  @moduledoc "Search metadata for the buying guide, derived from the same data as its visible pages."

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{CardImage, Catalogue, Kinds}
  alias TcgCheapWeb.{GuideComponents, PageMarkdown, Polish, SocialImage}

  def home(params) do
    metadata(
      gettext("Pokémon TCG – porównywarka cen boosterów, ETB i boxów"),
      gettext(
        "Porównaj ceny Pokémon TCG w polskich sklepach. Sprawdź oferty boosterów, ETB i boxów, historię cen i czy warto kupić teraz."
      ),
      url(~p"/"),
      social_image: home_image(),
      social_image_alt: home_image_alt(),
      robots:
        if(Enum.any?(~w(q rodzaj wersja rozszerzenie widok), &Map.has_key?(params, &1)),
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

  # People ask what a booster costs, also in the chains ("ile kosztuje booster
  # pokemon w żabce"): the answer is today's cheapest English booster.
  def booster_prices(page) do
    canonical = url(~p"/ile-kosztuje-booster-pokemon")

    metadata(
      gettext("Ile kosztuje booster Pokémon? Aktualne ceny w Polsce"),
      Enum.join(booster_answer(page), " "),
      canonical,
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
            "name" => gettext("Ile kosztuje booster"),
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
        shop: GuideComponents.shop_name(cheapest.verdict.cheapest)
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
      expansion_title(name, page.set),
      Enum.join(expansion_answer(name, page), " "),
      canonical,
      social_image: home_image(),
      social_image_alt: home_image_alt(),
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

  defp expansion_title(name, %{pull_rates: %{}}),
    do: gettext("%{expansion} – ceny, drop rate i lista kart Pokémon TCG", expansion: name)

  defp expansion_title(name, %{rarities: [_ | _]}),
    do: gettext("%{expansion} – ceny i lista kart Pokémon TCG", expansion: name)

  defp expansion_title(name, _set),
    do: gettext("%{expansion} – ceny boosterów, ETB i boxów Pokémon TCG", expansion: name)

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
            "%{expansion}: porównaj ceny boosterów, ETB, boxów i kolekcji w polskich sklepach.",
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
        shop: GuideComponents.shop_name(cheapest)
      )

  defp booster_answer(name, %{verdict: %{cheapest: cheapest}}),
    do:
      gettext("Booster %{expansion}: najtaniej teraz %{price} w %{shop}.",
        expansion: name,
        price: Polish.price(cheapest.price),
        shop: GuideComponents.shop_name(cheapest)
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

    # Only current, in-stock shop offers count, never MSRP, Cardmarket or a last-known price.
    # Google requires offers on a Product, so without one there's no Product block.
    product_data =
      case Enum.filter(page.offers, & &1.in_stock) do
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
      product_title(page),
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
            shop: GuideComponents.shop_name(cheapest)
          )

        {cheapest, false} ->
          gettext("%{name}: najtaniej teraz %{price} w %{shop}.",
            name: product.name,
            price: Polish.price(cheapest.price),
            shop: GuideComponents.shop_name(cheapest)
          )
      end

    [lead, comparison(verdict) | set_content(page)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # A single booster's page also holds its set's pull rates and cards, which
  # people search for by name ("<set> drop rate", "<set> lista kart").
  defp product_title(%{booster_set: %{pull_rates: %{}}, product: product}),
    do: gettext("%{name} – cena, drop rate i lista kart", name: product.name)

  defp product_title(%{booster_set: %{rarities: [_ | _]}, product: product}),
    do: gettext("%{name} – cena i lista kart", name: product.name)

  defp product_title(%{product: product}),
    do: gettext("%{name} – ceny i oferty Pokémon TCG", name: product.name)

  defp set_content(%{booster_set: %{rarities: [_ | _] = rarities} = set}) do
    cards = Enum.sum_by(rarities, &length(&1.cards))

    [
      pull_rates_summary(set.pull_rates),
      # "Lista 22 kart": the genitive after "lista", whatever the count.
      gettext("Lista %{count} kart z cenami.", count: Polish.number(cards))
    ]
  end

  defp set_content(_page), do: [gettext("Porównanie cen w polskich sklepach i historia cen.")]

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
        shop: GuideComponents.shop_name(cheapest)
      )

  defp answer(_verdict), do: gettext("Teraz żaden sklep nie ma tego produktu na stanie.")

  # `social_image` is the designed link-preview card (TcgCheapWeb.SocialImage),
  # not the product photo, which stays in the structured data.
  def single(page) do
    card = page.card
    canonical = unverified_url(TcgCheapWeb.Endpoint, page.path)
    answer = Enum.find(page.answers, & &1.cheapest)

    description =
      if answer do
        gettext(
          "%{name} %{number}: od %{price} w polskich sklepach. %{verdict}. Ceny, stan i warianty karty.",
          name: card.name,
          number: card.number,
          price: Polish.price(answer.cheapest.price),
          verdict: GuideComponents.single_verdict_label(answer.verdict)
        )
      else
        gettext(
          "%{name} %{number}: brak ofert bez gradingu na stanie w polskich sklepach. Sprawdź referencję Cardmarket i pozostałe oferty.",
          name: card.name,
          number: card.number
        )
      end

    metadata(
      gettext("%{name} %{number} %{set} – cena karty Pokémon w Polsce",
        name: card.name,
        number: card.number,
        set: page.expansion_name
      ),
      description,
      canonical,
      # Matches CardGuide.sitemap_cards/0: a card without an offer leaves the index until one returns.
      robots: if(answer, do: "index, follow", else: "noindex, follow"),
      social_image: home_image(),
      social_image_alt: home_image_alt(),
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

  # Like a sealed product's: only current, in-stock, ungraded shop offers, and
  # only the answer's variant, so the price range starts at the "od" price the
  # description and the page's answer state. Without an answer there's no
  # Product block, as Google requires offers on one.
  defp single_product(_page, nil, _description, _canonical), do: nil

  defp single_product(page, answer, description, canonical) do
    offers =
      Enum.filter(
        page.offers,
        &(&1.in_stock and is_nil(&1.grading) and &1.variant == answer.variant)
      )

    {low, high} = Enum.min_max_by(offers, & &1.price, Decimal)

    product = %{
      "@type" => "Product",
      "name" => "#{page.card.name} #{page.card.number} #{page.expansion_name}",
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

  defp metadata(title, description, canonical, opts) do
    %{
      title: title,
      description: description,
      canonical: canonical,
      markdown: PageMarkdown.url_for(canonical),
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
          document.getElementById("seo-markdown").setAttribute("href", seo.markdown)
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
