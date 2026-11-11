defmodule TcgCheapWeb.BoosterPriceLive do
  @moduledoc """
  "Ile kosztuje booster Pokémon?": a buying guide in the articles' layout.

  What is true for every set (how sets come out, what each kind of box is,
  when to buy it) is plain prose; today's numbers from the newest set (its
  boxes, what they cost over their boosters, what the cards in them are
  worth) sit in cream "today" cards headed by that set. Order: the short
  answer and the better question (what do you want?) with four ways in by
  purpose, the newest set's boxes, how sets come out with each recent set's
  booster today, what a box costs over its boosters, each kind of box
  grouped by purpose, three rules, whether some boxes hit more often, the
  retail chains' deals and the method.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{BoosterGuide, CardImage}
  alias TcgCheapWeb.{Polish, SEO, VisitorLocation}

  @impl true
  def mount(_params, _session, socket) do
    page = BoosterGuide.guide()
    seo = SEO.booster_prices(page)

    {:ok,
     socket
     |> assign(page: page, seo: seo, page_title: seo.page_title)
     |> VisitorLocation.assign_location()}
  end

  @impl true
  def handle_event("location-" <> _ = event, params, socket),
    do: {:noreply, VisitorLocation.handle_event(event, params, socket)}

  @impl true
  def render(assigns) do
    page = assigns.page
    latest = page.latest
    set = latest && latest.set
    boxes = if latest, do: latest.products, else: []
    entries = entries(page)
    examples = Enum.flat_map(entries, &List.wrap(&1.box))
    shelf = shelf(boxes)

    assigns =
      assign(assigns,
        set: set,
        logos: Map.new(page.sets, &{&1.name, &1.logo}),
        latest_booster: Enum.find(boxes, &(&1.product.name == &1.product.set_name <> " Booster")),
        shelf: shelf,
        intents: intents(page, shelf),
        compared:
          shelf
          |> Enum.map(&elem(&1, 0))
          |> Enum.filter(& &1.extra)
          |> Enum.sort_by(&(-ratio(&1.extra, &1.price))),
        groups: groups(entries),
        fallback:
          examples
          |> Enum.map(& &1.product.set_name)
          |> Enum.reject(&(&1 == set))
          |> Enum.uniq(),
        special: Enum.reject(page.sets, & &1.booster_box?)
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
        <main id="booster-prices" class="guide-main expensive-cards">
          <article class="expensive-article">
            <header class="expensive-intro expensive-column">
              <.link id="booster-prices-back" data-guide-back navigate={~p"/"} class="guide-back">
                <.fluent_icon name={:arrow_left} />{gettext("Wszystkie produkty")}
              </.link>
              <p class="expensive-kicker">
                {gettext("Poradnik · ceny z %{date}", date: Polish.date(@page.today))}
              </p>
              <h1 id="booster-prices-title">{gettext("Ile kosztuje booster Pokémon?")}</h1>
              <p id="booster-prices-answer" class="expensive-lead">
                <%= if @latest_booster do %>
                  {lead(@latest_booster)}
                <% else %>
                  {Enum.join(SEO.booster_answer(@page), " ")}
                <% end %>
              </p>
              <p class="expensive-lead">{better_question(@page)}</p>
            </header>

            <nav class="expensive-toc expensive-column" aria-labelledby="po-co-title">
              <h2 id="po-co-title">{gettext("Najpierw: czego chcesz?")}</h2>
              <ol>
                <li :for={intent <- @intents}>
                  <a href={intent.href} class="expensive-toc-item boosters-intent">
                    <img :if={intent.image} src={intent.image} alt="" loading="lazy" />
                    <span class="expensive-toc-text">
                      <strong>{intent.title}</strong>
                      <span>{intent.teaser}</span>
                    </span>
                  </a>
                </li>
              </ol>
            </nav>

            <section
              :if={@shelf != []}
              id="w-sklepach"
              class="expensive-section expensive-wide boosters-today"
              aria-labelledby="w-sklepach-title"
            >
              <.today_head
                id="w-sklepach-title"
                title={gettext("%{set} w sklepach", set: @set)}
                logo={@logos[@set]}
                date={@page.today}
              />
              <ul class="boosters-shelf">
                <li :for={{box, entry} <- @shelf}>
                  <a href={"#produkt-#{entry.id}"} class="boosters-shelf-item">
                    <.product_image
                      small_photo={box.product.stored_photo_small_url}
                      photo={box.product.stored_photo_card_url}
                      blur={box.product.photo_placeholder}
                      kind={box.product.kind}
                      sizes="(max-width: 42rem) 40vw, 9rem"
                      alt=""
                      class="boosters-shelf-image"
                    />
                    <span class="boosters-shelf-name">{entry.short}</span>
                    <strong>{shelf_price(box)}</strong>
                  </a>
                </li>
              </ul>
            </section>

            <section
              id="premiery"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="premiery-title"
            >
              <h2 id="premiery-title">{gettext("Jak wychodzą nowe sety")}</h2>
              <p>
                {gettext(
                  "Nowy angielski set wychodzi mniej więcej co dwa miesiące. Najpierw są turnieje przedpremierowe, czyli prerelease: do dwóch tygodni przed premierą sklepy z oficjalnego programu Play! Pokémon sprzedają na nie Build & Battle Box, a gracze grają talią z tego pudełka. W dniu premiery w sklepach pojawia się reszta: pojedyncze boostery, blistry, Booster Bundle, Elite Trainer Box i Booster Box. Puszki i kolekcje dochodzą później, czasem z boosterami kilku setów."
                )
                |> glue_short_words()}
              </p>
              <p>
                {gettext(
                  "Co kilka setów wychodzi set specjalny. Nie ma Booster Boxa, więc jego boostery kupisz w ETB, Booster Bundle, blistrach, puszkach i kolekcjach, a puszek i kolekcji wychodzi wtedy dużo więcej."
                )
                |> glue_short_words()}
              </p>
              <div :if={@page.sets != []} class="boosters-today">
                <.today_head
                  id="sets-title"
                  title={
                    gettext("%{count} ostatnich setów: najtańszy booster dziś",
                      count: length(@page.sets)
                    )
                  }
                  date={@page.today}
                />
                <p :if={@special != []} class="boosters-today-text">
                  {special_sets(@special, @page.sets, @page.today)}
                </p>
                <.set_timeline sets={@page.sets} />
              </div>
            </section>

            <section
              :if={@compared != [] and @latest_booster}
              id="doplata"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="doplata-title"
            >
              <h2 id="doplata-title">{gettext("Za co dopłacasz w pudełku")}</h2>
              <p>
                {gettext(
                  "W pudełkach jednego setu są te same boostery, które kupisz osobno. Reszta ceny to dopłata za dodatki: kartę promo, akcesoria, talię albo samo opakowanie."
                )
                |> glue_short_words()}
              </p>
              <div class="boosters-today">
                <.today_head
                  id="doplata-chart-title"
                  title={gettext("Dziś w %{set}", set: @set)}
                  logo={@logos[@set]}
                  date={@page.today}
                />
                <p class="boosters-today-text">
                  {gettext(
                    "Pojedynczy booster kosztuje tu %{single}. Ciemna część paska to boostery z pudełka po tej cenie, pomarańczowa to dopłata.",
                    single: shelf_price(@latest_booster)
                  )
                  |> glue_short_words()}
                </p>
                <.extras_chart boxes={@compared} />
              </div>
            </section>

            <section
              id="produkty"
              class="expensive-section expensive-column"
              aria-labelledby="produkty-title"
            >
              <div class="expensive-prose">
                <h2 id="produkty-title">{gettext("Co jest w każdym pudełku")}</h2>
                <p>
                  {gettext(
                    "Każdy set wychodzi w podobnych pudełkach, więc opisy pasują do każdego setu."
                  )}
                  {products_today(@set, @fallback)}
                </p>
              </div>
              <div :for={{id, label, group} <- @groups} id={"grupa-#{id}"} class="boosters-group">
                <p class="boosters-group-label">{label}</p>
                <.entry
                  :for={entry <- group}
                  entry={entry}
                  logos={@logos}
                  today={@page.today}
                  sets={@page.sets}
                />
              </div>
            </section>

            <section
              id="zasady"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="zasady-title"
            >
              <h2 id="zasady-title">{gettext("Zanim kupisz")}</h2>
              <.rules page={@page} set={@set} />
            </section>

            <section
              id="szanse"
              class="expensive-section expensive-column expensive-prose"
              aria-labelledby="szanse-title"
            >
              <h2 id="szanse-title">{gettext("Czy w którymś pudełku łatwiej o rzadką kartę?")}</h2>
              <p>
                {gettext(
                  "Wydawca nie podaje, jak często trafiają się rzadkie karty, ani jak układa boostery w kartonach. Szanse na stronach boosterów to szacunki fanów, policzone z otwartych paczek. Część kolekcjonerów uważa, że w Booster Boxie liczba rzadkich kart jest z góry ustalona, więc boostery pakowane osobno, na przykład w blistrach, mają inne szanse. Nikt tego nie potwierdził danymi, więc traktuj to jako opinię, nie regułę."
                )
                |> glue_short_words()}
              </p>
            </section>

            <div :if={@page.retail_deals != []} class="expensive-column">
              <.retail_deals
                id="booster-prices-retail-deals"
                title={gettext("Okazje w sieciówkach")}
                deals={@page.retail_deals}
                products?
              />
            </div>

            <section
              id="metoda"
              class="expensive-section expensive-column expensive-method"
              aria-labelledby="metoda-title"
            >
              <h2 id="metoda-title">{gettext("Skąd te liczby")}</h2>
              <ul>
                <li>
                  {gettext(
                    "Ceny to ceny na stanie w sklepach internetowych, bez dostawy; sklepy z zagranicy z wysyłką do Polski. Aktualizujemy je codziennie."
                  )}
                </li>
                <li>
                  {gettext(
                    "Cena pudełka to jego typowa cena: mediana najniższych cen w sklepach, które je mają. Porównujemy ją z typową ceną boostera z tego samego setu. Gdy pudełko ma mniej niż trzy sklepy, porównujemy najniższą cenę pudełka z najniższą ceną boostera."
                  )}
                </li>
                <li>
                  {gettext(
                    "Wartość kart z pudełek to średnia cena sprzedaży z Cardmarketu (trend) w złotych. Zawartość pudełek sprawdzamy na stronach wydawcy i sklepów; przy każdym produkcie są źródła."
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

  # The short answer: the newest set's booster today, its typical price
  # only when enough shops have it and it differs from the cheapest.
  defp lead(booster) do
    low = booster.verdict.cheapest.price

    if booster.few_shops? or
         Decimal.equal?(Decimal.round(low, 0), Decimal.round(booster.price, 0)),
       do:
         gettext("Krótka odpowiedź: booster najnowszego setu, %{set}, kosztuje dziś od %{low}.",
           set: booster.product.set_name,
           low: amount(low)
         )
         |> glue_short_words(),
       else:
         gettext(
           "Krótka odpowiedź: booster najnowszego setu, %{set}, kosztuje dziś od %{low}, a zwykle %{typical}.",
           set: booster.product.set_name,
           low: amount(low),
           typical: whole(booster.price)
         )
         |> glue_short_words()
  end

  # Why the price of one booster is not the first question: what the
  # biggest boxes cost today, then what to ask yourself instead.
  defp better_question(page) do
    box =
      page.latest && Enum.find(page.latest.products, &(&1.type == :booster_box and &1.boosters))

    special_etb =
      page.sets
      |> Enum.filter(
        &((not &1.booster_box? and &1.etb) && &1.released_on &&
            Date.diff(page.today, &1.released_on) <= 365)
      )
      |> Enum.max_by(&Decimal.to_float(&1.etb.verdict.cheapest.price), fn -> nil end)

    costly =
      if box && special_etb,
        do:
          " " <>
            gettext(
              "Booster Box %{set} kosztuje %{box}, a Elite Trainer Box %{special} od %{etb}.",
              set: box.product.set_name,
              box: shelf_price(box),
              special: special_etb.name,
              etb: amount(special_etb.etb.verdict.cheapest.price)
            ),
        else: ""

    glue_short_words(
      gettext("Ale to nie jest najlepsze pierwsze pytanie. Pokémony to dziś drogie hobby.") <>
        costly <>
        " " <>
        gettext(
          "Zanim cokolwiek kupisz, zastanów się, czego od niego chcesz: emocji z otwierania, jednej konkretnej karty, prezentu czy grania. Od tego zależy, co kupić."
        )
    )
  end

  defp products_today(nil, _fallback), do: ""

  defp products_today(set, []),
    do: gettext("Ceny i zawartość z dziś są na kremowych kartach, z %{set}.", set: set)

  defp products_today(set, fallback),
    do:
      gettext(
        "Ceny i zawartość z dziś są na kremowych kartach: z %{set}, a tam, gdzie %{set} czegoś nie ma, z %{fallback}.",
        set: set,
        fallback: join(fallback)
      )

  # Today's facts about special sets: which they are, the one with the most
  # tins and collections, and their boosters against main sets' from the
  # last year, so set age does not drive the difference.
  defp special_sets(special, sets, today) do
    richest = Enum.max_by(special, &(&1.tins + &1.collections))
    year = Enum.filter(sets, &(&1.released_on && Date.diff(today, &1.released_on) <= 365))

    text =
      gettext(
        "Sety specjalne na liście to %{names}. W naszym katalogu %{set} ma %{tins} i %{collections}.",
        names: join(Enum.map(special, & &1.name)),
        set: richest.name,
        tins: Polish.plural(richest.tins, "puszkę", "puszki", "puszek"),
        collections: Polish.plural(richest.collections, "kolekcję", "kolekcje", "kolekcji")
      )

    {year_special, year_main} = Enum.split_with(year, &(not &1.booster_box?))

    prices =
      if year_special != [] and year_main != [],
        do:
          " " <>
            gettext(
              "Boostery setów specjalnych z ostatniego roku kosztują dziś od %{special}, a zwykłych od %{main}.",
              special: price_range(year_special),
              main: price_range(year_main)
            ),
        else: ""

    glue_short_words(text <> prices)
  end

  defp price_range(sets) do
    prices = Enum.map(sets, & &1.booster.verdict.cheapest.price)
    {low, high} = {Enum.min(prices, Decimal), Enum.max(prices, Decimal)}

    if Decimal.equal?(low, high),
      do: amount(low),
      else: gettext("%{low} do %{high}", low: amount(low), high: amount(high))
  end

  # A shop's price as it is, without ",00" on a whole one.
  defp amount(value),
    do: if(Decimal.integer?(value), do: Polish.zloty(value), else: Polish.price(value))

  # A price we work out (a median, a sum, a difference) in whole złoty.
  defp whole(value), do: Polish.zloty(value)

  # "A, B i C".
  defp join([one]), do: one

  defp join(names),
    do: Enum.join(Enum.drop(names, -1), ", ") <> " " <> gettext("i") <> " " <> List.last(names)

  defp ratio(part, whole), do: Decimal.to_float(part) / Decimal.to_float(whole)

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :logo, :string, default: nil
  attr :date, Date, required: true

  # The head of a "today" card: the set's logo when we have it, what the
  # card shows and the day of its prices.
  defp today_head(assigns) do
    ~H"""
    <div class="boosters-today-head">
      <img :if={@logo} src={@logo} alt="" class="boosters-today-logo" loading="lazy" />
      <strong id={@id}>{@title}</strong>
      <span>{gettext("ceny z %{date}", date: Polish.short_date(@date))}</span>
    </div>
    """
  end

  attr :sets, :list, required: true

  # Each recent set, newest first: its release day, a mark for a special
  # set, its cheapest booster as a bar on one scale and its cheapest Elite
  # Trainer Box as a number.
  defp set_timeline(assigns) do
    top =
      assigns.sets
      |> Enum.map(&Decimal.to_float(&1.booster.verdict.cheapest.price))
      |> Enum.max(fn -> 1.0 end)

    assigns = assign(assigns, top: top)

    ~H"""
    <ol class="boosters-sets" aria-labelledby="sets-title">
      <li :for={set <- @sets} id={"set-#{set.booster.product.slug}"}>
        <div class="boosters-set-name">
          <time :if={set.released_on} datetime={Date.to_iso8601(set.released_on)}>
            {Polish.date(set.released_on)}
          </time>
          <strong>{set.name}</strong>
          <span :if={not set.booster_box?} class="boosters-set-tag">
            <.fluent_icon name={:ribbon} />{gettext("set specjalny")}
          </span>
        </div>
        <.link
          navigate={~p"/produkty/#{set.booster.product.slug}"}
          class="boosters-set-price"
          style={"--share: #{Float.round(Decimal.to_float(set.booster.verdict.cheapest.price) / @top, 4)}"}
        >
          <span class="boosters-set-bar"></span>
          <strong>{amount(set.booster.verdict.cheapest.price)}</strong>
        </.link>
        <span class="boosters-set-etb">
          <%= if set.etb do %>
            <.link navigate={~p"/produkty/#{set.etb.product.slug}"}>
              {gettext("ETB od %{price}", price: amount(set.etb.verdict.cheapest.price))}
            </.link>
          <% else %>
            {gettext("ETB: brak na stanie")}
          <% end %>
        </span>
      </li>
    </ol>
    """
  end

  attr :boxes, :list, required: true

  # One bar per kind of box, as long as its price, split into its boosters at
  # the single booster's price and what it costs on top, most dopłata first,
  # so boxes of any price compare by share. A box cheaper than its boosters
  # shows the saving as an outline past its price.
  defp extras_chart(assigns) do
    top = assigns.boxes |> Enum.map(&max(1.0, ratio(&1.loose, &1.price))) |> Enum.max()
    assigns = assign(assigns, top: top)

    ~H"""
    <figure class="boosters-extras">
      <p class="boosters-legend" aria-hidden="true">
        <span class="boosters-legend-loose">{gettext("boostery kupione osobno")}</span>
        <span class="boosters-legend-extra">{gettext("dopłata za dodatki")}</span>
        <span class="boosters-legend-saving">{gettext("tyle oszczędzasz")}</span>
      </p>
      <ol>
        <li :for={box <- @boxes}>
          <a href={"#produkt-#{entry_id(box.type)}"} class="boosters-extras-name">
            {short_name(box.type)}
          </a>
          <span
            class="boosters-extras-track"
            style={"--loose: #{Float.round(min(1.0, ratio(box.loose, box.price)) / @top, 4)}; --extra: #{Float.round(abs(ratio(box.extra, box.price)) / @top, 4)}"}
          >
            <span class="boosters-extras-loose"></span>
            <span class={[
              "boosters-extras-rest",
              if(Decimal.negative?(box.extra), do: "is-saving", else: "is-extra")
            ]}></span>
            <strong>{whole(box.price)}</strong>
          </span>
          <span class="boosters-extras-note">{extra_line(box)}</span>
        </li>
      </ol>
    </figure>
    """
  end

  # "9 boosterów osobno: 225 zł · dopłata 154 zł (41% ceny)".
  defp extra_line(box) do
    loose =
      gettext("%{boosters} osobno: %{loose}",
        boosters: booster_count_label(box.boosters),
        loose: whole(box.loose)
      )

    rest =
      cond do
        no_extra?(box) ->
          gettext("bez dopłaty")

        Decimal.negative?(box.extra) ->
          gettext("taniej o %{amount}", amount: whole(Decimal.abs(box.extra)))

        true ->
          gettext("dopłata %{amount} (%{percent}% ceny)",
            amount: whole(box.extra),
            percent: round(ratio(box.extra, box.price) * 100)
          )
      end

    few =
      if box.few_shops?,
        do: " · " <> gettext("mało sklepów, liczymy najniższe ceny"),
        else: ""

    loose <> " · " <> rest <> few
  end

  attr :entry, :map, required: true
  attr :logos, :map, required: true
  attr :today, Date, required: true
  attr :sets, :list, required: true

  # One kind of box: what is always true of it, then a "today" card with the
  # newest box of that kind.
  defp entry(assigns) do
    ~H"""
    <section
      id={"produkt-#{@entry.id}"}
      class="boosters-type"
      aria-labelledby={"produkt-#{@entry.id}-title"}
    >
      <div class="boosters-type-head">
        <div :if={@entry.box} class="boosters-type-photo">
          <.product_image
            small_photo={@entry.box.product.stored_photo_small_url}
            photo={@entry.box.product.stored_photo_card_url}
            blur={@entry.box.product.photo_placeholder}
            kind={@entry.box.product.kind}
            sizes="(max-width: 42rem) 30vw, 12rem"
            alt=""
            class="boosters-type-image"
          />
        </div>
        <h3 id={"produkt-#{@entry.id}-title"}>{@entry.title}</h3>
        <div class="boosters-type-body">
          <p>{glue_short_words(@entry.what)}</p>
          <p :if={@entry.unique} class="boosters-type-unique">
            <strong>{gettext("Tylko w nim:")}</strong> {glue_short_words(@entry.unique)}
          </p>
        </div>
      </div>

      <div class="boosters-verdict">
        <span :if={@entry.stamp} class={["boosters-stamp", "is-#{elem(@entry.stamp, 0)}"]}>
          <img src={elem(@entry.stamp, 1)} alt="" loading="lazy" />
        </span>
        <p class="boosters-verdict-yes">
          <.fluent_icon name={:checkmark_circle} />
          <span><strong>{gettext("Bierz, gdy")}</strong> {glue_short_words(@entry.yes)}</span>
        </p>
        <p class="boosters-verdict-no">
          <.fluent_icon name={:dismiss_circle} />
          <span><strong>{gettext("Odpuść, gdy")}</strong> {glue_short_words(@entry.no)}</span>
        </p>
      </div>

      <div :if={@entry.box} class="boosters-today">
        <.today_head
          title={gettext("Dziś w %{set}", set: @entry.box.product.set_name)}
          logo={@logos[@entry.box.product.set_name]}
          date={@today}
        />
        <div class="boosters-today-body">
          <div class="boosters-today-main">
            <.contents_strip box={@entry.box} sets={@sets} />
            <p class="boosters-today-price">
              <.link navigate={~p"/produkty/#{@entry.box.product.slug}"}>{@entry.box.product.name}</.link>: {price_line(
                @entry.box
              )}
            </p>
            <p :for={line <- @entry.today} class="boosters-today-text">
              {glue_short_words(line)}
            </p>
          </div>
          <div :if={@entry.cards != [] or @entry.compare != []} class="boosters-today-cards">
            <.card_strip :if={@entry.cards != []} cards={@entry.cards} />
            <div :if={@entry.compare != []} class="boosters-compare">
              <p class="boosters-compare-label">{gettext("Dla porównania, z poprzednich setów:")}</p>
              <.card_strip cards={@entry.compare} />
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :box, :map, required: true
  attr :sets, :list, required: true

  # What a box holds, as pictures: its set's booster, the cards it holds and
  # each accessory we have a picture of; the rest as a line of words.
  defp contents_strip(assigns) do
    box = assigns.box
    set = Enum.find(assigns.sets, &(&1.name == box.product.set_name))

    pictured =
      for item <- box.items,
          picture = item_picture(item),
          do: %{label: item_label(item), picture: picture}

    unpictured =
      for item <- box.items, !item_picture(item), item.type != :code_card, do: item_label(item)

    assigns =
      assign(assigns,
        booster: box.product.kind != :booster && box.boosters && set && set.booster,
        pictured: Enum.take(pictured, 7),
        rest: Enum.map(Enum.drop(pictured, 7), & &1.label) ++ unpictured
      )

    ~H"""
    <ul :if={@booster || @pictured != []} class="boosters-contents">
      <li :if={@booster}>
        <.product_image
          small_photo={@booster.product.stored_photo_small_url}
          photo={@booster.product.stored_photo_card_url}
          blur={@booster.product.photo_placeholder}
          kind={:booster}
          sizes="4rem"
          alt=""
          class="boosters-contents-image"
        />
        <span>{booster_count_label(@box.boosters)}</span>
      </li>
      <li :for={item <- @pictured}>
        <img src={item.picture} alt="" loading="lazy" />
        <span>{item.label}</span>
      </li>
    </ul>
    <p :if={@rest != []} class="boosters-contents-rest">
      {gettext("W środku też: %{items}.", items: Enum.join(@rest, ", "))}
    </p>
    """
  end

  defp item_picture(%{type: type} = item) when type in [:promo_card, :oversize_card, :card],
    do: card_picture(item)

  defp item_picture(item), do: generic_contents_photo(item)

  attr :cards, :list, required: true

  # Cards with their picture and Cardmarket price; "brak ceny" when we do
  # not know it.
  defp card_strip(assigns) do
    ~H"""
    <ul class="boosters-cards">
      <li :for={card <- @cards}>
        <img
          :if={card_picture(card.item)}
          src={card_picture(card.item)}
          alt=""
          width="96"
          height="134"
          loading="lazy"
        />
        <span class="boosters-card-name">{card.item.name}</span>
        <span :if={card_note(card)} class="boosters-card-set">{card_note(card)}</span>
        <strong :if={card.value}>{amount(card.value)}</strong>
        <span :if={!card.value} class="boosters-card-missing">{gettext("brak ceny")}</span>
      </li>
    </ul>
    """
  end

  defp card_note(%{set: set}), do: set
  defp card_note(%{item: %{type: :oversize_card}}), do: gettext("duża karta")
  defp card_note(_card), do: nil

  defp card_picture(%{image: image}) when is_binary(image), do: CardImage.thumbnail_url(image)

  defp card_picture(%{photo: photo}) when is_binary(photo),
    do: CardImage.photo_url(photo, "thumbnail")

  defp card_picture(_item), do: nil

  # "od 339,99 zł, zwykle 379 zł".
  defp price_line(box) do
    cheapest = box.verdict.cheapest.price

    if box.few_shops? or Decimal.equal?(cheapest, box.price),
      do: gettext("od %{price}", price: amount(cheapest)),
      else:
        gettext("od %{low}, zwykle %{typical}", low: amount(cheapest), typical: whole(box.price))
  end

  defp shelf_price(box) do
    if box.few_shops?,
      do: gettext("od %{price}", price: amount(box.verdict.cheapest.price)),
      else: gettext("zwykle %{price}", price: whole(box.price))
  end

  attr :page, :map, required: true
  attr :set, :string, default: nil

  # The rules that hold whatever you buy, each with today's number when we
  # have it.
  defp rules(assigns) do
    boxes = if assigns.page.latest, do: assigns.page.latest.products, else: []
    etb = Enum.find(boxes, &(&1.type == :elite_trainer_box))
    promos = known(Map.get(assigns.page.by_type, :elite_trainer_box, []))

    spread =
      etb &&
        case Enum.map(etb.verdict.shop_prices, & &1.price) do
          [_, _ | _] = prices -> {Enum.min(prices, Decimal), Enum.max(prices, Decimal)}
          _one -> nil
        end

    assigns = assign(assigns, spread: spread, promos: promos)

    ~H"""
    <ul class="boosters-advice">
      <li>
        <strong>{gettext("Porównaj sklepy.")}</strong>
        {gettext("To samo pudełko kosztuje w różnych sklepach bardzo różnie.")}
        <span :if={@spread} class="boosters-advice-today">
          {gettext("Dziś Elite Trainer Box %{set} kosztuje od %{low} do %{high}.",
            set: @set,
            low: amount(elem(@spread, 0)),
            high: amount(elem(@spread, 1))
          )
          |> glue_short_words()}
        </span>
      </li>
      <li>
        <strong>{gettext("Kusi cię karta promo?")}</strong>
        {gettext("Najpierw sprawdź, ile kosztuje osobno, a dopiero potem dopłacaj do całego pudełka.")
        |> glue_short_words()}
        <span :if={@promos != []} class="boosters-advice-today">
          {gettext("Karty promo z ETB ostatnich setów kosztują dziś na Cardmarkecie %{range}.",
            range: value_range(@promos)
          )
          |> glue_short_words()}
        </span>
      </li>
      <li>
        <strong>{gettext("Nie kupuj pudełek jako inwestycji.")}</strong>
        {gettext(
          "Jedne zamknięte pudełka drożeją, inne nie. Kupujesz po cenie sklepowej, a sprzedajesz taniej. To ryzyko i tego nie polecamy."
        )
        |> glue_short_words()}
      </li>
    </ul>
    """
  end

  # Four ways in by purpose, each with a picture of what it points to.
  defp intents(page, shelf) do
    photo = fn type ->
      Enum.find_value(shelf, fn {box, _entry} ->
        box.type == type &&
          (box.product.stored_photo_small_url || box.product.stored_photo_card_url)
      end)
    end

    card = %{
      title: gettext("Chcę jedną konkretną kartę"),
      teaser: gettext("Kup ją osobno. Booster to loteria"),
      href: ~p"/karty",
      image: ~p"/images/guides/umbreon-ex-161.webp"
    }

    if page.latest do
      [
        %{
          title: gettext("Lubię emocje otwierania"),
          teaser: gettext("Same boostery: pojedynczo, po sześć albo cały karton"),
          href: "#grupa-boostery",
          image: photo.(:booster)
        },
        card,
        %{
          title: gettext("Szukam prezentu"),
          teaser: gettext("ETB, puszka albo kolekcja i ile dopłacasz za opakowanie"),
          href: "#grupa-prezent",
          image: photo.(:elite_trainer_box)
        },
        %{
          title: gettext("Chcę zacząć grać"),
          teaser: gettext("Gotowa talia i kilka boosterów"),
          href: "#produkt-build-and-battle",
          image: photo.(:build_and_battle)
        }
      ]
    else
      [card]
    end
  end

  @shelf_types [
    :booster,
    :blister,
    :premium_checklane,
    :three_pack,
    :booster_bundle,
    :build_and_battle,
    :elite_trainer_box,
    :booster_box
  ]

  # The newest set's boxes, one per kind (the one most shops have), in the
  # entries' order.
  defp shelf(boxes) do
    for type <- @shelf_types,
        box =
          boxes
          |> Enum.filter(&(&1.type == type))
          |> Enum.max_by(&length(&1.verdict.shop_prices), fn -> nil end),
        do: {box, %{id: entry_id(type), short: short_name(type)}}
  end

  defp entry_id(type) when type in [:booster, :sleeved_booster], do: "booster"
  defp entry_id(type) when type in [:blister, :premium_checklane], do: "blister"
  defp entry_id(:three_pack), do: "3-pack"
  defp entry_id(:booster_bundle), do: "booster-bundle"
  defp entry_id(:build_and_battle), do: "build-and-battle"
  defp entry_id(:elite_trainer_box), do: "etb"
  defp entry_id(:booster_box), do: "booster-box"
  defp entry_id(type) when type in [:tin, :mini_tin], do: "puszka"
  defp entry_id(:collection), do: "kolekcja"

  defp short_name(:booster), do: gettext("Booster")
  defp short_name(:blister), do: gettext("Blister z 1 boosterem")
  defp short_name(:premium_checklane), do: gettext("Premium Checklane")
  defp short_name(:three_pack), do: gettext("Blister z 3 boosterami")
  defp short_name(:booster_bundle), do: gettext("Booster Bundle")
  defp short_name(:build_and_battle), do: gettext("Build & Battle Box")
  defp short_name(:elite_trainer_box), do: gettext("Elite Trainer Box")
  defp short_name(:booster_box), do: gettext("Booster Box")

  defp groups(entries) do
    by_id = Map.new(entries, &{&1.id, &1})

    [
      {"boostery", gettext("Same boostery"), ~w(booster booster-bundle booster-box)},
      {"karta", gettext("Booster i karta promo"), ~w(blister 3-pack)},
      {"gra", gettext("Do gry"), ~w(build-and-battle)},
      {"prezent", gettext("Na prezent"), ~w(etb puszka kolekcja)}
    ]
    |> Enum.map(fn {id, label, ids} -> {id, label, Enum.map(ids, &Map.fetch!(by_id, &1))} end)
  end

  # The guide's kinds of box, each with the newest set's box of that kind (or
  # the newest set's that has one), its copy and today's lines and cards.
  defp entries(page) do
    by_type = page.by_type
    example = fn type -> example(Map.get(by_type, type, [])) end

    [
      booster(example.(:booster), example.(:sleeved_booster)),
      bundle(example.(:booster_bundle)),
      booster_box(example.(:booster_box)),
      blister(example.(:blister), example.(:premium_checklane), Map.get(by_type, :blister, [])),
      three_pack(example.(:three_pack), Map.get(by_type, :three_pack, [])),
      build_and_battle(example.(:build_and_battle)),
      elite_trainer_box(example.(:elite_trainer_box), Map.get(by_type, :elite_trainer_box, [])),
      tin(example.(:tin), example.(:mini_tin), example.(:collection)),
      collection(example.(:collection))
    ]
    |> Enum.map(&Map.put(&1, :stamp, stamp(&1.box)))
  end

  # The newest set's box whose boosters we can price (newest set first), the
  # one most shops have.
  defp example(boxes) do
    priced = Enum.filter(boxes, &(&1.loose || &1.product.kind == :booster))

    case priced do
      [] ->
        nil

      [first | _] ->
        priced
        |> Enum.filter(&(&1.product.set_name == first.product.set_name))
        |> Enum.max_by(&length(&1.verdict.shop_prices))
    end
  end

  # The round picture beside the verdict: the box's own promo card, else the
  # box itself.
  defp stamp(nil), do: nil

  defp stamp(box) do
    case Enum.find_value(box.cards, &(&1.item.type == :promo_card && card_picture(&1.item))) do
      nil -> box.product.stored_photo_small_url && {:box, box.product.stored_photo_small_url}
      picture -> {:card, picture}
    end
  end

  defp base(id, title, box),
    do: %{id: id, title: title, box: box, unique: nil, today: [], cards: [], compare: []}

  defp booster(box, sleeved) do
    base("booster", gettext("Booster"), box)
    |> Map.merge(%{
      what:
        gettext(
          "Saszetka z kartami jednego setu: 10 losowych kart, karta energii i karta z kodem do gry Pokémon TCG Live. Każde pudełko niżej to boostery i coś jeszcze, dlatego liczymy, ile kosztowałyby same boostery z tego pudełka."
        ),
      today:
        List.wrap(
          sleeved &&
            gettext(
              "Sleeved Booster to ten sam booster w kartonowej osłonce, od %{price}. Za osłonkę nie warto dopłacać.",
              price: amount(sleeved.verdict.cheapest.price)
            )
        ),
      yes: gettext("chcesz otworzyć kilka boosterów albo szukasz drobnego prezentu."),
      no: gettext("szukasz jednej, konkretnej karty. Taniej kupisz ją osobno.")
    })
  end

  defp bundle(box) do
    base("booster-bundle", gettext("Booster Bundle"), box)
    |> Map.merge(%{
      what: gettext("Sześć boosterów w kartonowym pudełku. Bez dodatków."),
      today: List.wrap(box && box.extra && bundle_note(box)),
      yes: gettext("wychodzi taniej niż sześć boosterów osobno."),
      no: gettext("wychodzi drożej. Wtedy weź pojedyncze.")
    })
  end

  defp bundle_note(box) do
    cond do
      no_extra?(box) ->
        gettext("Dziś kosztuje tyle samo co sześć boosterów osobno.")

      Decimal.positive?(box.extra) ->
        gettext(
          "Dziś kosztuje o %{amount} więcej niż sześć boosterów osobno, więc lepiej weź pojedyncze.",
          amount: whole(box.extra)
        )

      true ->
        gettext("Dziś kosztuje o %{amount} mniej niż sześć boosterów osobno.",
          amount: whole(Decimal.abs(box.extra))
        )
    end
  end

  defp booster_box(box) do
    base("booster-box", gettext("Booster Box"), box)
    |> Map.merge(%{
      what:
        gettext(
          "36 boosterów w zafoliowanym kartonie. Wychodzi tylko do zwykłych setów, sety specjalne go nie mają. Do niektórych setów jest też Enhanced Booster Display z dodatkową kartą promo."
        ),
      today: List.wrap(box && box.extra && box_per_booster(box)),
      yes: gettext("otwierasz dużo albo bierzesz karton na spółkę ze znajomymi."),
      no: gettext("nie chcesz wydawać kilkuset złotych na jeden set.")
    })
  end

  # Typical against typical; with few shops, cheapest against cheapest.
  defp box_per_booster(box) do
    per = Polish.price(box.price |> Decimal.div(box.boosters) |> Decimal.round(2))

    if box.few_shops?,
      do:
        gettext("Jeden booster z kartonu wychodzi po %{per}, a osobno kosztuje od %{single}.",
          per: per,
          single: amount(box.single)
        ),
      else:
        gettext(
          "Jeden booster z kartonu wychodzi po %{per}, a osobno kosztuje zwykle %{single}.",
          per: per,
          single: whole(box.single)
        )
  end

  defp blister(box, premium, all) do
    base("blister", gettext("Blister z jednym boosterem"), box)
    |> Map.merge(%{
      what:
        gettext(
          "Booster, karta promo i moneta, zamknięte w plastiku. Karta promo jest z serii Black Star Promos, więc nie trafisz jej w żadnym boosterze. Jest też wersja Premium Checklane: booster, moneta i trzy karty jednego Pokémona, od formy podstawowej po ostatnią ewolucję, przedrukowane z wcześniejszego setu."
        ),
      unique: gettext("karta promo pokazana na opakowaniu."),
      today:
        Enum.filter([box && box.extra && extra_note(box), premium && premium_note(premium)], & &1),
      cards: own_cards(box),
      compare: compare(all, box),
      yes:
        gettext("podoba ci się ta karta promo albo szukasz prezentu za kilkadziesiąt złotych."),
      no: gettext("chcesz samego boostera. Tu kosztuje więcej niż kupiony osobno.")
    })
  end

  defp premium_note(premium) do
    cards = premium.cards

    # A sum of some of the cards would read as the value of all three.
    sum =
      if cards != [] and Enum.all?(cards, & &1.value),
        do:
          " " <>
            gettext("Trzy karty z niego są warte na Cardmarkecie razem %{sum}.",
              sum: amount(Enum.reduce(cards, Decimal.new(0), &Decimal.add(&1.value, &2)))
            ),
        else: ""

    gettext("Premium Checklane Blister kosztuje od %{price}.",
      price: amount(premium.verdict.cheapest.price)
    ) <> sum
  end

  defp three_pack(box, all) do
    base("3-pack", gettext("Blister z trzema boosterami"), box)
    |> Map.merge(%{
      what: gettext("Trzy boostery i karta promo w jednym opakowaniu."),
      unique: gettext("karta promo z opakowania."),
      today: List.wrap(box && box.extra && extra_note(box)),
      cards: own_cards(box),
      compare: compare(all, box),
      yes:
        gettext(
          "kosztuje niewiele więcej niż trzy boostery osobno. Wtedy kartę promo masz prawie gratis."
        ),
      no: gettext("trzy pojedyncze boostery wychodzą wyraźnie taniej.")
    })
  end

  defp build_and_battle(box) do
    base("build-and-battle", gettext("Build & Battle Box"), box)
    |> Map.merge(%{
      what:
        gettext(
          "Pudełko na turniej przedpremierowy: gotowa talia 40 kart i cztery boostery, którymi ją ulepszasz. Przed premierą kupisz je tylko jako wejściówkę na prerelease, po premierze trafia do zwykłej sprzedaży. Talia 40 kart służy do krótszej odmiany gry; do zwykłej gry 60 kartami są gotowe talie, na przykład League Battle Deck."
        ),
      unique: gettext("jedna z czterech kart promo przygotowanych do tego pudełka."),
      today: List.wrap(box && box.extra && extra_note(box)),
      yes: gettext("idziesz na prerelease albo chcesz od razu zagrać z kimś krótką partię."),
      no: gettext("chcesz tylko otwierać boostery.")
    })
  end

  defp elite_trainer_box(box, all) do
    more =
      box && box.extra && boosters_for(box.extra, box.single) >= 1 &&
        gettext("Za samą dopłatę kupisz około %{count}.",
          count: booster_count_label(boosters_for(box.extra, box.single))
        )

    base("etb", gettext("Elite Trainer Box (ETB)"), box)
    |> Map.merge(%{
      what:
        gettext(
          "Pudełko na prezent albo na start: zwykle dziewięć boosterów, karta promo, akcesoria do gry (koszulki, karty energii, kości, moneta) i pudełko z przegródkami, w którym potem trzymasz karty."
        ),
      unique:
        gettext(
          "karta promo. Poza nim ma ją tylko Pokémon Center Elite Trainer Box, wersja ze sklepu wydawcy. Tamta ma 11 boosterów zamiast 9 i drugą kartę promo, z logo Pokémon Center."
        ),
      today: Enum.filter([box && box.extra && extra_note(box), more], & &1),
      cards: own_cards(box),
      compare: compare(all, box),
      yes:
        gettext(
          "kupujesz prezent albo zaczynasz grać. Koszulki, energie i kości się przydadzą, a karty schowasz w pudełku."
        ),
      no: gettext("chcesz samych boosterów.")
    })
  end

  defp tin(box, mini, collection) do
    shared = box && collection && shared_promo(box, collection)

    base("puszka", gettext("Puszka (tin)"), box)
    |> Map.merge(%{
      what:
        gettext(
          "Metalowa puszka z kilkoma boosterami i kartą promo, zwykle z Pokémonem z wieczka. Puszka zostaje i przyda się na karty. W niektórych puszkach są boostery kilku różnych setów, więc sprawdź opis."
        ),
      unique: gettext("sama puszka."),
      today:
        Enum.filter(
          [
            box && box.extra && extra_note(box),
            shared &&
              gettext("Ta sama karta %{card} jest też w pudełku %{product}.",
                card: shared,
                product: collection.product.name
              ),
            mini &&
              gettext("Mini puszka (Mini Tin) jest mniejsza: %{contents}. Kosztuje od %{price}.",
                contents: contents_words(mini),
                price: amount(mini.verdict.cheapest.price)
              )
          ],
          & &1
        ),
      cards: own_cards(box),
      yes: gettext("kupujesz prezent. Puszka dobrze wygląda i zostaje na półce."),
      no: gettext("puszka kosztuje wyraźnie więcej niż boostery w niej kupione osobno.")
    })
  end

  defp collection(box) do
    base("kolekcja", gettext("Kolekcja"), box)
    |> Map.merge(%{
      what:
        gettext(
          "Pudełko z kilkoma boosterami i kartą promo, często też z jej dużą wersją. W droższych kolekcjach bywa figurka, przypinka, plakat albo segregator. Najwięcej kolekcji wychodzi do setów specjalnych."
        ),
      unique: gettext("karty promo i gadżety z tego pudełka."),
      today: List.wrap(box && box.extra && extra_note(box)),
      cards: own_cards(box),
      yes: gettext("chcesz mieć konkretnego Pokémona na półce."),
      no: gettext("liczysz, że karty z pudełka będą coś warte.")
    })
  end

  # "Kosztuje o 154 zł więcej niż 9 boosterów osobno (po 25 zł)."
  defp extra_note(%{boosters: 1} = box) do
    single = whole(box.single)

    cond do
      no_extra?(box) ->
        gettext("Kosztuje tyle samo co sam booster (%{single}).", single: single)

      Decimal.negative?(box.extra) ->
        gettext("Kosztuje o %{amount} mniej niż sam booster (%{single}).",
          amount: whole(Decimal.abs(box.extra)),
          single: single
        )

      true ->
        gettext("Kosztuje o %{amount} więcej niż sam booster (%{single}).",
          amount: whole(box.extra),
          single: single
        )
    end
  end

  defp extra_note(box) do
    boosters = booster_count_label(box.boosters)
    single = whole(box.single)

    cond do
      no_extra?(box) ->
        gettext("Kosztuje tyle samo co %{boosters} osobno (po %{single}).",
          boosters: boosters,
          single: single
        )

      Decimal.negative?(box.extra) ->
        gettext("Kosztuje o %{amount} mniej niż %{boosters} osobno (po %{single}).",
          amount: whole(Decimal.abs(box.extra)),
          boosters: boosters,
          single: single
        )

      true ->
        gettext("Kosztuje o %{amount} więcej niż %{boosters} osobno (po %{single}).",
          amount: whole(box.extra),
          boosters: boosters,
          single: single
        )
    end
  end

  # Within half a złoty either way: we say prices in whole złoty.
  defp no_extra?(box), do: Decimal.equal?(Decimal.round(box.extra, 0), 0)

  # The name of a promo card two boxes both hold, by its Cardmarket product.
  defp shared_promo(one, other) do
    ids =
      for card <- other.cards,
          card.item.cardmarket_id,
          into: MapSet.new(),
          do: card.item.cardmarket_id

    Enum.find_value(one.cards, fn card ->
      card.item.type == :promo_card and MapSet.member?(ids, card.item.cardmarket_id) and
        card.item.name
    end)
  end

  defp boosters_for(extra, single),
    do: extra |> Decimal.div(single) |> Decimal.round(0, :down) |> Decimal.to_integer()

  # A box's own cards, priced or not, so a missing price shows as missing.
  defp own_cards(nil), do: []
  defp own_cards(box), do: box.cards

  # The first card of each box of the same kind from other sets, when we know
  # its price.
  defp compare(boxes, own) do
    own_set = own && own.product.set_name

    boxes
    |> Enum.reject(&(&1.product.set_name == own_set))
    |> known()
    |> Enum.uniq_by(& &1.set)
    |> Enum.take(3)
  end

  # The cards with a known price that boxes hold, one per box, with their set.
  defp known(boxes) do
    for box <- boxes,
        card <- Enum.take(box.cards, 1),
        card.value,
        do: Map.put(card, :set, box.product.set_name)
  end

  defp value_range(cards) do
    values = Enum.map(cards, & &1.value)
    {low, high} = {Enum.min(values, Decimal), Enum.max(values, Decimal)}

    if Decimal.equal?(low, high),
      do: amount(low),
      else: gettext("od %{low} do %{high}", low: amount(low), high: amount(high))
  end

  # What a box holds, in words: "2 boostery, naklejki, karta z ilustracją".
  defp contents_words(box) do
    [box.boosters && booster_count_label(box.boosters) | Enum.map(box.items, &item_label/1)]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  defp item_label(%{quantity: 1} = item), do: contents_item_label(item)
  defp item_label(item), do: "#{contents_item_label(item)} (#{item.quantity})"

  defp booster_count_label(count),
    do: Polish.plural(count, "booster", "boostery", "boosterów")
end
