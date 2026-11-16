defmodule TcgCheapWeb.BrowseLive.Filters do
  @moduledoc "The buying guide's filters: the kind and edition menu, the expansion shelf and the path each choice leads to."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{Kinds, Regions}
  alias TcgCheapWeb.{Format, Paths, SEO}

  @region_params Map.new(Regions.all(), &{Atom.to_string(&1), &1})
  @all_regions "wszystkie"
  # Sets shown before "Pozostałe sety".
  @first_expansions 14

  @doc "The `wersja` param as a region filter; `wszystkie` is every edition."
  def region_param(@all_regions, _expansion), do: nil

  def region_param(param, expansion),
    do: Map.get(@region_params, param, default_region(expansion))

  # Most buyers want English products; an expansion has its own language, so
  # a link to one (e.g. a Japanese set) shows it whatever the edition.
  @doc "The edition a list shows unless another is chosen."
  def default_region(nil), do: :en
  def default_region(_expansion), do: nil

  # The `wersja` of a list: none for the default edition.
  @doc "The list's `wersja` param: none for the default edition."
  def region_value(%{mode: :cards}), do: nil

  def region_value(%{region: region, expansion: expansion}) do
    cond do
      region == default_region(expansion) -> nil
      is_nil(region) -> @all_regions
      true -> region
    end
  end

  # The list with some filters changed: a chosen expansion's at its set page.
  # The language links offered under a chosen expansion are only its own, so
  # the expansion can stay.
  @doc "The path of the list with `changes` applied to its filters."
  def list_path(filters, changes) do
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

  @doc "The path a list's filters hang off: the cards, a chosen set's page or the home page."
  def base_path(%{mode: :cards}), do: Paths.cards()

  def base_path(%{expansion: id, expansion_name: name}) when is_integer(id) and is_binary(name),
    do: SEO.Expansion.path(id, name)

  def base_path(_filters), do: Paths.home()

  @doc "Whether a kind, an edition or an expansion is chosen."
  def filtered?(filters), do: filters.kind || region_value(filters) || filters.expansion

  attr :filters, :map, required: true
  attr :facets, :map, required: true

  # The products tab is also the kind menu: shelves, the chosen shelf's exact
  # kinds and the language edition. A badge counts the chosen kind and edition.
  def kind_menu(assigns) do
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
                {gettext("Wszystkie")}<span class="guide-filter-count">{Format.number(@total)}</span>
              </.link>
            </li>
            <li :for={{shelf, count} <- @shelves}>
              <.link
                id={"kind-#{shelf}"}
                patch={list_path(@filters, kind: shelf)}
                phx-click={close_menus()}
                aria-current={if(@filters.kind == shelf, do: "true")}
              >
                {Kinds.label(shelf)}<span class="guide-filter-count">{Format.number(count)}</span>
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
                {Kinds.label(kind)}<span class="guide-filter-count">{Format.number(count)}</span>
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

  # The sets, English ones first (`TcgCheap.Sealed.ProductFacets.read/1`): beside
  # the list on a wide screen, a shelf above it on a narrow one.
  def set_column(assigns) do
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
          {Format.number(@expansion.count)}
        </span>
      </.link>
    </li>
    """
  end
end
