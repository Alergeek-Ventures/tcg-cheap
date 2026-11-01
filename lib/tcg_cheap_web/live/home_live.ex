defmodule TcgCheapWeb.HomeLive do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue with the cheapest Polish
  price and a verdict, searchable (`?q=`), filterable by kind (`?rodzaj=`) and
  paged with "Pokaż więcej". A known barcode, typed or scanned with the phone
  camera, opens its product directly.
  """

  use TcgCheapWeb, :live_view

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Ean, Guide, Kinds, Shops}
  alias TcgCheapWeb.{Polish, VisitorLocation}

  @max_query_length 100
  @kind_params Map.new(Kinds.all(), &{Atom.to_string(&1), &1})

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sprawdź, czy cena jest dobra")
     |> assign(:html_lang, "pl")
     |> VisitorLocation.assign_location()
     |> stream_configure(:products, dom_id: &"product-#{&1.product.slug}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query =
      params
      |> Map.get("q", "")
      |> to_string()
      |> String.trim()
      |> String.slice(0, @max_query_length)

    kind = Map.get(@kind_params, params["rodzaj"])

    case Sealed.product_for_barcode(query) do
      %{slug: slug} -> {:noreply, push_navigate(socket, to: ~p"/produkty/#{slug}")}
      nil -> {:noreply, list(socket, query, kind)}
    end
  end

  defp list(socket, query, kind) do
    {summaries, more?, count} = Guide.browse(query, kind, 0, DateTime.utc_now())

    socket
    |> assign(:query, query)
    |> assign(:barcode?, Ean.normalize(query) != nil)
    |> assign(:kind, kind)
    |> assign(:form, to_form(%{"q" => query}))
    |> assign(:result_count, count)
    |> assign(:loaded, length(summaries))
    |> assign(:more?, more?)
    |> stream(:products, summaries, reset: true)
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) when is_binary(query) do
    query = query |> String.trim() |> String.slice(0, @max_query_length)
    {:noreply, push_patch(socket, to: list_path(query, socket.assigns.kind), replace: true)}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  def handle_event("more", _params, %{assigns: %{more?: true}} = socket) do
    %{query: query, kind: kind, loaded: loaded} = socket.assigns
    {summaries, more?, _count} = Guide.browse(query, kind, loaded, DateTime.utc_now())

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
      else: {:noreply, list(located, located.assigns.query, located.assigns.kind)}
  end

  defp list_path(query, kind) do
    params =
      [q: query, rodzaj: kind && Atom.to_string(kind)]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    ~p"/?#{params}"
  end

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
        odbiór: {@pickup.shop.pickup_city}, {VisitorLocation.km(@pickup.km)} · {Polish.price(
          @pickup.offer.price
        )}
      </span>
    </p>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :kinds, Kinds.labels())

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="guide-world">
        <.site_header>
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
            <h1 id="guide-title">Sprawdź, czy cena jest dobra</h1>
            <p id="guide-promise">
              Najniższe ceny z {length(Shops.all())} polskich sklepów, sprawdzane codziennie
              i porównane z typową ceną.
            </p>
          </section>

          <section class="guide-search" aria-labelledby="guide-search-title">
            <h2 id="guide-search-title" class="sr-only">Szukaj produktu</h2>
            <.form
              for={@form}
              id="guide-search-form"
              action={~p"/"}
              method="get"
              phx-change="search"
              phx-submit="search"
            >
              <label for="guide-search-query" class="guide-search-label">Szukaj produktu</label>
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
                  placeholder="np. Pitch Black ETB"
                />
                <div id="guide-scan" class="guide-scan" phx-hook=".BarcodeScan" phx-update="ignore">
                  <button
                    id="guide-scan-open"
                    type="button"
                    class="guide-scan-open"
                    aria-label="Skanuj kod kreskowy"
                    hidden
                  >
                    <.fluent_icon name={:barcode} class="size-6" />
                  </button>
                  <dialog
                    id="guide-scan-dialog"
                    class="guide-scan-dialog"
                    aria-labelledby="guide-scan-title"
                  >
                    <h2 id="guide-scan-title">Skieruj aparat na kod kreskowy</h2>
                    <video id="guide-scan-video" muted playsinline></video>
                    <p id="guide-scan-status" aria-live="polite"></p>
                    <button id="guide-scan-close" type="button">Zamknij</button>
                  </dialog>
                </div>
              </div>
              <input :if={@kind} type="hidden" name="rodzaj" value={@kind} />
            </.form>
            <nav
              id="guide-kinds"
              class="guide-kinds"
              aria-label="Rodzaj produktu"
              phx-hook=".ActiveKind"
            >
              <.link
                id="kind-all"
                patch={list_path(@query, nil)}
                aria-current={if(is_nil(@kind), do: "true")}
              >Wszystkie</.link>
              <.link
                :for={{kind, label} <- @kinds}
                id={"kind-#{kind}"}
                patch={list_path(@query, kind)}
                aria-current={if(@kind == kind, do: "true")}
              >{label}</.link>
            </nav>
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
                    this.status.textContent = "Brak dostępu do aparatu. Wpisz cyfry spod kodu kreskowego."
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
            <script :type={Phoenix.LiveView.ColocatedHook} name=".ActiveKind">
              // On a phone the kinds scroll sideways; keep the chosen one in view.
              export default {
                mounted() { this.reveal() },
                updated() { this.reveal() },
                reveal() {
                  const active = this.el.querySelector("[aria-current]")
                  if (!active) return
                  const row = this.el.getBoundingClientRect()
                  const chip = active.getBoundingClientRect()
                  if (chip.left < row.left || chip.right > row.right) {
                    this.el.scrollLeft += chip.left - row.left - row.width / 3
                  }
                }
              }
            </script>
          </section>

          <section class="guide-results" aria-labelledby="guide-results-title">
            <div class="guide-results-heading">
              <h2 id="guide-results-title">
                {if @query == "" and is_nil(@kind), do: "Wszystkie produkty", else: "Wyniki"}
              </h2>
              <p id="guide-result-count" aria-live="polite">
                {Polish.plural(@result_count, "produkt", "produkty", "produktów")}
              </p>
            </div>
            <ul id="guide-products" class="guide-products" phx-update="stream">
              <li id="guide-products-empty" class="guide-empty hidden only:block">
                <%= cond do %>
                  <% @barcode? -> %>
                    Nie znamy jeszcze tego kodu kreskowego. Wpisz nazwę produktu, np. Pitch Black ETB.
                  <% @kind -> %>
                    Nic nie znaleźliśmy w tym rodzaju. Spróbuj samej nazwy dodatku albo wybierz „Wszystkie”.
                  <% true -> %>
                    Nic nie znaleźliśmy. Spróbuj samej nazwy dodatku, np. Pitch Black.
                <% end %>
                <.link id="guide-empty-reset" patch={~p"/"}>Pokaż wszystkie produkty</.link>
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
                    <p :if={product_meta(summary.product) != ""} class="guide-product-meta">
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
              <button id="guide-more" type="button" phx-click="more" phx-disable-with="Wczytuję…">
                Pokaż więcej
              </button>
              <p>Pokazano {@loaded} z {@result_count}.</p>
            </div>
          </section>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
