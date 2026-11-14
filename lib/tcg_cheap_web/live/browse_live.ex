defmodule TcgCheapWeb.BrowseLive do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue with the cheapest Polish
  price and a verdict, searchable (`?q=`), filterable in a side panel by kind
  (`?rodzaj=`), language edition (`?wersja=`, English unless `wszystkie`
  or an expansion is chosen) and expansion, and paged with "Pokaż więcej".

  A chosen expansion's list is its set page (`/rozszerzenia/<name>-<id>`, the
  Cardmarket expansion id; `?rozszerzenie=<id>` leads there): the answer for
  the set on top, its products, and the set's pull rates and cards.

  The card list (`/karty`) is the same list of English single cards, with the
  expansion as a filter (`?rozszerzenie=<id>`).
  """

  use TcgCheapWeb, :live_view

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.BrowseLive.Banners
  import TcgCheapWeb.BrowseLive.Filters
  import TcgCheapWeb.ListingComponents
  import TcgCheapWeb.OfferComponents
  import TcgCheapWeb.SetComponents
  import TcgCheapWeb.SiteComponents

  alias TcgCheap.Sealed

  alias TcgCheap.Sealed.{CardGuide, Catalogue, Guide, Kinds}

  alias TcgCheapWeb.{Analytics, Format, Paths, Region, RegionText, SEO, VisitorLocation}

  @max_query_length 100
  # The most rows a returning visitor gets back at once: ten pages. The count
  # comes from the browser, so it is bounded here; further rows load on request.
  @max_restored_rows 300
  @kind_params Map.new(Kinds.choices(), &{Atom.to_string(&1), &1})

  defmodule NotFound do
    @moduledoc false
    defexception message: "expansion not found", plug_status: 404
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> VisitorLocation.assign_location()
     |> assign(
       all_expansions?: false,
       set_page: nil,
       market: nil,
       retail_deals: [],
       # A reconnect mounts the page again; its view was already counted.
       remount?: connected?(socket) and get_connect_params(socket)["_mounts"] != 0,
       list_restore: if(connected?(socket), do: get_connect_params(socket)["_guide_list"])
     )
     |> stream_configure(:products, dom_id: &"product-#{&1.product.slug}")
     |> stream_configure(:cards, dom_id: &"card-#{&1.card.id}")
     |> stream_configure(:cards_out, dom_id: &"card-out-#{&1.card.id}")
     |> stream(:cards_out, [])
     |> stream(:products, [])
     |> stream(:cards, [])}
  end

  @impl true
  def handle_params(params, uri, socket) do
    filters = parse_filters(socket.assigns.live_action, params)

    previous = socket.assigns[:filters]
    socket = socket |> list(filters) |> restore_list(uri)
    expansion = chosen_expansion(socket.assigns)
    socket = update(socket, :filters, &Map.put(&1, :expansion_name, expansion && expansion.name))

    # An expansion's list lives at its set page, under its current name.
    at_set_page? = expansion && params["slug"] == Catalogue.slug(expansion.name, expansion.id)

    case {socket.assigns.live_action, expansion, at_set_page?} do
      {:cards, expansion, _at_set_page?} ->
        market = singles_market(socket.assigns.region, expansion)
        seo = SEO.cards(params, market)

        # A chosen expansion's cards open with the same banner as its set page.
        {:noreply,
         socket
         |> assign(
           set_page: expansion && set_page(socket, expansion),
           market: market,
           seo: seo,
           page_title: seo.page_title
         )
         |> track_changes(previous)}

      {:expansion, nil, _at_set_page?} ->
        raise NotFound

      # The patch lands on the set page with the same expansion, so its view counts here.
      {_action, %{} = expansion, false} ->
        {:noreply,
         socket
         |> track_set_view(expansion, previous)
         |> push_patch(to: list_path(socket.assigns.filters, []), replace: true)}

      {:expansion, expansion, true} ->
        set_page = set_page(socket, expansion)
        seo = SEO.expansion(params, expansion, set_page)

        {:noreply,
         socket
         |> assign(set_page: set_page, market: nil, seo: seo, page_title: seo.page_title)
         |> track_set_view(expansion, previous)
         |> track_changes(previous)}

      {:index, nil, _at_set_page?} ->
        seo = SEO.home(params)

        {:noreply,
         socket
         |> assign(
           set_page: nil,
           market: polish_only(socket, &Guide.sealed_market/0),
           retail_deals: polish_only(socket, [], fn -> newest_retail_deals(Date.utc_today()) end),
           seo: seo,
           page_title: seo.page_title
         )
         |> track_changes(previous)}
    end
  end

  defp parse_filters(action, params) do
    mode = if action == :cards, do: :cards, else: :products
    expansion = expansion_param(action, params)

    %{
      mode: mode,
      query: params |> query_param() |> String.trim() |> String.slice(0, @max_query_length),
      kind: if(mode == :products, do: Map.get(@kind_params, params["rodzaj"])),
      expansion: expansion,
      region: if(mode == :products, do: region_param(params["wersja"], expansion))
    }
  end

  defp chosen_expansion(%{filters: %{expansion: id}, facets: facets}),
    do: id && (Enum.find(facets.expansions, &(&1.id == id)) || catalogue_expansion(id))

  defp catalogue_expansion(id) do
    if name = Map.get(Guide.expansion_names([id]), id),
      do: %{id: id, name: name, count: 0, logo_url: nil}
  end

  # Without a chosen expansion, the card list opens with the whole guide's
  # singles, which only the Polish market has.
  defp singles_market(region, nil),
    do: if(Region.poland?(region), do: Guide.singles_market())

  defp singles_market(_region, _expansion), do: nil

  # The banners read Polish shops' singles and sealed deals and the Polish
  # chains' leaflets, in złoty: other regions have none.
  defp polish_only(socket, none \\ nil, read),
    do: if(Region.poland?(socket.assigns.region), do: read.(), else: none)

  # The set's booster, pull rates and cards change only with the expansion.
  defp set_page(%{assigns: %{set_page: %{id: id} = page}}, %{id: id}), do: page

  defp set_page(socket, %{id: id, name: name}),
    do:
      id
      |> Guide.expansion(name, DateTime.utc_now(), socket.assigns.region.market)
      |> Map.put(:id, id)

  defp query_param(%{"q" => query}) when is_binary(query), do: query
  defp query_param(_params), do: ""

  # The set page's slug ends in the Cardmarket id; the list's `rozszerzenie`
  # is that id and leads to the set page.
  defp expansion_param(:expansion, %{"slug" => slug}), do: ok_or_nil(Paths.expansion_id(slug))

  defp expansion_param(_action, %{"rozszerzenie" => id}) when is_binary(id),
    do: ok_or_nil(Paths.expansion_id_param(id))

  defp expansion_param(_action, _params), do: nil

  defp ok_or_nil({:ok, id}), do: id
  defp ok_or_nil(:error), do: nil

  defp sealed_filters(filters), do: Map.take(filters, [:query, :kind, :region, :expansion])

  # The cards the same words find when products find none, often a Pokémon's
  # name typed into the products list. A chosen kind means a product was meant.
  defp card_matches(%{kind: nil, query: query, expansion: expansion}) when query != "",
    do: CardGuide.count(query, expansion)

  defp card_matches(_filters), do: 0

  # Without a search or an expansion, every visitor sees the same list.
  defp card_list(%{query: "", expansion: nil}), do: Guide.card_discovery()

  defp card_list(filters) do
    %{
      available: CardGuide.browse(Map.put(filters, :stock, :in), 0),
      expansions: CardGuide.expansion_facets(filters)
    }
  end

  defp list(socket, %{mode: :cards} = filters) do
    %{available: {available, more?, count}, expansions: expansions} = card_list(filters)
    {unavailable, out_more?, out_count} = CardGuide.browse(Map.put(filters, :stock, :out), 0)
    only_out? = count == 0
    rows = if only_out?, do: unavailable, else: available

    socket
    |> assign(
      filters: filters,
      facets: %{expansions: expansions, regions: [], kinds: []},
      card_matches: 0,
      form: to_form(%{"q" => filters.query}),
      result_count: count + out_count,
      cards_stock: if(only_out?, do: :out, else: :in),
      cards_main_count: if(only_out?, do: out_count, else: count),
      cards_out_count: if(only_out?, do: 0, else: out_count),
      cards_out_loaded: length(unavailable),
      cards_out_more?: out_more?,
      cards_out_open?: false,
      loaded: length(rows),
      more?: if(only_out?, do: out_more?, else: more?),
      priority_product_id: nil
    )
    |> stream(:products, [], reset: true)
    |> stream(:cards, rows, reset: true)
    |> stream(:cards_out, if(only_out?, do: [], else: unavailable), reset: true)
  end

  defp list(socket, filters) do
    {summaries, more?, count} =
      Guide.browse(sealed_filters(filters), 0, DateTime.utc_now(), socket.assigns.region.market)

    first_summary = List.first(summaries)

    socket
    |> assign(:filters, filters)
    |> assign(:facets, Guide.facets(sealed_filters(filters)))
    |> assign(:form, to_form(%{"q" => filters.query}))
    |> assign(:cards_out_count, 0)
    |> assign(:result_count, count)
    |> assign(:card_matches, if(count == 0, do: card_matches(filters), else: 0))
    |> assign(:loaded, length(summaries))
    |> assign(:more?, more?)
    |> assign(:priority_product_id, first_summary && first_summary.product.id)
    |> stream(:cards_out, [], reset: true)
    |> stream(:cards, [], reset: true)
    |> stream(:products, summaries, reset: true)
  end

  # Per-history-entry presentation state complements the URL's query/filters.
  # Restore only on a fresh mount of that exact URL, before LiveView restores
  # scroll. Refetch the rows so prices stay current.
  defp restore_list(
         %{assigns: %{list_restore: %{"url" => url, "open" => open} = saved}} = socket,
         uri
       )
       when is_binary(url) and is_list(open) do
    parsed = URI.parse(uri)
    path = parsed.path <> if(parsed.query in [nil, ""], do: "", else: "?" <> parsed.query)
    socket = assign(socket, :list_restore, nil)

    if path == url do
      socket
      |> restore_rows(saved["loaded"], :loaded, :more?, &load_more/1)
      |> restore_rows(saved["outLoaded"], :cards_out_loaded, :cards_out_more?, &load_more_out/1)
      |> assign(:cards_out_open?, "guide-cards-out" in open)
    else
      socket
    end
  end

  defp restore_list(socket, _uri), do: socket

  defp restore_rows(socket, count, loaded, more?, load) when is_integer(count) and count > 0 do
    limit = min(count, @max_restored_rows)

    if socket.assigns[more?] && socket.assigns[loaded] < limit,
      do: restore_rows(load.(socket), count, loaded, more?, load),
      else: socket
  end

  defp restore_rows(socket, _count, _loaded, _more?, _load), do: socket

  # Once per set page visit: on arrival, or when another set is chosen.
  defp track_set_view(%{assigns: %{remount?: true}} = socket, _expansion, nil), do: socket

  defp track_set_view(socket, %{id: id}, %{expansion: id}), do: socket

  defp track_set_view(socket, expansion, _previous),
    do:
      Analytics.track(socket, "expansion_viewed", %{
        expansion: expansion.id,
        expansion_name: expansion.name
      })

  # Only changes made on the page: the first render arrives with its pageview,
  # whose URL already holds the query and filters.
  defp track_changes(socket, nil), do: socket

  # Switching between products and cards also resets the other list's filters.
  defp track_changes(%{assigns: %{filters: %{mode: mode}}} = socket, %{mode: previous})
       when mode != previous,
       do: Analytics.track(socket, "mode_changed", list_properties(socket))

  defp track_changes(%{assigns: %{filters: filters}} = socket, previous) do
    changed =
      Enum.filter([:kind, :region, :expansion], &(Map.get(previous, &1) != Map.get(filters, &1)))

    socket
    |> track_search(previous.query, filters.query)
    |> track_filters(changed)
  end

  defp track_search(socket, query, query), do: socket

  defp track_search(socket, _previous, ""),
    do: Analytics.track(socket, "search_cleared", list_properties(socket))

  defp track_search(socket, _previous, _query),
    do: Analytics.track(socket, "search_performed", list_properties(socket))

  defp track_filters(socket, []), do: socket

  # Cleared means no filter is left, however many were removed.
  defp track_filters(%{assigns: %{filters: filters}} = socket, changed) do
    if filtered?(filters) do
      Enum.reduce(changed, socket, fn filter, socket ->
        properties = Map.merge(list_properties(socket), %{filter: filter, value: filters[filter]})
        Analytics.track(socket, "filter_changed", properties)
      end)
    else
      Analytics.track(socket, "filters_cleared", list_properties(socket))
    end
  end

  defp list_properties(%{assigns: assigns}) do
    %{filters: filters, facets: facets} = assigns

    %{
      mode: filters.mode,
      query: filters.query,
      kind: filters.kind,
      region: filters.region,
      expansion: filters.expansion,
      expansion_name:
        Enum.find_value(facets.expansions, &(&1.id == filters.expansion && &1.name)),
      result_count: assigns.result_count
    }
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) when is_binary(query) do
    query = query |> String.trim() |> String.slice(0, @max_query_length)

    {:noreply,
     push_patch(socket, to: list_path(socket.assigns.filters, query: query), replace: true)}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  def handle_event("more", _params, %{assigns: %{more?: true}} = socket) do
    socket = load_more(socket)

    case socket.assigns do
      %{filters: %{mode: :products}, loaded: loaded} ->
        properties = Map.put(list_properties(socket), :loaded, loaded)
        {:noreply, Analytics.track(socket, "more_products_loaded", properties)}

      %{filters: %{mode: :cards}, loaded: loaded, cards_stock: stock} ->
        {:noreply, track_more_cards(socket, stock, loaded)}
    end
  end

  def handle_event("more", _params, socket), do: {:noreply, socket}

  def handle_event("more_out", _params, %{assigns: %{cards_out_more?: true}} = socket) do
    socket = load_more_out(socket)
    {:noreply, track_more_cards(socket, :out, socket.assigns.cards_out_loaded)}
  end

  def handle_event("all-expansions", _params, socket),
    do: {:noreply, assign(socket, :all_expansions?, true)}

  def handle_event("location-" <> _ = event, params, socket) do
    {:noreply, VisitorLocation.handle_event(event, params, socket)}
  end

  defp track_more_cards(socket, stock, loaded) do
    properties = Map.merge(list_properties(socket), %{stock: stock, loaded: loaded})
    Analytics.track(socket, "more_cards_loaded", properties)
  end

  defp load_more(%{assigns: %{filters: %{mode: :cards} = filters}} = socket) do
    {rows, more?, _count} =
      CardGuide.browse(
        Map.put(filters, :stock, socket.assigns.cards_stock),
        socket.assigns.loaded
      )

    socket
    |> assign(loaded: socket.assigns.loaded + length(rows), more?: more?)
    |> stream(:cards, rows)
  end

  defp load_more(%{assigns: %{filters: filters, loaded: loaded}} = socket) do
    {rows, more?, _count} =
      Guide.browse(
        sealed_filters(filters),
        loaded,
        DateTime.utc_now(),
        socket.assigns.region.market
      )

    socket
    |> assign(loaded: loaded + length(rows), more?: more?)
    |> stream(:products, rows)
  end

  defp load_more_out(socket) do
    {rows, more?, _count} =
      CardGuide.browse(
        Map.put(socket.assigns.filters, :stock, :out),
        socket.assigns.cards_out_loaded
      )

    socket
    |> assign(
      cards_out_open?: true,
      cards_out_loaded: socket.assigns.cards_out_loaded + length(rows),
      cards_out_more?: more?
    )
    |> stream(:cards_out, rows)
  end

  defp result_label(count, :cards), do: Format.cards(count)

  defp result_label(count, :products),
    do: Format.products(count)

  # The newest chain deals first: the home page reports them as news.
  defp newest_retail_deals(today) do
    today
    |> Sealed.list_current_retail_deals!()
    |> Enum.sort_by(& &1.starts_on, {:desc, Date})
    |> Enum.take(3)
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
            :if={Region.poland?(@region)}
            location={@location}
            ready={@location_ready?}
            form={@town_form}
            matches={@town_matches}
            error={@location_error}
          />
        </.site_header>
        <main id="guide-main" class="guide-main" data-guide-url={@current_path}>
          <%= cond do %>
            <% @set_page && @filters.mode == :cards -> %>
              <.set_intro
                name={@filters.expansion_name}
                page={@set_page}
                close={list_path(@filters, expansion: nil, expansion_name: nil)}
                cards_href="#guide-results-title"
                singles?={true}
                polish?={Region.poland?(@region)}
              />
            <% @set_page -> %>
              <.set_intro
                name={@filters.expansion_name}
                page={@set_page}
                close={Paths.home()}
                polish?={Region.poland?(@region)}
              />
            <% true -> %>
              <.site_intro filters={@filters} market={@market} />
              <.retail_news
                :if={@filters.mode == :products and Region.poland?(@region)}
                deals={@retail_deals}
              />
          <% end %>
          <section class="guide-search" aria-labelledby="guide-search-title">
            <h2 id="guide-search-title" class="sr-only">
              {if(@filters.mode == :cards,
                do: gettext("Szukaj karty"),
                else: gettext("Szukaj produktu")
              )}
            </h2>
            <.form
              for={@form}
              id="guide-search-form"
              action={base_path(@filters)}
              method="get"
              phx-change="search"
              phx-submit="search"
            >
              <label for="guide-search-query" class="guide-search-label">{if(@filters.mode == :cards,
                do: gettext("Szukaj karty"),
                else: gettext("Szukaj produktu")
              )}</label>
              <div class="guide-search-field">
                <.fluent_icon name={:search} class="guide-search-icon" />
                <.input
                  field={@form[:q]}
                  type="text"
                  id="guide-search-query"
                  class="guide-search-input"
                  maxlength="100"
                  autocomplete="off"
                  phx-debounce="300"
                  placeholder={
                    if(@filters.mode == :cards, do: gettext("np. Pikachu"), else: gettext("np. ETB"))
                  }
                />
              </div>
              <input
                :if={@filters.mode == :cards and @filters.expansion}
                type="hidden"
                name="rozszerzenie"
                value={@filters.expansion}
              />
              <input :if={@filters.kind} type="hidden" name="rodzaj" value={@filters.kind} />
              <input
                :if={region_value(@filters)}
                type="hidden"
                name="wersja"
                value={region_value(@filters)}
              />
            </.form>
            <nav id="guide-mode" class="guide-mode" aria-label={gettext("Szukaj w katalogu")}>
              <%= if @filters.mode == :products do %>
                <.kind_menu filters={@filters} facets={@facets} />
              <% else %>
                <.link
                  id="mode-products"
                  patch={
                    list_path(@filters,
                      mode: :products,
                      kind: nil,
                      region: default_region(@filters.expansion)
                    )
                  }
                >{gettext("Produkty")}</.link>
              <% end %>
              <.link
                id="mode-cards"
                patch={list_path(@filters, mode: :cards, kind: nil, region: nil)}
                aria-current={if(@filters.mode == :cards, do: "true")}
              >{gettext("Karty")}</.link>
            </nav>
          </section>

          <div class="guide-browse">
            <.set_column filters={@filters} facets={@facets} all_expansions?={@all_expansions?} />
            <section class="guide-results" aria-labelledby="guide-results-title">
              <div class="guide-results-heading">
                <h2 id="guide-results-title" tabindex="-1">
                  {gettext("Wyniki")}
                </h2>
                <p id="guide-result-count" aria-live="polite">
                  {result_label(@result_count, @filters.mode)}
                </p>
              </div>
              <p
                :if={@filters.mode == :products && RegionText.list_prices_note()}
                id="guide-prices-note"
                class="guide-note guide-prices-note"
              >
                {RegionText.list_prices_note()}
              </p>
              <ul
                id="guide-products"
                class="guide-products"
                phx-update="stream"
                data-track-positions
              >
                <li id="guide-products-empty" class="guide-empty hidden only:block">
                  <%= if @filters.mode == :cards do %>
                    {gettext("Nie znaleźliśmy takiej karty. Wpisz angielską nazwę, np. Pikachu.")}
                  <% else %>
                    {gettext("Nic nie znaleźliśmy.")}
                    <.link
                      :if={@card_matches > 0}
                      id="guide-empty-cards"
                      patch={list_path(@filters, mode: :cards, kind: nil, region: nil)}
                    >{gettext("Pokaż pasujące karty: %{count}", count: @card_matches)}</.link>
                  <% end %>
                  <.link
                    id="guide-empty-reset"
                    patch={
                      list_path(@filters,
                        query: "",
                        expansion: nil,
                        expansion_name: nil,
                        kind: nil,
                        region: default_region(nil)
                      )
                    }
                  >{if(@filters.mode == :cards,
                    do: gettext("Pokaż wszystkie karty"),
                    else: gettext("Pokaż wszystkie produkty")
                  )}</.link>
                </li>
                <li :for={{dom_id, summary} <- @streams.products} id={dom_id} class="guide-product">
                  <.product_row
                    summary={summary}
                    priority={summary.product.id == @priority_product_id}
                    delivery_noted?={RegionText.list_prices_note() != nil}
                  />
                </li>
                <.card_row :for={{dom_id, row} <- @streams.cards} id={dom_id} row={row} />
              </ul>
              <div :if={@more?} class="guide-more">
                <button
                  id="guide-more"
                  type="button"
                  phx-click="more"
                  phx-disable-with={gettext("Wczytuję…")}
                >
                  {gettext("Pokaż więcej")}
                </button>
                <p>
                  {gettext("Pokazano %{loaded} z %{count}.",
                    loaded: Format.number(@loaded),
                    count:
                      Format.number(
                        if(@filters.mode == :cards, do: @cards_main_count, else: @result_count)
                      )
                  )}
                </p>
              </div>
              <.offers_disclosure
                :if={@cards_out_count > 0}
                id="guide-cards-out"
                open={@cards_out_open?}
                label={gettext("Bez towaru: %{cards}", cards: result_label(@cards_out_count, :cards))}
              >
                <ul id="guide-cards-out-list" class="guide-products" phx-update="stream">
                  <.card_row :for={{dom_id, row} <- @streams.cards_out} id={dom_id} row={row} />
                </ul>
                <div :if={@cards_out_more?} class="guide-more">
                  <button
                    id="guide-more-out"
                    type="button"
                    phx-click="more_out"
                    phx-disable-with={gettext("Wczytuję…")}
                  >{gettext("Pokaż więcej")}</button>
                  <p>
                    {gettext("Pokazano %{loaded} z %{count}.",
                      loaded: Format.number(@cards_out_loaded),
                      count: Format.number(@cards_out_count)
                    )}
                  </p>
                </div>
              </.offers_disclosure>
              <div
                :if={@filters.mode == :products && @set_page && @set_page.set}
                id="set-content"
                class="guide-set"
              >
                <.pull_rates
                  pull_rates={@set_page.set.pull_rates}
                  standard_pack_size={@set_page.set.standard_pack_size}
                />
                <.set_cards
                  rarities={@set_page.set.rarities}
                  cards_source_url={@set_page.set.cards_source_url}
                  priced_on={@set_page.set.priced_on}
                  logo_url={@set_page.set.logo_url}
                />
              </div>
            </section>
          </div>
        </main>
        <.site_footer sets={@footer_sets} />
      </div>
    </Layouts.app>
    """
  end
end
