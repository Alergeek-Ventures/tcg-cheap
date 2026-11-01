defmodule TcgCheapWeb.HomeLive do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue with the cheapest Polish
  price and a verdict, searchable (`?q=`), filterable in a side panel by kind
  (`?rodzaj=`), language edition (`?wersja=`) and expansion
  (`?rozszerzenie=`, a Cardmarket expansion id), and paged with "Pokaż
  więcej". A known barcode, typed or scanned with the phone camera, opens its
  product directly.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Ean, Guide, Kinds, Regions, Shops}
  alias TcgCheapWeb.{Polish, SEO, VisitorLocation}

  @max_query_length 100
  @kind_params Map.new(Kinds.all(), &{Atom.to_string(&1), &1})
  @region_params Map.new(Regions.all(), &{Atom.to_string(&1), &1})
  # Expansions listed before "Pokaż wszystkie".
  @first_expansions 12

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> VisitorLocation.assign_location()
     |> stream_configure(:products, dom_id: &"product-#{&1.product.slug}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    seo = SEO.home(params)
    socket = assign(socket, seo: seo, page_title: seo.title)

    filters = %{
      query: params |> query_param() |> String.trim() |> String.slice(0, @max_query_length),
      kind: Map.get(@kind_params, params["rodzaj"]),
      region: Map.get(@region_params, params["wersja"]),
      expansion: expansion_param(params["rozszerzenie"])
    }

    case Sealed.product_for_barcode(filters.query) do
      %{slug: slug} -> {:noreply, push_navigate(socket, to: ~p"/produkty/#{slug}")}
      nil -> {:noreply, list(socket, filters)}
    end
  end

  defp query_param(%{"q" => query}) when is_binary(query), do: query
  defp query_param(_params), do: ""

  defp expansion_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id in 1..9_999_999 -> id
      _ -> nil
    end
  end

  defp expansion_param(_value), do: nil

  defp list(socket, filters) do
    {summaries, more?, count} = Guide.browse(filters, 0, DateTime.utc_now())

    socket
    |> assign(:filters, filters)
    |> assign(:facets, Guide.facets(filters))
    |> assign(:barcode?, Ean.normalize(filters.query) != nil)
    |> assign(:form, to_form(%{"q" => filters.query}))
    |> assign(:result_count, count)
    |> assign(:loaded, length(summaries))
    |> assign(:more?, more?)
    |> stream(:products, summaries, reset: true)
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

    {:noreply,
     socket
     |> assign(:loaded, loaded + length(summaries))
     |> assign(:more?, more?)
     |> stream(:products, summaries)}
  end

  def handle_event("more", _params, socket), do: {:noreply, socket}

  def handle_event("location-" <> _ = event, params, socket) do
    located = VisitorLocation.handle_event(event, params, socket)

    # The "odbiór w pobliżu" marks depend on it; the list starts over.
    if located.assigns.location == socket.assigns.location,
      do: {:noreply, located},
      else: {:noreply, list(located, located.assigns.filters)}
  end

  # The list with some filters changed. The language links offered under a
  # chosen expansion are only its own, so the expansion can stay.
  defp list_path(filters, changes) do
    filters = Map.merge(filters, Map.new(changes))

    params =
      [
        q: filters.query,
        rodzaj: filters.kind,
        wersja: filters.region,
        rozszerzenie: filters.expansion
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map(fn {key, value} -> {key, to_string(value)} end)

    ~p"/?#{params}"
  end

  defp filtered?(filters), do: filters.kind || filters.region || filters.expansion

  defp active_filters(filters),
    do: Enum.count([filters.kind, filters.region, filters.expansion], & &1)

  attr :id, :string, required: true
  attr :offers, :list, required: true
  attr :location, :map, default: nil

  # The cheapest in-stock pickup nearby and where it is, which is often not
  # the cheapest price shown in the row.
  defp nearby_pickup(assigns) do
    assigns =
      assign(assigns, :pickup, VisitorLocation.cheapest_pickup(assigns.offers, assigns.location))

    ~H"""
    <p :if={@pickup} id={@id} class="guide-product-nearby">
      <.fluent_icon name={:location} />
      <span>
        {gettext("odbiór: %{city}, %{distance} · %{price}",
          city: @pickup.shop.pickup_city,
          distance: VisitorLocation.km(@pickup.km),
          price: Polish.price(@pickup.offer.price)
        )}
      </span>
    </p>
    """
  end

  attr :filters, :map, required: true
  attr :facets, :map, required: true
  attr :kinds, :list, required: true
  attr :result_count, :integer, required: true

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
            <li :for={{kind, label} <- @kinds}>
              <.link
                id={"kind-#{kind}"}
                patch={list_path(@filters, kind: kind)}
                aria-current={if(@filters.kind == kind, do: "true")}
              >{label}</.link>
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
            patch={list_path(@filters, expansion: nil)}
            aria-current={if(is_nil(@filters.expansion), do: "true")}
          >{gettext("Wszystkie")}</.link>
          <ul class="guide-expansion-tiles">
            <.expansion_option
              :for={expansion <- @first}
              expansion={expansion}
              filters={@filters}
              logo
            />
          </ul>
          <details
            :if={@rest != []}
            id="guide-expansions-more"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary>{gettext("Pokaż pozostałe (%{count})", count: length(@rest))}</summary>
            <ul class="guide-expansion-names">
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
  attr :logo, :boolean, default: false, doc: "a tile with the logo, when there is one"

  # The language tag shows only while every language is listed.
  defp expansion_option(assigns) do
    assigns = assign(assigns, :logo_url, assigns.logo && assigns.expansion.logo_url)

    ~H"""
    <li>
      <.link
        id={"expansion-#{@expansion.id}"}
        patch={list_path(@filters, expansion: @expansion.id)}
        aria-current={if(@filters.expansion == @expansion.id, do: "true")}
      >
        <img :if={@logo_url} src={@logo_url} alt="" loading="lazy" />
        <span class={["guide-expansion-name", @logo_url && "sr-only"]}>{@expansion.name}</span>
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

  @impl true
  def render(assigns) do
    assigns = assign(assigns, kinds: Kinds.labels(), active: active_filters(assigns.filters))

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
          <section class="guide-intro" aria-labelledby="guide-title">
            <h1 id="guide-title">{gettext("Sprawdź, czy cena jest dobra")}</h1>
            <p id="guide-promise">
              {gettext(
                "Najniższe ceny z %{count} polskich sklepów, sprawdzane codziennie i porównane z typową ceną.",
                count: length(Shops.all())
              )}
            </p>
          </section>

          <section class="guide-search" aria-labelledby="guide-search-title">
            <h2 id="guide-search-title" class="sr-only">{gettext("Szukaj produktu")}</h2>
            <.form
              for={@form}
              id="guide-search-form"
              action={~p"/"}
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
                  placeholder={gettext("np. Pitch Black ETB")}
                />
                <div
                  id="guide-scan"
                  class="guide-scan"
                  phx-hook=".BarcodeScan"
                  data-camera-error={
                    gettext("Brak dostępu do aparatu. Wpisz cyfry spod kodu kreskowego.")
                  }
                  phx-update="ignore"
                >
                  <button
                    id="guide-scan-open"
                    type="button"
                    class="guide-scan-open"
                    aria-label={gettext("Skanuj kod kreskowy")}
                    hidden
                  >
                    <.fluent_icon name={:barcode} class="size-6" />
                  </button>
                  <dialog
                    id="guide-scan-dialog"
                    class="guide-scan-dialog"
                    aria-labelledby="guide-scan-title"
                  >
                    <h2 id="guide-scan-title">{gettext("Skieruj aparat na kod kreskowy")}</h2>
                    <video id="guide-scan-video" muted playsinline></video>
                    <p id="guide-scan-status" aria-live="polite"></p>
                    <button id="guide-scan-close" type="button">{gettext("Zamknij")}</button>
                  </dialog>
                </div>
                <button
                  type="button"
                  id="guide-filters-toggle"
                  class="guide-filters-toggle"
                  aria-controls="guide-filters-body"
                  aria-expanded="false"
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
              <input :if={@filters.region} type="hidden" name="wersja" value={@filters.region} />
              <input
                :if={@filters.expansion}
                type="hidden"
                name="rozszerzenie"
                value={@filters.expansion}
              />
            </.form>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".BarcodeScan">
              // Only where the browser can read barcodes natively (e.g. Chrome on
              // Android); elsewhere the code can still be typed in.
              export default {
                async mounted() {
                  if (!("BarcodeDetector" in window)) return
                  const supported = await BarcodeDetector.getSupportedFormats()
                  const formats = ["ean_13", "upc_a"].filter(format => supported.includes(format))
                  if (formats.length === 0) return
                  this.detector = new BarcodeDetector({formats})
                  this.dialog = this.el.querySelector("dialog")
                  this.video = this.el.querySelector("video")
                  this.status = this.el.querySelector("[aria-live]")
                  const open = this.el.querySelector("#guide-scan-open")
                  open.hidden = false
                  open.addEventListener("click", () => this.start())
                  this.el.querySelector("#guide-scan-close").addEventListener("click", () => this.dialog.close())
                  this.dialog.addEventListener("close", () => this.stop())
                },
                destroyed() { this.stop() },
                async start() {
                  this.status.textContent = ""
                  this.video.hidden = false
                  this.dialog.showModal()
                  try {
                    this.stream = await navigator.mediaDevices.getUserMedia({video: {facingMode: "environment"}})
                  } catch {
                    this.video.hidden = true
                    this.status.textContent = this.el.dataset.cameraError
                    return
                  }
                  this.video.srcObject = this.stream
                  await this.video.play()
                  this.scan()
                },
                async scan() {
                  if (!this.stream) return
                  const [code] = await this.detector.detect(this.video).catch(() => [])
                  if (code) {
                    this.dialog.close()
                    this.pushEvent("search", {q: code.rawValue})
                  } else {
                    this.timer = setTimeout(() => this.scan(), 200)
                  }
                },
                stop() {
                  clearTimeout(this.timer)
                  this.stream?.getTracks().forEach(track => track.stop())
                  this.stream = null
                  if (this.video) this.video.srcObject = null
                }
              }
            </script>
          </section>

          <div class="guide-browse">
            <.filters
              filters={@filters}
              facets={@facets}
              kinds={@kinds}
              result_count={@result_count}
            />
            <section class="guide-results" aria-labelledby="guide-results-title">
              <div class="guide-results-heading">
                <h2 id="guide-results-title" tabindex="-1">
                  {if @filters.query == "" and !filtered?(@filters),
                    do: gettext("Wszystkie produkty"),
                    else: gettext("Wyniki")}
                </h2>
                <p id="guide-result-count" aria-live="polite">
                  {Polish.plural(@result_count, "produkt", "produkty", "produktów")}
                  <span :if={filtered?(@filters)}>
                    ·
                    <.link
                      id="guide-filters-clear"
                      class="guide-filters-clear"
                      patch={list_path(@filters, kind: nil, region: nil, expansion: nil)}
                    >{gettext("Wyczyść filtry")}</.link>
                  </span>
                </p>
              </div>
              <ul id="guide-products" class="guide-products" phx-update="stream">
                <li id="guide-products-empty" class="guide-empty hidden only:block">
                  <%= cond do %>
                    <% @barcode? -> %>
                      {gettext(
                        "Nie znamy jeszcze tego kodu kreskowego. Wpisz nazwę produktu, np. Pitch Black ETB."
                      )}
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
                  <.link navigate={~p"/produkty/#{summary.product.slug}"} class="guide-product-link">
                    <.product_image
                      url={summary.product.image_url}
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
                      <p
                        :if={summary.verdict.cheapest || summary.cardmarket_pln}
                        class="guide-product-price"
                      >
                        <%= if summary.verdict.cheapest do %>
                          <strong>{Polish.price(summary.verdict.cheapest.price)}</strong>
                          <span>{shop_name(summary.verdict.cheapest)}</span>
                        <% else %>
                          <span>Cardmarket ≈ {Polish.zloty(summary.cardmarket_pln)}</span>
                        <% end %>
                      </p>
                      <p class="guide-product-judgement">
                        <.verdict_badge
                          verdict={summary.verdict}
                          id={"verdict-#{summary.product.slug}"}
                          class="guide-product-verdict"
                        />
                      </p>
                      <.nearby_pickup
                        id={"nearby-#{summary.product.slug}"}
                        offers={summary.in_stock_offers}
                        location={@location}
                      />
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
            </section>
          </div>
        </main>
        <.site_footer />
      </div>
    </Layouts.app>
    """
  end
end
