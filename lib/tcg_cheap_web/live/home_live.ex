defmodule TcgCheapWeb.HomeLive do
  @moduledoc """
  The region's home page, in the order a visitor needs it:

    1. one search across products and cards (`?q=`), its first results right
       here and the whole list one link away; narrowing it to products or
       cards (`?w=produkty`, `?w=karty`) leads to that list, the query with it;
    2. today's deals in one row, the shops' and the retail chains' alike, the
       chains' prices rated against the shops' (`TcgCheap.Sealed.Deals`);
    3. our articles;
    4. the rest: the two lists' doors and the newest sets.

  The lists themselves live at `/produkty` and `/karty`.
  """

  use TcgCheapWeb, :live_view

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.ListingComponents
  import TcgCheapWeb.SiteComponents

  alias TcgCheap.Cards
  alias TcgCheap.Sealed.{BoosterGuide, Deals, Expansions, ProductList, RetailDeal, Shops}

  alias TcgCheapWeb.{
    Analytics,
    CardRecords,
    Format,
    Paths,
    Region,
    RegionText,
    SEO,
    VisitorLocation
  }

  @max_query_length 100
  # Each kind's first results: enough to recognise the right one.
  @results 4
  @sets 6
  @news_days 120
  # A search narrowed to one kind is its list's own search.
  @lists ~w(produkty karty)

  @impl true
  def mount(_params, _session, socket) do
    # The deals and the products door's numbers are Polish shops' and
    # chains' prices: other regions have none yet. The cards door counts the
    # region's singles, where shops sell them.
    region = socket.assigns.region
    polish? = Region.poland?(region)
    today = Date.utc_today()

    {:ok,
     socket
     |> VisitorLocation.assign_location()
     |> assign(
       deals: if(polish?, do: Deals.current(), else: []),
       sealed: if(polish?, do: Deals.market()),
       singles: if(Region.singles?(region), do: Cards.SinglesBanner.market(region.market)),
       articles: articles(),
       sets: news_sets(today)
     )
     |> stream_configure(:found_products, dom_id: &"home-product-#{&1.product.slug}")
     |> stream_configure(:found_cards, dom_id: &"home-card-#{&1.card.id}")}
  end

  @impl true
  # Also a search sent without LiveView, or an old link: the history entry is
  # replaced, so going back does not lead here again.
  def handle_params(%{"w" => list} = params, _uri, socket) when list in @lists,
    do: {:noreply, push_navigate(socket, to: list_path(list, query_param(params)), replace: true)}

  def handle_params(params, _uri, socket) do
    query = params |> query_param() |> String.trim() |> String.slice(0, @max_query_length)
    seo = SEO.Home.metadata(params)

    previous = socket.assigns[:query]

    {:noreply,
     socket
     |> assign(seo: seo, page_title: seo.page_title, query: query)
     |> assign(:form, to_form(%{"q" => query, "w" => ""}))
     |> search(query)
     |> track_search(previous)}
  end

  # Only searches made on the page: the first render arrives with its
  # pageview, whose URL already holds the query.
  defp track_search(socket, nil), do: socket
  defp track_search(%{assigns: %{query: query}} = socket, query), do: socket

  defp track_search(%{assigns: %{query: ""}} = socket, _previous),
    do: Analytics.track(socket, "search_cleared", %{mode: :all})

  defp track_search(%{assigns: assigns} = socket, _previous),
    do:
      Analytics.track(socket, "search_performed", %{
        mode: :all,
        query: assigns.query,
        product_count: assigns.product_count,
        card_count: assigns.card_count
      })

  @impl true
  def handle_event("search", %{"w" => list} = params, socket) when list in @lists,
    do: {:noreply, push_navigate(socket, to: list_path(list, query_param(params)))}

  def handle_event("search", params, socket) do
    query = params |> query_param() |> String.trim()
    {:noreply, push_patch(socket, to: Paths.home(query_params(query)), replace: true)}
  end

  def handle_event("location-" <> _ = event, params, socket),
    do: {:noreply, VisitorLocation.handle_event(event, params, socket)}

  # Nested params (`?q[a]=b`) are no query.
  defp query_param(%{"q" => query}) when is_binary(query), do: query
  defp query_param(_params), do: ""

  defp list_path("produkty", query), do: Paths.products(query_params(query))
  defp list_path("karty", query), do: Paths.cards(query_params(query))

  defp query_params(query) do
    case String.trim(query) do
      "" -> []
      query -> [q: String.slice(query, 0, @max_query_length)]
    end
  end

  defp search(socket, "") do
    socket
    |> assign(product_count: 0, card_count: 0)
    |> stream(:found_products, [], reset: true)
    |> stream(:found_cards, [], reset: true)
  end

  defp search(socket, query) do
    {products, product_count} = find_products(query, socket.assigns.region)
    {cards, card_count} = find_cards(query, socket.assigns.region)

    socket
    |> assign(product_count: product_count, card_count: card_count)
    |> stream(:found_products, products, reset: true)
    |> stream(:found_cards, cards, reset: true)
  end

  # The products list's own search: English editions, as the list opens.
  defp find_products(query, region) do
    filters = %{query: query, kind: nil, edition: :en, expansion: nil}
    {summaries, _more?, count} = ProductList.browse(filters, 0, DateTime.utc_now(), region.market)
    {Enum.take(summaries, @results), count}
  end

  # The card list's own search: cards in stock first, as the list shows them.
  defp find_cards(query, region) do
    market = region.market

    {available, _more?, count} =
      Cards.Guide.browse(%{query: query, expansion: nil, stock: :in}, 0, market)

    {unavailable, _more?, out_count} =
      Cards.Guide.browse(%{query: query, expansion: nil, stock: :out}, 0, market)

    {Enum.take(available ++ unavailable, @results), count + out_count}
  end

  # Sets still to come or out for a few months: news, not the whole catalogue.
  defp news_sets(today) do
    since = Date.add(today, -@news_days)

    @sets
    |> Expansions.latest()
    |> Enum.filter(&(&1.released_on && Date.compare(&1.released_on, since) != :lt))
  end

  # The region's articles, each with a cover of its own drawn from what it
  # tells today: a leaflet of the cheapest boosters, the record card in a
  # showcase, the spread of what cards cost.
  defp articles do
    for page <- [:booster_prices, :expensive_cards, :card_value],
        path = Paths.page(page),
        do: Map.merge(%{id: page, path: path}, article(page))
  end

  defp article(:booster_prices) do
    guide = BoosterGuide.guide()

    %{
      title: gettext("Ile kosztuje booster Pokémon?"),
      text: gettext("Najtańszy booster każdego setu w sklepach i w sieciówkach."),
      cover: %{cheapest: guide.cheapest}
    }
  end

  defp article(:expensive_cards) do
    record = hd(CardRecords.all())

    %{
      title: gettext("Najdroższe karty Pokémon"),
      text: gettext("Rekordy aukcji i najdroższe karty, które kupisz dziś."),
      cover: %{
        record: record,
        record_image: record.image && ~p"/images/records/#{record.image}",
        # Today's two most expensive, behind the record.
        today:
          Cards.Expensive.overview().highlights
          |> Enum.map(& &1.image_large)
          |> Enum.reject(&is_nil/1)
          |> Enum.take(2)
      }
    }
  end

  defp article(:card_value) do
    %{spread: spread} = Cards.Value.guide()

    %{
      title: gettext("Ile jest warta twoja karta?"),
      text: gettext("Jak w kilka minut sprawdzić cenę karty, którą masz."),
      cover: %{spread: spread, bars: spread && bars(spread)}
    }
  end

  # The spread's price ranges as bars. Counts run from thousands to a few, so
  # a bar's height is the square root of its share: the dear tail stays
  # visible. The range of the dearest card is the one lit.
  defp bars(%{bins: bins, max: max}) do
    top = bins |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end)

    for bin <- bins do
      %{
        height: if(top > 0, do: round(:math.sqrt(bin.count / top) * 100), else: 0),
        dearest?: not Decimal.lt?(max, bin.from) and (is_nil(bin.to) or Decimal.lt?(max, bin.to))
      }
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <SEO.sync seo={@seo} />
      <div class="guide-world">
        <.site_header
          region={@region}
          locale={@locale}
          current_path={@current_path}
          region_hint={@region_hint}
        >
          <VisitorLocation.location_control
            :if={VisitorLocation.pickup?()}
            location={@location}
            ready={@location_ready?}
            form={@town_form}
            matches={@town_matches}
            error={@location_error}
          />
        </.site_header>
        <main id="home-main" class="guide-main home-main">
          <section id="home-intro" class="home-intro" aria-labelledby="guide-title">
            <h1 id="guide-title">{gettext("Czy to dobra cena?")}</h1>
            <p id="guide-promise">{RegionText.products_promise()}</p>
            <%!-- Without LiveView the form still searches: a GET to this page. --%>
            <.form
              for={@form}
              id="home-search"
              class="home-search"
              action={Paths.home()}
              method="get"
              role="search"
              phx-change="search"
              phx-submit="search"
            >
              <label for="home-search-query" class="sr-only">{gettext("Szukaj produktu albo karty")}</label>
              <div class="home-search-field">
                <.fluent_icon name={:search} class="home-search-icon" />
                <input
                  id="home-search-query"
                  name="q"
                  type="search"
                  value={@form[:q].value}
                  maxlength="100"
                  autocomplete="off"
                  phx-debounce="300"
                  placeholder={gettext("np. ETB albo Pikachu")}
                />
              </div>
              <fieldset class="home-search-scope">
                <legend class="sr-only">{gettext("Szukaj w")}</legend>
                <label :for={{value, label} <- scope_choices()}>
                  <input type="radio" name="w" value={value} checked={@form[:w].value == value} />
                  <span>{label}</span>
                </label>
              </fieldset>
            </.form>

            <div :if={@query != ""} id="home-results" class="home-results" aria-live="polite">
              <section
                id="home-results-products"
                class="home-results-kind"
                aria-labelledby="home-results-products-title"
              >
                <div class="home-results-head">
                  <h2 id="home-results-products-title">{gettext("Produkty")}</h2>
                  <.link :if={@product_count > 0} navigate={Paths.products(q: @query)}>
                    {gettext("Wszystkie: %{count}", count: Format.number(@product_count))}&nbsp;→
                  </.link>
                </div>
                <ul
                  id="home-found-products"
                  class="guide-products"
                  phx-update="stream"
                  data-track-positions
                >
                  <li id="home-found-products-empty" class="guide-empty hidden only:block">
                    {gettext("Nic nie znaleźliśmy.")}
                  </li>
                  <li
                    :for={{dom_id, summary} <- @streams.found_products}
                    id={dom_id}
                    class="guide-product"
                  >
                    <.product_row summary={summary} />
                  </li>
                </ul>
              </section>
              <section
                id="home-results-cards"
                class="home-results-kind"
                aria-labelledby="home-results-cards-title"
              >
                <div class="home-results-head">
                  <h2 id="home-results-cards-title">{gettext("Karty")}</h2>
                  <.link :if={@card_count > 0} navigate={Paths.cards(q: @query)}>
                    {gettext("Wszystkie: %{count}", count: Format.number(@card_count))}&nbsp;→
                  </.link>
                </div>
                <ul
                  id="home-found-cards"
                  class="guide-products"
                  phx-update="stream"
                  data-track-positions
                >
                  <li id="home-found-cards-empty" class="guide-empty hidden only:block">
                    {gettext("Nie znaleźliśmy takiej karty. Wpisz angielską nazwę, np. Pikachu.")}
                  </li>
                  <.card_row
                    :for={{dom_id, row} <- @streams.found_cards}
                    id={dom_id}
                    row={row}
                    placement="home"
                  />
                </ul>
              </section>
            </div>
          </section>

          <section
            :if={@deals != []}
            id="home-deals"
            class="home-section"
            aria-labelledby="home-deals-title"
          >
            <div class="home-section-head">
              <h2 id="home-deals-title">{gettext("Okazje dziś")}</h2>
              <.link :if={Paths.page(:booster_prices)} navigate={Paths.page(:booster_prices)}>
                {gettext("Wszystkie ceny boosterów")}&nbsp;→
              </.link>
            </div>
            <ul class="home-deals" data-track-positions>
              <.deal_card :for={deal <- @deals} deal={deal} />
            </ul>
          </section>

          <section
            :if={@articles != []}
            id="home-articles"
            class="home-section"
            aria-labelledby="home-articles-title"
          >
            <div class="home-section-head">
              <h2 id="home-articles-title">{gettext("Poradniki")}</h2>
            </div>
            <ul class="home-articles">
              <li
                :for={article <- @articles}
                id={"home-article-#{article.id}"}
                class={["home-article", "home-article-#{article.id}"]}
              >
                <.article_cover article={article} />
                <h3>
                  <.link
                    navigate={article.path}
                    data-track="home_article_clicked"
                    data-track-article={article.id}
                  >{article.title}</.link>
                </h3>
                <p>{article.text}</p>
              </li>
            </ul>
          </section>

          <div id="home-doors" class="home-doors">
            <.door
              id="home-products"
              title={gettext("Produkty")}
              href={Paths.products()}
              text={gettext("Boostery, ETB, boxy, puszki i kolekcje: najtańszy sklep i ocena ceny.")}
            >
              <:fact :if={@sealed}>
                {gettext("%{count} w dobrej cenie dziś", count: Format.number(@sealed.good))}
              </:fact>
              <:fact :if={@sealed}>
                {ngettext(
                  "%{number} produkt na stanie",
                  "%{number} produkty na stanie",
                  @sealed.in_stock,
                  number: Format.number(@sealed.in_stock)
                )}
              </:fact>
            </.door>
            <.door
              id="home-cards"
              title={gettext("Karty")}
              href={Paths.cards()}
              text={
                # Shops' prices only where the region has singles shops.
                if(@singles,
                  do: gettext("Angielskie karty: ceny w sklepach i na Cardmarket."),
                  else: gettext("Angielskie karty: ceny na Cardmarket.")
                )
              }
            >
              <:fact :if={@singles}>
                {ngettext(
                  "%{number} karta na stanie",
                  "%{number} karty na stanie",
                  @singles.in_stock,
                  number: Format.number(@singles.in_stock)
                )}
              </:fact>
            </.door>
          </div>

          <section
            :if={@sets != []}
            id="home-sets"
            class="home-section"
            aria-labelledby="home-sets-title"
          >
            <div class="home-section-head">
              <h2 id="home-sets-title">{gettext("Nowe sety")}</h2>
            </div>
            <ul class="home-sets">
              <li :for={set <- @sets} id={"home-set-#{set.id}"}>
                <.link navigate={SEO.Expansion.path(set.id, set.name)} class="home-set">
                  <span :if={set.logo_url} class="home-set-logo">
                    <img src={set.logo_url} alt="" loading="lazy" />
                  </span>
                  <span class="home-set-name">{set.name}</span>
                  <span class="home-set-when">{release_line(set.released_on)}</span>
                </.link>
              </li>
            </ul>
          </section>
        </main>
        <.site_footer sets={@footer_sets} />
      </div>
    </Layouts.app>
    """
  end

  defp scope_choices,
    do: [
      {"", gettext("Wszystko")},
      {"produkty", gettext("Produkty")},
      {"karty", gettext("Karty")}
    ]

  attr :deal, :map, required: true

  # One deal of the row: where it is sold, the box, its price against the
  # shops' typical price; a chain's deal also its days and source.
  defp deal_card(assigns) do
    assigns = assign(assigns, retail: retail(assigns.deal.source))

    ~H"""
    <li id={"home-deal-#{@deal.id}"} class={["home-deal", @retail && "home-deal-retail"]}>
      <p class="home-deal-from">
        <%= if @retail do %>
          <img
            src={~p"/images/chains/#{Atom.to_string(@retail.chain) <> ".webp"}"}
            alt={RetailDeal.chain_name(@retail.chain)}
            width="96"
            height="32"
            loading="lazy"
            class={[
              "home-deal-chain",
              RetailDeal.square_logo?(@retail.chain) && "home-deal-chain-square"
            ]}
          />
        <% else %>
          {shop_name(@deal.source)}
        <% end %>
      </p>
      <div :if={@deal.photo} class="home-deal-photo">
        <img src={@deal.photo} alt="" loading="lazy" />
      </div>
      <h3 class="home-deal-name">
        <.link
          navigate={Paths.product(@deal.product.slug)}
          data-track="home_deal_clicked"
          data-track-product-slug={@deal.product.slug}
          data-track-source={if(@retail, do: @retail.chain, else: "shop")}
        >{@deal.product.name}</.link>
      </h3>
      <p class="home-deal-price">
        <strong>{Format.price(@deal.price)}</strong>
        <span :if={@deal.percent} class="home-deal-percent">{"−#{@deal.percent}%"}</span>
      </p>
      <p class="home-deal-typical">
        {gettext("zwykle %{price} w sklepach", price: Format.price(@deal.typical))}
      </p>
      <p :if={@retail} class="home-deal-when">
        {TcgCheapWeb.RetailComponents.deal_days(@retail)} ·
        <a
          href={@retail.source_url}
          target="_blank"
          rel="noopener nofollow"
          data-track="retail_deal_source_clicked"
          data-track-chain={@retail.chain}
          aria-label={
            gettext("%{chain}: źródło ceny (otwiera się w nowej karcie)",
              chain: RetailDeal.chain_name(@retail.chain)
            )
          }
        >{gettext("źródło")}&nbsp;↗</a>
      </p>
    </li>
    """
  end

  attr :article, :map, required: true

  # Each article's cover is its own picture, so three side by side never
  # read as one template.
  defp article_cover(%{article: %{id: :booster_prices, cover: cover}} = assigns) do
    assigns = assign(assigns, cover: cover)

    ~H"""
    <div class="home-article-cover home-cover-leaflet" aria-hidden="true">
      <p :if={@cover.cheapest} class="home-cover-price">
        <span>{gettext("od")}</span>
        <strong>{Format.price(@cover.cheapest.verdict.cheapest.price)}</strong>
      </p>
      <%!-- Drawn foil packs: shop photos of packs vary too much to stand side by side. --%>
      <div class="home-cover-packs">
        <.foil_pack :for={hue <- [25, 200, 300]} hue={hue} />
      </div>
    </div>
    """
  end

  defp article_cover(%{article: %{id: :expensive_cards, cover: cover}} = assigns) do
    assigns = assign(assigns, cover: cover)

    ~H"""
    <div class="home-article-cover home-cover-showcase" aria-hidden="true">
      <p class="home-cover-record">{CardRecords.usd(@cover.record.usd)}</p>
      <div class="home-cover-cards">
        <img :for={src <- @cover.today} src={src} alt="" loading="lazy" class="home-cover-behind" />
        <img
          :if={@cover.record_image}
          src={@cover.record_image}
          alt=""
          loading="lazy"
          class="home-cover-front"
        />
      </div>
    </div>
    """
  end

  defp article_cover(%{article: %{id: :card_value, cover: cover}} = assigns) do
    assigns = assign(assigns, cover: cover)

    ~H"""
    <div class="home-article-cover home-cover-spread" aria-hidden="true">
      <p :if={@cover.spread} class="home-cover-half">
        <strong>{gettext("nawet %{price}", price: Format.whole_price(@cover.spread.max))}</strong>
        <span>{gettext("tyle kosztuje najdroższa karta w sklepach")}</span>
      </p>
      <ol :if={@cover.bars} class="home-cover-bars">
        <li
          :for={bar <- @cover.bars}
          class={bar.dearest? && "home-cover-bar-lit"}
          style={"--height: #{bar.height}%"}
        >
        </li>
      </ol>
      <p :if={@cover.spread} class="home-cover-axis">
        <span>{Format.whole_price(0)}</span><span>{Format.whole_price(1000)}+</span>
      </p>
      <%!-- Your card: somewhere on this spread. --%>
      <span class="home-cover-mystery">?</span>
    </div>
    """
  end

  attr :hue, :integer, required: true

  # A booster pack's shape: crimped top and bottom, holographic foil running
  # from its hue to the next ones, a shine and a sparkle.
  defp foil_pack(assigns) do
    ~H"""
    <svg class="home-cover-pack" viewBox="0 0 100 160">
      <defs>
        <linearGradient id={"home-foil-#{@hue}"} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color={"oklch(0.72 0.17 #{@hue})"} />
          <stop offset="0.5" stop-color={"oklch(0.82 0.14 #{@hue + 50})"} />
          <stop offset="1" stop-color={"oklch(0.6 0.19 #{@hue + 100})"} />
        </linearGradient>
      </defs>
      <path
        class="home-cover-pack-foil"
        fill={"url(#home-foil-#{@hue})"}
        d="M4 10 L10 4 L16 10 L22 4 L28 10 L34 4 L40 10 L46 4 L52 10 L58 4 L64 10 L70 4 L76 10 L82 4 L88 10 L94 4 L96 10 L96 150 L90 156 L84 150 L78 156 L72 150 L66 156 L60 150 L54 156 L48 150 L42 156 L36 150 L30 156 L24 150 L18 156 L12 150 L6 156 L4 150 Z"
      />
      <path class="home-cover-pack-shine" d="M22 10 L44 10 L12 150 L4 150 L4 80 Z" />
      <path
        class="home-cover-pack-sparkle"
        d="M50 44 C52 58 56 62 70 64 C56 66 52 70 50 84 C48 70 44 66 30 64 C44 62 48 58 50 44 Z"
      />
      <rect class="home-cover-pack-band" x="4" y="112" width="92" height="14" />
    </svg>
    """
  end

  defp retail({:retail, deal}), do: deal
  defp retail({:shop, _shop}), do: nil

  defp shop_name({:shop, shop}), do: Shops.name(shop)

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :href, :string, required: true
  attr :text, :string, required: true
  slot :fact

  # A list's door: the whole card leads to the list.
  defp door(assigns) do
    ~H"""
    <section id={@id} class="home-door" aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"}>
        <.link navigate={@href} class="home-door-link">{@title}&nbsp;→</.link>
      </h2>
      <p class="home-door-text">{@text}</p>
      <ul :if={@fact != []} class="home-door-facts">
        <li :for={fact <- @fact}>{render_slot(fact)}</li>
      </ul>
    </section>
    """
  end

  # A set's release day: still to come, or when it came out.
  defp release_line(released_on) do
    case Date.diff(released_on, Date.utc_today()) do
      days when days >= 0 -> gettext("premiera %{when}", when: Format.days_until(days))
      _past -> gettext("wydany %{date}", date: Format.date(released_on))
    end
  end
end
