defmodule TcgCheapWeb.PageMarkdown do
  @moduledoc """
  The guide's pages as markdown for AI agents (`TcgCheapWeb.MarkdownController`),
  built from the same read models and sentences as their HTML: the page's
  answer first, then the facts and offers behind it. Links point to the HTML
  pages, which stay canonical.
  """

  use TcgCheapWeb, :verified_routes

  alias TcgCheap.Sealed.{CardGuide, Kinds, PriceGuide, Rarities, Regions, Shops}
  alias TcgCheapWeb.{GuideComponents, Polish, SEO}

  @doc "The markdown version's URL of a page's canonical URL."
  @spec url_for(String.t()) :: String.t()
  def url_for(canonical) do
    if String.ends_with?(canonical, "/"), do: canonical <> "index.md", else: canonical <> ".md"
  end

  @doc "How the guide rates a price, for the home page and llms.txt."
  @spec method() :: [String.t()]
  def method do
    [
      "Ceny pochodzą z publicznych feedów produktowych polskich sklepów, pobieranych raz dziennie, i nie obejmują dostawy.",
      "Typowa cena to mediana najniższych cen na stanie w polskich sklepach (jedna cena na sklep, co najmniej #{PriceGuide.min_shops()} sklepy).",
      "Dobra cena to najwyżej 95% typowej, normalna najwyżej 110%, powyżej jest drogo. Dobra cena musi też być najwyżej 95% zwykłej ceny produktu z ostatnich #{PriceGuide.window_days()} dni i trendu Cardmarket w złotych z przesyłką z Niemiec, gdy są znane.",
      "Przy mniejszej liczbie sklepów nie ma oceny, a jako kontekst podajemy trend Cardmarket w złotych.",
      "Ocena nigdy nie opiera się na cenie sugerowanej producenta. Brakujące dane pokazujemy jako brakujące."
    ]
  end

  def home(seo, summaries, today) do
    page(seo, today, [
      section("Jak oceniamy cenę", list(method())),
      section(
        "Produkty",
        [
          "Najpierw produkty na stanie w polskich sklepach, potem najnowsze; angielskie wydania. Pełna lista rozszerzeń: #{url(~p"/llms.txt")}",
          products_table(summaries)
        ]
      )
    ])
  end

  def product(seo, page) do
    product = page.product

    page(seo, page.today, [
      section("Werdykt", list(verdict_facts(page))),
      section("Produkt", list(product_facts(product))),
      section("Oferty w polskich sklepach", offers_table(page.offers, page.today)),
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
      section("Oferty w polskich sklepach", card_offers_table(page.offers, today))
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
        "Najtańsza oferta#{if page.preorder?, do: " (przedsprzedaż)", else: ""}: #{Polish.price(verdict.cheapest.price)} w #{GuideComponents.shop_name(verdict.cheapest)}",
      verdict.typical_source == :shops &&
        "Typowa cena w polskich sklepach: #{Polish.zloty(verdict.typical)} (mediana z #{length(verdict.shop_prices)} sklepów)",
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

  defp offers_table([], _today), do: "Żaden polski sklep nie ma teraz tej oferty."

  defp offers_table(offers, today) do
    table(
      ["Sklep", "Cena", "Dostępność"],
      Enum.map(offers, fn offer ->
        [
          link(GuideComponents.shop_name(offer), offer.url),
          Polish.price(offer.price),
          availability(offer, today)
        ]
      end)
    )
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
    offer = "#{Polish.price(cheapest.price)} w #{GuideComponents.shop_name(cheapest)}"

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
        "#{title}: #{Polish.price(price)} w #{Shops.name(shop)}"

      {price, :cardmarket} ->
        "#{title}: #{Polish.price(price)} (trend Cardmarket, bez dostawy)"
    end
  end

  defp single_answer(answer) do
    variant = GuideComponents.card_variant_label(answer.variant)

    price =
      if answer.cheapest,
        do:
          "od #{Polish.price(answer.cheapest.price)} w #{GuideComponents.shop_name(answer.cheapest)}",
        else: "brak ofert bez gradingu na stanie"

    reference =
      if answer.reference,
        do: "; Cardmarket z przesyłką: #{Polish.price(answer.reference)}",
        else: ""

    "#{variant}: #{price}#{reference} (#{GuideComponents.single_verdict_label(answer.verdict)})"
  end

  defp card_offers_table([], _today), do: "Żaden polski sklep nie ma teraz tej karty."

  defp card_offers_table(offers, today) do
    table(
      ["Sklep", "Cena", "Wariant", "Stan / grading", "Dostępność"],
      Enum.map(offers, fn offer ->
        [
          link(GuideComponents.shop_name(offer), offer.url),
          Polish.price(offer.price),
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
