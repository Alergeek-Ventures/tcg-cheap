defmodule TcgCheapWeb.CardValueLive do
  @moduledoc """
  "Jak sprawdzić wartość karty Pokémon": a guide for someone holding a card
  and asking what it is worth. A card search right in the guide answers for
  one card; how prices spread over every card in Polish shops, and a card
  for each of a few prices, tell what to expect; the steps say where to look
  on the card and what changes its price, grading included.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{CardGuide, CardValue}
  alias TcgCheapWeb.{Polish, SEO, VisitorLocation}

  # The guide answers with the first few cards; the card list has the rest.
  @shown 5
  # CGC's own price list, for the cheapest grading fee the guide names.
  @cgc_fees "https://www.cgccards.com/submit/services-fees/cgc-grading/"

  @impl true
  def mount(_params, _session, socket) do
    %{spread: spread, examples: examples} = guide = CardValue.guide()
    seo = SEO.card_value(guide)

    {:ok,
     socket
     |> assign(
       spread: spread,
       examples: examples,
       seo: seo,
       page_title: seo.page_title,
       query: "",
       results: [],
       result_count: 0,
       form: to_form(%{"q" => ""})
     )
     |> VisitorLocation.assign_location()}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) when is_binary(query) do
    query = query |> String.trim() |> String.slice(0, 100)

    {results, count} =
      if query == "" do
        {[], 0}
      else
        {rows, _more?, count} = CardGuide.browse(%{query: query, expansion: nil, stock: nil}, 0)
        {Enum.take(rows, @shown), count}
      end

    {:noreply,
     assign(socket,
       query: query,
       results: results,
       result_count: count,
       form: to_form(%{"q" => query})
     )}
  end

  def handle_event("location-" <> _ = event, params, socket),
    do: {:noreply, VisitorLocation.handle_event(event, params, socket)}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, cgc_fees: @cgc_fees)

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
        <main id="card-value" class="guide-main expensive-cards">
          <article class="expensive-article">
            <header class="expensive-intro expensive-column">
              <.link id="card-value-back" navigate={~p"/karty"} class="guide-back">
                <.fluent_icon name={:arrow_left} />{gettext("Wszystkie karty")}
              </.link>
              <p class="expensive-kicker">
                {if(@spread,
                  do: gettext("Poradnik · ceny z %{date}", date: Polish.date(@spread.on)),
                  else: gettext("Poradnik")
                )}
              </p>
              <h1 id="card-value-title">{gettext("Ile jest warta twoja karta Pokémon?")}</h1>
              <p class="expensive-lead">
                {gettext(
                  "Karty z dzieciństwa w szufladzie albo kolekcja po starszym bracie? Zanim je sprzedasz, sprawdź, ile kosztują dziś w polskich sklepach."
                )
                |> glue_short_words()}
              </p>
            </header>

            <section
              id="sprawdz"
              class="value-search expensive-column"
              aria-labelledby="value-search-label"
            >
              <.form
                for={@form}
                id="value-search-form"
                action={~p"/karty"}
                method="get"
                phx-change="search"
                phx-submit="search"
              >
                <label id="value-search-label" for="value-search-query" class="value-search-label">
                  {gettext("Nazwa albo numer z dołu karty")}
                </label>
                <div class="guide-search value-search-box">
                  <div class="guide-search-field">
                    <.fluent_icon name={:search} class="guide-search-icon" />
                    <input
                      type="search"
                      name="q"
                      id="value-search-query"
                      class="guide-search-input"
                      value={@form[:q].value}
                      maxlength="100"
                      autocomplete="off"
                      phx-debounce="300"
                      placeholder={gettext("np. Umbreon albo 161/131")}
                    />
                  </div>
                </div>
              </.form>
              <div id="value-results" aria-live="polite">
                <ul :if={@results != []} id="value-result-list" class="guide-products">
                  <.card_row
                    :for={row <- @results}
                    id={"value-result-#{row.card.id}"}
                    row={row}
                    placement="card_value"
                    verdict?={false}
                  />
                </ul>
                <.link
                  :if={@result_count > length(@results)}
                  id="value-all-results"
                  navigate={~p"/karty?#{[q: @query]}"}
                  class="value-all-results"
                >
                  {gettext("Wszystkie wyniki: %{count}", count: @result_count)}&nbsp;→
                </.link>
                <p :if={@results != []} id="value-results-note" class="value-note">
                  {gettext("To ceny, za które sklepy sprzedają. Sprzedając, dostaniesz mniej –")
                  |> glue_short_words()}
                  <a href="#sprzedaz">{gettext("dlaczego")}</a>.
                </p>
                <p :if={@query != "" and @results == []} id="value-no-results" class="value-note">
                  {gettext(
                    "Nie mamy tej karty – nie sprzedaje jej żaden polski sklep, który śledzimy. To nie znaczy, że nic nie jest warta. Spróbuj angielskiej nazwy, np. Pikachu, albo numeru z dołu karty."
                  )
                  |> glue_short_words()}
                </p>
              </div>
            </section>

            <section
              :if={@spread}
              id="ceny"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="ceny-title"
            >
              <h2 id="ceny-title">{gettext("Ile kosztuje karta Pokémon?")}</h2>
              <p>
                {gettext(
                  "Większość kart jest warta niewiele. Połowa z %{count} kart na stanie w polskich sklepach kosztuje najwyżej %{median}, a 9 na 10 – najwyżej %{ninetieth}.",
                  count: Polish.number(@spread.count),
                  median: Polish.zloty_ceiling(@spread.median),
                  ninetieth: Polish.zloty_ceiling(@spread.ninetieth)
                )
                |> glue_short_words()}
                {if(@spread.over_100 > 0,
                  do:
                    gettext("Ponad 100 zł kosztuje tylko 1 karta na %{count}.",
                      count: round(@spread.count / @spread.over_100)
                    )
                )}
              </p>
              <.spread_chart bins={@spread.bins} total={@spread.count} />

              <h3 :if={@examples != []} id="przyklady">
                {gettext("Co kupisz za złotówkę, a co za tysiąc?")}
              </h3>
              <ul :if={@examples != []} class="expensive-tiles value-examples">
                <li :for={example <- @examples}>
                  <.example_tile price={example.price} row={example.row} />
                </li>
              </ul>
              <p>
                {gettext(
                  "Drogie są karty rzadkie: sekretne, z ilustracją na całą kartę, złote, a ze starych – pierwsze wydania w idealnym stanie. Które karty są najdroższe i dlaczego, opowiadamy w artykule"
                )
                |> glue_short_words()}
                <.link navigate={~p"/najdrozsze-karty-pokemon"}>{gettext("Najdroższe karty Pokémon")}</.link>.
              </p>
            </section>

            <section
              id="krok-po-kroku"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="krok-po-kroku-title"
            >
              <h2 id="krok-po-kroku-title">{gettext("Jak sprawdzić wartość karty krok po kroku")}</h2>
              <ol class="expensive-steps value-steps">
                <li>
                  <strong>{gettext("Znajdź numer.")}</strong>
                  {gettext(
                    "Na dole karty jest numer, na przykład 161/131 – karta 161 z rozszerzenia, które ma 131 kart. Obok jest kod rozszerzenia (PRE to Prismatic Evolutions) i język (EN). Numer większy niż liczba kart oznacza kartę sekretną – zwykle jedną z droższych."
                  )
                  |> glue_short_words()}
                  <div class="value-numbers">
                    <figure class="value-number">
                      <div class="value-number-card">
                        <img
                          src={~p"/images/guides/umbreon-ex-161.webp"}
                          alt={gettext("Karta Umbreon ex z rozszerzenia Prismatic Evolutions")}
                          width="400"
                          height="550"
                          loading="lazy"
                        />
                        <span class="value-number-ring value-number-ring-new" aria-hidden="true"></span>
                      </div>
                      <img
                        class="value-number-zoom"
                        src={~p"/images/guides/umbreon-ex-161-number.webp"}
                        alt={gettext("Powiększony dół karty: kod PRE EN i numer 161/131")}
                        width="222"
                        height="44"
                        loading="lazy"
                      />
                      <figcaption>
                        {gettext("Nowe karty: numer na dole po lewej")}
                      </figcaption>
                    </figure>
                    <figure class="value-number">
                      <div class="value-number-card">
                        <img
                          src={~p"/images/guides/charizard-base-4.webp"}
                          alt={gettext("Karta Charizard z Base Set, pierwsze wydanie z 1999 roku")}
                          width="400"
                          height="550"
                          loading="lazy"
                        />
                        <span class="value-number-ring value-number-ring-old" aria-hidden="true"></span>
                      </div>
                      <img
                        class="value-number-zoom"
                        src={~p"/images/guides/charizard-base-4-number.webp"}
                        alt={gettext("Powiększony dół karty: numer 4/102")}
                        width="222"
                        height="36"
                        loading="lazy"
                      />
                      <figcaption>
                        {gettext("Stare karty: numer na dole po prawej")}
                      </figcaption>
                    </figure>
                  </div>
                </li>
                <li>
                  <strong>{gettext("Sprawdź wersję.")}</strong>
                  {gettext(
                    "Ta sama karta bywa zwykła, reverse holo (błyszczy całe tło poza obrazkiem) albo z pierwszego wydania. Każda wersja ma osobną cenę – oferty każdej z nich zobaczysz na stronie karty."
                  )
                  |> glue_short_words()}
                  <figure class="value-stamp">
                    <img
                      src={~p"/images/guides/charizard-base-4-edition.webp"}
                      alt={gettext("Znaczek „Edition 1”")}
                      width="76"
                      height="76"
                      loading="lazy"
                    />
                    <figcaption>
                      {gettext(
                        "Znaczek pierwszego wydania na Charizardzie z 1999 roku: po lewej stronie, pod obrazkiem."
                      )
                      |> glue_short_words()}
                    </figcaption>
                  </figure>
                </li>
                <li>
                  <strong>{gettext("Oceń stan.")}</strong>
                  {gettext(
                    "Ceny w sklepach są zwykle za karty bez śladów gry. Zagięcia, rysy i obite rogi wyraźnie obniżają cenę."
                  )
                  |> glue_short_words()}
                </li>
                <li>
                  <strong>{gettext("Sprawdź cenę.")}</strong>
                  {gettext(
                    "Wpisz kartę w wyszukiwarkę wyżej. Pokażemy, za ile sprzedają ją polskie sklepy, a na stronie karty także jej cenę na Cardmarket. Podajemy ceny kart angielskich – japońska czy niemiecka wersja kosztuje inaczej."
                  )
                  |> glue_short_words()}
                </li>
                <li>
                  <strong>{gettext("Przy drogich kartach – ocena.")}</strong>
                  {gettext(
                    "Kartę wartą setki złotych i w idealnym stanie warto czasem oddać do oceny."
                  )
                  |> glue_short_words()}
                  <a href="#czy-warto">{gettext("Kiedy to się opłaca")}&nbsp;→</a>
                </li>
              </ol>
            </section>

            <section
              id="grading"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="grading-title"
            >
              <h2 id="grading-title">{gettext("Ocena, czyli grading")}</h2>
              <p>
                {gettext(
                  "Przy drogiej karcie liczy się nie tylko stan, ale też to, kto go potwierdził. Firma gradingowa ogląda kartę pod lupą, wystawia ocenę od 1 do 10 i zamyka ją w plastikowym etui z etykietą – kolekcjonerzy mówią na nie slab. Najbardziej znane są PSA, CGC i Beckett."
                )
                |> glue_short_words()}
              </p>
              <p>
                {gettext(
                  "Na etykiecie jest nazwa karty, ocena i numer, po którym sprawdzisz kartę na stronie firmy. Najwyższa ocena to 10 – niektóre firmy dodają do niej słowo, na przykład Pristine albo Gem Mint."
                )
                |> glue_short_words()}
              </p>
              <ul class="value-slab-photos">
                <li :for={photo <- slab_photos()}>
                  <figure>
                    <img
                      src={~p"/images/grading/#{photo.file}"}
                      alt={photo.alt}
                      width={photo.width}
                      height={photo.height}
                      loading="lazy"
                    />
                    <figcaption>
                      <strong>{photo.grade}</strong>
                      <span>{photo.card}</span>
                      <span>
                        {gettext("Zdjęcie:")}
                        <a href={photo.source} rel="noopener" target="_blank">{photo.company}</a>
                      </span>
                    </figcaption>
                  </figure>
                </li>
              </ul>
              <h3 id="firmy-gradingowe">{gettext("Firmy, które oceniają karty Pokémon")}</h3>
              <dl class="value-graders">
                <div :for={{country, graders} <- graders()}>
                  <dt>{country}</dt>
                  <dd>
                    <a
                      :for={grader <- graders}
                      href={grader.site}
                      rel="noopener nofollow"
                      target="_blank"
                      class="value-grader"
                    >
                      <img
                        src={~p"/images/grading/#{grader.logo}"}
                        class={(grader[:emblem?] || grader[:tall?]) && "value-grader-emblem"}
                        alt={grader.name}
                        width={grader.width}
                        height={grader.height}
                        loading="lazy"
                      />
                      <%!-- An emblem alone does not say whose it is. --%>
                      <span :if={grader[:emblem?]} aria-hidden="true">{grader.name}</span>
                    </a>
                  </dd>
                </div>
              </dl>

              <h3 id="czy-warto">{gettext("Czy warto oceniać kartę?")}</h3>
              <p>
                {gettext(
                  "Jeden punkt oceny potrafi zmienić cenę kilkunastokrotnie – widać to na rekordach z aukcji, które opisujemy w artykule"
                )
                |> glue_short_words()}
                <.link navigate={~p"/najdrozsze-karty-pokemon#rekordy"}>{gettext("Najdroższe karty Pokémon")}</.link>. {gettext(
                  "Ale to wyjątki: ocena kosztuje, a dziesiątki nikt nie gwarantuje."
                )
                |> glue_short_words()}
              </p>
              <div class="value-worth">
                <div>
                  <p class="value-worth-title">{gettext("Warto, gdy")}</p>
                  <ul>
                    <li>{gettext("karta kosztuje setki albo tysiące złotych,")}</li>
                    <li>
                      {gettext(
                        "jest w idealnym stanie: bez rys, zagięć i obitych rogów, z równymi marginesami,"
                      )
                      |> glue_short_words()}
                    </li>
                    <li>
                      {gettext("chcesz ją sprzedać – kupujący płacą więcej za sprawdzony stan.")
                      |> glue_short_words()}
                    </li>
                  </ul>
                </div>
                <div>
                  <p class="value-worth-title">{gettext("Nie warto, gdy")}</p>
                  <ul>
                    <li>
                      {gettext(
                        "karta kosztuje kilka albo kilkadziesiąt złotych – sama ocena kosztuje więcej,"
                      )
                      |> glue_short_words()}
                    </li>
                    <li>
                      {gettext("ma ślady gry – niska ocena nie podniesie ceny,")
                      |> glue_short_words()}
                    </li>
                    <li>
                      {gettext("chcesz nią grać – ze slabu nie wyjmiesz jej bez rozbicia etui.")
                      |> glue_short_words()}
                    </li>
                  </ul>
                </div>
              </div>
              <p>
                {gettext("Ile to kosztuje:")}
                <a href={@cgc_fees} rel="noopener nofollow" target="_blank">
                  {gettext(
                    "w CGC najtaniej 17 dolarów za kartę przy 25 kartach naraz albo 20 dolarów za jedną"
                  )}
                </a>
                {gettext(
                  "(cennik z listopada 2026). Do tego wysyłka w obie strony i miesiące czekania: na najtańszą ocenę CGC podaje około 150 dni roboczych."
                )
                |> glue_short_words()}
              </p>
            </section>

            <section
              id="sprzedaz"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="sprzedaz-title"
            >
              <h2 id="sprzedaz-title">{gettext("Za ile sprzedasz kartę?")}</h2>
              <p>
                {gettext(
                  "Cena w sklepie to nie to, co dostaniesz do ręki. Sklep, który skupuje karty, zapłaci mniej, bo musi na nich jeszcze zarobić. Na Cardmarket dostaniesz więcej, ale zapłacisz prowizję i sam wyślesz kartę."
                )
                |> glue_short_words()}
              </p>
            </section>

            <section
              id="stare-karty"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="stare-karty-title"
            >
              <h2 id="stare-karty-title">{gettext("Czy stare karty Pokémon są coś warte?")}</h2>
              <p>
                {gettext(
                  "Niektóre tak. Najrzadsze karty z lat 90. w idealnym stanie sprzedają się na aukcjach za tysiące dolarów –"
                )
                |> glue_short_words()}
                <.link navigate={~p"/najdrozsze-karty-pokemon#rekordy"}>{gettext("rekordy opisujemy tutaj")}</.link>. {gettext(
                  "Zwykłe, zagrane karty z tamtych lat zwykle kosztują niewiele. Ceny starych kart mocno zależą od stanu, więc traktuj je jako orientacyjne."
                )
                |> glue_short_words()}
              </p>
            </section>

            <section
              :if={@spread}
              id="metoda"
              class="expensive-section expensive-column expensive-method"
              aria-labelledby="metoda-title"
            >
              <h2 id="metoda-title">{gettext("Skąd te liczby")}</h2>
              <ul>
                <li>
                  {gettext(
                    "Liczymy angielskie karty bez oceny, które co najmniej jeden polski sklep ma dziś na stanie. Każda karta liczy się raz, z ceną najtańszej oferty w polskim sklepie. Sklepy z zagranicy pomijamy, bo ich ceny zawierają wysyłkę."
                  )}
                </li>
                <li>
                  {gettext(
                    "Przykłady to karty, które polskie sklepy sprzedają za mniej więcej tyle, ile kosztują na Cardmarket, więc ich cena jest typowa."
                  )}
                </li>
                <li>
                  {gettext(
                    "W wyszukiwarce przy karcie na stanie pokazujemy najtańszą ofertę, najpierw zwykłej wersji. Przy karcie, której sklepy nie mają na stanie, pokazujemy cenę z Cardmarket."
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

  attr :bins, :list, required: true
  attr :total, :integer, required: true

  # The spread as a histogram: one column per price range, its height the
  # share of cards in it. Each column says its count, range and share on
  # hover and focus; the tallest also says its share on top.
  defp spread_chart(assigns) do
    tallest = assigns.bins |> Enum.map(& &1.count) |> Enum.max()
    assigns = assign(assigns, tallest: max(tallest, 1))

    ~H"""
    <figure class="value-chart" aria-labelledby="value-chart-title">
      <figcaption id="value-chart-title" class="value-chart-title">
        {gettext("Karty na stanie w polskich sklepach według ceny")}
      </figcaption>
      <ol class="value-chart-bins">
        <li
          :for={bin <- @bins}
          class="value-chart-bin"
          tabindex="0"
          style={"--share: #{Float.round(bin.count / @tallest, 4)}"}
        >
          <span class="value-chart-bar"></span>
          <span :if={bin.count == @tallest} class="value-chart-cap" aria-hidden="true">
            {percent(bin.count, @total)}
          </span>
          <span class="value-chart-tip">
            <strong>{Polish.plural(bin.count, "karta", "karty", "kart")}</strong>
            <span>{range_label(bin)}</span>
            <span>{gettext("%{percent} wszystkich", percent: percent(bin.count, @total))}</span>
          </span>
        </li>
      </ol>
      <ol class="value-chart-axis" aria-hidden="true">
        <li :for={bin <- @bins}>{bin.from}</li>
      </ol>
      <p class="value-chart-unit" aria-hidden="true">{gettext("cena w złotych")}</p>
    </figure>
    """
  end

  defp range_label(%{from: 0, to: to}), do: gettext("poniżej %{price}", price: Polish.zloty(to))
  defp range_label(%{from: from, to: nil}), do: gettext("od %{price}", price: Polish.zloty(from))

  defp range_label(%{from: from, to: to}),
    do: gettext("od %{from} do %{to}", from: Polish.number(from), to: Polish.zloty(to))

  defp percent(0, _total), do: "0%"

  defp percent(count, total) do
    case round(count * 100 / total) do
      0 -> "<1%"
      share -> "#{share}%"
    end
  end

  attr :price, :integer, required: true
  attr :row, :map, required: true

  # The article's card tile, headed by the price it is an example of and
  # answering with the shop's price.
  defp example_tile(assigns) do
    ~H"""
    <.link
      navigate={@row.card.public_path}
      class="expensive-tile"
      data-track="card_clicked"
      data-track-placement="card_value_example"
      data-track-card={@row.card.id}
    >
      <span class="value-example-label">{example_label(@price)}</span>
      <%!-- The name follows, so the picture adds nothing for a screen reader. --%>
      <img src={@row.image_large || @row.image} alt="" loading="lazy" width="245" height="342" />
      <span class="expensive-tile-name">{@row.card.name}</span>
      <span class="expensive-tile-meta">
        {[@row.card.rarity, "#{@row.card.number} · #{@row.card.expansion_name}"]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")}
      </span>
      <strong class="expensive-tile-value">{Polish.price(@row.offer.price)}</strong>
      <span class="expensive-stock">{shop_name(@row.offer)}</span>
    </.link>
    """
  end

  # Grading companies a collector in Poland meets, by the country of their
  # headquarters as their own sites name it; we found no Polish one, Polish shops
  # send cards to these. Logos from their sites, at their aspect; square
  # ones stand taller to look as big, and ACE's, an emblem only, is named
  # beside it.
  defp graders do
    [
      {gettext("USA"),
       [
         %{
           name: "PSA",
           site: "https://www.psacard.com/",
           logo: "psa-logo.svg",
           width: 80,
           height: 30
         },
         %{
           name: "CGC",
           site: "https://www.cgccards.com/",
           logo: "cgc-logo.svg",
           width: 245,
           height: 53
         },
         %{
           name: "Beckett",
           site: "https://www.beckett.com/grading",
           logo: "beckett-logo.svg",
           width: 160,
           height: 31
         },
         %{
           name: "TAG",
           site: "https://taggrading.com/",
           logo: "tag-logo.webp",
           width: 320,
           height: 118
         },
         %{name: "SGC", site: "https://gosgc.com/", logo: "sgc-logo.svg", width: 508, height: 202}
       ]},
      {gettext("Wielka Brytania"),
       [
         %{
           name: "ACE",
           site: "https://acegrading.com/",
           logo: "ace-logo.svg",
           width: 340,
           height: 340,
           emblem?: true
         },
         %{
           name: "MGC",
           site: "https://www.majestygrading.com/",
           logo: "mgc-logo.webp",
           width: 172,
           height: 240,
           tall?: true
         }
       ]},
      {gettext("Francja"),
       [
         %{
           name: "PCA",
           site: "https://pcagrade.com/",
           logo: "pca-logo.webp",
           width: 320,
           height: 107
         }
       ]},
      {gettext("Niemcy"),
       [
         %{
           name: "AP Grading",
           site: "https://www.apgrading.net/",
           logo: "ap-grading-logo.svg",
           width: 400,
           height: 128
         }
       ]}
    ]
  end

  # Pokémon cards in slabs, from the graders' own sites, credited and linked
  # as the article credits its pictures: no freely licensed photo exists.
  defp slab_photos do
    [
      %{
        file: "beckett-slab-charizard.webp",
        width: 400,
        height: 628,
        company: "Beckett",
        source: "https://www.beckett.com/grading",
        grade: "Beckett 10 Pristine",
        card: gettext("Charizard, japońska edycja 25th Anniversary"),
        alt: gettext("Karta Charizard w slabie Beckett z czarną etykietą i oceną 10")
      },
      %{
        file: "cgc-slab-charizard.webp",
        width: 330,
        height: 558,
        company: "CGC",
        source:
          "https://www.cgcgrading.com/news/articles/shadowless-charizard-earns-a-coveted-cgc-pristine-10-grade-7x3rkrADYweW8xuMWjvb9h",
        grade: "CGC Pristine 10",
        card: gettext("Charizard z Base Set, wersja Shadowless"),
        alt: gettext("Karta Charizard z Base Set w slabie CGC z oceną Pristine 10")
      },
      %{
        file: "tag-slab-charizard-vmax.webp",
        width: 400,
        height: 548,
        company: "TAG",
        source: "https://taggrading.com/",
        grade: "TAG 10 Gem Mint",
        card: gettext("Charizard VMAX z Champion's Path"),
        alt: gettext("Karta Charizard VMAX w slabie TAG z oceną 10")
      },
      %{
        file: "ace-slab-bulbasaur.webp",
        width: 400,
        height: 671,
        company: "ACE",
        source: "https://acegrading.com/",
        grade: "ACE 10 Gem Mint",
        card: gettext("Bulbasaur z japońskiego 151"),
        alt: gettext("Karta Bulbasaur w slabie ACE z oceną 10")
      }
    ]
  end

  defp example_label(1), do: gettext("Za złotówkę")
  defp example_label(10), do: gettext("Za dychę")
  defp example_label(100), do: gettext("Za stówę")
  defp example_label(1000), do: gettext("Za tysiąc")
end
