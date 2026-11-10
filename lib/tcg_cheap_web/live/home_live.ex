defmodule TcgCheapWeb.HomeLive do
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

  import TcgCheapWeb.GuideComponents
  import TcgCheapWeb.SetComponents

  alias TcgCheap.Sealed

  alias TcgCheap.Sealed.{CardGuide, CardImage, Catalogue, Guide, Kinds, Rarities, Regions}

  alias TcgCheapWeb.{Analytics, Polish, SEO, VisitorLocation}

  @max_query_length 100
  @kind_params Map.new(Kinds.choices(), &{Atom.to_string(&1), &1})
  @region_params Map.new(Regions.all(), &{Atom.to_string(&1), &1})
  @all_regions "wszystkie"
  # Sets shown before "Pozostałe sety".
  @first_expansions 14

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
        market = singles_market(expansion)
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
           market: Guide.sealed_market(),
           retail_deals: newest_retail_deals(Date.utc_today()),
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

  # Without a chosen expansion, the card list opens with the whole guide's singles.
  defp singles_market(nil), do: Guide.singles_market()
  defp singles_market(_expansion), do: nil

  # The set's booster, pull rates and cards change only with the expansion.
  defp set_page(%{assigns: %{set_page: %{id: id} = page}}, %{id: id}), do: page

  defp set_page(_socket, %{id: id, name: name}),
    do: id |> Guide.expansion(name, DateTime.utc_now()) |> Map.put(:id, id)

  defp query_param(%{"q" => query}) when is_binary(query), do: query
  defp query_param(_params), do: ""

  # The set page's slug ends in the Cardmarket id; the list's `rozszerzenie`
  # is that id and leads to the set page.
  defp expansion_param(:expansion, %{"slug" => slug}) do
    case Regex.run(~r/-(\d+)\z/, slug) do
      [_, id] -> expansion_id(id)
      nil -> nil
    end
  end

  defp expansion_param(_action, %{"rozszerzenie" => id}) when is_binary(id), do: expansion_id(id)
  defp expansion_param(_action, _params), do: nil

  defp expansion_id(value) do
    case Integer.parse(value) do
      {id, ""} when id in 1..9_999_999 -> id
      _ -> nil
    end
  end

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
    {summaries, more?, count} = Guide.browse(sealed_filters(filters), 0, DateTime.utc_now())
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
    if socket.assigns[more?] && socket.assigns[loaded] < count,
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
    {rows, more?, _count} = Guide.browse(sealed_filters(filters), loaded, DateTime.utc_now())

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

  defp region_param(@all_regions, _expansion), do: nil

  defp region_param(param, expansion),
    do: Map.get(@region_params, param, default_region(expansion))

  # Most buyers want English products; an expansion has its own language, so
  # a link to one (e.g. a Japanese set) shows it whatever the edition.
  defp default_region(nil), do: :en
  defp default_region(_expansion), do: nil

  # The `wersja` of a list: none for the default edition.
  defp region_value(%{mode: :cards}), do: nil

  defp region_value(%{region: region, expansion: expansion}) do
    cond do
      region == default_region(expansion) -> nil
      is_nil(region) -> @all_regions
      true -> region
    end
  end

  # The list with some filters changed: a chosen expansion's at its set page.
  # The language links offered under a chosen expansion are only its own, so
  # the expansion can stay.
  defp list_path(filters, changes) do
    filters = Map.merge(filters, Map.new(changes))

    params =
      [
        q: filters.query,
        rodzaj: filters.kind,
        wersja: region_value(filters),
        rozszerzenie: if(filters.mode == :cards, do: filters.expansion)
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map(fn {key, value} -> {key, to_string(value)} end)

    base_path(filters) <> if(params == [], do: "", else: "?" <> URI.encode_query(params))
  end

  defp base_path(%{mode: :cards}), do: ~p"/karty"

  defp base_path(%{expansion: id, expansion_name: name}) when is_integer(id) and is_binary(name),
    do: SEO.expansion_path(id, name)

  defp base_path(_filters), do: ~p"/"

  defp filtered?(filters), do: filters.kind || region_value(filters) || filters.expansion

  defp result_label(count, :cards), do: Polish.plural(count, "karta", "karty", "kart")

  defp result_label(count, :products),
    do: Polish.plural(count, "produkt", "produkty", "produktów")

  attr :filters, :map, required: true
  attr :facets, :map, required: true

  # The products tab is also the kind menu: shelves, the chosen shelf's exact
  # kinds and the language edition. A badge counts the chosen kind and edition.
  defp kind_menu(assigns) do
    counts = Map.new(assigns.facets.kinds)
    shelf = assigns.filters.kind && (Kinds.shelf(assigns.filters.kind) || assigns.filters.kind)

    assigns =
      assign(assigns,
        shelves:
          for(shelf <- Kinds.shelves(), count = shelf_count(counts, shelf), do: {shelf, count}),
        exact:
          if(shelf,
            do:
              for(
                kind <- Kinds.members(shelf),
                Map.has_key?(counts, kind),
                do: {kind, counts[kind]}
              ),
            else: []
          ),
        total: counts |> Map.values() |> Enum.sum(),
        chosen: Enum.count([assigns.filters.kind, region_value(assigns.filters)], & &1)
      )

    ~H"""
    <details
      id="guide-kind-menu"
      class="guide-pop guide-kind-menu"
      name="guide-pop"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary
        id="mode-products"
        aria-current="true"
        data-track="filters_panel_opened"
        phx-click={JS.dispatch("guide:pin-filters", to: "#guide-search-form")}
      >
        {gettext("Produkty")}
        <.fluent_icon name={:chevron_down} class="guide-pop-chevron" />
        <span :if={@chosen > 0} class="guide-chosen">
          {@chosen}<span class="sr-only">{ngettext(" filtr", " filtry", @chosen)}</span>
        </span>
      </summary>
      <div class="guide-panel guide-filter">
        <nav id="guide-kinds" aria-labelledby="guide-kinds-title">
          <h2 id="guide-kinds-title">{gettext("Rodzaj")}</h2>
          <ul>
            <li>
              <.link
                id="kind-all"
                patch={list_path(@filters, kind: nil)}
                phx-click={close_menus()}
                aria-current={if(is_nil(@filters.kind), do: "true")}
              >
                {gettext("Wszystkie")}<span class="guide-filter-count">{Polish.number(@total)}</span>
              </.link>
            </li>
            <li :for={{shelf, count} <- @shelves}>
              <.link
                id={"kind-#{shelf}"}
                patch={list_path(@filters, kind: shelf)}
                phx-click={close_menus()}
                aria-current={if(@filters.kind == shelf, do: "true")}
              >
                {Kinds.label(shelf)}<span class="guide-filter-count">{Polish.number(count)}</span>
              </.link>
            </li>
          </ul>
          <ul :if={length(@exact) > 1} class="guide-kinds-exact">
            <li :for={{kind, count} <- @exact}>
              <.link
                id={"kind-#{kind}"}
                patch={list_path(@filters, kind: kind)}
                phx-click={close_menus()}
                aria-current={if(@filters.kind == kind, do: "true")}
              >
                {Kinds.label(kind)}<span class="guide-filter-count">{Polish.number(count)}</span>
              </.link>
            </li>
          </ul>
        </nav>
        <nav id="guide-regions" aria-labelledby="guide-regions-title">
          <h2 id="guide-regions-title">{gettext("Wersja językowa")}</h2>
          <ul>
            <li>
              <.link
                id="region-all"
                patch={list_path(@filters, region: nil)}
                phx-click={close_menus()}
                aria-current={if(is_nil(@filters.region), do: "true")}
              >{gettext("Wszystkie")}</.link>
            </li>
            <li :for={{region, _count} <- @facets.regions}>
              <.link
                id={"region-#{region}"}
                patch={list_path(@filters, region: region)}
                phx-click={close_menus()}
                aria-current={if(@filters.region == region, do: "true")}
              >
                {Regions.label(region)}
              </.link>
            </li>
          </ul>
        </nav>
      </div>
    </details>
    """
  end

  defp shelf_count(counts, shelf) do
    case shelf |> Kinds.members() |> Enum.map(&counts[&1]) |> Enum.reject(&is_nil/1) do
      [] -> nil
      found -> Enum.sum(found)
    end
  end

  attr :filters, :map, required: true
  attr :facets, :map, required: true
  attr :all_expansions?, :boolean, required: true

  # The sets, English ones first (`TcgCheap.Sealed.Guide.facets/1`): beside
  # the list on a wide screen, a shelf above it on a narrow one.
  defp set_column(assigns) do
    {first, rest} = split_expansions(assigns.facets.expansions, assigns.filters.expansion)

    assigns = assign(assigns, first: first, rest: rest)

    ~H"""
    <aside id="guide-filters" class="guide-filters" aria-label={gettext("Sety")}>
      <nav
        :if={@facets.expansions != []}
        id="guide-expansions"
        class="guide-filter guide-expansions"
        aria-labelledby="guide-expansions-title"
      >
        <h2 id="guide-expansions-title">{gettext("Sety")}</h2>
        <.expansions_all filters={@filters} />
        <ul class="guide-expansion-names guide-expansion-shelf">
          <.expansion_option :for={expansion <- @first} expansion={expansion} filters={@filters} />
        </ul>
        <.expansions_rest rest={@rest} filters={@filters} all_expansions?={@all_expansions?} />
      </nav>
    </aside>
    """
  end

  # The chosen expansion leads, so it stays in view among the first ones.
  defp split_expansions(expansions, chosen) do
    expansions
    |> Enum.sort_by(&(&1.id != chosen))
    |> Enum.split(@first_expansions)
  end

  attr :filters, :map, required: true

  defp expansions_all(assigns) do
    ~H"""
    <.link
      class="guide-expansions-all"
      patch={
        list_path(@filters,
          expansion: nil,
          expansion_name: nil,
          region:
            if(@filters.expansion,
              do: @filters.region || default_region(nil),
              else: @filters.region
            )
        )
      }
      phx-click={close_menus()}
      aria-current={if(is_nil(@filters.expansion), do: "true")}
    >{gettext("Wszystkie sety")}</.link>
    """
  end

  attr :rest, :list, required: true
  attr :filters, :map, required: true
  attr :all_expansions?, :boolean, required: true

  defp expansions_rest(assigns) do
    ~H"""
    <details
      :if={@rest != []}
      class="guide-expansions-more"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <%!-- Rendered on first opening: hundreds of rows (noindex filter links)
           would otherwise weigh down every page load and patch. --%>
      <summary phx-click={!@all_expansions? && "all-expansions"}>
        {gettext("Pozostałe sety (%{count})", count: length(@rest))}
      </summary>
      <ul :if={@all_expansions?} class="guide-expansion-names">
        <.expansion_option :for={expansion <- @rest} expansion={expansion} filters={@filters} />
      </ul>
    </details>
    """
  end

  defp close_menus, do: JS.remove_attribute("open", to: ".guide-pop")

  attr :expansion, :map, required: true
  attr :filters, :map, required: true

  # The language tag shows only while every language is listed. A row without
  # a logo keeps a blank slot so the names line up.
  defp expansion_option(assigns) do
    assigns = assign(assigns, :logo_url, assigns.expansion.logo_url)

    ~H"""
    <li>
      <.link
        id={"expansion-#{@expansion.id}"}
        patch={
          list_path(@filters,
            expansion: @expansion.id,
            expansion_name: @expansion.name,
            region: default_region(@expansion.id)
          )
        }
        phx-click={close_menus()}
        aria-current={if(@filters.expansion == @expansion.id, do: "true")}
        title={@expansion.name}
      >
        <img :if={@logo_url} src={@logo_url} alt="" loading="lazy" />
        <span :if={is_nil(@logo_url)} class="guide-expansion-nologo" aria-hidden="true"></span>
        <span class="guide-expansion-name">
          {@expansion.name}
        </span>
        <span class="guide-filter-count">
          <span
            :if={is_nil(@filters.region) and @expansion.region != :en}
            class="guide-expansion-region"
          >
            {Regions.tag(@expansion.region)}
          </span>
          {Polish.number(@expansion.count)}
        </span>
      </.link>
    </li>
    """
  end

  attr :name, :string, required: true
  attr :logo_url, :string, default: nil
  attr :close, :string, required: true

  # The set's logo carries its name, so the name is only visible without one;
  # with a logo it stays in the heading's text for screen readers and search.
  defp set_title(assigns) do
    ~H"""
    <div class="set-title">
      <h1 id="guide-title">
        <img :if={@logo_url} src={@logo_url} alt="" class="set-logo" />
        <span :if={@logo_url} class="sr-only">{@name}</span>
        <%= if !@logo_url do %>
          {@name}
        <% end %>
      </h1>
      <.link
        id="set-close"
        patch={@close}
        class="set-close"
        aria-label={gettext("Zamknij set i wyczyść filtry")}
      >
        <.fluent_icon name={:dismiss} />
      </.link>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :page, :map, required: true
  attr :close, :string, default: "/"
  attr :cards_href, :string, default: "#product-cards"
  attr :singles?, :boolean, default: false

  # A set page's top: the set's most valuable card, what pulling it from packs
  # costs on average against buying it, and the next three cards the same way;
  # a set without card prices shows its single booster instead.
  defp set_intro(assigns) do
    set = assigns.page.set

    assigns =
      assign(assigns,
        logo_url: set && set.logo_url,
        top_cards: if(set, do: set.top_cards, else: []),
        card_count: if(set, do: set.card_count, else: 0)
      )

    ~H"""
    <section id="set-intro" class="guide-intro set-intro" aria-labelledby="guide-title">
      <.set_title name={@name} logo_url={@logo_url} close={@close} />
      <%= cond do %>
        <% @singles? -> %>
          <.set_singles
            singles={@page.set && @page.set.singles}
            top={List.first(@top_cards)}
            cards_href={@cards_href}
          />
        <% @top_cards != [] -> %>
          <.set_chase
            top={hd(@top_cards)}
            next={tl(@top_cards)}
            booster={@page.booster}
            count={@card_count}
            cards_href={@cards_href}
          />
        <% @page.booster -> %>
          <.set_booster
            booster={@page.booster}
            set={@page.set}
            cardmarket={@page.cardmarket}
            count={@card_count}
            cards_href={@cards_href}
          />
        <% true -> %>
          <%= if @card_count > 0 do %>
            <div id="set-chase" class="set-chase set-chase-empty">
              <.chase_foot count={@card_count} priced?={false} href={@cards_href} />
            </div>
          <% else %>
            <p id="guide-promise">{Enum.join(SEO.expansion_answer(@name, @page), " ")}</p>
          <% end %>
      <% end %>
    </section>
    """
  end

  attr :filters, :map, required: true
  attr :market, :map, required: true

  # The list without an expansion opens like a set page: our title and promise
  # where the set's logo goes, then the whole guide's numbers for singles or
  # sealed products, so choosing a set swaps the content, not the layout.
  defp site_intro(assigns) do
    ~H"""
    <section id="set-intro" class="guide-intro set-intro" aria-labelledby="guide-title">
      <div class="set-title site-title">
        <div class="site-title-text">
          <%!-- The card list's own question, as the products list asks its own. --%>
          <h1 id="guide-title">
            {if(@filters.mode == :cards,
              do: gettext("Ile kosztuje ta karta?"),
              else: gettext("Czy to dobra cena?")
            )}
          </h1>
          <p id="guide-promise">
            {if(@filters.mode == :cards,
              do: gettext("Najtańsze karty Pokémon TCG w sklepach wysyłających do Polski."),
              else: gettext("Najtańsze oferty Pokémon TCG w sklepach wysyłających do Polski.")
            )}
          </p>
        </div>
      </div>
      <%= if @filters.mode == :cards do %>
        <.set_singles
          singles={@market}
          top={@market.top}
          cards_href="#guide-results-title"
          all?={true}
        />
      <% else %>
        <.sealed_market market={@market} />
      <% end %>
    </section>
    """
  end

  # The newest chain deals first: the home page reports them as news.
  defp newest_retail_deals(today) do
    today
    |> Sealed.list_current_retail_deals!()
    |> Enum.sort_by(& &1.starts_on, {:desc, Date})
    |> Enum.take(3)
  end

  attr :deals, :list, required: true

  # Retail chains' prices running today, announced as news under the banner;
  # the booster price page lists them all. Without one, a link to that page.
  defp retail_news(%{deals: []} = assigns) do
    ~H"""
    <p id="home-booster-prices" class="reference-link">
      <.link navigate={~p"/ile-kosztuje-booster-pokemon"}>{gettext(
        "Ile kosztuje booster? Ceny boosterów"
      )}&nbsp;→</.link>
    </p>
    """
  end

  defp retail_news(assigns) do
    ~H"""
    <section id="home-booster-prices" aria-labelledby="home-retail-news-title">
      <div class="retail-news-head">
        <h2 id="home-retail-news-title">{gettext("Okazje w sieciówkach")}</h2>
        <.link navigate={~p"/ile-kosztuje-booster-pokemon"}>{gettext("Wszystkie ceny boosterów")}&nbsp;→</.link>
      </div>
      <.retail_clips id="home-retail-deal" deals={@deals} products? />
    </section>
    """
  end

  attr :market, :map, required: true

  # The sealed banner: the product a Polish shop sells furthest under the
  # typical shop price today, then the product market in numbers.
  defp sealed_market(assigns) do
    ~H"""
    <div id="set-chase" class={["set-chase", !@market.deal && "set-chase-empty"]}>
      <%= if deal = @market.deal do %>
        <%!-- One product: what it holds above, the box itself below, in a card's shape. --%>
        <.link
          class="set-chase-art set-chase-products"
          navigate={~p"/produkty/#{deal.product.slug}"}
          tabindex="-1"
          aria-hidden="true"
        >
          <span :if={deal.contents_photos != []} class="set-chase-contents">
            <img :for={photo <- deal.contents_photos} src={photo} alt="" loading="eager" />
          </span>
          <img
            :if={deal.product.stored_photo_card_url}
            src={deal.product.stored_photo_card_url}
            alt=""
            loading="eager"
            fetchpriority="high"
            class="set-chase-box"
          />
        </.link>
        <div class="set-chase-head">
          <p class="set-chase-kicker">{gettext("Najlepsza okazja teraz")}</p>
          <h2 class="set-chase-name">
            <.link navigate={~p"/produkty/#{deal.product.slug}"}>{deal.product.name}</.link>
          </h2>
          <p class="set-chase-meta">{Kinds.label(deal.product.kind)}</p>
        </div>
        <div class="set-chase-pair">
          <p id="set-chase-pull" class="set-chase-side set-chase-pull">
            <span class="set-chase-label">{gettext("Zwykle w sklepach")}</span>
            <strong>{Polish.price(deal.typical)}</strong>
            <span class="set-chase-detail">{ngettext(
              "mediana z %{count} sklepu",
              "mediana z %{count} sklepów",
              deal.shops
            )}</span>
          </p>
          <span class="set-chase-or">{"−#{deal.percent}%"}</span>
          <.link
            id="set-chase-buy"
            class="set-chase-side set-chase-buy"
            navigate={~p"/produkty/#{deal.product.slug}"}
          >
            <span class="set-chase-label">{gettext("Kupisz za")}</span>
            <strong>{Polish.price(deal.price)}</strong>
            <span class="set-chase-detail">{chase_source({:shop, deal.shop})}</span>
          </.link>
        </div>
      <% end %>
      <ul id="sealed-market-facts" class="set-chase-facts">
        <li>
          <strong>{Polish.number(@market.in_stock)}</strong>
          <span>{ngettext(
            "produkt na stanie w sklepach",
            "produkty na stanie w sklepach",
            @market.in_stock
          )}</span>
        </li>
        <li>
          <strong>{Polish.number(@market.good)}</strong>
          <span>{gettext("w dobrej cenie dziś")}</span>
        </li>
        <li>
          <strong>{Polish.number(@market.shops)}</strong>
          <span>{ngettext(
            "sklep z produktami na stanie",
            "sklepy z produktami na stanie",
            @market.shops
          )}</span>
        </li>
        <li class="set-chase-fact-extra">
          <strong>{Polish.number(@market.offers)}</strong>
          <span>{ngettext("oferta na stanie", "oferty na stanie", @market.offers)}</span>
        </li>
      </ul>
      <p class="set-chase-foot">
        <span>{gettext("Ceny bez dostawy.")}</span>
        <a href="#guide-results-title">{gettext("Zobacz produkty")}</a>
      </p>
    </div>
    """
  end

  attr :singles, :map, default: nil
  attr :top, :map, default: nil
  attr :cards_href, :string, required: true
  attr :all?, :boolean, default: false

  # The singles banner: the set's best deal in a Polish shop against its
  # Cardmarket trend, then what the set's singles market looks like in numbers.
  defp set_singles(assigns) do
    ~H"""
    <div
      :if={@singles}
      id="set-chase"
      class={["set-chase", !@singles.deal && "set-chase-empty"]}
      data-track-context
      data-track-placement="banner"
      data-track-card={@singles.deal && @singles.deal.card.id}
      data-track-card-name={@singles.deal && @singles.deal.card.name}
    >
      <%= if deal = @singles.deal do %>
        <.link
          class="set-chase-art"
          navigate={deal.path}
          data-track="card_clicked"
          tabindex="-1"
          aria-hidden="true"
        >
          <.chase_art top={deal} hero?={true} />
        </.link>
        <div class="set-chase-head">
          <p class="set-chase-kicker">
            {if(@all?,
              do: gettext("Najlepsza okazja teraz"),
              else: gettext("Najlepsza okazja w secie")
            )}
          </p>
          <h2 class="set-chase-name">
            <.link
              navigate={deal.path}
              data-track="card_clicked"
            >{deal.card.name}</.link>
          </h2>
          <p class="set-chase-meta">
            {if(@all?,
              do:
                gettext("nr %{number} · %{expansion}",
                  number: deal.card.number,
                  expansion: deal.card.expansion_name
                ),
              else: chase_identity(deal.card)
            )}
          </p>
        </div>
        <div class="set-chase-pair">
          <p id="set-chase-pull" class="set-chase-side set-chase-pull">
            <span class="set-chase-label">{gettext("Na Cardmarket")}</span>
            <strong>{Polish.price(deal.trend)}</strong>
            <span class="set-chase-detail">{gettext("z wysyłką do Polski")}</span>
          </p>
          <span class="set-chase-or">{"−#{deal.percent}%"}</span>
          <.link
            id="set-chase-buy"
            class="set-chase-side set-chase-buy"
            navigate={deal.path}
            data-track="card_clicked"
          >
            <span class="set-chase-label">{gettext("Kupisz ją za")}</span>
            <strong>{Polish.price(deal.price)}</strong>
            <span class="set-chase-detail">{chase_source({:shop, deal.shop})}</span>
          </.link>
        </div>
      <% end %>
      <ul id="set-singles-facts" class="set-chase-facts">
        <li>
          <strong>{Polish.number(@singles.in_stock)}</strong>
          <span>{gettext("z %{total} kart na stanie w sklepach", total: Polish.number(@singles.total))}</span>
        </li>
        <li :if={@singles.set_price}>
          <strong>{Polish.about(@singles.set_price)}</strong>
          <span>{gettext("cały set, najtaniej")}</span>
        </li>
        <li :if={@all?}>
          <strong>{Polish.number(@singles.cheaper)}</strong>
          <span>{gettext("taniej niż na Cardmarket z wysyłką")}</span>
        </li>
        <%!-- The whole guide's numbers match the products list's: in stock, cheaper, shops; the dearest card rounds out the phone grid. --%>
        <li :if={@all?}>
          <strong>{Polish.number(@singles.shops)}</strong>
          <span>{ngettext(
            "sklep z kartami na stanie",
            "sklepy z kartami na stanie",
            @singles.shops
          )}</span>
        </li>
        <li :if={@top} class={@all? && "set-chase-fact-extra"}>
          <strong>{Polish.price(@top.price)}</strong>
          <span>{if(@all?,
            do: gettext("najcenniejsza na stanie: %{card}", card: @top.card.name),
            else: gettext("najcenniejsza: %{card}", card: @top.card.name)
          )}</span>
        </li>
        <li :if={!@all?} class={@singles.set_price && "set-chase-fact-extra"}>
          <strong>{Polish.number(@singles.cheaper)}</strong>
          <span>{gettext("taniej niż na Cardmarket z wysyłką")}</span>
        </li>
      </ul>
      <p class="set-chase-foot">
        <span>{gettext("Ceny bez dostawy. Z zagranicy: z wysyłką do Polski.")}</span>
        <a href={@cards_href}>{gettext("Zobacz karty")}</a>
      </p>
    </div>
    """
  end

  attr :booster, :map, required: true
  attr :set, :map, default: nil
  attr :cardmarket, :list, default: []
  attr :count, :integer, required: true
  attr :cards_href, :string, required: true

  # A set whose cards have no prices yet opens with its single booster: what
  # shops usually ask against the cheapest offer, then the set in numbers.
  defp set_booster(assigns) do
    reference = booster_reference(assigns.booster)

    assigns =
      assign(assigns,
        cheapest: assigns.booster.verdict.cheapest,
        reference: reference,
        percent: booster_discount(assigns.booster.verdict.cheapest, reference),
        facts: booster_facts(assigns, reference)
      )

    ~H"""
    <div id="set-chase" class="set-chase">
      <.link
        class={["set-chase-art", @booster.product.stored_photo_card_url && "set-chase-products"]}
        navigate={~p"/produkty/#{@booster.product.slug}"}
        tabindex="-1"
        aria-hidden="true"
      >
        <img
          :if={@booster.product.stored_photo_card_url}
          src={@booster.product.stored_photo_card_url}
          alt=""
          loading="eager"
          fetchpriority="high"
          class="set-chase-box"
        />
        <span :if={!@booster.product.stored_photo_card_url} class="set-chase-img set-chase-noart">
          <span class="set-chase-noart-note">{gettext("brak zdjęcia")}</span>
        </span>
      </.link>
      <div class="set-chase-head">
        <p class="set-chase-kicker">
          {if(@booster.preorder?,
            do: gettext("Booster w przedsprzedaży"),
            else: gettext("Pojedynczy booster")
          )}
        </p>
        <h2 class="set-chase-name">
          <.link id="set-booster" navigate={~p"/produkty/#{@booster.product.slug}"}>
            {@booster.product.name}
          </.link>
        </h2>
        <p class="set-chase-meta"><.verdict_badge verdict={@booster.verdict} /></p>
      </div>
      <div class="set-chase-pair">
        <p :if={@reference} id="set-chase-pull" class="set-chase-side set-chase-pull">
          <%= case @reference do %>
            <% {:shops, typical, shops} -> %>
              <span class="set-chase-label">{gettext("Zwykle w sklepach")}</span>
              <strong>{Polish.price(typical)}</strong>
              <span class="set-chase-detail">{ngettext(
                "mediana z %{count} sklepu",
                "mediana z %{count} sklepów",
                shops
              )}</span>
            <% {:cardmarket, price, _shops} -> %>
              <span class="set-chase-label">{gettext("Na Cardmarket")}</span>
              <strong>{Polish.price(price)}</strong>
              <span class="set-chase-detail">{gettext("z wysyłką do Polski")}</span>
          <% end %>
        </p>
        <span :if={@percent} class="set-chase-or">{"−#{@percent}%"}</span>
        <.link
          id="set-chase-buy"
          class="set-chase-side set-chase-buy"
          navigate={~p"/produkty/#{@booster.product.slug}"}
        >
          <%= if @cheapest do %>
            <span class="set-chase-label">{gettext("Kupisz za")}</span>
            <strong>{Polish.price(@cheapest.price)}</strong>
            <span class="set-chase-detail">{gettext("w %{shop}", shop: priced_shop_name(@cheapest))
            |> glue_short_words()}</span>
          <% else %>
            <span class="set-chase-label">{gettext("Kupisz za")}</span>
            <strong class="set-chase-unknown">{gettext("brak na stanie")}</strong>
          <% end %>
        </.link>
      </div>
      <ul :if={@facts != []} id="set-booster-facts" class="set-chase-facts">
        <li
          :for={{{value, label}, index} <- Enum.with_index(@facts)}
          class={index == 3 && "set-chase-fact-extra"}
        >
          <strong>{value}</strong>
          <span>{label}</span>
        </li>
      </ul>
      <.chase_foot count={@count} priced?={false} href={@cards_href} />
    </div>
    """
  end

  # The shops' median when enough shops have it, else Cardmarket with delivery.
  defp booster_reference(%{verdict: %{typical_source: :shops} = verdict}),
    do: {:shops, verdict.typical, length(verdict.shop_prices)}

  defp booster_reference(%{cardmarket_delivered_pln: %Decimal{} = price}),
    do: {:cardmarket, price, nil}

  defp booster_reference(_booster), do: nil

  # Three numbers beside the banner, as on every set page, and a fourth for
  # the 2×2 grid on a phone: the set's own first, then its boxes on Cardmarket.
  defp booster_facts(
         %{booster: booster, set: set, cardmarket: cardmarket, count: count},
         reference
       ) do
    # Borrowed odds are another set's, so they say nothing of this one's chase.
    rarest =
      set && set.pull_rates && !set.pull_rates.borrowed_from && List.first(set.pull_rates.rates)

    shop_count = match?({:shops, _typical, _shops}, reference) && elem(reference, 2)

    [
      count > 0 && {Polish.number(count), ngettext("karta w secie", "kart w secie", count)},
      rarest && {Polish.odds(rarest.rate), rarest.rarity},
      shop_count && {Polish.number(shop_count), booster_shops_label(booster, shop_count)}
      | Enum.map(
          cardmarket,
          &{Polish.price(&1.price), gettext("%{kind} na Cardmarket", kind: Kinds.label(&1.kind))}
        )
    ]
    |> Enum.filter(& &1)
    |> Enum.take(4)
  end

  defp booster_shops_label(%{preorder?: true}, count),
    do: ngettext("sklep przyjmuje zamówienia", "sklepy przyjmują zamówienia", count)

  defp booster_shops_label(_booster, count),
    do: ngettext("sklep ma go na stanie", "sklepy mają go na stanie", count)

  # How far the cheapest offer is under the reference, when it is.
  defp booster_discount(%{price: price}, {_source, reference, _shops}) do
    if Decimal.lt?(price, reference),
      do:
        Decimal.new(1)
        |> Decimal.sub(Decimal.div(price, reference))
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()
  end

  defp booster_discount(_cheapest, _reference), do: nil

  attr :top, :map, required: true
  attr :next, :list, required: true
  attr :booster, :map, required: true
  attr :count, :integer, required: true
  attr :cards_href, :string, required: true

  defp set_chase(assigns) do
    ~H"""
    <div
      id="set-chase"
      class="set-chase"
      data-track-context
      data-track-placement="banner"
      data-track-card={@top.card.id}
      data-track-card-name={@top.card.name}
    >
      <.link
        class="set-chase-art"
        navigate={@top.path}
        data-track="card_clicked"
        tabindex="-1"
        aria-hidden="true"
      >
        <.chase_art top={@top} hero?={true} />
      </.link>
      <div class="set-chase-head">
        <p class="set-chase-kicker">{gettext("Najcenniejsza karta w secie")}</p>
        <h2 class="set-chase-name">
          <.link
            navigate={@top.path}
            data-track="card_clicked"
          >{@top.card.name}</.link>
        </h2>
        <p class="set-chase-meta">{chase_identity(@top.card)}</p>
      </div>
      <div class="set-chase-pair">
        <.link
          :if={@top.packs && @booster}
          id="set-chase-pull"
          class="set-chase-side set-chase-pull"
          navigate={~p"/produkty/#{@booster.product.slug}"}
        >
          <.chase_pull_copy top={@top} booster={@booster} />
        </.link>
        <p :if={!@top.packs || !@booster} id="set-chase-pull" class="set-chase-side set-chase-pull">
          <.chase_pull_copy top={@top} booster={@booster} />
        </p>
        <span class="set-chase-or" aria-hidden="true">{gettext("albo")}</span>
        <.link
          id="set-chase-buy"
          class="set-chase-side set-chase-buy"
          navigate={@top.path}
          data-track="card_clicked"
        >
          <span class="set-chase-label">{gettext("Kupisz ją za")}</span>
          <strong>{Polish.price(@top.price)}</strong>
          <span class="set-chase-detail">{chase_source(@top.source)}</span>
        </.link>
      </div>
      <div :if={@next != []} class="set-chase-rest">
        <h3 id="set-chase-next-title" class="set-chase-kicker">
          {gettext("Kolejne: wylosujesz albo kupisz")}
        </h3>
        <ul id="set-chase-next" class="set-chase-more" aria-labelledby="set-chase-next-title">
          <li
            :for={top <- @next}
            data-track-context
            data-track-placement="banner"
            data-track-card={top.card.id}
            data-track-card-name={top.card.name}
          >
            <div class="set-chase-mini">
              <.link
                class="set-chase-mini-thumb"
                navigate={top.path}
                data-track="card_clicked"
                tabindex="-1"
                aria-hidden="true"
              >
                <.chase_art top={top} />
              </.link>
              <.link
                class="set-chase-mini-name"
                navigate={top.path}
                data-track="card_clicked"
              >{top.card.name}</.link>
              <span class="set-chase-mini-meta">{chase_identity(top.card)}</span>
              <span class="set-chase-chips">
                <.link
                  :if={top.packs && @booster}
                  class="set-chase-chip set-chase-chip-pull"
                  navigate={~p"/produkty/#{@booster.product.slug}"}
                >
                  <span class="sr-only">{gettext("wylosujesz średnio: ")}</span>{chase_pull_short(top)}
                </.link>
                <span
                  :if={!top.packs || !@booster}
                  class={[
                    "set-chase-chip set-chase-chip-pull",
                    !top.packs && "set-chase-chip-unknown"
                  ]}
                >
                  <span class="sr-only">{gettext("wylosujesz: ")}</span>{chase_pull_short(top)}
                </span>
                <.link
                  class="set-chase-chip set-chase-chip-buy"
                  navigate={top.path}
                  data-track="card_clicked"
                >
                  <span class="sr-only">{gettext("kupisz za ")}</span>{Polish.price(top.price)}
                </.link>
              </span>
            </div>
          </li>
        </ul>
      </div>
      <.chase_foot count={@count} priced?={true} href={@cards_href} />
    </div>
    """
  end

  attr :top, :map, required: true
  attr :hero?, :boolean, default: false

  defp chase_art(assigns) do
    ~H"""
    <img
      :if={@top.image}
      src={
        if(@hero?, do: CardImage.detail_url(@top.image), else: CardImage.thumbnail_url(@top.image))
      }
      alt=""
      width="600"
      height="825"
      loading={if(@hero?, do: "eager", else: "lazy")}
      class={if(@hero?, do: "set-chase-img", else: "set-chase-mini-art")}
    />
    <span
      :if={!@top.image}
      class={[if(@hero?, do: "set-chase-img", else: "set-chase-mini-art"), "set-chase-noart"]}
      aria-hidden="true"
    >
      <span class="set-chase-noart-number">{@top.card.number}</span>
      <span :if={@hero?} class="set-chase-noart-note">{gettext("brak zdjęcia")}</span>
    </span>
    """
  end

  attr :top, :map, required: true
  attr :booster, :map, required: true

  defp chase_pull_copy(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@top.packs) -> %>
        <span class="set-chase-label">{gettext("Wylosujesz?")}</span>
        <strong class="set-chase-unknown">{gettext("szansy nie znamy")}</strong>
      <% @top.cost -> %>
        <span class="set-chase-label">{gettext("Wylosujesz średnio za")}</span>
        <strong>{Polish.about(@top.cost)}</strong>
        <span class="set-chase-detail">{gettext("%{packs} po %{price}",
          packs: Polish.packs(@top.packs),
          price: Polish.price(@booster.verdict.cheapest.price)
        )}</span>
      <% true -> %>
        <span class="set-chase-label">{gettext("Wylosujesz średnio raz na")}</span>
        <strong>{Polish.packs(@top.packs)}</strong>
        <span class="set-chase-detail">{chase_booster_state(@booster)}</span>
    <% end %>
    """
  end

  defp chase_booster_state(%{preorder?: true, premiere: %Date{} = date}),
    do: gettext("booster w przedsprzedaży, premiera %{date}", date: Polish.day_month(date))

  defp chase_booster_state(%{preorder?: true}), do: gettext("booster w przedsprzedaży")
  defp chase_booster_state(_booster), do: gettext("boostera nie ma teraz na stanie")

  defp chase_pull_short(%{packs: nil}), do: gettext("szansy nie znamy")
  defp chase_pull_short(%{cost: %Decimal{} = cost}), do: Polish.about(cost)

  defp chase_pull_short(%{packs: packs}),
    do: gettext("raz na %{packs}", packs: Polish.packs(packs))

  defp chase_identity(card),
    do:
      gettext("nr %{number} · %{rarity}",
        number: card.number,
        rarity:
          if(card.rarity, do: Rarities.label(card.rarity), else: gettext("Rzadkość nieznana"))
      )

  defp chase_source({:shop, shop}),
    do: glue_short_words(gettext("w %{shop}", shop: priced_shop_name(%{shop: shop})))

  defp chase_source(:cardmarket), do: gettext("na Cardmarket")

  attr :count, :integer, required: true
  attr :priced?, :boolean, required: true
  attr :href, :string, required: true

  defp chase_foot(assigns) do
    ~H"""
    <p class="set-chase-foot">
      <span :if={@priced?}>{gettext("Ceny bez dostawy, szanse to szacunki.")}</span>
      <a :if={@count > 0} href={@href}>{ngettext(
        "Wszystkie karty (%{cards})",
        "Wszystkie %{cards} karty",
        @count,
        cards: Polish.number(@count)
      )}</a>
    </p>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true

  defp card_row(assigns) do
    # With an offer in stock, the row answers as the card's page does: its
    # cheapest shop, the verdict and that shop's price. Without one, the
    # lower known price.
    assigns =
      assign(assigns,
        status: single_verdict_status(assigns.row.verdict),
        price:
          CardGuide.price(%{
            polish_price: assigns.row.price,
            cardmarket_trend_pln: assigns.row.cardmarket_trend_pln
          })
      )

    ~H"""
    <li
      id={@id}
      class="guide-product guide-card"
    >
      <.link
        navigate={@row.path}
        class="guide-product-link"
        data-track="card_clicked"
        data-track-placement="list"
        data-track-card={@row.card.id}
        data-track-card-name={@row.card.name}
        data-track-verdict={@row.verdict}
      >
        <div class="guide-product-image guide-card-image">
          <img
            :if={@row.image}
            src={@row.image}
            alt=""
            loading="lazy"
            width="88"
            height="88"
          />
          <span :if={!@row.image} class="guide-card-placeholder" aria-hidden="true"></span>
        </div>
        <div class="guide-product-copy">
          <h3 class="guide-product-name">{@row.card.name}</h3>
          <p class="guide-product-meta">{@row.card.number} · {@row.expansion_name}</p>
        </div>
        <div class="guide-product-deal">
          <%= if @row.offer do %>
            <span class="guide-product-shop">{priced_shop_name(@row.offer)}</span>
            <%!-- Without a Cardmarket price there is nothing to judge; the card's page says why. --%>
            <.verdict_badge
              :if={@status != :insufficient_data}
              verdict={%{status: @status}}
              id={"card-verdict-#{@row.card.id}"}
              class="guide-product-verdict"
            />
            <p class="guide-product-price"><strong>{Polish.price(@row.offer.price)}</strong></p>
          <% else %>
            <p class="guide-product-price">
              <strong :if={@price}>{Polish.price(@price)}</strong>
              <span :if={!@price}>{gettext("Cena nieznana")}</span>
            </p>
          <% end %>
        </div>
      </.link>
    </li>
    """
  end

  @impl true
  def render(assigns) do
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
        <main id="guide-main" class="guide-main" data-guide-url={@locale_return_to}>
          <%= cond do %>
            <% @set_page && @filters.mode == :cards -> %>
              <.set_intro
                name={@filters.expansion_name}
                page={@set_page}
                close={list_path(@filters, expansion: nil, expansion_name: nil)}
                cards_href="#guide-results-title"
                singles?={true}
              />
            <% @set_page -> %>
              <.set_intro name={@filters.expansion_name} page={@set_page} />
            <% true -> %>
              <.site_intro filters={@filters} market={@market} />
              <.retail_news :if={@filters.mode == :products} deals={@retail_deals} />
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
                    loaded: @loaded,
                    count: if(@filters.mode == :cards, do: @cards_main_count, else: @result_count)
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
                      loaded: @cards_out_loaded,
                      count: @cards_out_count
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
