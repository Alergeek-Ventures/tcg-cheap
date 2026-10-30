defmodule TcgCheapWeb.HomeLive do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue with the cheapest Polish
  price and a verdict, searchable (`?q=`), filterable by kind (`?rodzaj=`) and
  paged with "Pokaż więcej".
  """

  use TcgCheapWeb, :live_view

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{Guide, Kinds}
  alias TcgCheapWeb.Polish

  @max_query_length 100
  @kind_params Map.new(Kinds.all(), &{Atom.to_string(&1), &1})

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sprawdź, czy cena jest dobra")
     |> assign(:html_lang, "pl")
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
    {summaries, more?, count} = Guide.browse(query, kind, 0, DateTime.utc_now())

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:kind, kind)
     |> assign(:form, to_form(%{"q" => query}))
     |> assign(:result_count, count)
     |> assign(:loaded, length(summaries))
     |> assign(:more?, more?)
     |> stream(:products, summaries, reset: true)}
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

  defp list_path(query, kind) do
    params =
      [q: query, rodzaj: kind && Atom.to_string(kind)]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    ~p"/?#{params}"
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :kinds, Kinds.labels())

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="guide-world">
        <.site_header current={:buying} />
        <main id="guide-main" class="guide-main">
          <section class="guide-intro" aria-labelledby="guide-title">
            <h1 id="guide-title">Sprawdź, czy cena jest dobra</h1>
            <p id="guide-promise">
              Najniższa cena w polskich sklepach i ocena, czy to dobra cena.
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
                <%= if @kind do %>
                  Nic nie znaleźliśmy w tym rodzaju. Spróbuj samej nazwy dodatku albo wybierz „Wszystkie”.
                <% else %>
                  Nic nie znaleźliśmy. Spróbuj samej nazwy dodatku, np. Pitch Black.
                <% end %>
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
                    <p class="guide-product-meta">{product_meta(summary.product)}</p>
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
                        status={summary.verdict.status}
                        id={"verdict-#{summary.product.slug}"}
                        class="guide-product-verdict"
                      />
                      <span
                        :if={
                          summary.verdict.typical_source == :cardmarket and
                            summary.verdict.status in [:good, :normal, :expensive]
                        }
                        class="guide-product-source"
                      >wg Cardmarket</span>
                    </p>
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

          <.guide_footnote />
        </main>
      </div>
    </Layouts.app>
    """
  end
end
