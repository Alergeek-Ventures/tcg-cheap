defmodule TcgCheapWeb.PageMarkdown do
  @moduledoc """
  The guide's pages as markdown for AI agents (`TcgCheapWeb.MarkdownController`),
  built from the same read models and sentences as their HTML: the page's
  answer first, then the facts and offers behind it. Links point to the HTML
  pages, which stay canonical.
  """

  use TcgCheapWeb, :verified_routes

  alias TcgCheap.Sealed.{CardGuide, Kinds, PriceGuide, Rarities, Regions, RetailDeal}
  alias TcgCheapWeb.{CardRecords, GuideComponents, Polish, SEO}

  @doc "The markdown version's URL of a page's canonical URL."
  @spec url_for(String.t()) :: String.t()
  def url_for(canonical) do
    if String.ends_with?(canonical, "/"), do: canonical <> "index.md", else: canonical <> ".md"
  end

  @doc "How the guide rates a price, for the home page and llms.txt."
  @spec method() :: [String.t()]
  def method do
    [
      "Ceny pochodzą z publicznych feedów produktowych sklepów, pobieranych raz dziennie. Ceny polskich sklepów nie obejmują dostawy, a sklepów za granicą obejmują wysyłkę do Polski.",
      "Typowa cena to mediana najniższych cen na stanie w sklepach (jedna cena na sklep, co najmniej #{PriceGuide.min_shops()} sklepy).",
      "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich #{PriceGuide.window_days()} dni i trendu Cardmarket w złotych z przesyłką z Niemiec, gdy są znane.",
      "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w złotych.",
      "Ocena nigdy nie opiera się na cenie sugerowanej producenta. Brakujące dane pokazujemy jako brakujące."
    ]
  end

  def home(seo, summaries, retail_deal, today) do
    page(seo, today, [
      section("Jak oceniamy cenę", list(method())),
      section(
        "Ile kosztuje booster",
        [
          retail_deal &&
            "W sieciówkach: #{if retail_deal.product, do: retail_deal.product.name, else: retail_deal.title} #{Polish.price(retail_deal.price)}, #{RetailDeal.chain_name(retail_deal.chain)} #{Polish.days(retail_deal.starts_on, retail_deal.ends_on)}.",
          "Ceny boosterów i wszystkie okazje w sieciówkach: #{url_for(url(~p"/ile-kosztuje-booster-pokemon"))}"
        ]
        |> Enum.filter(&is_binary/1)
      ),
      section(
        "Produkty",
        [
          "Najpierw produkty na stanie w sklepach, potem najnowsze; angielskie wydania. Pełna lista rozszerzeń: #{url(~p"/llms.txt")}",
          products_table(summaries)
        ]
      )
    ])
  end

  def cards(seo, cards, today) do
    page(seo, today, [
      section("Karty", [
        "Angielskie karty na stanie w sklepach: najniższa cena bez dostawy (ze sklepów za granicą z wysyłką) i ocena wobec Cardmarket z przesyłką. Pełna lista rozszerzeń: #{url(~p"/llms.txt")}",
        cards_table(cards)
      ])
    ])
  end

  def booster_prices(seo, page) do
    page(seo, page.today, [
      retail_deals("Okazje w sieciówkach", page.retail_deals),
      section("Boostery w sklepach", [
        "Angielskie, najnowsze sety najpierw. Najniższa cena na stanie w sklepach internetowych, bez dostawy (ze sklepów za granicą z wysyłką).",
        products_table(page.boosters)
      ])
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
        "Angielskie karty według ceny rynkowej: trendu Cardmarket w złotych#{rate(overview.rate)}. Najtaniej: najniższa cena karty na stanie w polskim sklepie, bez dostawy.",
        expensive_cards_table(ranking)
      ]),
      section(
        "Najdroższa karta z nowych rozszerzeń",
        list(
          Enum.map(overview.new_sets, fn row ->
            "#{row.card.expansion_name}: #{link(row.card.name, url_from_path(row.card.public_path))}, #{Polish.zloty(row.value)}"
          end)
        )
      )
    ])
  end

  defp rate(nil), do: ""
  defp rate(rate), do: " po kursie NBP #{Polish.rate(rate.rate)} zł za euro"

  defp expensive_cards_table(rows) do
    table(
      ["Karta", "Rozszerzenie", "Cena rynkowa", "Najtaniej w Polsce", "Ocena"],
      Enum.map(rows, fn row ->
        [
          link("#{row.card.name} #{row.card.number}", url_from_path(row.card.public_path)),
          row.card.expansion_name,
          Polish.zloty(row.value),
          if(row.offer,
            do: "#{Polish.price(row.offer.price)} w #{GuideComponents.shop_name(row.offer)}",
            else: "brak na stanie"
          ),
          if(row.verdict, do: GuideComponents.single_verdict_label(row.verdict), else: "")
        ]
      end)
    )
  end

  def product(seo, page) do
    product = page.product

    page(seo, page.today, [
      section("Werdykt", list(verdict_facts(page))),
      section("Produkt", list(product_facts(product))),
      section("Oferty", offers_table(page.offers, page.today)),
      retail_deals("W sieciówkach", page.retail_deals),
      page.booster_set && pull_rates(page.booster_set)
    ])
  end

  def expansion(seo, today, %{set: set}, summaries) do
    page(seo, today, [
      section("Produkty", products_table(summaries)),
      set && pull_rates(set),
      set && set.rarities != [] && cards(set)
    ])
  end

  def single(seo, page) do
    card = page.card
    today = Date.utc_today()

    page(seo, today, [
      section("Ceny", list(Enum.map(page.answers, &single_answer/1))),
      section(
        "Karta",
        list([
          "Numer: #{card.number}",
          "Rozszerzenie: " <>
            link(
              page.expansion_name,
              SEO.expansion_url(card.tcgdex_set.cardmarket_expansion_id, page.expansion_name)
            ),
          card.rarity && "Rzadkość: #{Rarities.label(card.rarity)}"
        ])
      ),
      section("Oferty", card_offers_table(page.offers, today))
    ])
  end

  def not_found do
    """
    # Nie znaleziono

    Tej strony nie ma w TCG Cheap. Spis stron: #{url(~p"/llms.txt")}
    """
  end

  defp page(seo, today, sections) do
    [
      "# #{seo.title}",
      "> #{seo.description}",
      "Strona: #{seo.canonical}\nStan na: #{Date.to_iso8601(today)}"
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
      "Ocena: #{GuideComponents.verdict_label(verdict)}",
      verdict.cheapest &&
        "Najtańsza oferta#{if page.preorder?, do: " (przedsprzedaż)", else: ""}: #{Polish.price(verdict.cheapest.price)} w #{GuideComponents.priced_shop_name(verdict.cheapest)}",
      verdict.typical_source == :shops &&
        "Typowa cena w sklepach: #{Polish.zloty(verdict.typical)} (mediana z #{length(verdict.shop_prices)} sklepów)",
      verdict.good_max &&
        "Dobra cena do #{Polish.zloty(verdict.good_max)}, normalna do #{Polish.zloty(verdict.normal_max)}",
      past.typical &&
        "Zwykła cena z ostatnich #{PriceGuide.window_days()} dni: #{Polish.zloty(past.typical)}",
      page.cardmarket_pln &&
        "Trend Cardmarket: #{Polish.price(page.cardmarket_pln)} bez dostawy" <>
          if(page.cardmarket_delivered_pln,
            do: ", #{Polish.price(page.cardmarket_delivered_pln)} z przesyłką z Niemiec",
            else: ""
          )
    ]
  end

  defp product_facts(product) do
    [
      "Rodzaj: #{Kinds.label(product.kind)}",
      product.region && "Wydanie: #{Regions.label(product.region)}",
      product.set_name && product.cardmarket_expansion_id &&
        "Rozszerzenie: " <>
          link(
            product.set_name,
            SEO.expansion_url(product.cardmarket_expansion_id, product.set_name)
          )
    ]
  end

  # As on the HTML pages: apart from the shop offers, never in the verdict.
  defp retail_deals(_title, []), do: nil

  defp retail_deals(title, deals) do
    section(title, [
      "Ceny z gazetek sieci i zgłoszeń z konkretnych sklepów. Dostępność bywa różna, więc nie wliczamy ich do oceny.",
      table(
        ["Sieć", "Produkt", "Cena", "Kiedy", "Źródło"],
        Enum.map(deals, fn deal ->
          [
            RetailDeal.chain_name(deal.chain),
            if(deal.product,
              do: link(deal.title, url(~p"/produkty/#{deal.product.slug}")),
              else: deal.title
            ),
            Polish.price(deal.price),
            Enum.join(
              Enum.reject([Polish.days(deal.starts_on, deal.ends_on), deal.note], &is_nil/1),
              ", "
            ),
            link("źródło", deal.source_url)
          ]
        end)
      )
    ])
  end

  defp offers_table([], _today), do: "Żaden sklep nie ma teraz tej oferty."

  defp offers_table(offers, today) do
    table(
      ["Sklep", "Cena", "Dostępność"],
      Enum.map(offers, fn offer ->
        [
          link(offer_shop(offer), offer.url),
          Polish.price(GuideComponents.row_price(offer)),
          availability(offer, today)
        ]
      end)
    )
  end

  # As on the HTML page, a shop abroad's price includes its delivery:
  # "Bangerpack (z wysyłką ze Szwecji)".
  defp offer_shop(offer) do
    case GuideComponents.delivered_term(offer) do
      nil -> GuideComponents.shop_name(offer)
      term -> "#{GuideComponents.shop_name(offer)} (#{term})"
    end
  end

  # An offer counts as current for a few days after a shop's last fetch; as
  # the HTML page does, an older one says when it was checked.
  defp availability(offer, today) do
    case DateTime.to_date(offer.last_seen_at) do
      ^today -> stock(offer)
      checked_on -> "#{stock(offer)}, sprawdzono #{Polish.days_ago(checked_on, today)}"
    end
  end

  defp stock(%{in_stock: true}), do: "na stanie"
  defp stock(%{preorder: true}), do: "przedsprzedaż"
  defp stock(_offer), do: "brak"

  defp cards_table([]), do: "Brak kart na stanie."

  defp cards_table(cards) do
    table(
      ["Karta", "Rozszerzenie", "Najtaniej", "Ocena"],
      Enum.map(cards, fn row ->
        [
          link("#{row.card.name} #{row.card.number}", url_from_path(row.path)),
          row.expansion_name,
          if(row.offer,
            do:
              "#{Polish.price(row.offer.price)} w #{GuideComponents.priced_shop_name(row.offer)}",
            else: "brak na stanie"
          ),
          GuideComponents.single_verdict_label(row.verdict)
        ]
      end)
    )
  end

  defp products_table([]), do: "Brak produktów."

  defp products_table(summaries) do
    table(
      ["Produkt", "Rodzaj", "Najtaniej", "Ocena"],
      Enum.map(summaries, fn %{product: product, verdict: verdict} = summary ->
        [
          link(product.name, url(~p"/produkty/#{product.slug}")),
          Kinds.label(product.kind),
          cheapest(summary),
          GuideComponents.verdict_label(verdict)
        ]
      end)
    )
  end

  defp cheapest(%{verdict: %{cheapest: nil}}), do: "brak na stanie"

  defp cheapest(%{verdict: %{cheapest: cheapest}} = summary) do
    offer = "#{Polish.price(cheapest.price)} w #{GuideComponents.priced_shop_name(cheapest)}"

    cond do
      summary.preorder? and summary.premiere ->
        "#{offer} (przedsprzedaż, premiera #{Polish.date(summary.premiere)})"

      summary.preorder? ->
        "#{offer} (przedsprzedaż)"

      true ->
        offer
    end
  end

  # With the caveats the HTML table states: a rate for one card of the
  # rarity, another set's rates standing in, a smaller pack than they count.
  defp pull_rates(%{pull_rates: %{rates: [_ | _]} = pull_rates} = set) do
    notes =
      [
        Map.get(set, :smaller_pack?) &&
          "Te szanse dotyczą zwykłej paczki#{if set.standard_pack_size, do: " #{set.standard_pack_size} kart", else: ""}. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo.",
        pull_rates.borrowed_from &&
          "Tego setu nikt jeszcze nie policzył: to szanse z wcześniejszego setu (#{pull_rates.borrowed_from}), niezweryfikowane dla tego.",
        "To szacunki społeczności, sprawdzone #{Polish.date(pull_rates.checked_on)}. Źródła: " <>
          Enum.map_join(pull_rates.sources, ", ", & &1.url)
      ]

    rows =
      Enum.map(pull_rates.rates, fn %{rarity: rarity, rate: rate} ->
        [
          if(rate.card, do: "#{rarity} (konkretna karta: #{rate.card})", else: rarity),
          Polish.odds(rate)
        ]
      end)

    section("Szanse na drop (pull rates)", [
      list(notes),
      table(["Rzadkość", "Szansa w paczce"], rows)
    ])
  end

  defp pull_rates(_set), do: nil

  # Every card of the set by rarity, at the lower of its Polish shop price
  # and its Cardmarket trend, as the set page lists them.
  defp cards(set) do
    section(
      "Lista kart (#{Polish.plural(set.card_count, "karta", "karty", "kart")})",
      Enum.map(set.rarities, fn %{rarity: rarity, cards: cards} ->
        "### #{rarity || "Bez rzadkości"}\n\n" <> list(Enum.map(cards, &card_line/1))
      end)
    )
  end

  defp card_line(card) do
    name = "#{card.name} #{card.number}"
    title = if card.public_path, do: link(name, url_from_path(card.public_path)), else: name

    case {CardGuide.price(card), CardGuide.price_source(card)} do
      {nil, _source} ->
        title

      {price, {:shop, shop}} ->
        "#{title}: #{Polish.price(price)} w #{GuideComponents.priced_shop_name(%{shop: shop})}"

      {price, :cardmarket} ->
        "#{title}: #{Polish.price(price)} (trend Cardmarket, bez dostawy)"
    end
  end

  defp single_answer(answer) do
    variant = GuideComponents.card_variant_label(answer.variant)

    price =
      if answer.cheapest,
        do:
          "od #{Polish.price(answer.cheapest.price)} w #{GuideComponents.priced_shop_name(answer.cheapest)}",
        else: "brak ofert bez gradingu na stanie"

    reference =
      if answer.reference,
        do: "; Cardmarket z przesyłką: #{Polish.price(answer.reference)}",
        else: ""

    "#{variant}: #{price}#{reference} (#{GuideComponents.single_verdict_label(answer.verdict)})"
  end

  defp card_offers_table([], _today), do: "Żaden sklep nie ma teraz tej karty."

  defp card_offers_table(offers, today) do
    table(
      ["Sklep", "Cena", "Wariant", "Stan / grading", "Dostępność"],
      Enum.map(offers, fn offer ->
        [
          link(offer_shop(offer), offer.url),
          Polish.price(GuideComponents.row_price(offer)),
          GuideComponents.card_variant_label(offer.variant),
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

  defp url_from_path(path), do: unverified_url(TcgCheapWeb.Endpoint, path)
end
