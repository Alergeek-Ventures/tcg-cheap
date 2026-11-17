defmodule TcgCheapWeb.PageMarkdown do
  @moduledoc """
  The guide's pages as markdown for AI agents (`TcgCheapWeb.MarkdownController`),
  built from the same read models and sentences as their HTML: the page's
  answer first, then the facts and offers behind it. Links point to the HTML
  pages, which stay canonical.
  """

  use TcgCheapWeb, :verified_routes
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Cards
  alias TcgCheap.Sealed.{Editions, Kinds, Market, PriceGuide, RetailDeal}

  alias TcgCheapWeb.{
    CardRecords,
    Format,
    ListingComponents,
    OfferComponents,
    Paths,
    Region,
    RegionText,
    SEO,
    VerdictComponents
  }

  @doc "The markdown version's URL of a page's canonical URL."
  @spec url_for(String.t()) :: String.t()
  def url_for(canonical) do
    if String.ends_with?(canonical, "/"), do: canonical <> "index.md", else: canonical <> ".md"
  end

  @doc "How the guide rates a price, for the home page and llms.txt, in the current region."
  @spec method() :: [String.t()]
  def method do
    %{prices: prices, good_price: good_price, few_shops: few_shops} =
      RegionText.markdown_method(PriceGuide.window_days())

    [
      prices,
      gettext(
        "Typowa cena to mediana cen samego produktu, bez dostawy, po jednej z każdego sklepu, który ma go na stanie (co najmniej %{minimum} sklepy).",
        minimum: PriceGuide.min_shops()
      ),
      good_price,
      few_shops,
      gettext(
        "Ocena nigdy nie opiera się na cenie sugerowanej producenta. Brakujące dane pokazujemy jako brakujące."
      )
    ]
  end

  @doc "The home page: how a price is rated, today's deals (Polish) and where to go next."
  def home(seo, deals, today) do
    page(seo, today, [
      section(gettext("Jak oceniamy cenę"), list(method())),
      deals != [] && section(gettext("Okazje dziś"), list(Enum.map(deals, &deal_line/1))),
      section(
        gettext("Gdzie dalej"),
        list([
          link(gettext("Ceny produktów"), url_for(Paths.url(Paths.products()))),
          link(gettext("Ceny kart"), url_for(Paths.url(Paths.cards()))),
          Paths.page(:booster_prices) &&
            link(
              gettext("Ile kosztuje booster Pokémon?"),
              url_for(Paths.url(Paths.page(:booster_prices)))
            ),
          Paths.page(:expensive_cards) &&
            link(
              gettext("Najdroższe karty Pokémon"),
              url_for(Paths.url(Paths.page(:expensive_cards)))
            ),
          Paths.page(:card_value) &&
            link(
              gettext("Ile jest warta twoja karta?"),
              url_for(Paths.url(Paths.page(:card_value)))
            )
        ])
      )
    ])
  end

  # "Delta Reign ETB: 699,00 zł w Gralnia, zwykle 899,90 zł (−22%)", a chain's
  # deal with its days.
  defp deal_line(deal) do
    where =
      case deal.source do
        {:shop, shop} ->
          gettext("w %{shop}", shop: OfferComponents.shop_name(%{shop: shop}))

        {:retail, retail} ->
          "#{RetailDeal.chain_name(retail.chain)}, #{Format.days(retail.starts_on, retail.ends_on)}"
      end

    gettext("%{product}: %{price} %{where}, zwykle %{typical} w sklepach%{percent}",
      product: link(deal.product.name, Paths.url(Paths.product(deal.product.slug))),
      price: Format.price(deal.price),
      where: where,
      typical: Format.price(deal.typical),
      percent: if(deal.percent, do: " (−#{deal.percent}%)", else: "")
    )
  end

  @doc "The products list's first page: how a price is rated, then the products."
  def products(seo, summaries, today) do
    page(seo, today, [
      section(gettext("Jak oceniamy cenę"), list(method())),
      section(
        gettext("Produkty"),
        [
          gettext(
            "Najpierw produkty na stanie w sklepach, potem najnowsze; angielskie wydania. Pełna lista rozszerzeń: %{url}",
            url: url(~p"/llms.txt")
          ),
          products_table(summaries)
        ]
      )
    ])
  end

  def cards(seo, cards, today) do
    page(seo, today, [
      section(gettext("Karty"), [
        if(singles?(),
          do:
            gettext(
              "Angielskie karty na stanie w sklepach: najniższa cena bez dostawy (ze sklepów za granicą z wysyłką) i ocena wobec Cardmarket z przesyłką. Pełna lista rozszerzeń: %{url}",
              url: url(~p"/llms.txt")
            ),
          else: gettext("Angielskie karty z trendem Cardmarket, bez dostawy.")
        ),
        cards_table(cards)
      ])
    ])
  end

  def booster_prices(seo, page) do
    page(seo, page.today, [
      section("Najpierw: czego chcesz?", [
        "Pokémony to dziś drogie hobby. Zanim cokolwiek kupisz, zastanów się, czego od niego chcesz:",
        list([
          "Emocji z otwierania: same boostery – pojedynczo, w Booster Bundle (6) albo w Booster Boxie (36).",
          "Jednej konkretnej karty: kup ją osobno, booster to loteria – " <>
            link("ceny kart w sklepach", Paths.url(Paths.cards())) <> ".",
          "Prezentu: Elite Trainer Box, puszka albo kolekcja – płacisz też za opakowanie i dodatki.",
          "Grania: Build & Battle Box (talia 40 kart i cztery boostery) albo gotowa talia 60 kart."
        ])
      ]),
      section("Jak wychodzą nowe sety", [
        "Nowy angielski set wychodzi mniej więcej co dwa miesiące. Do dwóch tygodni przed premierą sklepy z programu Play! Pokémon sprzedają Build & Battle Box na turnieje przedpremierowe (prerelease). W dniu premiery w sklepach pojawia się reszta: pojedyncze boostery, blistry, Booster Bundle, Elite Trainer Box i Booster Box. Puszki i kolekcje dochodzą później.",
        "Set specjalny nie ma Booster Boxa; jego boostery są w ETB, Booster Bundle, blistrach, puszkach i kolekcjach.",
        sets_table(page.sets)
      ]),
      extras_section(page.latest),
      retail_deals("Okazje w sieciówkach", page.retail_deals),
      section("Boostery w sklepach", [
        "Angielskie, najnowsze sety najpierw. Najniższa cena na stanie w sklepach internetowych, bez dostawy (ze sklepów za granicą z wysyłką).",
        products_table(page.boosters)
      ])
    ])
  end

  defp sets_table([]), do: nil

  defp sets_table(sets) do
    table(
      ["Set", "Premiera", "Rodzaj", "Booster od", "Elite Trainer Box od"],
      Enum.map(sets, fn set ->
        [
          link(set.name, Paths.url(Paths.product(set.booster.product.slug))),
          if(set.released_on, do: Date.to_iso8601(set.released_on), else: "–"),
          if(set.booster_box?, do: "zwykły", else: "specjalny (bez Booster Boxa)"),
          Format.price(set.booster.verdict.cheapest.price),
          if(set.etb, do: Format.price(set.etb.verdict.cheapest.price), else: "brak na stanie")
        ]
      end)
    )
  end

  # What each of the newest set's boxes costs over its boosters bought one
  # by one, as the HTML chart shows it.
  defp extras_section(nil), do: nil

  defp extras_section(%{set: set, products: products}) do
    rows =
      for box <- products, box.extra do
        [
          link(box.product.name, Paths.url(Paths.product(box.product.slug))),
          Format.whole_price(box.price) <>
            if(box.few_shops?, do: " (najniższa, mało sklepów)", else: ""),
          "#{Format.boosters(box.boosters)} po #{Format.whole_price(box.single)}: #{Format.whole_price(box.loose)}",
          if(Decimal.negative?(box.extra),
            do: "taniej o #{Format.whole_price(Decimal.abs(box.extra))}",
            else: Format.whole_price(box.extra)
          )
        ]
      end

    if rows != [],
      do:
        section("Za co dopłacasz w pudełku – #{set}", [
          "W pudełkach jednego setu są te same boostery, które kupisz osobno. Reszta ceny to dopłata za dodatki: kartę promo, akcesoria, talię albo samo opakowanie. Cena to typowa cena w sklepach (mediana cen samego pudełka, bez dostawy); gdy pudełko ma mniej niż trzy sklepy – najniższa, i wtedy boostery też liczymy po najniższej cenie.",
          table(["Pudełko", "Cena", "Te same boostery osobno", "Dopłata"], rows)
        ])
  end

  def expensive_cards(seo, overview, records, ranking) do
    page(seo, Date.utc_today(), [
      section("Rekordy aukcji", [
        "Najwyższy publiczny wynik aukcji każdej karty, z opłatą kupującego, potwierdzony przez dom aukcyjny, Guinness World Records albo duże media. Sprawdzone #{Date.to_iso8601(CardRecords.checked_on())}.",
        table(
          ["Karta", "Ocena", "Cena", "Sprzedana", "Dom aukcyjny"],
          Enum.map(records, fn record ->
            [
              "#{link(record.name, record.source)} (#{record.detail})",
              record.grade,
              CardRecords.usd(record.usd),
              CardRecords.month(record.sold),
              record.house
            ]
          end)
        )
      ]),
      section("Najdroższe karty dziś", [
        "Angielskie karty od ery Sword & Shield (od listopada 2019) według ceny rynkowej: trendu Cardmarket w złotych#{rate(overview.rate)}. Przy starszych kartach trend miesza egzemplarze w różnym stanie i z oceną. Najtaniej: najniższa cena karty na stanie w polskim sklepie, bez dostawy.",
        expensive_cards_table(ranking)
      ]),
      section(
        "Najdroższa karta z nowych rozszerzeń",
        list(
          Enum.map(overview.new_sets, fn row ->
            "#{row.card.expansion_name}: #{link(row.card.name, url_from_path(row.card.public_path))}, #{Format.whole_price(row.value)}"
          end)
        )
      )
    ])
  end

  def card_value(seo, %{spread: spread, examples: examples}) do
    page(seo, Date.utc_today(), [
      spread &&
        section("Ile kosztuje karta Pokémon", [
          "Połowa z #{Format.number(spread.count)} angielskich kart na stanie w polskich sklepach kosztuje najwyżej #{Format.whole_price_ceiling(spread.median)}, a 9 na 10 – najwyżej #{Format.whole_price_ceiling(spread.ninetieth)}. Każda karta liczy się raz, z ceną najtańszej oferty w polskim sklepie, bez dostawy.",
          table(
            ["Cena", "Karty", "Udział"],
            Enum.map(spread.bins, fn bin ->
              [spread_range(bin), Format.number(bin.count), spread_share(bin.count, spread.count)]
            end)
          )
        ]),
      examples != [] &&
        section("Co kupisz za złotówkę, a co za tysiąc", [
          "Karty, które polskie sklepy sprzedają za mniej więcej tyle, ile kosztują na Cardmarket.",
          table(
            ["Za około", "Karta", "Rozszerzenie", "Cena w sklepie"],
            Enum.map(examples, fn %{price: price, row: row} ->
              [
                Format.whole_price(price),
                link("#{row.card.name} #{row.card.number}", url_from_path(row.card.public_path)),
                row.card.expansion_name,
                "#{Format.price(row.offer.price)} w #{OfferComponents.shop_name(row.offer)}"
              ]
            end)
          )
        ]),
      section(
        "Jak sprawdzić wartość karty",
        list([
          "Numer: na dole karty, np. 161/131 – karta 161 z rozszerzenia, które ma 131 kart; obok kod rozszerzenia i język. Numer większy niż liczba kart oznacza kartę sekretną. Na starych kartach numer jest w prawym dolnym rogu.",
          "Wersja: zwykła, reverse holo albo pierwsze wydanie (znaczek „Edition 1” na starych kartach) mają osobne ceny.",
          "Stan: zagięcia, rysy i obite rogi wyraźnie obniżają cenę.",
          "Cena: wyszukaj kartę po nazwie albo numerze (także 161/131) na #{Paths.url(Paths.cards())}; strona karty ma ceny w sklepach i cenę na Cardmarket.",
          "Ocena (grading): tylko przy kartach wartych setki złotych i w idealnym stanie."
        ])
      ),
      section(
        "Ocena, czyli grading",
        list([
          "Firma gradingowa ocenia stan karty w skali od 1 do 10 i zamyka ją w plastikowym etui z etykietą (slab).",
          "Firmy: PSA, CGC, Beckett, TAG, SGC (USA), ACE, MGC (Wielka Brytania), PCA (Francja), AP Grading (Niemcy).",
          "Warto przy kartach wartych setki albo tysiące złotych, w idealnym stanie, na sprzedaż. Nie warto przy kartach za kilka złotych, ze śladami gry albo do grania.",
          "Koszt: w CGC najtaniej 17 dolarów za kartę przy 25 kartach naraz albo 20 dolarów za jedną (cennik z listopada 2026), do tego wysyłka i około 150 dni roboczych czekania."
        ])
      ),
      section(
        "Za ile sprzedasz kartę",
        "Sklep, który skupuje karty, zapłaci mniej niż jego cena sprzedaży. Na Cardmarket dostaniesz więcej, ale zapłacisz prowizję i sam wyślesz kartę."
      )
    ])
  end

  defp spread_range(%{from: 0, to: to}), do: "poniżej #{Format.whole_price(to)}"
  defp spread_range(%{from: from, to: nil}), do: "od #{Format.whole_price(from)}"
  defp spread_range(%{from: from, to: to}), do: Format.whole_price_range(from, to)

  defp spread_share(count, total) do
    case round(count * 100 / total) do
      0 when count > 0 -> "<1%"
      share -> "#{share}%"
    end
  end

  # As the article: an offer it does not judge has no verdict, not "no
  # Cardmarket price".
  defp expensive_card_verdict(verdict) do
    if verdict && VerdictComponents.single_verdict_shown?(verdict),
      do: VerdictComponents.single_verdict_label(verdict),
      else: ""
  end

  defp rate(nil), do: ""
  defp rate(rate), do: " po kursie NBP #{Format.rate(rate.rate)} zł za euro"

  defp expensive_cards_table(rows) do
    table(
      ["Karta", "Rozszerzenie", "Cena rynkowa", "Najtaniej w Polsce", "Ocena"],
      Enum.map(rows, fn row ->
        [
          link("#{row.card.name} #{row.card.number}", url_from_path(row.card.public_path)),
          row.card.expansion_name,
          Format.whole_price(row.value),
          if(row.offer,
            do: "#{Format.price(row.offer.price)} w #{OfferComponents.shop_name(row.offer)}",
            else: "brak na stanie"
          ),
          expensive_card_verdict(row.verdict)
        ]
      end)
    )
  end

  def product(seo, page) do
    product = page.product

    page(seo, page.today, [
      section(gettext("Werdykt"), list(verdict_facts(page))),
      section(gettext("Produkt"), list(product_facts(product))),
      section(gettext("Oferty"), offers_table(page.offers, page.compared, page.today)),
      retail_deals(gettext("W sieciówkach"), page.retail_deals),
      page.booster_set && pull_rates(page.booster_set)
    ])
  end

  def expansion(seo, today, %{set: set}, summaries) do
    page(seo, today, [
      section(gettext("Produkty"), products_table(summaries)),
      set && pull_rates(set),
      set && set.rarities != [] && cards(set)
    ])
  end

  def single(seo, page) do
    card = page.card
    today = Date.utc_today()

    page(seo, today, [
      if(singles?(),
        do: section(gettext("Ceny"), list(Enum.map(page.answers, &single_answer/1))),
        else: section("Cardmarket", cardmarket_trend(page))
      ),
      section(
        gettext("Karta"),
        list([
          gettext("Numer: %{number}", number: Cards.Guide.printed_number(card)),
          gettext("Rozszerzenie") <>
            ": " <>
            link(
              page.expansion_name,
              SEO.Expansion.url(card.tcgdex_set.cardmarket_expansion_id, page.expansion_name)
            ),
          card.rarity && gettext("Rzadkość") <> ": " <> Cards.Rarities.label(card.rarity)
        ])
      ),
      singles?() &&
        section(gettext("Oferty"), card_offers_table(page.offers, page.compared, today))
    ])
  end

  defp cardmarket_trend(%{price: price, rate: rate, market: market}) do
    trend = price && price.trend

    case Market.in_market(trend, rate, market) do
      nil ->
        gettext("Brak ceny Cardmarket.")

      value ->
        if Region.current().market.currency == "EUR",
          do: gettext("Trend Cardmarket: %{price}, bez dostawy.", price: Format.price(value)),
          else:
            gettext("Trend Cardmarket: %{price} (%{eur}), bez dostawy.",
              price: Format.price(value),
              eur: Format.eur(trend)
            )
    end
  end

  defp singles?, do: Region.singles?(Region.current())

  def not_found do
    """
    # #{gettext("Nie znaleziono")}

    #{gettext("Tej strony nie ma w TCG Cheap. Spis stron: %{url}", url: url(~p"/llms.txt"))}
    """
  end

  defp page(seo, today, sections) do
    [
      "# #{seo.title}",
      "> #{seo.description}",
      gettext("Strona: %{url}", url: seo.canonical) <>
        "\n" <> gettext("Stan na: %{date}", date: Date.to_iso8601(today))
      | Enum.filter(sections, &is_binary/1)
    ]
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp section(title, body), do: Enum.join(["## #{title}" | List.wrap(body)], "\n\n")

  defp list(items),
    do: items |> Enum.reject(&(&1 in [nil, false])) |> Enum.map_join("\n", &"- #{&1}")

  defp table(header, rows) do
    lines =
      [header, Enum.map(header, fn _ -> "---" end) | rows]
      |> Enum.map(fn cells -> "| " <> Enum.map_join(cells, " | ", &cell/1) <> " |" end)

    Enum.join(lines, "\n")
  end

  defp cell(text), do: String.replace(text, "|", "\\|")

  @doc "A markdown link; the URL in angle brackets, as a shop's may hold spaces or parentheses."
  def link(text, url), do: "[#{String.replace(text, ~w([ ]), &("\\" <> &1))}](<#{url}>)"

  defp verdict_facts(%{verdict: verdict, past: past} = page) do
    [
      gettext("Ocena: %{verdict}", verdict: VerdictComponents.verdict_label(verdict)),
      verdict.cheapest && cheapest_offer(verdict.cheapest, page.preorder?),
      verdict.typical_source == :shops &&
        gettext(
          "Typowa cena w sklepach: %{typical} (mediana cen produktu bez dostawy z %{count} sklepów)",
          typical: Format.limit_price(verdict.typical),
          count: length(verdict.shop_prices)
        ),
      verdict.good_max &&
        gettext("Dobra cena do %{good}, normalna do %{normal}",
          good: Format.limit_price(verdict.good_max),
          normal: Format.limit_price(verdict.normal_max)
        ),
      past.typical &&
        gettext("Zwykła cena z ostatnich %{days} dni: %{price}",
          days: PriceGuide.window_days(),
          price: Format.limit_price(past.typical)
        ),
      page.cardmarket_price && cardmarket_trend_fact(page)
    ]
  end

  defp cheapest_offer(cheapest, preorder?) do
    values = [
      price: Format.price(cheapest.price),
      shop: OfferComponents.priced_shop_name(cheapest)
    ]

    if preorder?,
      do: gettext("Najtańsza oferta (przedsprzedaż): %{price} w %{shop}", values),
      else: gettext("Najtańsza oferta: %{price} w %{shop}", values)
  end

  defp cardmarket_trend_fact(%{cardmarket_delivered_price: nil} = page),
    do:
      gettext("Trend Cardmarket: %{price} bez dostawy",
        price: Format.price(page.cardmarket_price)
      )

  defp cardmarket_trend_fact(page) do
    gettext("Trend Cardmarket: %{price} bez dostawy, %{delivered} z przesyłką z Niemiec",
      price: Format.price(page.cardmarket_price),
      delivered: Format.price(page.cardmarket_delivered_price)
    )
  end

  defp product_facts(product) do
    [
      gettext("Rodzaj") <> ": " <> Kinds.label(product.kind),
      product.edition && gettext("Wydanie") <> ": " <> Editions.label(product.edition),
      product.set_name && product.cardmarket_expansion_id &&
        gettext("Rozszerzenie") <>
          ": " <>
          link(
            product.set_name,
            SEO.Expansion.url(product.cardmarket_expansion_id, product.set_name)
          )
    ]
  end

  # As on the HTML pages: apart from the shop offers, never in the verdict.
  defp retail_deals(_title, []), do: nil

  defp retail_deals(title, deals) do
    section(title, [
      gettext(
        "Ceny z gazetek sieci i zgłoszeń z konkretnych sklepów. Dostępność bywa różna, więc nie wliczamy ich do oceny."
      ),
      table(
        [
          pgettext("markdown", "Sieć"),
          gettext("Produkt"),
          pgettext("markdown", "Cena"),
          pgettext("markdown", "Kiedy"),
          gettext("Źródło")
        ],
        Enum.map(deals, fn deal ->
          [
            RetailDeal.chain_name(deal.chain),
            if(deal.product,
              do: link(deal.title, Paths.url(Paths.product(deal.product.slug))),
              else: deal.title
            ),
            Format.price(deal.price),
            Enum.join(
              Enum.reject(
                [
                  Format.days(deal.starts_on, deal.ends_on),
                  deal.note && Format.recorded(deal.note)
                ],
                &is_nil/1
              ),
              ", "
            ),
            link(gettext("źródło"), deal.source_url)
          ]
        end)
      )
    ])
  end

  defp offers_table([], _compared, _today),
    do: gettext("Żaden sklep nie ma teraz tej oferty.")

  # At the compared price, as the HTML rows: a shop abroad's with delivery.
  defp offers_table(offers, compared, today) do
    table(
      [gettext("Sklep"), pgettext("markdown", "Cena"), gettext("Dostępność")],
      Enum.map(offers, fn offer ->
        [
          link(offer_shop(offer), OfferComponents.offer_url(offer)),
          Format.price(compared[offer.id] || offer.price),
          availability(offer, today)
        ]
      end)
    )
  end

  # As on the HTML page, a shop abroad's price includes its delivery:
  # "Bangerpack (z wysyłką ze Szwecji)".
  defp offer_shop(offer) do
    case OfferComponents.delivered_term(offer) do
      nil -> OfferComponents.shop_name(offer)
      term -> "#{OfferComponents.shop_name(offer)} (#{term})"
    end
  end

  # An offer counts as current for a few days after a shop's last fetch; as
  # the HTML page does, an older one says when it was checked.
  defp availability(offer, today) do
    case DateTime.to_date(offer.last_seen_at) do
      ^today ->
        stock(offer)

      checked_on ->
        gettext("%{stock}, sprawdzono %{when}",
          stock: stock(offer),
          when: Format.days_ago(checked_on, today)
        )
    end
  end

  defp stock(%{in_stock: true}), do: gettext("na stanie")
  defp stock(%{preorder: true}), do: gettext("przedsprzedaż")
  defp stock(_offer), do: pgettext("markdown", "brak")

  defp cards_table([]), do: gettext("Brak kart na stanie.")

  defp cards_table(cards) do
    if singles?(), do: shop_cards_table(cards), else: cardmarket_cards_table(cards)
  end

  # Without singles shops in the region, Cardmarket's trend alone.
  defp cardmarket_cards_table(cards) do
    table(
      [gettext("Karta"), gettext("Rozszerzenie"), gettext("Trend Cardmarket")],
      Enum.map(cards, fn row ->
        price = row.cardmarket_trend

        [
          link("#{row.card.name} #{row.card.number}", url_from_path(row.path)),
          row.expansion_name,
          if(price, do: Format.price(price), else: gettext("brak ceny"))
        ]
      end)
    )
  end

  defp shop_cards_table(cards) do
    table(
      [
        gettext("Karta"),
        gettext("Rozszerzenie"),
        pgettext("markdown", "Najtaniej"),
        gettext("Ocena")
      ],
      Enum.map(cards, fn row ->
        [
          link("#{row.card.name} #{row.card.number}", url_from_path(row.path)),
          row.expansion_name,
          if(row.offer,
            do: price_in_shop(row.offer.price, OfferComponents.priced_shop_name(row.offer)),
            else: gettext("brak na stanie")
          ),
          VerdictComponents.single_verdict_label(row.verdict)
        ]
      end)
    )
  end

  defp products_table([]), do: gettext("Brak produktów.")

  defp products_table(summaries) do
    table(
      [
        gettext("Produkt"),
        gettext("Rodzaj"),
        pgettext("markdown", "Najtaniej"),
        gettext("Ocena")
      ],
      Enum.map(summaries, fn %{product: product, verdict: verdict} = summary ->
        [
          link(product.name, Paths.url(Paths.product(product.slug))),
          Kinds.label(product.kind),
          cheapest(summary),
          VerdictComponents.verdict_label(verdict)
        ]
      end)
    )
  end

  defp cheapest(%{verdict: %{cheapest: nil}}), do: gettext("brak na stanie")

  defp cheapest(%{verdict: %{cheapest: cheapest}} = summary) do
    offer = price_in_shop(cheapest.price, OfferComponents.priced_shop_name(cheapest))

    cond do
      summary.preorder? and summary.premiere ->
        gettext("%{offer} (przedsprzedaż, premiera %{date})",
          offer: offer,
          date: Format.date(summary.premiere)
        )

      summary.preorder? ->
        gettext("%{offer} (przedsprzedaż)", offer: offer)

      true ->
        offer
    end
  end

  defp price_in_shop(price, shop),
    do: gettext("%{price} w %{shop}", price: Format.price(price), shop: shop)

  # With the caveats the HTML table states: a rate for one card of the
  # rarity, another set's rates standing in, a smaller pack than they count.
  defp pull_rates(%{pull_rates: %{rates: [_ | _]} = pull_rates} = set) do
    notes =
      [
        Map.get(set, :smaller_pack?) && smaller_pack_note(set.standard_pack_size),
        pull_rates.borrowed_from &&
          gettext(
            "Tego setu nikt jeszcze nie policzył: to szanse z wcześniejszego setu (%{set}), niezweryfikowane dla tego.",
            set: pull_rates.borrowed_from
          ),
        gettext("To szacunki społeczności, sprawdzone %{date}. Źródła: %{sources}",
          date: Format.date(pull_rates.checked_on),
          sources: Enum.map_join(pull_rates.sources, ", ", & &1.url)
        )
      ]

    rows =
      Enum.map(pull_rates.rates, fn %{rarity: rarity, rate: rate} ->
        [
          if(rate.card,
            do: "#{rarity} (#{gettext("konkretna karta: %{name}", name: rate.card)})",
            else: rarity
          ),
          Format.odds(rate)
        ]
      end)

    section(gettext("Szanse na drop (pull rates)"), [
      list(notes),
      table([gettext("Rzadkość"), gettext("Szansa w paczce")], rows)
    ])
  end

  defp pull_rates(_set), do: nil

  defp smaller_pack_note(nil),
    do:
      gettext(
        "Te szanse dotyczą zwykłej paczki. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo."
      )

  defp smaller_pack_note(count),
    do:
      gettext(
        "Te szanse dotyczą zwykłej paczki %{count} kart. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo.",
        count: count
      )

  # Every card of the set by rarity, at the lower of its shop price and its
  # Cardmarket trend, as the set page lists them.
  defp cards(set) do
    section(
      gettext("Lista kart (%{cards})", cards: Format.cards(set.card_count)),
      Enum.map(set.rarities, fn %{rarity: rarity, cards: cards} ->
        "### #{rarity || gettext("Bez rzadkości")}\n\n" <> list(Enum.map(cards, &card_line/1))
      end)
    )
  end

  defp card_line(card) do
    name = "#{card.name} #{card.number}"
    title = if card.public_path, do: link(name, url_from_path(card.public_path)), else: name

    source = if singles?(), do: Cards.Guide.price_source(card), else: :cardmarket

    case {Cards.Guide.price(card), source} do
      {nil, _source} ->
        title

      {price, {:shop, shop}} ->
        "#{title}: #{price_in_shop(price, OfferComponents.priced_shop_name(%{shop: shop}))}"

      {price, :cardmarket} ->
        gettext("%{title}: %{price} (trend Cardmarket, bez dostawy)",
          title: title,
          price: Format.price(price)
        )
    end
  end

  defp single_answer(answer) do
    variant = ListingComponents.card_variant_label(answer.variant)

    price =
      if answer.cheapest,
        do:
          gettext("od %{price} w %{shop}",
            price: Format.price(answer.cheapest.price),
            shop: OfferComponents.priced_shop_name(answer.cheapest)
          ),
        else: gettext("brak ofert bez gradingu na stanie")

    reference =
      if answer.reference,
        do: gettext("; Cardmarket z przesyłką: %{price}", price: Format.price(answer.reference)),
        else: ""

    "#{variant}: #{price}#{reference} (#{VerdictComponents.single_verdict_label(answer.verdict)})"
  end

  defp card_offers_table([], _compared, _today),
    do: gettext("Żaden sklep nie ma teraz tej karty.")

  # At the compared price, as the HTML rows: a shop abroad's with delivery.
  defp card_offers_table(offers, compared, today) do
    table(
      [
        gettext("Sklep"),
        pgettext("markdown", "Cena"),
        gettext("Wariant"),
        gettext("Stan / grading"),
        gettext("Dostępność")
      ],
      Enum.map(offers, fn offer ->
        [
          link(offer_shop(offer), OfferComponents.offer_url(offer)),
          Format.price(compared[offer.id] || offer.price),
          ListingComponents.card_variant_label(offer.variant),
          offer.grading || (offer.condition && condition(offer.condition)) || "",
          availability(offer, today)
        ]
      end)
    )
  end

  defp condition(condition),
    do:
      condition
      |> Atom.to_string()
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)

  # A card path from the domain, in the region's form.
  defp url_from_path(path), do: path |> Paths.localize() |> Paths.url()
end
