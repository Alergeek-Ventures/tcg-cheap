defmodule TcgCheapWeb.HomeLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Catalogue.SearchText
  alias TcgCheap.Pricing.Singles.Freshness

  @max_autocomplete_options 10
  @recent_release_window_days 180

  @impl true
  def mount(_params, _session, socket) do
    as_of = DateTime.utc_now()

    {price_changes, price_changes_ok?} =
      safe_discovery(fn -> TcgCheap.Core.list_homepage_price_changes(as_of, 4) end)

    {recent_sealed, recent_sealed_ok?} =
      safe_discovery(fn ->
        as_of_date = DateTime.to_date(as_of)

        TcgCheap.Core.list_recent_public_sealed_products(
          Date.add(as_of_date, 1 - @recent_release_window_days),
          as_of_date
        )
      end)

    {:ok,
     socket
     |> assign(
       page_title: "Compare Pokémon prices",
       mode: :singles,
       search_form: to_form(%{"query" => ""}, as: :search),
       search_status: :idle,
       result_count: 0,
       search_query: "",
       autocomplete_options: [],
       active_option_id: nil,
       price_changes_count: length(price_changes),
       recent_sealed_count: length(recent_sealed),
       discovery_available?: price_changes_ok? or recent_sealed_ok?,
       fallback_cards_count: 0,
       fallback_sealed_count: 0
     )
     |> stream_configure(:card_results, dom_id: fn result -> "card-option-#{result.id}" end)
     |> stream_configure(:sealed_results, dom_id: fn result -> "sealed-option-#{result.id}" end)
     |> stream_configure(:discovery_price_changes,
       dom_id: fn result -> "discovery-change-#{result.card_printing_id}" end
     )
     |> stream_configure(:discovery_recent_sealed,
       dom_id: fn result -> "discovery-sealed-#{result.id}" end
     )
     |> stream_configure(:fallback_cards, dom_id: fn result -> "fallback-card-#{result.id}" end)
     |> stream_configure(:fallback_sealed,
       dom_id: fn result -> "fallback-sealed-#{result.id}" end
     )
     |> stream(:card_results, [])
     |> stream(:sealed_results, [])
     |> stream(:discovery_price_changes, price_changes)
     |> stream(:discovery_recent_sealed, recent_sealed)
     |> stream(:fallback_cards, [])
     |> stream(:fallback_sealed, [])}
  end

  @impl true
  def handle_event(
        "search",
        %{"search" => %{"query" => query}},
        %{assigns: %{mode: :sealed}} = socket
      ) do
    normalized = SearchText.normalize(query)
    socket = assign(socket, :search_query, normalized)

    cond do
      normalized == "" -> clear_sealed_results(socket, :idle)
      length(String.graphemes(normalized)) < 2 -> clear_sealed_results(socket, :short)
      length(String.graphemes(normalized)) > 100 -> clear_sealed_results(socket, :invalid)
      true -> search_sealed_locally(socket, normalized)
    end
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    normalized = SearchText.normalize(query)
    socket = assign(socket, :search_query, normalized)

    cond do
      normalized == "" -> clear_results(socket, :idle)
      length(String.graphemes(normalized)) < 2 -> clear_results(socket, :short)
      length(String.graphemes(normalized)) > 100 -> clear_results(socket, :invalid)
      true -> search_locally(socket, normalized)
    end
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_mode", %{"mode" => "sealed"}, socket) do
    {:noreply,
     socket
     |> assign(mode: :sealed, search_form: to_form(%{"query" => ""}, as: :search))
     |> assign(
       search_status: :idle,
       result_count: 0,
       search_query: "",
       autocomplete_options: [],
       active_option_id: nil,
       fallback_cards_count: 0,
       fallback_sealed_count: 0
     )
     |> stream(:card_results, [], reset: true)
     |> stream(:sealed_results, [], reset: true)
     |> stream(:fallback_cards, [], reset: true)
     |> stream(:fallback_sealed, [], reset: true)}
  end

  def handle_event("switch_mode", %{"mode" => "singles"}, socket) do
    {:noreply,
     socket
     |> assign(mode: :singles, search_form: to_form(%{"query" => ""}, as: :search))
     |> assign(
       search_status: :idle,
       result_count: 0,
       search_query: "",
       autocomplete_options: [],
       active_option_id: nil,
       fallback_cards_count: 0,
       fallback_sealed_count: 0
     )
     |> stream(:card_results, [], reset: true)
     |> stream(:sealed_results, [], reset: true)
     |> stream(:fallback_cards, [], reset: true)
     |> stream(:fallback_sealed, [], reset: true)}
  end

  def handle_event("switch_mode", _params, socket), do: {:noreply, socket}

  def handle_event("autocomplete_key", %{"key" => key}, socket)
      when key in ["ArrowDown", "ArrowUp"] do
    move_active_option(socket, key)
  end

  def handle_event("autocomplete_key", %{"key" => "Enter", "query" => query}, socket)
      when is_binary(query) do
    if SearchText.normalize(query) == socket.assigns.search_query do
      case Enum.find(
             socket.assigns.autocomplete_options,
             &(&1.dom_id == socket.assigns.active_option_id)
           ) do
        %{slug: slug} when socket.assigns.mode == :sealed ->
          {:noreply, push_navigate(socket, to: ~p"/sealed/#{slug}")}

        %{tcgdex_id: tcgdex_id} ->
          {:noreply, push_navigate(socket, to: ~p"/cards/#{tcgdex_id}")}

        nil ->
          {:noreply, socket}
      end
    else
      clear_results_for_mode(socket, :idle)
    end
  end

  def handle_event("autocomplete_key", %{"key" => "Enter"}, socket), do: {:noreply, socket}

  def handle_event("autocomplete_key", %{"key" => "Escape"}, socket) do
    clear_results_for_mode(socket, :idle)
  end

  def handle_event("autocomplete_key", _params, socket), do: {:noreply, socket}

  def handle_event(
        "select_option",
        %{"tcgdex-id" => tcgdex_id},
        %{assigns: %{mode: :singles}} = socket
      ) do
    case Enum.find(socket.assigns.autocomplete_options, &(Map.get(&1, :tcgdex_id) == tcgdex_id)) do
      %{tcgdex_id: ^tcgdex_id} ->
        {:noreply, push_navigate(socket, to: ~p"/cards/#{tcgdex_id}")}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("select_option", %{"slug" => slug}, %{assigns: %{mode: :sealed}} = socket) do
    case Enum.find(socket.assigns.autocomplete_options, &(&1.slug == slug)) do
      %{slug: ^slug} -> {:noreply, push_navigate(socket, to: ~p"/sealed/#{slug}")}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("select_option", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}>TCG CHEAP</.link>
        </header>

        <main id="decision-main" class="decision-main">
          <div class="decision-container">
            <section class="decision-intro" aria-labelledby="decision-title">
              <h1 id="decision-title">Compare Pokémon prices</h1>
              <div id="mode-switch" class="mode-switch" role="group" aria-label="Choose product mode">
                <button
                  id="mode-singles"
                  type="button"
                  phx-click="switch_mode"
                  phx-value-mode="singles"
                  aria-pressed={to_string(@mode == :singles)}
                >Singles</button>
                <button
                  id="mode-sealed"
                  type="button"
                  phx-click="switch_mode"
                  phx-value-mode="sealed"
                  aria-pressed={to_string(@mode == :sealed)}
                >Sealed products</button>
              </div>
            </section>

            <%= if @mode == :singles do %>
              <section class="decision-search" aria-labelledby="search-title">
                <h2 id="search-title">Find a card</h2>
                <.form for={@search_form} id="card-search-form">
                  <label for="card-search-query" class="sr-only">Search for a card</label>
                  <div class="search-field-wrap">
                    <.input
                      field={@search_form[:query]}
                      type="search"
                      id="card-search-query"
                      name="search[query]"
                      autocomplete="off"
                      maxlength="100"
                      phx-hook="CardAutocomplete"
                      role="combobox"
                      aria-autocomplete="list"
                      aria-controls="card-search-results"
                      aria-expanded={to_string(@autocomplete_options != [])}
                      aria-activedescendant={active_option_dom_id(@active_option_id)}
                      placeholder="Search for a card"
                    />
                  </div>
                </.form>
              </section>

              <section class="decision-results" aria-label="Search results">
                <p id="card-search-summary" class="sr-only" aria-live="polite">
                  {summary_text(
                    @search_status,
                    @result_count,
                    @search_query,
                    @fallback_sealed_count
                  )}
                </p>

                <div
                  id="card-search-results"
                  phx-update="stream"
                  class="evidence-slips"
                  role="listbox"
                  aria-label="Card search results"
                >
                  <div
                    :for={{stream_id, result} <- @streams.card_results}
                    id={stream_id}
                    class={["evidence-slot", @active_option_id == stream_id && "active-option"]}
                    role="option"
                    aria-selected={to_string(@active_option_id == stream_id)}
                    aria-labelledby={option_labelledby(result)}
                    phx-click="select_option"
                    phx-value-tcgdex-id={result.tcgdex_id}
                    tabindex="-1"
                  >
                    <article
                      id={"card-search-result-#{result.id}"}
                      class="evidence-slip"
                      aria-labelledby={"card-search-name-#{result.id} card-search-set-#{result.id}"}
                    >
                      <div class="evidence-art">
                        <%= if image_url = CardImage.thumbnail_url(result.image_url) do %>
                          <img
                            id={"card-search-image-#{result.id}"}
                            src={image_url}
                            alt={card_link_label(result)}
                            width="245"
                            height="337"
                            loading="lazy"
                            decoding="async"
                            referrerpolicy="no-referrer"
                          />
                        <% else %>
                          <div
                            id={"card-search-image-missing-#{result.id}"}
                            class="card-image-missing"
                            role="img"
                            aria-label="No image is available for this card."
                          >
                            <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
                          </div>
                        <% end %>
                      </div>
                      <div class="evidence-copy">
                        <p id={"card-search-name-#{result.id}"} class="evidence-name">
                          {result.name}
                        </p>
                        <p id={"card-search-set-#{result.id}"} class="evidence-set">
                          {result.set_name} · #{result.collector_number}
                        </p>
                        <div
                          :if={rarity_present?(result.rarity)}
                          class="evidence-tags"
                          aria-label="Rarity"
                        >
                          <span
                            :if={result.rarity}
                            class="evidence-tag"
                            id={"card-rarity-#{result.id}"}
                          >{result.rarity}</span>
                        </div>
                        <div class="estimate-cell">
                          <strong id={"card-estimate-#{result.id}"}>{estimate_display(
                            Map.get(result, :tcgdex_cardmarket_v1_current_valuation)
                          )}</strong>
                          <span
                            :if={Map.get(result, :tcgdex_cardmarket_v1_current_valuation)}
                            id={"card-freshness-#{result.id}"}
                          >{freshness_text(Map.get(result, :tcgdex_cardmarket_v1_current_valuation))}</span>
                        </div>
                        <span
                          id={"card-select-action-#{result.id}"}
                          class="detail-action"
                        >View price</span>
                      </div>
                    </article>
                  </div>
                </div>

                <div :if={@search_status == :short} id="card-search-short" class="state-note">
                  Type at least 2 characters.
                </div>
                <div :if={@search_status == :empty} id="card-search-empty" class="state-note">
                  No cards found.
                </div>
                <div
                  :if={@search_status == :error}
                  id="card-search-error"
                  class="state-note state-error"
                >
                  Search is unavailable. Try again.
                </div>
                <div :if={@search_status == :invalid} id="card-search-invalid" class="state-note">
                  Search is too long. Use 100 characters or fewer.
                </div>

                <p :if={@search_status == :results} class="estimate-note">
                  Estimates only · Shipping not included.
                </p>
                <details :if={@search_status == :results} id="price-details" class="price-details">
                  <summary>How prices work</summary>
                  <div id="price-methodology" class="price-methodology">
                    <p>
                      <strong>Methodology:</strong>
                      aggregate Cardmarket estimate from TCGdex under <code>tcgdex_cardmarket_v1</code>.
                      Seller identity and seller/offer count are unavailable from the active aggregate;
                      language, condition, finish exactness, and Poland shipping are not verified; shipping
                      is not calculated.
                    </p>
                  </div>
                  <aside id="price-disclaimer" class="price-disclaimer" aria-label="Price disclaimer">
                    TCG Cheap is unofficial and not affiliated with Pokémon, Nintendo, TCGdex,
                    Cardmarket, or listed companies. This estimate is not guaranteed resale value
                    or investment advice.
                  </aside>
                </details>
              </section>
            <% else %>
              <section class="decision-search" aria-labelledby="sealed-search-title">
                <h2 id="sealed-search-title">Find a sealed product</h2>
                <.form for={@search_form} id="sealed-search-form">
                  <label for="sealed-search-query" class="sr-only">Search for a sealed product</label>
                  <div class="search-field-wrap">
                    <.input
                      field={@search_form[:query]}
                      type="search"
                      id="sealed-search-query"
                      name="search[query]"
                      autocomplete="off"
                      maxlength="100"
                      phx-hook="CardAutocomplete"
                      role="combobox"
                      aria-autocomplete="list"
                      aria-controls="sealed-search-results"
                      aria-expanded={to_string(@autocomplete_options != [])}
                      aria-activedescendant={active_option_dom_id(@active_option_id)}
                      placeholder="Search for a sealed product"
                    />
                  </div>
                </.form>
              </section>

              <section class="decision-results" aria-label="Sealed product search results">
                <div
                  id="sealed-search-results"
                  phx-update="stream"
                  class="evidence-slips"
                  role="listbox"
                  aria-label="Sealed product search results"
                >
                  <div
                    :for={{stream_id, result} <- @streams.sealed_results}
                    id={stream_id}
                    class={["evidence-slot", @active_option_id == stream_id && "active-option"]}
                    role="option"
                    aria-selected={to_string(@active_option_id == stream_id)}
                    aria-labelledby={sealed_option_labelledby(result)}
                    phx-click="select_option"
                    phx-value-slug={result.slug}
                    tabindex="-1"
                  >
                    <article id={"sealed-search-result-#{result.id}"} class="evidence-slip">
                      <div
                        class="evidence-art"
                        id={"sealed-art-#{result.id}"}
                        role="img"
                        aria-label={"No image is available for #{result.name}."}
                      >
                        <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 14 36 5l24 9v68l-24 9-24-9zM12 14l24 9 24-9M36 23v68M22 39h28M22 49h20" /></svg>
                      </div>
                      <div class="evidence-copy">
                        <p id={"sealed-search-name-#{result.id}"} class="evidence-name">
                          {result.name}
                        </p>
                        <p id={"sealed-search-type-#{result.id}"} class="evidence-set">
                          {human_product_type(result.product_type)}
                        </p>
                        <p
                          :if={result.series_name || result.set_name}
                          id={"sealed-search-collection-#{result.id}"}
                          class="evidence-set"
                        >
                          {sealed_collection(result)}
                        </p>
                        <p id={"sealed-search-release-#{result.id}"} class="evidence-set">
                          Released {format_release_date(result.release_date)}
                        </p>
                        <div
                          :if={result.distribution_status == "discontinued"}
                          class="evidence-tags"
                          aria-label="Product status"
                        >
                          <span id={"sealed-discontinued-#{result.id}"} class="evidence-tag">Discontinued</span>
                        </div>
                        <span id={"sealed-select-action-#{result.id}"} class="detail-action">View offers</span>
                      </div>
                    </article>
                  </div>
                </div>
                <.sealed_search_state
                  status={@search_status}
                  count={@result_count}
                  query={@search_query}
                  fallback_count={@fallback_cards_count}
                />
              </section>
            <% end %>

            <.discovery_ledgers
              streams={@streams}
              price_count={@price_changes_count}
              sealed_count={@recent_sealed_count}
              available?={@discovery_available?}
              hidden={@search_status != :idle}
            />

            <%= if @search_status == :empty do %>
              <.fallback_ledgers
                mode={@mode}
                streams={@streams}
                cards_count={@fallback_cards_count}
                sealed_count={@fallback_sealed_count}
              />
            <% end %>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  attr :streams, :map, required: true
  attr :price_count, :integer, required: true
  attr :sealed_count, :integer, required: true
  attr :available?, :boolean, required: true
  attr :hidden, :boolean, required: true

  def discovery_ledgers(assigns) do
    ~H"""
    <section
      :if={@price_count > 0 or @sealed_count > 0}
      id="homepage-discovery"
      class="discovery-ledgers"
      aria-label="Local discovery"
      hidden={@hidden}
    >
      <div :if={@price_count > 0} id="biggest-changes" class="discovery-ledger">
        <div class="discovery-heading">
          <h2>Biggest changes</h2><span>{@price_count}</span>
        </div>
        <div id="biggest-changes-list" phx-update="stream" class="discovery-rows">
          <.link
            :for={{stream_id, change} <- @streams.discovery_price_changes}
            id={stream_id}
            navigate={~p"/cards/#{change.tcgdex_id}"}
            class="discovery-row"
          >
            <div :if={CardImage.thumbnail_url(change.image_url)} class="discovery-thumb">
              <img
                src={CardImage.thumbnail_url(change.image_url)}
                alt=""
                width="80"
                height="110"
                loading="lazy"
                decoding="async"
                referrerpolicy="no-referrer"
              />
            </div>
            <div
              :if={!CardImage.thumbnail_url(change.image_url)}
              id={"discovery-image-missing-#{change.card_printing_id}"}
              class="discovery-thumb card-image-missing"
              role="img"
              aria-label="No image is available for this card."
            >
              <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
            </div>
            <div class="discovery-copy">
              <h3 id={"discovery-change-name-#{change.card_printing_id}"}>{change.name}</h3><p>
                {change.set_name} · #{change.collector_number}
              </p><p class="discovery-evidence">
                <strong>€{format_eur(change.current_value_eur)}</strong>
                <span>{signed_percent(change.change_percent)}</span>
                <span>{Date.diff(change.current_date, change.start_date)} days</span>
                <span>{discovery_freshness_text(change.current_fetched_at)}</span>
              </p>
            </div>
          </.link>
        </div>
      </div>
      <div :if={@sealed_count > 0} id="recent-sealed-releases" class="discovery-ledger">
        <div class="discovery-heading">
          <h2>Recent sealed releases</h2><span>{@sealed_count}</span>
        </div>
        <div id="recent-sealed-releases-list" phx-update="stream" class="discovery-rows">
          <.link
            :for={{stream_id, product} <- @streams.discovery_recent_sealed}
            id={stream_id}
            navigate={~p"/sealed/#{product.slug}"}
            class="discovery-row discovery-sealed-row"
          >
            <div class="discovery-copy">
              <h3 id={"discovery-sealed-name-#{product.id}"}>{product.name}</h3><p>
                {human_product_type(product.product_type)} · Released {format_release_date(
                  product.release_date
                )}
              </p><p :if={product.distribution_status == "discontinued"} class="discovery-status">
                Discontinued
              </p>
            </div>
          </.link>
        </div>
      </div>
    </section>
    <p :if={!@available?} id="homepage-discovery-unavailable" class="state-note" hidden={@hidden}>
      Local discovery is temporarily unavailable.
    </p>
    """
  end

  attr :mode, :atom, required: true
  attr :streams, :map, required: true
  attr :cards_count, :integer, required: true
  attr :sealed_count, :integer, required: true

  def fallback_ledgers(assigns) do
    ~H"""
    <section
      :if={@mode == :singles and @sealed_count > 0}
      id="sealed-fallback"
      class="fallback-ledger"
      aria-labelledby="sealed-fallback-title"
    >
      <h2 id="sealed-fallback-title">Sealed products instead</h2>
      <div id="sealed-fallback-list" phx-update="stream">
        <.link
          :for={{id, product} <- @streams.fallback_sealed}
          id={id}
          navigate={~p"/sealed/#{product.slug}"}
        >{product.name} · {human_product_type(product.product_type)}</.link>
      </div>
    </section>
    <section
      :if={@mode == :sealed and @cards_count > 0}
      id="card-fallback"
      class="fallback-ledger"
      aria-labelledby="card-fallback-title"
    >
      <h2 id="card-fallback-title">Singles instead</h2>
      <div id="card-fallback-list" phx-update="stream">
        <.link
          :for={{id, card} <- @streams.fallback_cards}
          id={id}
          navigate={~p"/cards/#{card.tcgdex_id}"}
        >{card.name} · {card.set_name} · #{card.collector_number}</.link>
      </div>
    </section>
    """
  end

  attr :status, :atom, required: true
  attr :count, :integer, required: true
  attr :query, :string, required: true
  attr :fallback_count, :integer, required: true

  def sealed_search_state(assigns) do
    ~H"""
    <p id="sealed-search-summary" class="sr-only" aria-live="polite">
      {sealed_summary_text(@status, @count, @query, @fallback_count)}
    </p>
    <div :if={@status == :short} id="sealed-search-short" class="state-note">
      Type at least 2 characters.
    </div>
    <div :if={@status == :empty} id="sealed-search-empty" class="state-note">
      No sealed products found.
    </div>
    <div :if={@status == :error} id="sealed-search-error" class="state-note state-error">
      Sealed product search is unavailable. Try again.
    </div>
    <div :if={@status == :invalid} id="sealed-search-invalid" class="state-note">
      Search is too long. Use 100 characters or fewer.
    </div>
    """
  end

  defp estimate_display(nil), do: "Price unavailable"
  defp estimate_display(%{value_eur: value}), do: "€" <> format_eur(value)
  defp estimate_display(_), do: "Price unavailable"

  defp freshness_text(valuation) do
    now = DateTime.utc_now()
    updated_text(valuation.fetched_at, Freshness.status(valuation, now), now)
  end

  defp discovery_freshness_text(fetched_at) do
    now = DateTime.utc_now()
    updated_text(fetched_at, Freshness.status_at(fetched_at, now), now)
  end

  defp updated_text(fetched_at, status, now) do
    age = max(DateTime.diff(now, fetched_at, :day), 0)

    updated =
      case age do
        0 -> "Updated today"
        1 -> "Updated yesterday"
        days -> "Updated #{days} days ago"
      end

    if status == :stale,
      do: updated <> " · May be outdated",
      else: updated
  end

  defp format_eur(%Decimal{} = value) do
    [whole, fraction] =
      value
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> String.split(".", parts: 2)
      |> Kernel.++(["0"])
      |> Enum.take(2)

    whole <> "." <> String.pad_trailing(fraction, 2, "0")
  end

  defp format_eur(value) when is_binary(value), do: format_eur(Decimal.new(value))
  defp format_eur(value) when is_integer(value), do: format_eur(Decimal.new(value))

  defp signed_percent(%Decimal{} = value) do
    sign = if Decimal.compare(value, Decimal.new(0)) == :lt, do: "", else: "+"
    sign <> (value |> Decimal.round(2) |> Decimal.to_string(:normal)) <> "%"
  end

  defp signed_percent(value) when is_binary(value), do: signed_percent(Decimal.new(value))

  defp search_locally(socket, query) do
    case TcgCheap.Core.search_card_printings(query) do
      {:ok, results} when is_list(results) and results != [] ->
        options =
          results
          |> Enum.take(@max_autocomplete_options)
          |> Enum.map(fn result ->
            %{dom_id: "card-option-#{result.id}", tcgdex_id: result.tcgdex_id, result: result}
          end)

        {:noreply,
         socket
         |> assign(
           search_status: :results,
           result_count: length(results),
           autocomplete_options: options,
           active_option_id: List.first(options).dom_id
         )
         |> clear_fallback_streams()
         |> stream(:card_results, Enum.map(options, & &1.result), reset: true)}

      {:ok, []} ->
        {:noreply,
         socket
         |> assign(
           search_status: :empty,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil
         )
         |> load_sealed_fallback(query)
         |> stream(:card_results, [], reset: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           search_status: :error,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil
         )
         |> clear_fallback_streams()
         |> stream(:card_results, [], reset: true)}
    end
  end

  defp search_sealed_locally(socket, query) do
    case TcgCheap.Core.search_public_sealed_products(query, @max_autocomplete_options) do
      {:ok, results} when is_list(results) and results != [] ->
        options =
          Enum.map(results, &%{dom_id: "sealed-option-#{&1.id}", slug: &1.slug, result: &1})

        {:noreply,
         socket
         |> assign(
           search_status: :results,
           result_count: length(results),
           autocomplete_options: options,
           active_option_id: List.first(options).dom_id
         )
         |> clear_fallback_streams()
         |> stream(:sealed_results, Enum.map(options, & &1.result), reset: true)}

      {:ok, []} ->
        {:noreply,
         socket
         |> assign(
           search_status: :empty,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil
         )
         |> load_card_fallback(query)
         |> stream(:sealed_results, [], reset: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           search_status: :error,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil
         )
         |> clear_fallback_streams()
         |> stream(:sealed_results, [], reset: true)}
    end
  end

  defp clear_fallback_streams(socket) do
    socket
    |> assign(fallback_cards_count: 0, fallback_sealed_count: 0)
    |> stream(:fallback_cards, [], reset: true)
    |> stream(:fallback_sealed, [], reset: true)
  end

  defp load_sealed_fallback(socket, query) do
    case TcgCheap.Core.search_public_sealed_products(query, 4) do
      {:ok, products} when is_list(products) ->
        socket
        |> assign(fallback_sealed_count: length(products))
        |> stream(:fallback_sealed, products, reset: true)
        |> stream(:fallback_cards, [], reset: true)

      _ ->
        clear_fallback_streams(socket)
    end
  end

  defp load_card_fallback(socket, query) do
    case TcgCheap.Core.search_card_printings(query, 4) do
      {:ok, cards} when is_list(cards) ->
        socket
        |> assign(fallback_cards_count: length(cards))
        |> stream(:fallback_cards, cards, reset: true)
        |> stream(:fallback_sealed, [], reset: true)

      _ ->
        clear_fallback_streams(socket)
    end
  end

  defp safe_discovery(fun) do
    case fun.() do
      {:ok, rows} when is_list(rows) -> {rows, true}
      _ -> {[], false}
    end
  rescue
    _ -> {[], false}
  end

  defp clear_results(socket, status) do
    {:noreply,
     socket
     |> assign(
       search_status: status,
       result_count: 0,
       autocomplete_options: [],
       active_option_id: nil
     )
     |> clear_fallback_streams()
     |> stream(:card_results, [], reset: true)}
  end

  defp clear_sealed_results(socket, status) do
    {:noreply,
     socket
     |> assign(
       search_status: status,
       result_count: 0,
       autocomplete_options: [],
       active_option_id: nil
     )
     |> clear_fallback_streams()
     |> stream(:sealed_results, [], reset: true)}
  end

  defp clear_results_for_mode(%{assigns: %{mode: :sealed}} = socket, status),
    do: clear_sealed_results(socket, status)

  defp clear_results_for_mode(socket, status), do: clear_results(socket, status)

  defp move_active_option(socket, key) do
    options = socket.assigns.autocomplete_options

    if options == [] do
      {:noreply, socket}
    else
      current_index = Enum.find_index(options, &(&1.dom_id == socket.assigns.active_option_id))
      next_index = next_option_index(key, current_index, length(options))
      selected = Enum.at(options, next_index)
      previous = Enum.find(options, &(&1.dom_id == socket.assigns.active_option_id))

      stream_options =
        [previous, selected]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.dom_id)

      {:noreply,
       socket
       |> assign(:active_option_id, selected.dom_id)
       |> stream_insert_options(stream_options)}
    end
  end

  defp stream_insert_options(socket, options) do
    stream_name = if socket.assigns.mode == :sealed, do: :sealed_results, else: :card_results

    Enum.reduce(options, socket, fn option, socket ->
      stream_insert(socket, stream_name, option.result)
    end)
  end

  defp next_option_index("ArrowDown", nil, _count), do: 0
  defp next_option_index("ArrowUp", nil, count), do: count - 1
  defp next_option_index("ArrowDown", index, count), do: rem(index + 1, count)
  defp next_option_index("ArrowUp", index, count), do: rem(index - 1 + count, count)

  defp active_option_dom_id(nil), do: nil
  defp active_option_dom_id(id), do: id

  defp summary_text(:results, 1, query, _fallback_count), do: "1 card for #{query}"
  defp summary_text(:results, count, query, _fallback_count), do: "#{count} cards for #{query}"

  defp summary_text(:empty, _count, query, 1),
    do: "No cards found for #{query}. 1 sealed product suggestion is available."

  defp summary_text(:empty, _count, query, fallback_count) when fallback_count > 1,
    do: "No cards found for #{query}. #{fallback_count} sealed product suggestions are available."

  defp summary_text(:empty, _count, query, _fallback_count), do: "No cards found for #{query}"
  defp summary_text(:error, _count, query, _fallback_count), do: "Search unavailable for #{query}"
  defp summary_text(:invalid, _count, query, _fallback_count), do: "Search too long for #{query}"

  defp summary_text(:short, _count, query, _fallback_count),
    do: "Type at least 2 characters for #{query}"

  defp summary_text(_status, _count, _query, _fallback_count), do: ""

  defp sealed_summary_text(:results, 1, query, _fallback_count),
    do: "1 sealed product for #{query}"

  defp sealed_summary_text(:results, count, query, _fallback_count),
    do: "#{count} sealed products for #{query}"

  defp sealed_summary_text(:empty, _count, _query, 1),
    do: "No sealed products found. 1 single-card suggestion is available."

  defp sealed_summary_text(:empty, _count, _query, fallback_count) when fallback_count > 1,
    do: "No sealed products found. #{fallback_count} single-card suggestions are available."

  defp sealed_summary_text(:empty, _count, _query, _fallback_count),
    do: "No sealed products found"

  defp sealed_summary_text(:short, _count, _query, _fallback_count),
    do: "Type at least 2 characters to find a sealed product"

  defp sealed_summary_text(:error, _count, query, _fallback_count),
    do: "Search unavailable for #{query}"

  defp sealed_summary_text(:invalid, _count, _query, _fallback_count),
    do: "Sealed product search too long"

  defp sealed_summary_text(_status, _count, _query, _fallback_count), do: ""

  defp sealed_option_labelledby(result) do
    [
      "sealed-search-name-#{result.id}",
      "sealed-search-type-#{result.id}",
      if(result.series_name || result.set_name, do: "sealed-search-collection-#{result.id}"),
      "sealed-search-release-#{result.id}",
      if(result.distribution_status == "discontinued", do: "sealed-discontinued-#{result.id}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp human_product_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp sealed_collection(result),
    do: Enum.filter([result.series_name, result.set_name], & &1) |> Enum.join(" · ")

  defp format_release_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  defp format_release_date(_), do: "Date unavailable"

  defp rarity_present?(rarity), do: not is_nil(rarity) and rarity != ""

  defp card_link_label(result),
    do: "#{result.name}, #{result.set_name}, collector number #{result.collector_number}"

  defp option_labelledby(result) do
    [
      "card-search-name-#{result.id}",
      "card-search-set-#{result.id}",
      if(rarity_present?(result.rarity), do: "card-rarity-#{result.id}"),
      "card-estimate-#{result.id}",
      if(Map.get(result, :tcgdex_cardmarket_v1_current_valuation),
        do: "card-freshness-#{result.id}"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
