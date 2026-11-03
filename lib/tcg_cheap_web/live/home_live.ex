defmodule TcgCheapWeb.HomeLive do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue with the cheapest Polish
  price and a verdict, searchable (`?q=`), filterable in a side panel by kind
  (`?rodzaj=`), language edition (`?wersja=`, English unless `wszystkie`
  or an expansion is chosen) and expansion, and paged with "Pokaż więcej".

  A chosen expansion's list is its set page (`/rozszerzenia/<name>-<id>`, the
  Cardmarket expansion id; `?rozszerzenie=<id>` leads there): the answer for
  the set on top, its products, and the set's pull rates and cards.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents
  import TcgCheapWeb.SetComponents

  alias TcgCheap.Sealed.{Catalogue, Guide, Kinds, Regions}
  alias TcgCheapWeb.{Analytics, Polish, SEO, VisitorLocation}

  @max_query_length 100
  @kind_params Map.new(Kinds.all(), &{Atom.to_string(&1), &1})
  @region_params Map.new(Regions.all(), &{Atom.to_string(&1), &1})
  @all_regions "wszystkie"
  # Expansions listed before "Pokaż wszystkie".
  @first_expansions 12

  defmodule NotFound do
    @moduledoc false
    defexception message: "expansion not found", plug_status: 404
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> VisitorLocation.assign_location()
     |> assign(all_expansions?: false, set_page: nil)
     |> stream_configure(:products, dom_id: &"product-#{&1.product.slug}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      query: params |> query_param() |> String.trim() |> String.slice(0, @max_query_length),
      kind: Map.get(@kind_params, params["rodzaj"]),
      expansion: expansion_param(socket.assigns.live_action, params)
    }

    filters = Map.put(filters, :region, region_param(params["wersja"], filters.expansion))

    previous = socket.assigns[:filters]
    socket = list(socket, filters)
    expansion = chosen_expansion(socket.assigns)
    socket = update(socket, :filters, &Map.put(&1, :expansion_name, expansion && expansion.name))

    # An expansion's list lives at its set page, under its current name.
    at_set_page? = expansion && params["slug"] == Catalogue.slug(expansion.name, expansion.id)

    case {socket.assigns.live_action, expansion, at_set_page?} do
      {:expansion, nil, _at_set_page?} ->
        raise NotFound

      {_action, %{}, false} ->
        {:noreply, push_patch(socket, to: list_path(socket.assigns.filters, []), replace: true)}

      {:expansion, expansion, true} ->
        set_page = set_page(socket, expansion)
        seo = SEO.expansion(params, expansion, set_page)

        {:noreply,
         socket
         |> assign(set_page: set_page, seo: seo, page_title: seo.title)
         |> track_changes(previous)}

      {:index, nil, _at_set_page?} ->
        seo = SEO.home(params)

        {:noreply,
         socket
         |> assign(set_page: nil, seo: seo, page_title: seo.title)
         |> track_changes(previous)}
    end
  end

  defp chosen_expansion(%{filters: %{expansion: id}, facets: facets}),
    do: id && Enum.find(facets.expansions, &(&1.id == id))

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

  defp list(socket, filters) do
    {summaries, more?, count} = Guide.browse(filters, 0, DateTime.utc_now())
    first_summary = List.first(summaries)

    socket
    |> assign(:filters, filters)
    |> assign(:facets, Guide.facets(filters))
    |> assign(:form, to_form(%{"q" => filters.query}))
    |> assign(:result_count, count)
    |> assign(:loaded, length(summaries))
    |> assign(:more?, more?)
    |> assign(:priority_product_id, first_summary && first_summary.product.id)
    |> stream(:products, summaries, reset: true)
  end

  # Only changes made on the page: the first render arrives with its pageview,
  # whose URL already holds the query and filters.
  defp track_changes(socket, nil), do: socket

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
    %{filters: filters, loaded: loaded} = socket.assigns
    {summaries, more?, _count} = Guide.browse(filters, loaded, DateTime.utc_now())

    socket =
      socket
      |> assign(:loaded, loaded + length(summaries))
      |> assign(:more?, more?)
      |> stream(:products, summaries)

    properties = Map.put(list_properties(socket), :loaded, socket.assigns.loaded)
    {:noreply, Analytics.track(socket, "more_products_loaded", properties)}
  end

  def handle_event("more", _params, socket), do: {:noreply, socket}

  def handle_event("all-expansions", _params, socket),
    do: {:noreply, assign(socket, :all_expansions?, true)}

  def handle_event("location-" <> _ = event, params, socket) do
    {:noreply, VisitorLocation.handle_event(event, params, socket)}
  end

  defp region_param(@all_regions, _expansion), do: nil

  defp region_param(param, expansion),
    do: Map.get(@region_params, param, default_region(expansion))

  # Most buyers want English products; an expansion has its own language, so
  # a link to one (e.g. a Japanese set) shows it whatever the edition.
  defp default_region(nil), do: :en
  defp default_region(_expansion), do: nil

  # The `wersja` of a list: none for the default edition.
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
      [q: filters.query, rodzaj: filters.kind, wersja: region_value(filters)]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map(fn {key, value} -> {key, to_string(value)} end)

    base_path(filters) <> if(params == [], do: "", else: "?" <> URI.encode_query(params))
  end

  defp base_path(%{expansion: id, expansion_name: name}) when is_integer(id) and is_binary(name),
    do: SEO.expansion_path(id, name)

  defp base_path(_filters), do: ~p"/"

  defp filtered?(filters), do: filters.kind || region_value(filters) || filters.expansion

  defp active_filters(filters),
    do: Enum.count([filters.kind, region_value(filters), filters.expansion], & &1)

  attr :filters, :map, required: true
  attr :facets, :map, required: true
  attr :result_count, :integer, required: true
  attr :all_expansions?, :boolean, required: true

  # Language edition, kind and expansion; folded behind "Filtry" on phones.
  defp filters(assigns) do
    # The chosen expansion leads, so it stays in view among the tiles.
    {first, rest} =
      assigns.facets.expansions
      |> Enum.sort_by(&(&1.id != assigns.filters.expansion))
      |> Enum.split(@first_expansions)

    assigns = assign(assigns, first: first, rest: rest)

    ~H"""
    <aside id="guide-filters" class="guide-filters" aria-label={gettext("Filtry")}>
      <div id="guide-filters-body" class="guide-filters-body">
        <nav id="guide-regions" class="guide-filter" aria-labelledby="guide-regions-title">
          <h2 id="guide-regions-title">{gettext("Wersja językowa")}</h2>
          <ul>
            <li>
              <.link
                id="region-all"
                patch={list_path(@filters, region: nil)}
                aria-current={if(is_nil(@filters.region), do: "true")}
              >{gettext("Wszystkie")}</.link>
            </li>
            <li :for={{region, count} <- @facets.regions}>
              <.link
                id={"region-#{region}"}
                patch={list_path(@filters, region: region)}
                aria-current={if(@filters.region == region, do: "true")}
              >
                {Regions.label(region)}
                <span class="guide-filter-count">{Polish.number(count)}</span>
              </.link>
            </li>
          </ul>
        </nav>
        <nav id="guide-kinds" class="guide-filter" aria-labelledby="guide-kinds-title">
          <h2 id="guide-kinds-title">{gettext("Rodzaj")}</h2>
          <ul>
            <li>
              <.link
                id="kind-all"
                patch={list_path(@filters, kind: nil)}
                aria-current={if(is_nil(@filters.kind), do: "true")}
              >{gettext("Wszystkie")}</.link>
            </li>
            <li :for={{kind, count} <- @facets.kinds}>
              <.link
                id={"kind-#{kind}"}
                patch={list_path(@filters, kind: kind)}
                aria-current={if(@filters.kind == kind, do: "true")}
              >
                {Kinds.label(kind)}
                <span class="guide-filter-count">{Polish.number(count)}</span>
              </.link>
            </li>
          </ul>
        </nav>
        <nav
          :if={@facets.expansions != []}
          id="guide-expansions"
          class="guide-filter guide-expansions"
          aria-labelledby="guide-expansions-title"
        >
          <h2 id="guide-expansions-title">{gettext("Rozszerzenie")}</h2>
          <.link
            id="expansion-all"
            class="guide-expansions-all"
            patch={list_path(@filters, expansion: nil, expansion_name: nil)}
            aria-current={if(is_nil(@filters.expansion), do: "true")}
          >{gettext("Wszystkie")}</.link>
          <ul class="guide-expansion-tiles">
            <.expansion_option
              :for={expansion <- @first}
              expansion={expansion}
              filters={@filters}
              tile
            />
          </ul>
          <details
            :if={@rest != []}
            id="guide-expansions-more"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <%!-- Rendered on first opening: hundreds of rows (noindex filter links)
                 would otherwise weigh down every page load and patch. --%>
            <summary phx-click={!@all_expansions? && "all-expansions"}>
              {gettext("Pokaż pozostałe (%{count})", count: length(@rest))}
            </summary>
            <ul :if={@all_expansions?} class="guide-expansion-names">
              <.expansion_option :for={expansion <- @rest} expansion={expansion} filters={@filters} />
            </ul>
          </details>
        </nav>
        <button
          type="button"
          id="guide-filters-apply"
          class="guide-filters-apply"
          phx-click={
            JS.remove_class("guide-filters-open", to: "#guide-filters")
            |> JS.set_attribute({"aria-expanded", "false"}, to: "#guide-filters-toggle")
            |> JS.focus(to: "#guide-results-title")
            |> JS.dispatch("guide:reveal", to: "#guide-results-title")
          }
        >
          {gettext("Pokaż %{products}",
            products: Polish.plural(@result_count, "produkt", "produkty", "produktów")
          )}
        </button>
      </div>
    </aside>
    """
  end

  attr :expansion, :map, required: true
  attr :filters, :map, required: true
  attr :tile, :boolean, default: false, doc: "a tile, else a row of the list"

  # The language tag shows only while every language is listed. A logo is
  # captioned with the English name on a tile and named beside it in a row; a
  # row without a logo (a tile too, as phones show tiles as rows) keeps a blank
  # slot so the names line up.
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
        aria-current={if(@filters.expansion == @expansion.id, do: "true")}
        title={@expansion.name}
      >
        <img :if={@logo_url} src={@logo_url} alt="" loading="lazy" />
        <span :if={is_nil(@logo_url)} class="guide-expansion-nologo" aria-hidden="true"></span>
        <span class={["guide-expansion-name", @tile && @logo_url && "guide-expansion-caption"]}>
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
  attr :page, :map, required: true

  # A set page's top: the set, then its answer at a glance (the single
  # booster's price, the rarest pull rates, the cards), the same facts as its
  # search snippet.
  defp set_intro(assigns) do
    set = assigns.page.set

    assigns =
      assign(assigns,
        logo_url: set && set.logo_url,
        rarest: if(set && set.pull_rates, do: Enum.take(set.pull_rates.rates, 2), else: []),
        cards: set && set.card_count > 0 && set
      )

    ~H"""
    <section id="set-intro" class="guide-intro set-intro" aria-labelledby="guide-title">
      <div class="set-title">
        <img :if={@logo_url} src={@logo_url} alt="" class="set-logo" />
        <h1 id="guide-title">{@name}</h1>
      </div>
      <%!-- Each fact leads on: the booster to its page, the odds and the cards to their tables. --%>
      <%= if @page.booster || @rarest != [] || @cards do %>
        <ul id="set-facts" class="set-facts">
          <li :if={@page.booster}>
            <.link
              id="set-booster"
              navigate={~p"/produkty/#{@page.booster.product.slug}"}
              class="set-fact"
            >
              <span class="set-fact-label">
                {if(@page.booster.preorder?,
                  do: gettext("Booster w przedsprzedaży"),
                  else: gettext("Pojedynczy booster")
                )}
              </span>
              <%= if cheapest = @page.booster.verdict.cheapest do %>
                <strong>{Polish.price(cheapest.price)}</strong>
                <span class="set-fact-detail">{gettext("w %{shop}", shop: shop_name(cheapest))}</span>
              <% else %>
                <strong>{gettext("brak na stanie")}</strong>
              <% end %>
            </.link>
          </li>
          <li :for={row <- @rarest}>
            <a href="#product-pull-rates" class="set-fact">
              <span class="set-fact-label">{row.rarity}</span>
              <strong>{Polish.odds(row.rate)}</strong>
            </a>
          </li>
          <li :if={@cards}>
            <a href="#product-cards" class="set-fact">
              <span class="set-fact-label">{gettext("Karty w secie")}</span>
              <strong>{Polish.number(@cards.card_count)}</strong>
              <span :if={@cards.top_card} class="set-fact-detail">
                {gettext("najdroższa: %{card}, %{price}",
                  card: elem(@cards.top_card, 0).name,
                  price: Polish.eur(elem(@cards.top_card, 1))
                )}
              </span>
            </a>
          </li>
        </ul>
      <% else %>
        <p id="guide-promise">{Enum.join(SEO.expansion_answer(@name, @page), " ")}</p>
      <% end %>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :active, active_filters(assigns.filters))

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
        <main id="guide-main" class="guide-main">
          <%= if @set_page do %>
            <.set_intro name={@filters.expansion_name} page={@set_page} />
          <% else %>
            <section class="guide-intro" aria-labelledby="guide-title">
              <h1 id="guide-title">{gettext("Czy to dobra cena?")}</h1>
              <p id="guide-promise">
                {gettext(
                  "Wpisz produkt Pokémon TCG, a pokażemy najtańszą ofertę w polskich sklepach i powiemy, czy cena jest dobra."
                )}
              </p>
            </section>
          <% end %>

          <section class="guide-search" aria-labelledby="guide-search-title">
            <h2 id="guide-search-title" class="sr-only">{gettext("Szukaj produktu")}</h2>
            <.form
              for={@form}
              id="guide-search-form"
              action={base_path(@filters)}
              method="get"
              phx-change="search"
              phx-submit="search"
            >
              <label for="guide-search-query" class="guide-search-label">{gettext("Szukaj produktu")}</label>
              <div class="guide-search-field">
                <.fluent_icon name={:search} class="guide-search-icon" />
                <.input
                  field={@form[:q]}
                  type="search"
                  id="guide-search-query"
                  class="guide-search-input"
                  maxlength="100"
                  autocomplete="off"
                  phx-debounce="300"
                  placeholder={
                    if(@set_page,
                      do: gettext("np. Elite Trainer Box"),
                      else: gettext("np. Pitch Black ETB")
                    )
                  }
                />
                <button
                  type="button"
                  id="guide-filters-toggle"
                  class="guide-filters-toggle"
                  aria-controls="guide-filters-body"
                  aria-expanded="false"
                  data-track="filters_panel_opened"
                  phx-click={
                    JS.dispatch("guide:pin-filters", to: "#guide-search-form")
                    |> JS.toggle_class("guide-filters-open", to: "#guide-filters")
                    |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                  }
                >
                  <.fluent_icon name={:filter} />{gettext("Filtry")}<span :if={@active > 0}> ({@active})</span>
                </button>
              </div>
              <input :if={@filters.kind} type="hidden" name="rodzaj" value={@filters.kind} />
              <input
                :if={region_value(@filters)}
                type="hidden"
                name="wersja"
                value={region_value(@filters)}
              />
            </.form>
          </section>

          <div class="guide-browse">
            <.filters
              filters={@filters}
              facets={@facets}
              result_count={@result_count}
              all_expansions?={@all_expansions?}
            />
            <section class="guide-results" aria-labelledby="guide-results-title">
              <div class="guide-results-heading">
                <h2 id="guide-results-title" tabindex="-1">
                  <%= cond do %>
                    <% @filters.query == "" and !filtered?(@filters) -> %>
                      {gettext("Produkty w wersji angielskiej")}
                    <% @filters.query == "" and @set_page != nil -> %>
                      {gettext("Produkty i ceny")}
                    <% true -> %>
                      {gettext("Wyniki")}
                  <% end %>
                </h2>
                <p id="guide-result-count" aria-live="polite">
                  {Polish.plural(@result_count, "produkt", "produkty", "produktów")}
                </p>
                <.link
                  :if={@active > 0}
                  id="guide-filters-clear"
                  class="guide-filters-clear"
                  patch={
                    list_path(@filters,
                      kind: nil,
                      region: default_region(nil),
                      expansion: nil,
                      expansion_name: nil
                    )
                  }
                >
                  <.fluent_icon name={:dismiss} />{gettext("Wyczyść filtry")}
                </.link>
              </div>
              <ul
                id="guide-products"
                class="guide-products"
                phx-update="stream"
                data-track-positions
              >
                <li id="guide-products-empty" class="guide-empty hidden only:block">
                  <%= cond do %>
                    <% filtered?(@filters) -> %>
                      {gettext(
                        "Nic nie znaleźliśmy przy tych filtrach. Spróbuj samej nazwy dodatku albo usuń filtry."
                      )}
                    <% true -> %>
                      {gettext("Nic nie znaleźliśmy. Spróbuj samej nazwy dodatku, np. Pitch Black.")}
                  <% end %>
                  <.link id="guide-empty-reset" patch={~p"/"}>{gettext("Pokaż wszystkie produkty")}</.link>
                </li>
                <li :for={{dom_id, summary} <- @streams.products} id={dom_id} class="guide-product">
                  <.link
                    navigate={~p"/produkty/#{summary.product.slug}"}
                    class="guide-product-link"
                    data-track="product_clicked"
                    data-track-product-slug={summary.product.slug}
                    data-track-verdict={summary.verdict.status}
                    data-track-preorder={to_string(summary.preorder?)}
                  >
                    <.product_image
                      small_photo={summary.product.stored_photo_small_url}
                      photo={summary.product.stored_photo_card_url}
                      page_photo={summary.product.stored_photo_page_url}
                      blur={summary.product.photo_placeholder}
                      sizes="(max-width: 42rem) 4.5rem, 5.5rem"
                      loading={
                        if(summary.product.id == @priority_product_id, do: "eager", else: "lazy")
                      }
                      fetchpriority={if(summary.product.id == @priority_product_id, do: "high")}
                      kind={summary.product.kind}
                      alt=""
                      class="guide-product-image"
                    />
                    <div class="guide-product-copy">
                      <h3 class="guide-product-name">{summary.product.name}</h3>
                      <p class="guide-product-meta">
                        {product_meta(summary.product)}
                      </p>
                    </div>
                    <div class="guide-product-deal">
                      <span :if={summary.verdict.cheapest} class="guide-product-shop">
                        {shop_name(summary.verdict.cheapest)}
                      </span>
                      <.verdict_badge
                        verdict={summary.verdict}
                        id={"verdict-#{summary.product.slug}"}
                        class="guide-product-verdict"
                      />
                      <p :if={summary.verdict.cheapest} class="guide-product-price">
                        <span
                          :if={summary.preorder?}
                          id={"preorder-#{summary.product.slug}"}
                          class="guide-product-preorder"
                        >
                          <.verdict_icon status={:preorder} />{preorder_tag(summary.premiere_in)}
                        </span>
                        <strong>{Polish.price(summary.verdict.cheapest.price)}</strong>
                      </p>
                    </div>
                  </.link>
                </li>
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
                  {gettext("Pokazano %{loaded} z %{count}.", loaded: @loaded, count: @result_count)}
                </p>
              </div>
              <div :if={@set_page && @set_page.set} id="set-content" class="guide-set">
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
        <.site_footer />
      </div>
    </Layouts.app>
    """
  end
end
