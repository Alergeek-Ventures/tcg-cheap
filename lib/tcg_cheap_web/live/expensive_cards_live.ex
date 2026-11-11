defmodule TcgCheapWeb.ExpensiveCardsLive do
  @moduledoc """
  "Najdroższe karty Pokémon": an article that stays true over time. The
  record sales with their sources and why such cards cost millions are
  edited by hand (`TcgCheapWeb.CardRecords`); what can be bought today
  comes from our data and changes with it: the top cards on Cardmarket,
  the most expensive ones in our shops, each new set's top card, what rises
  and falls, and the full ranking, whose filters scope only the ranking.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.ExpensiveCards
  alias TcgCheapWeb.{CardRecords, Polish, SEO, VisitorLocation}

  @page 30
  # The movers chart's fixed scale: a change past it draws a full bar and
  # still names its own value.
  @movers_scale 0.5
  # 30th Celebration's three secret Mew, the article's story of today's most
  # expensive cards, by TCGdex id.
  @mews ~w(30th-R 30th-G 30th-B)

  @impl true
  def mount(_params, _session, socket) do
    records = CardRecords.all()

    {:ok,
     socket
     |> assign(
       overview: ExpensiveCards.overview(),
       records: records,
       record_cards:
         records
         |> Enum.map(& &1.tcgdex_id)
         |> Enum.reject(&is_nil/1)
         |> ExpensiveCards.cards()
         |> Map.new(&{&1.card.tcgdex_id, &1}),
       mews: ExpensiveCards.cards(@mews),
       sets: ExpensiveCards.sets(),
       filters: nil
     )
     |> stream_configure(:ranking, dom_id: &"ranking-#{&1.card.id}")
     |> VisitorLocation.assign_location()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params, socket.assigns.sets)
    seo = SEO.expensive_cards(socket.assigns.overview, socket.assigns.records, filters)

    socket =
      if filters == socket.assigns.filters,
        do: socket,
        else: show_ranking(socket, filters)

    {:noreply, assign(socket, filters: filters, seo: seo, page_title: seo.page_title)}
  end

  # Other filters start the list again from its first page.
  defp show_ranking(socket, filters) do
    %{total: total, cards: cards} = ExpensiveCards.ranking(filters, 0, @page)

    socket
    |> assign(ranking_total: total, ranking_shown: length(cards))
    |> stream(:ranking, cards, reset: true)
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch(socket,
       to: path(Map.take(params, ["rozszerzenie", "dostepne"])),
       replace: true
     )}
  end

  def handle_event("more", _params, socket) do
    %{filters: filters, ranking_shown: shown} = socket.assigns
    %{total: total, cards: cards} = ExpensiveCards.ranking(filters, shown, @page)

    {:noreply,
     socket
     |> assign(ranking_total: total, ranking_shown: shown + length(cards))
     |> stream(:ranking, cards)}
  end

  def handle_event("location-" <> _ = event, params, socket),
    do: {:noreply, VisitorLocation.handle_event(event, params, socket)}

  defp parse_filters(params, sets) do
    set =
      with "" <> raw <- params["rozszerzenie"],
           {id, ""} <- Integer.parse(raw),
           true <- Enum.any?(sets, &(&1.id == id)) do
        id
      else
        _ -> nil
      end

    %{set: set, stock: if(params["dostepne"] == "1", do: :in, else: :all)}
  end

  # The filters live in the URL, so a filtered ranking can be shared.
  defp path(params) do
    query =
      params
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or (key == "dostepne" and value != "1")
      end)
      |> Map.new()

    if query == %{},
      do: ~p"/najdrozsze-karty-pokemon",
      else: ~p"/najdrozsze-karty-pokemon?#{query}"
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        record: hd(assigns.records),
        english: Enum.find(assigns.records, &(&1.id == "torchic-gold-star")),
        top: List.first(assigns.overview.highlights),
        top_in_stock: List.first(assigns.overview.in_stock),
        newest: List.first(assigns.overview.new_sets),
        movers_scale: @movers_scale,
        page_size: @page
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <SEO.sync seo={@seo} />
      <div class="guide-world">
        <.site_header locale={@locale} return_to={@locale_return_to}>
          <VisitorLocation.location_control
            location={@location}
            ready={@location_ready?}
            form={@town_form}
            matches={@town_matches}
            error={@location_error}
          />
        </.site_header>
        <main id="expensive-cards" class="guide-main expensive-cards">
          <article class="expensive-article">
            <header class="expensive-intro expensive-column">
              <.link id="expensive-cards-back" navigate={~p"/karty"} class="guide-back">
                <.fluent_icon name={:arrow_left} />{gettext("Wszystkie karty")}
              </.link>
              <p class="expensive-kicker">
                {if(@overview.priced_on,
                  do: gettext("Poradnik · ceny z %{date}", date: Polish.date(@overview.priced_on)),
                  else: gettext("Poradnik")
                )}
              </p>
              <h1 id="expensive-cards-title">{gettext("Najdroższe karty Pokémon")}</h1>
              <p id="expensive-cards-lead" class="expensive-lead">
                {gettext(
                  "Najdroższa karta Pokémon w historii kosztowała 16,49 mln dolarów. To Pikachu Illustrator – nagroda z japońskiego konkursu z 1998 roku, której nigdy nie dało się kupić w sklepie. Ale rekordy z aukcji to jedno, a karty, które realnie da się dziś kupić, to drugie. Opowiadamy o jednych i drugich – z cenami, które codziennie aktualizujemy."
                )
                |> glue_short_words()}
              </p>
            </header>

            <section
              class="expensive-stats expensive-wide"
              aria-label={gettext("Najważniejsze liczby")}
            >
              <.stat
                id="stat-record"
                label={gettext("Rekord wszech czasów")}
                to={@record.usd / 1_000_000}
                decimals={2}
                value={CardRecords.usd(@record.usd)}
                caption={@record.name}
                detail={"#{@record.grade} · #{elem(@record.sold, 0)}"}
                {CardRecords.usd_format()}
              />
              <.stat
                id="stat-english"
                label={gettext("Rekord karty po angielsku")}
                to={@english.usd / 1_000_000}
                decimals={1}
                value={CardRecords.usd(@english.usd)}
                caption={@english.name}
                detail={"#{@english.grade} · #{elem(@english.sold, 0)}"}
                {CardRecords.usd_format()}
              />
              <.stat
                :if={@top}
                id="stat-today"
                label={gettext("Najdroższa karta dziś")}
                to={Decimal.to_float(@top.value)}
                decimals={0}
                suffix=" zł"
                value={Polish.zloty(@top.value)}
                caption={"#{@top.card.name} #{@top.card.number}"}
                detail={@top.card.expansion_name}
              />
              <.stat
                :if={@top_in_stock}
                id="stat-shop"
                label={gettext("Najdroższa w polskim sklepie")}
                to={Decimal.to_float(@top_in_stock.offer.price)}
                decimals={0}
                prefix={gettext("od ")}
                suffix=" zł"
                value={gettext("od %{price}", price: Polish.zloty(@top_in_stock.offer.price))}
                caption={@top_in_stock.card.name}
                detail={shop_name(@top_in_stock.offer)}
              />
            </section>

            <nav class="expensive-toc expensive-column" aria-labelledby="expensive-toc-title">
              <h2 id="expensive-toc-title">{gettext("W artykule")}</h2>
              <ol>
                <li :for={item <- toc(assigns)}>
                  <a href={"##{item.id}"} class="expensive-toc-item">
                    <img
                      :if={item.image}
                      src={item.image}
                      alt=""
                      loading="lazy"
                      width="56"
                      height="78"
                    />
                    <span :if={!item.image} class="expensive-toc-icon" aria-hidden="true">
                      {item.icon}
                    </span>
                    <span class="expensive-toc-text">
                      <strong>{item.title}</strong>
                      <span>{item.teaser}</span>
                    </span>
                  </a>
                </li>
              </ol>
            </nav>

            <section id="rekordy" class="expensive-section" aria-labelledby="rekordy-title">
              <div class="expensive-column">
                <h2 id="rekordy-title">{gettext("Najdroższe karty Pokémon w historii")}</h2>
                <p class="expensive-prose">
                  {gettext(
                    "W 2021 roku rekordem było 5,3 mln dolarów za jedną kartę. W 2026 ten sam egzemplarz poszedł za ponad trzy razy więcej, a karty, które kiedyś można było po prostu wyciągnąć z boostera, przekroczyły milion. Każda z tych kart to jeden konkretny egzemplarz: oceniony przez firmę gradingową, zamknięty w plastikowym etui i sprzedany na publicznej aukcji."
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <ol class="expensive-records expensive-wide">
                <li :for={{record, rank} <- Enum.with_index(@records, 1)} id={"rekord-#{record.id}"}>
                  <.slab record={record} card={@record_cards[record.tcgdex_id]} />
                  <div class="expensive-record-body">
                    <p class="expensive-record-rank">
                      <span class="sr-only">{gettext("Miejsce")}</span> {rank}
                    </p>
                    <h3>{record.name}</h3>
                    <p class="expensive-record-detail">{record.detail}</p>
                    <p class="expensive-record-price">
                      <strong>{CardRecords.usd(record.usd)}</strong>
                      <span>
                        {CardRecords.month(record.sold)}, {record.house} ·
                        <a href={record.source} rel="noopener" target="_blank">{gettext("źródło")}</a>
                      </span>
                    </p>
                    <p class="expensive-record-story">{record.story |> glue_short_words()}</p>
                  </div>
                </li>
              </ol>
            </section>

            <section
              id="dlaczego"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="dlaczego-title"
            >
              <h2 id="dlaczego-title">{gettext("Skąd takie ceny")}</h2>
              <p>
                {gettext(
                  "Rekordowe karty łączą trzy rzeczy: jest ich bardzo mało, są w idealnym stanie i przedstawiają Pokémony, które ludzie kochają od dzieciństwa."
                )
                |> glue_short_words()}
              </p>
              <h3>{gettext("Mało egzemplarzy")}</h3>
              <figure class="expensive-aside">
                <img
                  src={~p"/images/records/blastoise-presentation.webp"}
                  alt={gettext("Karta pokazowa Blastoise z 1998 roku")}
                  loading="lazy"
                  width="245"
                  height="342"
                />
                <figcaption>
                  {gettext("Karta pokazowa Blastoise, CGC 8.5: 360 000 $ w 2021 roku.")}
                  <span>
                    {gettext("Zdjęcie:")}
                    <a
                      href="https://www.cgccards.com/news/article/8832/pokemon-blastoise-auction-record/"
                      rel="noopener"
                      target="_blank"
                    >CGC</a>
                  </span>
                </figcaption>
              </figure>
              <p>
                {gettext(
                  "Najdroższe karty często w ogóle nie trafiały do sprzedaży. Pikachu Illustrator i Mudkip z Art Academy były nagrodami w konkursach na ilustrację, trofea Pikachu dostawali zwycięzcy turniejów. W 1998 roku Wizards of the Coast wydrukowało dwie karty pokazowe, żeby pokazać Nintendo, jak gra będzie wyglądać na Zachodzie – jedna z nich, z Blastoise'em, poszła w 2021 roku za 360 000 dolarów. Gdy na świecie jest kilkadziesiąt sztuk, każda aukcja jest wydarzeniem."
                )
                |> glue_short_words()}
              </p>
              <h3>{gettext("Idealny stan")}</h3>
              <p>
                {gettext(
                  "Firmy takie jak PSA i CGC oceniają stan karty w skali od 1 do 10 i zamykają ją w plastikowym etui z etykietą. Dziesiątka zdarza się rzadko i to ona robi różnicę: Torchic ☆ z oceną 10 kosztował 2,7 mln dolarów, a ten sam Torchic z oceną 9 – siedemnaście razy mniej."
                )
                |> glue_short_words()}
              </p>
              <h3>{gettext("Pierwsze wydanie i ulubieńcy")}</h3>
              <p>
                {gettext(
                  "Karty z pierwszego angielskiego wydania z 1999 roku mają po lewej stronie, pod ilustracją, znaczek „Edition 1” i kosztują wielokrotnie więcej niż późniejsze dodruki. A wśród nowych kart najdrożej sprzedają się pełnoobrazkowe wersje ulubionych Pokémonów: Pikachu, Charizarda, Mew czy Umbreona."
                )
                |> glue_short_words()}
              </p>
            </section>

            <section
              :if={@mews != []}
              id="mew"
              class="expensive-section"
              aria-labelledby="mew-title"
            >
              <div class="expensive-column expensive-prose">
                <h2 id="mew-title">{gettext("Trzy Mew, których nie było na liście")}</h2>
                <p>
                  {gettext(
                    "Najdroższe karty, jakie można dziś kupić, pochodzą z 30th Celebration – jubileuszowego rozszerzenia na 30-lecie Pokémonów, które 16 września 2026 roku jako pierwsze w historii wyszło tego samego dnia po japońsku i po angielsku. Na oficjalnej liście kart ich nie było. Trzy sekretne Mew – czerwony, zielony i niebieski, oznaczone literami R, G i B – wypadły z pierwszych paczek, zanim ktokolwiek o nich usłyszał."
                  )
                  |> glue_short_words()}
                </p>
                <p>
                  {gettext(
                    "Kolory to ukłon w stronę pierwszych gier: Pokémon Red, Green i Blue. W nich Mew był ukrytym, 151. Pokémonem, o którym Pokédex mówił, że jest tak rzadki, iż wielu ekspertów uważa go za fatamorganę. Karty okazały się równie nieuchwytne: sklep TCGplayer otworzył przed premierą ponad 3000 paczek i nie trafił ani jednego."
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <ul class="expensive-mews expensive-wide">
                <li :for={row <- @mews} id={"mew-#{row.card.number}"}>
                  <.link
                    navigate={row.card.public_path}
                    class="expensive-mew"
                    data-track="card_clicked"
                    data-track-placement="expensive_mew"
                    data-track-card={row.card.id}
                  >
                    <img
                      :if={row.image_large || row.image}
                      src={row.image_large || row.image}
                      alt={gettext("Mew %{letter} z 30th Celebration", letter: row.card.number)}
                      loading="lazy"
                      width="245"
                      height="342"
                    />
                    <span class="expensive-mew-name">{gettext("Mew %{letter}",
                      letter: row.card.number
                    )}</span>
                    <strong :if={row.value}>{Polish.zloty(row.value)}</strong>
                    <span class={["expensive-stock", !row.offer && "expensive-stock-none"]}>
                      <%= if row.offer do %>
                        {gettext("W sklepach od %{price}", price: Polish.zloty(row.offer.price))}
                      <% else %>
                        {gettext("Brak w polskich sklepach")}
                      <% end %>
                    </span>
                  </.link>
                </li>
              </ul>
              <p class="expensive-note expensive-sources">
                {gettext("Źródła:")}
                <a
                  href="https://www.pokebeach.com/2026/09/30th-celebration-pull-rates-and-most-valuable-cards-worldwide-friendliest-pull-rates-of-the-modern-era"
                  rel="noopener"
                  target="_blank"
                >PokeBeach</a>, <a
                  href="https://www.tcgplayer.com/content/article/Pok%C3%A9mon-TCG-30th-Celebration-Pull-Rates/587b3657-481a-4ab8-827c-68cd3ab585b0"
                  rel="noopener"
                  target="_blank"
                >TCGplayer</a>.
              </p>
            </section>

            <section id="dzis" class="expensive-section" aria-labelledby="dzis-title">
              <div class="expensive-column expensive-prose">
                <h2 id="dzis-title">{gettext("Najdroższe karty Pokémon dziś")}</h2>
                <p :if={@top}>
                  {gettext("Na co dzień karty nie zmieniają właścicieli na aukcjach, tylko na")
                  |> glue_short_words()}&nbsp;<a
                    id="expensive-cardmarket"
                    href="https://www.cardmarket.com/en/Pokemon"
                    target="_blank"
                    rel="noopener nofollow"
                    class="cardmarket-price"
                  ><img src={~p"/images/cardmarket.png"} alt="" width="16" height="16" />Cardmarket</a>
                  {gettext(
                    "– największym w Europie serwisie, na którym kolekcjonerzy kupują i sprzedają pojedyncze karty. Z tamtejszych transakcji bierzemy cenę rynkową karty bez oceny i przeliczamy ją na złote – dla kart od ery Sword & Shield, bo przy starszych w tej cenie mieszają się egzemplarze zniszczone, idealne i ocenione. Dziś najdroższy jest %{card} z %{set}, a ponad 1000 zł kosztuje %{count}.",
                    card: @top.card.name,
                    set: @top.card.expansion_name,
                    count: Polish.plural(@overview.over_1000, "karta", "karty", "kart")
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <ol class="expensive-tiles expensive-wide">
                <li :for={row <- @overview.highlights} id={"dzis-#{row.card.id}"}>
                  <.card_tile row={row} placement="expensive_today" />
                </li>
              </ol>
            </section>

            <section id="w-polsce" class="expensive-section" aria-labelledby="w-polsce-title">
              <div class="expensive-column expensive-prose">
                <h2 id="w-polsce-title">{gettext("Najdroższe karty w polskich sklepach")}</h2>
                <p>
                  {gettext(
                    "Codziennie sprawdzamy oferty kilkudziesięciu sklepów z kartami. %{in_stock} ze %{count} najdroższych kart ma teraz na stanie przynajmniej jeden z nich. Przy każdej karcie mówimy też, czy sklep ją wycenia taniej, podobnie czy drożej, niż kosztowałoby jej sprowadzenie z Cardmarket.",
                    in_stock: @overview.top_in_stock,
                    count: @overview.top_count
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <ol class="expensive-shop-list expensive-wide">
                <li :for={row <- @overview.in_stock} id={"w-polsce-#{row.card.id}"}>
                  <.link
                    navigate={row.card.public_path}
                    class="expensive-shop-row"
                    data-track="card_clicked"
                    data-track-placement="expensive_shops"
                    data-track-card={row.card.id}
                  >
                    <img :if={row.image} src={row.image} alt="" loading="lazy" width="88" height="88" />
                    <span class="expensive-shop-copy">
                      <span class="expensive-shop-name">{row.card.name}</span>
                      <span class="expensive-shop-meta">
                        {row.card.number} · {row.card.expansion_name}
                      </span>
                      <span class="expensive-shop-meta">
                        {gettext("cena rynkowa %{value}", value: Polish.zloty(row.value))}
                      </span>
                    </span>
                    <span class="expensive-shop-deal">
                      <.verdict_badge
                        :if={single_verdict_status(row.verdict) != :insufficient_data}
                        verdict={%{status: single_verdict_status(row.verdict)}}
                        class="expensive-verdict"
                      />
                      <span class="expensive-shop-price">
                        <strong>{Polish.zloty(row.offer.price)}</strong>
                        <span>{priced_shop_name(row.offer)}</span>
                      </span>
                    </span>
                  </.link>
                </li>
              </ol>
            </section>

            <section
              :if={@overview.new_sets != []}
              id="nowe-rozszerzenia"
              class="expensive-section"
              aria-labelledby="nowe-rozszerzenia-title"
            >
              <div class="expensive-column expensive-prose">
                <h2 id="nowe-rozszerzenia-title">
                  {gettext("Najdroższa karta z każdego nowego rozszerzenia")}
                </h2>
                <p :if={@newest}>
                  {gettext(
                    "Co kilka miesięcy wychodzi nowe rozszerzenie, a z nim nowa karta, na którą polują wszyscy. W najnowszym, %{set}, najdroższy jest dziś %{card}.",
                    set: @newest.card.expansion_name,
                    card: @newest.card.name
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <ol class="expensive-tiles expensive-wide">
                <li :for={row <- @overview.new_sets} id={"nowe-#{row.card.id}"}>
                  <.card_tile row={row} placement="expensive_new_sets" set_first?={true} />
                </li>
              </ol>
            </section>

            <section
              :if={@overview.movers.rising != [] or @overview.movers.falling != []}
              id="zmiany"
              class="expensive-section"
              aria-labelledby="zmiany-title"
            >
              <div class="expensive-column expensive-prose">
                <h2 id="zmiany-title">{gettext("Co drożeje, a co tanieje")}</h2>
                <p>
                  {gettext(
                    "Ceny kart potrafią się zmienić w kilka dni: po premierze rozszerzenia, gdy Pokémon staje się modny albo gdy na rynek trafia dodruk. Poniżej karty spośród %{count} najdroższych, których cena w ostatnim tygodniu najbardziej odbiegła od średniej z miesiąca.",
                    count: @overview.top_count
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <div class="expensive-chart expensive-wide">
                <.movers
                  rising={@overview.movers.rising}
                  falling={@overview.movers.falling}
                  scale={@movers_scale}
                />
              </div>
            </section>

            <section id="ranking" class="expensive-section" aria-labelledby="ranking-title">
              <div class="expensive-column expensive-prose">
                <h2 id="ranking-title">{gettext("Pełny ranking najdroższych kart")}</h2>
                <p>
                  {gettext(
                    "500 najdroższych angielskich kart od ery Sword & Shield, od najdroższej. Wybierz rozszerzenie albo pokaż tylko te, które kupisz teraz w polskim sklepie."
                  )
                  |> glue_short_words()}
                </p>
              </div>
              <div class="expensive-column">
                <.ranking
                  rows={@streams.ranking}
                  total={@ranking_total}
                  shown={@ranking_shown}
                  filters={@filters}
                  sets={@sets}
                  page={@page_size}
                />
              </div>
            </section>

            <section
              id="jak-sprawdzic"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="jak-sprawdzic-title"
            >
              <h2 id="jak-sprawdzic-title">{gettext("Jak sprawdzić, ile jest warta twoja karta")}</h2>
              <p>
                {gettext(
                  "Masz w szufladzie stare karty albo właśnie wyciągnąłeś coś błyszczącego? Zanim wystawisz kartę na sprzedaż, sprawdź pięć rzeczy."
                )
                |> glue_short_words()}
              </p>
              <ol class="expensive-steps">
                <li>
                  <strong>{gettext("Numer i rozszerzenie.")}</strong>
                  {gettext(
                    "Numer karty, na przykład 161/131, jest na dole karty, obok symbolu rozszerzenia."
                  )}
                </li>
                <li>
                  <strong>{gettext("Wersja.")}</strong>
                  {gettext(
                    "Zwykła, reverse holo i pierwsze wydanie to osobne karty z osobnymi cenami."
                  )}
                </li>
                <li>
                  <strong>{gettext("Stan.")}</strong>
                  {gettext("Zagięcia, rysy i obite rogi wyraźnie obniżają cenę.")}
                </li>
                <li>
                  <strong>{gettext("Cena.")}</strong>
                  {gettext(
                    "W naszej wyszukiwarce zobaczysz cenę rynkową karty i oferty sklepów, które śledzimy."
                  )}
                  <.link navigate={~p"/karty"}>{gettext("Wyszukaj kartę")}&nbsp;→</.link>
                </li>
                <li>
                  <strong>{gettext("Ocena.")}</strong>
                  {gettext(
                    "Przy kartach wartych tysiące złotych i w bardzo dobrym stanie ocena PSA lub CGC może podnieść cenę. Przy tańszych jej koszt często przewyższa zysk."
                  )
                  |> glue_short_words()}
                </li>
              </ol>
            </section>

            <section
              id="pytania"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="pytania-title"
            >
              <h2 id="pytania-title">{gettext("Najczęstsze pytania")}</h2>
              <dl class="expensive-faq">
                <dt>{gettext("Jaka jest najdroższa karta Pokémon na świecie?")}</dt>
                <dd>
                  {gettext(
                    "Pikachu Illustrator z oceną PSA 10, sprzedany w lutym 2026 roku na aukcji Goldin za 16 492 000 dolarów. To rekord Guinnessa dla wszystkich kart kolekcjonerskich."
                  )
                  |> glue_short_words()}
                </dd>
                <dt>{gettext("Jaka jest najdroższa karta Pokémon po angielsku?")}</dt>
                <dd>
                  {gettext(
                    "Torchic ☆ (Gold Star) z rozszerzenia EX Team Rocket Returns z oceną PSA 10, sprzedany we wrześniu 2026 roku za 2,7 mln dolarów."
                  )
                  |> glue_short_words()}
                </dd>
                <dt :if={@top_in_stock}>
                  {gettext("Ile kosztuje najdroższa karta w polskim sklepie?")}
                </dt>
                <dd :if={@top_in_stock}>
                  {gettext(
                    "Dziś najdroższa karta na stanie w sklepach, które śledzimy, to %{card} (%{number}, %{set}): od %{price} w %{shop}.",
                    card: @top_in_stock.card.name,
                    number: @top_in_stock.card.number,
                    set: @top_in_stock.card.expansion_name,
                    price: Polish.zloty(@top_in_stock.offer.price),
                    shop: priced_shop_name(@top_in_stock.offer)
                  )
                  |> glue_short_words()}
                </dd>
                <dt>{gettext("Czy stare karty Pokémon są coś warte?")}</dt>
                <dd>
                  {gettext(
                    "Niektóre tak, ale wartość zależy od konkretnej karty, wydania i stanu – większość zwykłych kart z lat 90. kosztuje niewiele. Sprawdź numer, wersję i stan, a potem cenę w wyszukiwarce."
                  )
                  |> glue_short_words()}
                </dd>
              </dl>
            </section>

            <section
              id="metoda"
              class="expensive-section expensive-column expensive-method"
              aria-labelledby="metoda-title"
            >
              <h2 id="metoda-title">{gettext("Skąd te liczby")}</h2>
              <ul>
                <li>
                  {gettext(
                    "Rekordy to wyniki publicznych aukcji z prowizją kupującego, potwierdzone przez dom aukcyjny, Księgę rekordów Guinnessa albo duże media. Przy każdej karcie jest link do źródła. Stan na %{date}.",
                    date: Polish.date(CardRecords.checked_on())
                  )}
                </li>
                <li :if={@overview.priced_on && @overview.rate}>
                  {gettext(
                    "Cena rynkowa to trend ceny angielskiej karty bez oceny na Cardmarket z %{date}, przeliczony po kursie NBP %{rate} zł za euro. Aktualizujemy ją codziennie.",
                    date: Polish.date(@overview.priced_on),
                    rate: Polish.rate(@overview.rate.rate)
                  )}
                </li>
                <li>
                  {gettext(
                    "Ceny z dziś podajemy dla kart od ery Sword & Shield (od listopada 2019). Przy starszych kartach trend Cardmarket miesza egzemplarze w różnym stanie i z oceną, więc nie mówi, ile kosztuje karta: zwykły Gengar ze Skyridge miał trend 8549 €, a najtańszy egzemplarz kosztował 325 €."
                  )}
                </li>
                <li>
                  {gettext(
                    "Zmiana porównuje średnią cenę sprzedaży z ostatnich 7 dni ze średnią z 30 dni. Liczymy ją tylko dla 100 najdroższych kart – tańsze sprzedają się rzadko i pojedyncza transakcja za bardzo ją przesuwa."
                  )}
                </li>
                <li>
                  {gettext(
                    "W polskich sklepach podajemy najniższą cenę zwykłej wersji karty bez oceny na stanie, z oceną jak na stronie karty. Bierzemy pod uwagę tylko sklepy z Polski. Pomijamy karty, których nie umiemy jednoznacznie połączyć z ceną na Cardmarket."
                  )}
                </li>
              </ul>
            </section>
          </article>
        </main>
        <.site_footer sets={@footer_sets} />
      </div>
    </Layouts.app>
    """
  end

  # The table of contents as a list of what each section tells, with a card
  # from it where there is one.
  defp toc(assigns) do
    overview = assigns.overview
    image = fn row -> row && Map.get(row, :image) end
    rising = List.first(overview.movers.rising)

    [
      %{
        id: "rekordy",
        title: gettext("Rekordy wszech czasów"),
        teaser: gettext("Od 1,4 do 16,5 mln dolarów za jedną kartę"),
        image: image.(assigns.record_cards["ex7-108"])
      },
      %{
        id: "dlaczego",
        title: gettext("Skąd takie ceny"),
        teaser: gettext("Mało egzemplarzy, idealny stan i ulubieńcy z dzieciństwa"),
        image: image.(assigns.record_cards["base1-4"])
      },
      %{
        id: "mew",
        title: gettext("Trzy Mew z 30th Celebration"),
        teaser: gettext("Sekretne karty, których nie było na liście"),
        image: image.(List.first(assigns.mews))
      },
      assigns.top &&
        %{
          id: "dzis",
          title: gettext("Najdroższe karty dziś"),
          teaser:
            gettext("%{card} za %{value}",
              card: assigns.top.card.name,
              value: Polish.zloty(assigns.top.value)
            ),
          image: image.(Enum.at(overview.highlights, 1))
        },
      assigns.top_in_stock &&
        %{
          id: "w-polsce",
          title: gettext("W polskich sklepach"),
          teaser:
            gettext("%{in_stock} ze %{count} najdroższych kart jest na stanie",
              in_stock: overview.top_in_stock,
              count: overview.top_count
            ),
          image: image.(assigns.top_in_stock)
        },
      assigns.newest &&
        %{
          id: "nowe-rozszerzenia",
          title: gettext("Nowe rozszerzenia"),
          teaser:
            gettext("Najdroższa karta z %{set} i wcześniejszych",
              set: assigns.newest.card.expansion_name
            ),
          image: image.(assigns.newest)
        },
      rising &&
        %{
          id: "zmiany",
          title: gettext("Co drożeje, co tanieje"),
          teaser: gettext("Karty, których cena zmieniła się w ostatnim tygodniu"),
          image: image.(rising)
        },
      %{
        id: "ranking",
        title: gettext("Pełny ranking"),
        teaser: gettext("Najdroższe karty z cenami w polskich sklepach"),
        image: nil,
        icon: "≡"
      },
      %{
        id: "jak-sprawdzic",
        title: gettext("Ile warta jest twoja karta"),
        teaser: gettext("Pięć rzeczy do sprawdzenia, zanim sprzedasz"),
        image: nil,
        icon: "?"
      }
    ]
    |> Enum.filter(& &1)
    |> Enum.map(&Map.put_new(&1, :icon, nil))
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true, doc: "the figure as rendered without JavaScript"
  attr :to, :float, required: true
  attr :decimals, :integer, required: true
  attr :prefix, :string, default: ""
  attr :suffix, :string, default: ""

  attr :locale, :string,
    default: "pl-PL",
    doc: "the count-up's number format; złoty keep Polish grouping in English too"

  attr :caption, :string, required: true
  attr :detail, :string, required: true

  # The figure is in the HTML as it is; the hook only counts up to it once
  # it scrolls into view, and leaves it alone when motion is reduced.
  defp stat(assigns) do
    ~H"""
    <div class="expensive-stat">
      <p class="expensive-stat-label">{@label}</p>
      <p
        id={@id}
        class="expensive-stat-value"
        phx-hook=".CountUp"
        phx-update="ignore"
        data-to={@to}
        data-decimals={@decimals}
        data-prefix={@prefix}
        data-suffix={@suffix}
        data-locale={@locale}
      >
        {@value}
      </p>
      <p class="expensive-stat-caption">{@caption}<span>{@detail}</span></p>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CountUp">
      export default {
        mounted() {
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
          const final = this.el.textContent.trim()
          const to = parseFloat(this.el.dataset.to)
          const decimals = parseInt(this.el.dataset.decimals, 10)
          const { prefix, suffix, locale } = this.el.dataset
          const format = value => prefix + value.toLocaleString(locale, {
            minimumFractionDigits: decimals, maximumFractionDigits: decimals, useGrouping: true
          }).replace(/\s/g, " ") + suffix
          const run = () => {
            const start = performance.now()
            const step = now => {
              const t = Math.min((now - start) / 1200, 1)
              const eased = 1 - Math.pow(1 - t, 3)
              this.el.textContent = t < 1 ? format(to * eased) : final
              if (t < 1) requestAnimationFrame(step)
            }
            requestAnimationFrame(step)
          }
          this.observer = new IntersectionObserver(entries => {
            if (entries.some(entry => entry.isIntersecting)) {
              this.observer.disconnect()
              run()
            }
          })
          this.observer.observe(this.el)
        },
        destroyed() { this.observer?.disconnect() }
      }
    </script>
    """
  end

  attr :record, :map, required: true
  attr :card, :map, default: nil

  # A graded card in its case: the grade on the label, the card under it –
  # our catalogue's picture of its design, or the record's own picture with
  # its source.
  defp slab(assigns) do
    ~H"""
    <figure class="expensive-slab">
      <figcaption class="expensive-slab-label">
        <span>{@record.name}</span>
        <strong>{@record.grade}</strong>
      </figcaption>
      <img
        :if={@card && (@card.image_large || @card.image)}
        src={@card.image_large || @card.image}
        alt={@record.name}
        loading="lazy"
        width="245"
        height="342"
      />
      <img
        :if={!(@card && (@card.image_large || @card.image)) && @record[:image]}
        src={~p"/images/records/#{@record.image}"}
        alt={@record.name}
        loading="lazy"
        width="245"
        height="342"
      />
      <small :if={credit = @record[:image_credit]} class="expensive-slab-credit">
        {gettext("Zdjęcie:")}
        <a href={elem(credit, 1)} rel="noopener" target="_blank">{elem(credit, 0)}</a>
      </small>
    </figure>
    """
  end

  attr :rows, :any, required: true, doc: "the ranking's stream"
  attr :total, :integer, required: true
  attr :shown, :integer, required: true
  attr :filters, :map, required: true
  attr :sets, :list, required: true
  attr :page, :integer, required: true

  # One row per card, as the card list shows one: the card, its Cardmarket
  # price, and what a Polish shop asks with the verdict before it – or that
  # no shop has it. Changes are the article's business above, not the list's.
  defp ranking(assigns) do
    ~H"""
    <form
      id="expensive-filters"
      class="expensive-filters"
      phx-change="filter"
      phx-submit="filter"
      aria-label={gettext("Filtry rankingu")}
    >
      <label class="expensive-filter">
        <span class="sr-only">{gettext("Rozszerzenie")}</span>
        <select id="expensive-filter-set" name="rozszerzenie">
          <option value="">{gettext("Wszystkie rozszerzenia")}</option>
          <option :for={set <- @sets} value={set.id} selected={@filters.set == set.id}>
            {set.name}
          </option>
        </select>
      </label>
      <label class="expensive-toggle">
        <input type="hidden" name="dostepne" value="0" />
        <input
          id="expensive-filter-stock"
          type="checkbox"
          name="dostepne"
          value="1"
          checked={@filters.stock == :in}
        />
        <span><span class="expensive-toggle-check" aria-hidden="true">✓</span>{gettext(
          "Tylko na stanie"
        )}</span>
      </label>
      <p id="expensive-count" class="expensive-count" aria-live="polite">
        {Polish.plural(@total, "karta", "karty", "kart")}
      </p>
    </form>
    <div :if={@total > 0} class="expensive-columns" aria-hidden="true">
      <span>{gettext("Na Cardmarket")}</span>
      <span>{gettext("W sklepie")}</span>
    </div>
    <ol id="expensive-list" class="expensive-list" phx-update="stream">
      <li id="expensive-list-empty" class="guide-empty expensive-list-empty">
        {gettext("Żadna karta nie pasuje do tych filtrów.")}
      </li>
      <li :for={{id, row} <- @rows} id={id}>
        <.link
          navigate={row.card.public_path}
          class="expensive-row"
          data-track="card_clicked"
          data-track-placement="expensive_list"
          data-track-card={row.card.id}
        >
          <span class="expensive-row-rank" aria-hidden="true">{row.place}</span>
          <span class="expensive-row-image">
            <img :if={row.image} src={row.image} alt="" loading="lazy" width="88" height="88" />
          </span>
          <span class="expensive-row-name">
            <span class="expensive-row-place">{row.place}.</span> {row.card.name}
          </span>
          <span class="expensive-row-meta">{row.card.number} · {row.card.expansion_name}</span>
          <span class="expensive-row-market-label">{gettext("Na Cardmarket")}</span>
          <span class="expensive-row-market">{Polish.zloty(row.value)}</span>
          <%= if row.offer do %>
            <span class="expensive-row-verdict">
              <.verdict_badge
                :if={single_verdict_status(row.verdict) != :insufficient_data}
                verdict={%{status: single_verdict_status(row.verdict)}}
              />
            </span>
            <span class="expensive-row-shop">{Polish.price(row.offer.price)}</span>
          <% else %>
            <span class="expensive-row-none">{gettext("Nie ma w polskich sklepach")}</span>
          <% end %>
        </.link>
      </li>
    </ol>
    <div :if={@shown < @total} class="expensive-more-bar">
      <button id="expensive-more" type="button" class="expensive-more" phx-click="more">
        {gettext("Pokaż kolejne %{count}", count: min(@page, @total - @shown))}
      </button>
      <span>
        {gettext("%{shown} z %{total}", shown: @shown, total: Polish.number(@total))}
      </span>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :placement, :string, required: true
  attr :set_first?, :boolean, default: false

  defp card_tile(assigns) do
    ~H"""
    <.link
      navigate={@row.card.public_path}
      class="expensive-tile"
      data-track="card_clicked"
      data-track-placement={@placement}
      data-track-card={@row.card.id}
    >
      <span :if={@set_first?} class="expensive-tile-set">{@row.card.expansion_name}</span>
      <img
        :if={@row.image_large || @row.image}
        src={@row.image_large || @row.image}
        alt={@row.card.name}
        loading="lazy"
        width="245"
        height="342"
      />
      <span class="expensive-tile-name">{@row.card.name}</span>
      <span class="expensive-tile-meta">
        <%= if printings = @row[:printings] do %>
          <%= if length(printings) > 1 do %>
            {gettext("%{count} wersje: %{numbers}",
              count: length(printings),
              numbers: Enum.map_join(printings, ", ", & &1.card.number)
            )}
          <% else %>
            {@row.card.number}
          <% end %>
        <% else %>
          {@row.card.number}
        <% end %>
        <span :if={!@set_first?}>· {@row.card.expansion_name}</span>
      </span>
      <strong class="expensive-tile-value">{tile_value(@row)}</strong>
      <span class={["expensive-stock", !@row.offer && "expensive-stock-none"]}>
        <%= if @row.offer do %>
          {gettext("W sklepach od %{price}", price: Polish.zloty(@row.offer.price))}
        <% else %>
          {gettext("Brak w sklepach")}
        <% end %>
      </span>
    </.link>
    """
  end

  defp tile_value(%{printings: [_, _ | _] = printings}) do
    {low, high} = printings |> Enum.map(& &1.value) |> Enum.min_max_by(&Decimal.to_float/1)
    "#{Polish.zloty(low)} – #{Polish.zloty(high)}"
  end

  defp tile_value(row), do: Polish.zloty(row.value)

  attr :rising, :list, required: true
  attr :falling, :list, required: true
  attr :scale, :float, required: true

  # A diverging bar per card around a zero line on a fixed ±50% scale: rises
  # to the right, falls to the left, the percentage at the bar's end. The side
  # and the sign carry the direction; both draw in ink, as green and red mean
  # a good and a bad price everywhere else on the site.
  defp movers(assigns) do
    ~H"""
    <div class="expensive-movers">
      <div class="expensive-movers-axis" aria-hidden="true">
        <span>{gettext("← tanieje")}</span>
        <span>{gettext("drożeje →")}</span>
      </div>
      <ul>
        <li
          :for={row <- @rising ++ Enum.reverse(@falling)}
          class={if(Decimal.positive?(row.change), do: "is-up", else: "is-down")}
          style={"--size: #{bar_size(row.change, @scale)}"}
        >
          <.link
            navigate={row.card.public_path}
            class="expensive-mover"
            data-track="card_clicked"
            data-track-placement="expensive_movers"
          >
            <span class="expensive-mover-name">
              {row.card.name} <span>{row.card.expansion_name}</span>
            </span>
            <span class="expensive-mover-price">{Polish.zloty(row.value)}</span>
            <span class="expensive-mover-track">
              <span class="expensive-mover-bar" aria-hidden="true"></span>
              <span class="expensive-mover-value">{percent(row.change)}</span>
            </span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp bar_size(change, scale) do
    share = change |> Decimal.abs() |> Decimal.to_float() |> Kernel./(scale) |> min(1.0)
    "#{Float.round(share * 100, 1)}"
  end

  defp percent(change) do
    value = change |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
    sign = if value > 0, do: "+", else: if(value < 0, do: "−", else: "")
    "#{sign}#{abs(value)}%"
  end
end
