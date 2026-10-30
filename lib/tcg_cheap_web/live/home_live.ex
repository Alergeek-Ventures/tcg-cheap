defmodule TcgCheapWeb.HomeLive do
  @moduledoc "The buying guide: every catalogue product with its cheapest price and verdict."

  use TcgCheapWeb, :live_view

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{Catalogue, Guide}
  alias TcgCheapWeb.Polish

  @max_query_length 100

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
    query = params |> Map.get("q", "") |> to_string() |> String.slice(0, @max_query_length)
    summaries = Guide.summaries(Catalogue.search(query), DateTime.utc_now())

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:form, to_form(%{"q" => query}))
     |> assign(:result_count, length(summaries))
     |> stream(:products, summaries, reset: true)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) when is_binary(query) do
    query = query |> String.trim() |> String.slice(0, @max_query_length)
    params = if query == "", do: %{}, else: %{q: query}
    {:noreply, push_patch(socket, to: ~p"/?#{params}", replace: true)}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="guide-world">
        <.site_header current={:buying} />
        <main id="guide-main" class="guide-main">
          <section class="guide-intro" aria-labelledby="guide-title">
            <h1 id="guide-title">Sprawdź, czy cena jest dobra</h1>
            <p id="guide-promise">
              Porównujemy ceny zamkniętych produktów Pokémon TCG w polskich sklepach i mówimy,
              czy dzisiejsza najniższa cena jest dobra na tle ostatnich 30 dni.
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
                  phx-debounce="250"
                  placeholder="np. Pitch Black ETB"
                />
              </div>
            </.form>
          </section>

          <section class="guide-results" aria-labelledby="guide-results-title">
            <div class="guide-results-heading">
              <h2 id="guide-results-title">
                {if @query == "", do: "Wszystkie produkty", else: "Wyniki wyszukiwania"}
              </h2>
              <p id="guide-result-count" aria-live="polite">
                {Polish.plural(@result_count, "produkt", "produkty", "produktów")}
              </p>
            </div>
            <ul id="guide-products" class="guide-products" phx-update="stream">
              <li id="guide-products-empty" class="guide-empty hidden only:block">
                Nie znaleźliśmy produktu pasującego do „{@query}”. Spróbuj nazwy dodatku albo rodzaju produktu.
              </li>
              <li :for={{dom_id, summary} <- @streams.products} id={dom_id} class="guide-product">
                <.link navigate={~p"/produkty/#{summary.product.slug}"} class="guide-product-link">
                  <.product_image url={summary.image_url} alt="" class="guide-product-image" />
                  <div class="guide-product-copy">
                    <h3 class="guide-product-name">{summary.product.name}</h3>
                    <p class="guide-product-meta">{product_meta(summary.product)}</p>
                    <p class="guide-product-price">
                      <%= if summary.verdict.cheapest do %>
                        <strong>{Polish.price(summary.verdict.cheapest.price)}</strong>
                        <span>· {shop_name(summary.verdict.cheapest)}</span>
                      <% else %>
                        <span>Brak w sklepach</span>
                      <% end %>
                    </p>
                  </div>
                  <.verdict_badge
                    status={summary.verdict.status}
                    id={"verdict-#{summary.product.slug}"}
                    class="guide-product-verdict"
                  />
                </.link>
              </li>
            </ul>
          </section>

          <.guide_footnote />
        </main>
      </div>
    </Layouts.app>
    """
  end
end
