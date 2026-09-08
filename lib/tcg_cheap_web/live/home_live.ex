defmodule TcgCheapWeb.HomeLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.{CardImage, ExternalImage}
  alias TcgCheap.Catalogue.SearchText
  alias TcgCheap.Pricing.Singles.Freshness
  alias TcgCheap.Pricing.Singles.ValuationNotifications
  alias TcgCheap.Pricing.Singles.ValuationPolicy

  @max_autocomplete_options 10
  @max_discovery_rows 6
  # Keep the idle shelf useful for long-lived catalogue data (including 151).
  @recent_sealed_window_days 1_825
  @impl true
  def mount(_params, _session, socket) do
    as_of = DateTime.utc_now()

    {price_changes, price_changes_ok?} =
      safe_discovery(fn ->
        TcgCheap.Core.list_homepage_price_changes(as_of, @max_discovery_rows)
      end)

    {sealed_price_changes, sealed_price_changes_ok?} =
      safe_discovery(fn ->
        TcgCheap.Core.list_homepage_sealed_price_changes(as_of, @max_discovery_rows)
      end)

    as_of_date = DateTime.to_date(as_of)

    {recent_cards, recent_cards_ok?} =
      safe_discovery(fn -> TcgCheap.Core.list_public_recently_tracked_card_printings() end)
      |> then(fn {rows, ok?} -> {Enum.take(rows, @max_discovery_rows), ok?} end)

    {recent_sealed, recent_sealed_ok?} =
      safe_discovery(fn ->
        TcgCheap.Core.list_recent_public_sealed_products(
          Date.add(as_of_date, -@recent_sealed_window_days),
          as_of_date
        )
      end)
      |> then(fn {rows, ok?} -> {Enum.take(rows, @max_discovery_rows), ok?} end)

    {single_risers, single_fallers} = split_movers(price_changes)
    {sealed_risers, sealed_fallers} = split_movers(sealed_price_changes)

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
       singles_risers_count: length(single_risers),
       singles_fallers_count: length(single_fallers),
       sealed_risers_count: length(sealed_risers),
       sealed_fallers_count: length(sealed_fallers),
       singles_movers_available?: price_changes_ok?,
       sealed_movers_available?: sealed_price_changes_ok?,
       recent_cards_available?: recent_cards_ok?,
       recent_sealed_available?: recent_sealed_ok?,
       recent_cards_count: length(recent_cards),
       recent_sealed_count: length(recent_sealed),
       fallback_cards_count: 0,
       fallback_sealed_count: 0,
       home_search_cards: [],
       home_fallback_cards: [],
       home_recent_cards: recent_cards,
       home_single_movers: single_risers ++ single_fallers,
       subscribed_mapping_ids: MapSet.new(),
       subscribed_valuation_collection?: false,
       collection_refresh_timer: nil,
       collection_refresh_token: nil
     )
     |> stream_configure(:card_results, dom_id: fn result -> "card-option-#{result.id}" end)
     |> stream_configure(:sealed_results, dom_id: fn result -> "sealed-option-#{result.id}" end)
     |> stream_configure(:market_single_risers,
       dom_id: fn result -> "market-single-riser-#{result.card_printing_id}" end
     )
     |> stream_configure(:market_single_fallers,
       dom_id: fn result -> "market-single-faller-#{result.card_printing_id}" end
     )
     |> stream_configure(:market_sealed_risers,
       dom_id: fn result -> "market-sealed-riser-#{result.sealed_product_id}" end
     )
     |> stream_configure(:market_sealed_fallers,
       dom_id: fn result -> "market-sealed-faller-#{result.sealed_product_id}" end
     )
     |> stream_configure(:fallback_cards, dom_id: fn result -> "fallback-card-#{result.id}" end)
     |> stream_configure(:fallback_sealed,
       dom_id: fn result -> "fallback-sealed-#{result.id}" end
     )
     |> stream_configure(:idle_recent_cards,
       dom_id: fn result -> "idle-recent-card-#{result.id}" end
     )
     |> stream_configure(:idle_recent_sealed,
       dom_id: fn result -> "idle-recent-sealed-#{result.id}" end
     )
     |> stream(:card_results, [])
     |> stream(:sealed_results, [])
     |> stream(:market_single_risers, single_risers)
     |> stream(:market_single_fallers, single_fallers)
     |> stream(:market_sealed_risers, sealed_risers)
     |> stream(:market_sealed_fallers, sealed_fallers)
     |> stream(:fallback_cards, [])
     |> stream(:fallback_sealed, [])
     |> stream(:idle_recent_cards, recent_cards)
     |> stream(:idle_recent_sealed, recent_sealed)
     |> maybe_sync_mapping_subscriptions()}
  end

  @impl true
  def handle_info({:card_mapping_changed, %{card_printing_id: id}}, socket)
      when is_binary(id) do
    if MapSet.member?(socket.assigns.subscribed_mapping_ids, id) do
      {:noreply, refresh_home_card(socket, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:singles_collection_invalidated, payload}, socket)
      when is_map(payload) and map_size(payload) == 0 do
    cancel_collection_refresh(socket.assigns.collection_refresh_timer)
    token = make_ref()
    timer = Process.send_after(self(), {:refresh_singles_collection, token}, 100)

    {:noreply,
     assign(socket,
       collection_refresh_timer: timer,
       collection_refresh_token: token
     )}
  end

  def handle_info(
        {:refresh_singles_collection, token},
        %{assigns: %{collection_refresh_token: token}} = socket
      ) do
    {:noreply,
     socket
     |> assign(collection_refresh_timer: nil, collection_refresh_token: nil)
     |> refresh_singles_discovery()}
  end

  def handle_info({:refresh_singles_collection, _stale_token}, socket), do: {:noreply, socket}

  def handle_info(_, socket), do: {:noreply, socket}

  defp cancel_collection_refresh(nil), do: :ok
  defp cancel_collection_refresh(timer), do: Process.cancel_timer(timer)

  @impl true
  def handle_params(params, uri, socket) do
    mode = mode_from_params(params)
    query = params |> Map.get("q", "") |> normalize_query_param()
    canonical_path = home_path(mode, query)

    socket =
      socket
      |> assign(
        mode: mode,
        search_query: query,
        search_form: to_form(%{"query" => query}, as: :search)
      )
      |> reset_search_state()

    if canonical_uri?(uri, canonical_path) do
      execute_search(socket, query)
    else
      {:noreply, push_patch(socket, to: canonical_path, replace: true)}
    end
  end

  @impl true
  def handle_event(
        "search",
        %{"search" => %{"query" => query}},
        socket
      ) do
    normalized = SearchText.normalize(query)
    {:noreply, push_patch(socket, to: home_path(socket.assigns.mode, normalized), replace: true)}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_mode", %{"mode" => "sealed"}, socket) do
    {:noreply, push_patch(socket, to: home_path(:sealed, ""))}
  end

  def handle_event("switch_mode", %{"mode" => "singles"}, socket) do
    {:noreply, push_patch(socket, to: home_path(:singles, ""))}
  end

  def handle_event("switch_mode_with_query", %{"mode" => "sealed"}, socket) do
    query = socket.assigns.search_query
    {:noreply, push_patch(socket, to: home_path(:sealed, query))}
  end

  def handle_event("switch_mode_with_query", %{"mode" => "singles"}, socket) do
    query = socket.assigns.search_query
    {:noreply, push_patch(socket, to: home_path(:singles, query))}
  end

  def handle_event("switch_mode_with_query", _params, socket), do: {:noreply, socket}

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
      <div class="decision-world home-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}><.fluent_icon name={:gift_card_add} />TCG CHEAP</.link>
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
                <h2 id="search-title">Find an exact printing</h2>
                <.form for={@search_form} id="card-search-form">
                  <label for="card-search-query" class="sr-only">Search for a card</label>
                  <div class="search-field-wrap">
                    <.fluent_icon name={:search} class="search-field-icon" />
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
                      placeholder="Name, set, or collector number"
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
                        <div class="evidence-identity">
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
                        </div>
                        <% valuation = ValuationPolicy.current_valuation(result) %>
                        <div class="estimate-cell">
                          <strong id={"card-estimate-#{result.id}"}>{estimate_display(valuation)}</strong>
                          <span :if={valuation} id={"card-freshness-#{result.id}"}>
                            {freshness_text(valuation)}
                          </span>
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
                  No cards found. Try a name, set, or collector number.
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
                  Estimate only · Condition and shipping may vary.
                </p>
              </section>
            <% else %>
              <section class="decision-search" aria-labelledby="sealed-search-title">
                <h2 id="sealed-search-title">Find a sealed product</h2>
                <p id="sealed-data-note" class="search-context">
                  Only approved catalogue products appear; local-shop evidence is shown when available.
                  The catalogue is still growing.
                </p>
                <.form for={@search_form} id="sealed-search-form">
                  <label for="sealed-search-query" class="sr-only">Search for a sealed product</label>
                  <div class="search-field-wrap">
                    <.fluent_icon name={:search} class="search-field-icon" />
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
                      placeholder="Product name, set, or series"
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
                      <div class="evidence-art" id={"sealed-art-#{result.id}"}>
                        <%= if image_url = sealed_image_url(result) do %>
                          <img
                            id={"sealed-search-image-#{result.id}"}
                            class="sealed-package-image"
                            src={image_url}
                            alt={result.name <> " packaging"}
                            width="578"
                            height="325"
                            loading="lazy"
                            decoding="async"
                            referrerpolicy="no-referrer"
                          />
                        <% else %>
                          <div role="img" aria-label={"No image is available for #{result.name}."}>
                            <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 14 36 5l24 9v68l-24 9-24-9zM12 14l24 9 24-9M36 23v68M22 39h28M22 49h20" /></svg>
                          </div>
                        <% end %>
                      </div>
                      <div class="evidence-copy">
                        <div class="evidence-identity">
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
                            Release {format_release_date(result.release_date)}
                          </p>
                          <div
                            :if={result.distribution_status == "discontinued"}
                            class="evidence-tags"
                            aria-label="Product status"
                          >
                            <span id={"sealed-discontinued-#{result.id}"} class="evidence-tag">Discontinued</span>
                          </div>
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

            <.market_movers
              streams={@streams}
              mode={@mode}
              singles_risers_count={@singles_risers_count}
              singles_fallers_count={@singles_fallers_count}
              sealed_risers_count={@sealed_risers_count}
              sealed_fallers_count={@sealed_fallers_count}
              singles_available?={@singles_movers_available?}
              sealed_available?={@sealed_movers_available?}
              recent_cards_available?={@recent_cards_available?}
              recent_sealed_available?={@recent_sealed_available?}
              recent_cards_count={@recent_cards_count}
              recent_sealed_count={@recent_sealed_count}
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
  attr :mode, :atom, required: true
  attr :singles_risers_count, :integer, required: true
  attr :singles_fallers_count, :integer, required: true
  attr :sealed_risers_count, :integer, required: true
  attr :sealed_fallers_count, :integer, required: true
  attr :singles_available?, :boolean, required: true
  attr :sealed_available?, :boolean, required: true
  attr :recent_cards_available?, :boolean, required: true
  attr :recent_sealed_available?, :boolean, required: true
  attr :recent_cards_count, :integer, required: true
  attr :recent_sealed_count, :integer, required: true
  attr :hidden, :boolean, required: true

  def market_movers(assigns) do
    ~H"""
    <section
      id="market-movers"
      class="market-movers"
      aria-labelledby="market-movers-title"
      hidden={@hidden}
    >
      <div class="market-heading">
        <h2 id="market-movers-title">Price movement</h2>
        <details id="price-details">
          <summary>
            <.fluent_icon name={:info} />Method<.fluent_icon
              name={:chevron_down}
              class="disclosure-chevron"
            />
          </summary>
          <p>
            Movers compare first and latest daily prices across the most recent 30 UTC dates; at
            least two dates and a change of 2% or more are required.
          </p>
          <p :if={@mode == :singles}>
            Singles use aggregate Cardmarket estimates—not offers; TCGdex supplies canonical card
            identity. Condition and shipping vary. TCG Cheap is not affiliated with Cardmarket or
            TCGdex.
          </p>
          <p :if={@mode == :sealed}>
            Sealed benchmarks use approved local-shop observations—not offers; condition and
            shipping vary. TCG Cheap is independent of observed shops.
          </p>
        </details>
      </div>
      <div
        id="market-singles-panel"
        class="market-mode-panel"
        hidden={@mode != :singles}
      >
        <.mover_lane
          :if={@singles_risers_count > 0}
          title="Risers"
          id="market-singles-risers"
          count={@singles_risers_count}
          empty="No qualified risers yet"
          streams={@streams.market_single_risers}
          kind={:single}
        />
        <.mover_lane
          :if={@singles_fallers_count > 0}
          title="Fallers"
          id="market-singles-fallers"
          count={@singles_fallers_count}
          empty="No qualified fallers yet"
          streams={@streams.market_single_fallers}
          kind={:single}
        />
      </div>
      <div
        id="market-sealed-panel"
        class="market-mode-panel"
        hidden={@mode != :sealed}
      >
        <.mover_lane
          :if={@sealed_risers_count > 0}
          title="Risers"
          id="market-sealed-risers"
          count={@sealed_risers_count}
          empty="No qualified risers yet"
          streams={@streams.market_sealed_risers}
          kind={:sealed}
        />
        <.mover_lane
          :if={@sealed_fallers_count > 0}
          title="Fallers"
          id="market-sealed-fallers"
          count={@sealed_fallers_count}
          empty="No qualified fallers yet"
          streams={@streams.market_sealed_fallers}
          kind={:sealed}
        />
      </div>
      <.recent_idle_ledger
        id="market-singles-recent"
        streams={@streams.idle_recent_cards}
        count={@recent_cards_count}
        available?={@recent_cards_available?}
        kind={:single}
        hidden={@mode != :singles}
      />
      <.recent_idle_ledger
        id="market-sealed-recent"
        streams={@streams.idle_recent_sealed}
        count={@recent_sealed_count}
        available?={@recent_sealed_available?}
        kind={:sealed}
        hidden={@mode != :sealed}
      />
      <p
        :if={
          (@mode == :singles and !@singles_available?) or (@mode == :sealed and !@sealed_available?)
        }
        id="market-movers-unavailable"
        class="state-note state-error"
      >
        Market movers are unavailable right now. Try again later.
      </p>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :streams, :any, required: true
  attr :count, :integer, required: true
  attr :available?, :boolean, required: true
  attr :kind, :atom, required: true
  attr :hidden, :boolean, required: true

  def recent_idle_ledger(assigns) do
    ~H"""
    <section
      id={@id}
      class="market-recent-ledger"
      aria-labelledby={"#{@id}-title"}
      hidden={@hidden}
    >
      <h3 id={"#{@id}-title"}>
        {recent_heading(@kind)}
      </h3>
      <%= if !@available? or @count == 0 do %>
        <p id={"#{@id}-empty"} class="market-empty">
          {recent_empty_copy(@kind, @available?)}
        </p>
      <% else %>
        <div id={"#{@id}-list"} phx-update="stream" class="market-rows">
          <%= if @kind == :single do %>
            <.recent_single_rows streams={@streams} />
          <% else %>
            <.recent_sealed_rows streams={@streams} />
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  defp recent_heading(:single), do: "Recently tracked"
  defp recent_heading(:sealed), do: "Recent releases"

  defp recent_empty_copy(:single, true),
    do: "No recent prices yet. Search by name, set, or collector number."

  defp recent_empty_copy(:sealed, true),
    do: "No approved sealed products yet. Search by product, set, or series."

  defp recent_empty_copy(:single, false),
    do: "Recent local data is unavailable. Try a search again later."

  defp recent_empty_copy(:sealed, false),
    do: "Approved sealed product data is unavailable. Try a product, set, or series search later."

  attr :streams, :any, required: true

  def recent_single_rows(assigns) do
    ~H"""
    <.link
      :for={{stream_id, card} <- @streams}
      id={stream_id}
      navigate={~p"/cards/#{card.tcgdex_id}"}
      class="market-row"
    >
      <div class="market-thumb">
        <%= if image_url = CardImage.thumbnail_url(card.image_url) do %>
          <img
            src={image_url}
            alt=""
            width="80"
            height="110"
            loading="lazy"
            decoding="async"
            referrerpolicy="no-referrer"
          />
        <% else %>
          <span
            class="market-image-fallback"
            role="img"
            aria-label="No image is available for this card."
          ><svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg></span>
        <% end %>
      </div>
      <% valuation = ValuationPolicy.current_valuation(card) %>
      <div class="market-copy">
        <h4>{card.name}</h4>
        <p>{card.set_name} · #{card.collector_number}</p>
        <p class="recent-value">
          <strong>{estimate_display(valuation)}</strong>
        </p>
      </div>
    </.link>
    """
  end

  def recent_sealed_rows(assigns) do
    ~H"""
    <.link
      :for={{stream_id, product} <- @streams}
      id={stream_id}
      navigate={~p"/sealed/#{product.slug}"}
      class="market-row market-sealed-row"
    >
      <div class="market-thumb market-package">
        <%= if image_url = sealed_image_url(product) do %>
          <img
            class="sealed-package-image"
            src={image_url}
            alt={product.name <> " packaging"}
            width="578"
            height="325"
            loading="lazy"
            decoding="async"
            referrerpolicy="no-referrer"
          />
        <% else %>
          <span role="img" aria-label={"Package line-art placeholder for #{product.name}"}><svg
            viewBox="0 0 72 96"
            aria-hidden="true"
          ><path d="M12 14 36 5l24 9v68l-24 9-24-9zM12 14l24 9 24-9M36 23v68M22 39h28M22 49h20" /></svg></span>
        <% end %>
      </div>
      <div class="market-copy">
        <h4>{product.name}</h4>
        <p>{sealed_identity(product)}</p>
        <p>
          {if product.release_date,
            do: "Released " <> format_release_date(product.release_date),
            else: "Release date unavailable"}
        </p>
      </div>
    </.link>
    """
  end

  attr :title, :string, required: true
  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :empty, :string, required: true
  attr :streams, :any, required: true
  attr :kind, :atom, required: true

  def mover_lane(assigns) do
    ~H"""
    <section id={@id} class="market-lane" aria-labelledby={"#{@id}-title"}>
      <div class="market-lane-heading">
        <h3 id={"#{@id}-title"}>{@title}</h3><span>{@count}</span>
      </div>
      <div id={"#{@id}-list"} phx-update="stream" class="market-rows">
        <%= if @count == 0 do %>
          <p id={"#{@id}-empty"} class="market-empty">{@empty}</p>
        <% end %>
        <%= if @kind == :single do %>
          <.single_mover_rows streams={@streams} />
        <% else %>
          <.sealed_mover_rows streams={@streams} />
        <% end %>
      </div>
    </section>
    """
  end

  attr :streams, :any, required: true

  def single_mover_rows(assigns) do
    ~H"""
    <.link
      :for={{stream_id, mover} <- @streams}
      id={stream_id}
      navigate={~p"/cards/#{mover.tcgdex_id}"}
      class="market-row"
    >
      <div class="market-thumb">
        <%= if image_url = CardImage.thumbnail_url(mover.image_url) do %>
          <img
            src={image_url}
            alt=""
            width="80"
            height="110"
            loading="lazy"
            decoding="async"
            referrerpolicy="no-referrer"
          />
        <% else %>
          <span
            class="market-image-fallback"
            role="img"
            aria-label="No image is available for this card."
          ><svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg></span>
        <% end %>
      </div>
      <div class="market-copy">
        <h4>{mover.name}</h4><p>{mover.set_name} · #{mover.collector_number}</p><p class={
          movement_class(mover.change_percent)
        }>
          <span class="mover-movement"><strong>{movement_label(mover.change_percent)} {signed_percent(
            mover.change_percent
          )}</strong><.fluent_icon
            name={:arrow_trending}
            class={movement_icon_class(mover.change_percent)}
          /></span>
        </p>
      </div>
    </.link>
    """
  end

  def sealed_mover_rows(assigns) do
    ~H"""
    <.link
      :for={{stream_id, mover} <- @streams}
      id={stream_id}
      navigate={~p"/sealed/#{mover.slug}"}
      class="market-row market-sealed-row"
    >
      <div
        class="market-thumb market-package"
        role="img"
        aria-label={"Package line-art placeholder for #{mover.name}"}
      >
        <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 14 36 5l24 9v68l-24 9-24-9zM12 14l24 9 24-9M36 23v68M22 39h28M22 49h20" /></svg>
      </div>
      <div class="market-copy">
        <h4>{mover.name}</h4><p>{sealed_identity(mover)}</p><p class={
          movement_class(mover.change_percent)
        }>
          <span class="mover-movement"><strong>{movement_label(mover.change_percent)} {signed_percent(
            mover.change_percent
          )}</strong><.fluent_icon
            name={:arrow_trending}
            class={movement_icon_class(mover.change_percent)}
          /></span>
        </p>
      </div>
    </.link>
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
      <p>These cross-mode suggestions may help when no exact single matches your search.</p>
      <button
        id="switch-to-sealed-from-fallback"
        class="fallback-mode-switch"
        type="button"
        phx-click="switch_mode_with_query"
        phx-value-mode="sealed"
      >Search sealed products instead</button>
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
      <p>These cross-mode suggestions may help when no exact sealed product matches your search.</p>
      <button
        id="switch-to-singles-from-fallback"
        class="fallback-mode-switch"
        type="button"
        phx-click="switch_mode_with_query"
        phx-value-mode="singles"
      >Search singles instead</button>
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
      No sealed products found. Try a product name, set, or series.
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

  defp freshness_text(valuation) do
    now = DateTime.utc_now()
    updated_text(valuation.fetched_at, Freshness.status(valuation, now), now)
  end

  defp sealed_identity(mover) do
    [human_product_type(mover.product_type), mover.series_name, mover.set_name]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
  end

  defp sealed_image_url(product) do
    cond do
      ExternalImage.valid?(Map.get(product, :image_url)) -> Map.get(product, :image_url)
      image = retailer_image_url(product) -> image
      true -> nil
    end
  end

  defp retailer_image_url(product) do
    case Map.get(product, :public_image_mappings, []) do
      mappings when is_list(mappings) ->
        Enum.find_value(mappings, &retailer_mapping_image/1)

      _ ->
        nil
    end
  end

  defp retailer_mapping_image(mapping) do
    mapping
    |> Map.get(:retailer_listing)
    |> valid_retailer_image()
  end

  defp valid_retailer_image(listing) when is_map(listing) do
    image_url = Map.get(listing, :image_url)
    if ExternalImage.valid?(image_url), do: image_url
  end

  defp valid_retailer_image(_listing), do: nil

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

  defp split_movers(movers) do
    {risers, fallers} =
      Enum.split_with(movers, &(Decimal.compare(&1.change_percent, Decimal.new(0)) == :gt))

    {
      Enum.take(risers, div(@max_discovery_rows, 2)),
      fallers
      |> Enum.reject(&(Decimal.compare(&1.change_percent, Decimal.new(0)) == :eq))
      |> Enum.take(div(@max_discovery_rows, 2))
    }
  end

  defp movement_label(value) do
    if Decimal.compare(value, Decimal.new(0)) == :gt, do: "Rise", else: "Fall"
  end

  defp movement_class(value) do
    if Decimal.compare(value, Decimal.new(0)) == :gt, do: "movement-rise", else: "movement-fall"
  end

  defp movement_icon_class(value) do
    if Decimal.compare(value, Decimal.new(0)) == :lt, do: "movement-icon-down", else: nil
  end

  defp search_locally(socket, query) do
    case TcgCheap.Core.search_public_card_printings(query) do
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
           active_option_id: List.first(options).dom_id,
           home_search_cards: Enum.map(options, & &1.result)
         )
         |> clear_fallback_streams()
         |> stream(:card_results, Enum.map(options, & &1.result), reset: true)
         |> maybe_sync_mapping_subscriptions()}

      {:ok, []} ->
        {:noreply,
         socket
         |> assign(
           search_status: :empty,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil,
           home_search_cards: []
         )
         |> load_sealed_fallback(query)
         |> stream(:card_results, [], reset: true)
         |> maybe_sync_mapping_subscriptions()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           search_status: :error,
           result_count: 0,
           autocomplete_options: [],
           active_option_id: nil,
           home_search_cards: []
         )
         |> clear_fallback_streams()
         |> stream(:card_results, [], reset: true)
         |> maybe_sync_mapping_subscriptions()}
    end
  end

  defp execute_search(socket, "") do
    clear_results_for_mode(socket, :idle)
  end

  defp execute_search(socket, query) do
    grapheme_count = length(String.graphemes(query))

    cond do
      grapheme_count < 2 -> clear_results_for_mode(socket, :short)
      grapheme_count > 100 -> clear_results_for_mode(socket, :invalid)
      socket.assigns.mode == :sealed -> search_sealed_locally(socket, query)
      true -> search_locally(socket, query)
    end
  end

  defp normalize_query_param(value) when is_binary(value), do: SearchText.normalize(value)
  defp normalize_query_param(_value), do: ""

  defp mode_from_params(%{"mode" => "sealed"}), do: :sealed
  defp mode_from_params(_params), do: :singles

  defp home_path(mode, query) do
    params =
      case {mode, query} do
        {:sealed, ""} -> [mode: "sealed"]
        {:sealed, query} -> [mode: "sealed", q: query]
        {:singles, ""} -> []
        {:singles, query} -> [q: query]
      end

    case URI.encode_query(params) do
      "" -> ~p"/"
      query_string -> ~p"/" <> "?" <> query_string
    end
  end

  defp canonical_uri?(uri, canonical_path) do
    incoming = URI.parse(uri)
    canonical = URI.parse(canonical_path)

    incoming.path == canonical.path and incoming.query == canonical.query
  end

  defp reset_search_state(socket) do
    socket
    |> assign(
      search_status: :idle,
      result_count: 0,
      autocomplete_options: [],
      active_option_id: nil,
      fallback_cards_count: 0,
      fallback_sealed_count: 0,
      home_search_cards: []
    )
    |> stream(:card_results, [], reset: true)
    |> stream(:sealed_results, [], reset: true)
    |> stream(:fallback_cards, [], reset: true)
    |> stream(:fallback_sealed, [], reset: true)
    |> maybe_sync_mapping_subscriptions()
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
         |> stream(:sealed_results, Enum.map(options, & &1.result), reset: true)
         |> maybe_sync_mapping_subscriptions()}

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
    |> assign(fallback_cards_count: 0, fallback_sealed_count: 0, home_fallback_cards: [])
    |> stream(:fallback_cards, [], reset: true)
    |> stream(:fallback_sealed, [], reset: true)
    |> maybe_sync_mapping_subscriptions()
  end

  defp load_sealed_fallback(socket, query) do
    case TcgCheap.Core.search_public_sealed_products(query, 4) do
      {:ok, products} when is_list(products) ->
        socket
        |> assign(fallback_sealed_count: length(products), home_fallback_cards: [])
        |> stream(:fallback_sealed, products, reset: true)
        |> stream(:fallback_cards, [], reset: true)

      _ ->
        clear_fallback_streams(socket)
    end
  end

  defp load_card_fallback(socket, query) do
    case TcgCheap.Core.search_public_card_printings(query, 4) do
      {:ok, cards} when is_list(cards) ->
        socket
        |> assign(fallback_cards_count: length(cards), home_fallback_cards: cards)
        |> stream(:fallback_cards, cards, reset: true)
        |> stream(:fallback_sealed, [], reset: true)

      _ ->
        clear_fallback_streams(socket)
    end
  end

  defp maybe_sync_mapping_subscriptions(socket) do
    if connected?(socket) do
      socket =
        if socket.assigns.subscribed_valuation_collection? do
          socket
        else
          :ok = ValuationNotifications.subscribe_collection()
          assign(socket, :subscribed_valuation_collection?, true)
        end

      wanted = visible_mapping_ids(socket)
      subscribed = socket.assigns.subscribed_mapping_ids

      Enum.each(MapSet.difference(subscribed, wanted), fn id ->
        Phoenix.PubSub.unsubscribe(TcgCheap.PubSub, ValuationNotifications.topic(id))
      end)

      Enum.each(MapSet.difference(wanted, subscribed), fn id ->
        :ok = ValuationNotifications.subscribe(id)
      end)

      assign(socket, :subscribed_mapping_ids, wanted)
    else
      socket
    end
  end

  defp refresh_singles_discovery(socket) do
    as_of = DateTime.utc_now()

    {price_changes, price_changes_ok?} =
      safe_discovery(fn ->
        TcgCheap.Core.list_homepage_price_changes(as_of, @max_discovery_rows)
      end)

    {recent_cards, recent_cards_ok?} =
      safe_discovery(fn -> TcgCheap.Core.list_public_recently_tracked_card_printings() end)
      |> then(fn {rows, ok?} -> {Enum.take(rows, @max_discovery_rows), ok?} end)

    {single_risers, single_fallers} = split_movers(price_changes)

    socket
    |> assign(
      singles_movers_available?: price_changes_ok?,
      singles_risers_count: length(single_risers),
      singles_fallers_count: length(single_fallers),
      recent_cards_available?: recent_cards_ok?,
      recent_cards_count: length(recent_cards),
      home_recent_cards: recent_cards,
      home_single_movers: single_risers ++ single_fallers
    )
    |> stream(:market_single_risers, single_risers, reset: true)
    |> stream(:market_single_fallers, single_fallers, reset: true)
    |> stream(:idle_recent_cards, recent_cards, reset: true)
    |> maybe_sync_mapping_subscriptions()
  end

  defp visible_mapping_ids(socket) do
    [:home_search_cards, :home_fallback_cards, :home_recent_cards, :home_single_movers]
    |> Enum.flat_map(&Map.get(socket.assigns, &1, []))
    |> Enum.map(fn card -> Map.get(card, :id) || Map.get(card, :card_printing_id) end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp refresh_home_card(socket, id) do
    cards =
      socket.assigns.home_search_cards ++
        socket.assigns.home_fallback_cards ++ socket.assigns.home_recent_cards

    case Enum.find(cards, &(Map.get(&1, :id) == id)) do
      %{tcgdex_id: tcgdex_id} ->
        fresh =
          case TcgCheap.Core.list_public_card_printings_by_tcgdex_ids([tcgdex_id]) do
            {:ok, [card | _]} -> card
            _ -> nil
          end

        socket
        |> refresh_card_collection(:home_search_cards, :card_results, id, fresh)
        |> refresh_card_collection(:home_fallback_cards, :fallback_cards, id, fresh)
        |> refresh_card_collection(:home_recent_cards, :idle_recent_cards, id, fresh)
        |> refresh_mover_card(id)
        |> maybe_sync_mapping_subscriptions()

      nil ->
        refresh_mover_card(socket, id)
    end
  end

  defp refresh_card_collection(socket, assign_key, stream_name, id, fresh) do
    records = Map.get(socket.assigns, assign_key, [])

    case Enum.find(records, &(&1.id == id)) do
      nil ->
        socket

      old ->
        socket
        |> assign(assign_key, update_records(records, id, fresh))
        |> sync_search_option_state(assign_key, id, fresh)
        |> update_card_stream(stream_name, old, fresh)
    end
  end

  defp update_records(records, id, nil), do: Enum.reject(records, &(&1.id == id))
  defp update_records(records, id, fresh), do: Enum.map(records, &replace_record(&1, id, fresh))

  defp replace_record(%{id: id}, id, fresh), do: fresh
  defp replace_record(record, _id, _fresh), do: record

  defp update_card_stream(socket, stream_name, old, nil),
    do: stream_delete(socket, stream_name, old)

  defp update_card_stream(socket, stream_name, _old, fresh),
    do: stream_insert(socket, stream_name, fresh)

  defp sync_search_option_state(socket, :home_search_cards, id, fresh) do
    options = socket.assigns.autocomplete_options

    options = update_search_options(options, id, fresh)

    active_option_id =
      case Enum.find(options, &(&1.dom_id == socket.assigns.active_option_id)) do
        nil ->
          fallback_active_option_id(options)

        _option ->
          socket.assigns.active_option_id
      end

    assign(socket,
      autocomplete_options: options,
      result_count:
        if(fresh, do: socket.assigns.result_count, else: max(socket.assigns.result_count - 1, 0)),
      active_option_id: active_option_id
    )
  end

  defp sync_search_option_state(socket, _assign_key, _id, _fresh), do: socket

  defp update_search_options(options, id, nil),
    do: Enum.reject(options, &(&1.result.id == id))

  defp update_search_options(options, id, fresh),
    do: Enum.map(options, &update_search_option(&1, id, fresh))

  defp update_search_option(%{result: %{id: id}} = option, id, fresh),
    do: %{option | result: fresh}

  defp update_search_option(option, _id, _fresh), do: option

  defp fallback_active_option_id([]), do: nil
  defp fallback_active_option_id([option | _options]), do: option.dom_id

  defp refresh_mover_card(socket, id) do
    if Enum.any?(socket.assigns.home_single_movers, &(Map.get(&1, :card_printing_id) == id)) do
      {changes, ok?} =
        safe_discovery(fn ->
          TcgCheap.Core.list_homepage_price_changes(DateTime.utc_now(), @max_discovery_rows)
        end)

      {risers, fallers} = split_movers(changes)

      socket
      |> assign(
        singles_movers_available?: ok?,
        singles_risers_count: length(risers),
        singles_fallers_count: length(fallers),
        home_single_movers: risers ++ fallers
      )
      |> stream(:market_single_risers, risers, reset: true)
      |> stream(:market_single_fallers, fallers, reset: true)
      |> maybe_sync_mapping_subscriptions()
    else
      socket
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
       active_option_id: nil,
       home_search_cards: []
     )
     |> clear_fallback_streams()
     |> stream(:card_results, [], reset: true)
     |> maybe_sync_mapping_subscriptions()}
  end

  defp clear_sealed_results(socket, status) do
    {:noreply,
     socket
     |> assign(
       search_status: status,
       result_count: 0,
       autocomplete_options: [],
       active_option_id: nil,
       home_search_cards: []
     )
     |> clear_fallback_streams()
     |> stream(:sealed_results, [], reset: true)
     |> maybe_sync_mapping_subscriptions()}
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
      if(ValuationPolicy.current_valuation(result),
        do: "card-freshness-#{result.id}"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
