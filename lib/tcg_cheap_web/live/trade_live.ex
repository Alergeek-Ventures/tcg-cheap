defmodule TcgCheapWeb.TradeLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Catalogue.SearchText
  alias TcgCheap.Core
  alias TcgCheap.Pricing.ExchangeRate
  alias TcgCheap.Pricing.ExchangeRateAcquisition
  alias TcgCheap.Pricing.Singles.{Freshness, ValuationAcquisition}
  alias TcgCheap.Trades.{Composition, Valuation}
  alias TcgCheapWeb.PublicAcquisitionLimiter

  @max_options 10
  @max_acquisition 100

  @impl true
  def mount(_params, _session, socket) do
    {exchange_rate, exchange_rate_status} = local_exchange_rate()

    {:ok,
     socket
     |> assign(
       page_title: "Build a trade",
       composition: %Composition{},
       cards: %{},
       rows: %{left: [], right: []},
       warning: nil,
       selected_card: nil,
       search_form: to_form(%{"query" => ""}, as: :search),
       search_status: :idle,
       search_query: "",
       result_count: 0,
       autocomplete_options: [],
       active_option_id: nil,
       requested_card_ids: MapSet.new(),
       acquisition_states: %{},
       totals: %{
         left: Decimal.new(0),
         right: Decimal.new(0),
         left_complete?: true,
         right_complete?: true,
         left_unvalued_quantity: 0,
         right_unvalued_quantity: 0
       },
       announcement: "Trade is empty. Add cards to either side.",
       exchange_rate: exchange_rate,
       exchange_rate_status: exchange_rate_status,
       exchange_rate_requested?: false,
       share_status: nil,
       public_address: public_address(socket)
     )
     |> stream_configure(:card_results, dom_id: fn result -> "trade-card-option-#{result.id}" end)
     |> stream(:card_results, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {composition, meta} = Composition.from_params(params)
    pick = Map.get(params, "pick")
    {pick, pick_warning} = valid_pick(pick)

    composition_ids =
      (composition.left ++ composition.right) |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    {cards, read_warning} = load_cards(composition_ids)
    {cards, selected_card, pick_read_warning} = load_pick(cards, pick)
    selected_card = selected_card || if(is_nil(pick), do: socket.assigns.selected_card, else: nil)
    warning = warning_for(meta, pick_warning, read_warning || pick_read_warning)

    socket = assign(socket, :share_status, nil)
    {:noreply, rebuild_and_request(socket, composition, cards, warning, selected_card)}
  end

  @impl true
  def handle_info({:valuation_completed, %{card_printing_id: id}}, socket) when is_binary(id) do
    if current_card_id?(socket, id) do
      case load_cards(composition_ids(socket.assigns.composition)) do
        {cards, nil} ->
          tcgdex_id = card_tcgdex_id(cards, id)

          socket =
            assign(
              socket,
              :acquisition_states,
              Map.put(socket.assigns.acquisition_states, tcgdex_id, :fresh)
            )

          {:noreply,
           rebuild(
             socket,
             socket.assigns.composition,
             cards,
             socket.assigns.warning,
             socket.assigns.selected_card
           )}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:valuation_failed, %{card_printing_id: id}}, socket) when is_binary(id) do
    if current_card_id?(socket, id) do
      tcgdex_id = card_tcgdex_id(socket.assigns.cards, id)

      socket =
        assign(
          socket,
          :acquisition_states,
          Map.put(socket.assigns.acquisition_states, tcgdex_id, :failed)
        )

      {:noreply,
       rebuild(
         socket,
         socket.assigns.composition,
         socket.assigns.cards,
         socket.assigns.warning,
         socket.assigns.selected_card
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:card_mapping_changed, %{card_printing_id: id}}, socket)
      when is_binary(id) do
    mapping_changed(socket, id)
  end

  def handle_info(
        {:exchange_rate_completed, %{exchange_rate: %ExchangeRate{} = rate}},
        socket
      )
      when is_struct(rate, ExchangeRate) do
    if usable_rate?(rate) and newer_rate?(rate, socket.assigns.exchange_rate),
      do: {:noreply, assign(socket, exchange_rate: rate, exchange_rate_status: :ready)},
      else: {:noreply, socket}
  end

  def handle_info({:exchange_rate_failed, %{reason: _reason}}, socket),
    do: {:noreply, assign(socket, exchange_rate_status: :failed)}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query = SearchText.normalize(query)
    socket = assign(socket, search_query: query, selected_card: nil)

    cond do
      query == "" -> clear_results(socket, :idle)
      length(String.graphemes(query)) < 2 -> clear_results(socket, :short)
      length(String.graphemes(query)) > 100 -> clear_results(socket, :invalid)
      true -> search(socket, query)
    end
  end

  def handle_event("search", _, socket), do: {:noreply, socket}

  def handle_event("autocomplete_key", %{"key" => key}, socket)
      when key in ["ArrowDown", "ArrowUp"], do: move_active(socket, key)

  def handle_event("autocomplete_key", %{"key" => "Escape"}, socket),
    do: clear_results(socket, :idle)

  def handle_event("autocomplete_key", %{"key" => "Enter", "query" => query}, socket)
      when is_binary(query) do
    if SearchText.normalize(query) == socket.assigns.search_query do
      case Enum.find(
             socket.assigns.autocomplete_options,
             &(&1.dom_id == socket.assigns.active_option_id)
           ) do
        %{card: card} -> {:noreply, stage_selected(socket, card)}
        _ -> {:noreply, socket}
      end
    else
      clear_results(socket, :idle)
    end
  end

  def handle_event("autocomplete_key", %{"key" => "Enter"}, socket), do: {:noreply, socket}

  def handle_event("autocomplete_key", _, socket), do: {:noreply, socket}

  def handle_event("select_option", %{"tcgdex-id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.autocomplete_options, &(&1.tcgdex_id == id)) do
      %{card: card} -> {:noreply, stage_selected(socket, card)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_option", _, socket), do: {:noreply, socket}

  def handle_event(
        "add_to_side",
        %{"side" => side},
        %{assigns: %{selected_card: %{tcgdex_id: id} = card}} = socket
      )
      when side in ["left", "right"] and is_binary(id) do
    if Map.get(card, :unavailable?, false) do
      {:noreply, socket}
    else
      add_side(socket, side, id, card)
    end
  end

  def handle_event("add_to_side", _, socket), do: {:noreply, socket}

  def handle_event("increment", %{"side" => "left", "tcgdex-id" => id}, socket),
    do: mutate(socket, :increment, :left, id)

  def handle_event("increment", %{"side" => "right", "tcgdex-id" => id}, socket),
    do: mutate(socket, :increment, :right, id)

  def handle_event("decrement", %{"side" => "left", "tcgdex-id" => id}, socket),
    do: mutate(socket, :decrement, :left, id)

  def handle_event("decrement", %{"side" => "right", "tcgdex-id" => id}, socket),
    do: mutate(socket, :decrement, :right, id)

  def handle_event("remove", %{"side" => "left", "tcgdex-id" => id}, socket),
    do: mutate(socket, :remove, :left, id)

  def handle_event("remove", %{"side" => "right", "tcgdex-id" => id}, socket),
    do: mutate(socket, :remove, :right, id)

  def handle_event("trade_share_result", %{"status" => status, "path" => path}, socket)
      when status in ["copied", "failed"] and is_binary(path) do
    announcement =
      if status == "copied",
        do: "Link copied.",
        else: "Copy failed. Copy the current URL manually."

    if path == Composition.to_path(socket.assigns.composition),
      do: {:noreply, assign(socket, :share_status, announcement)},
      else: {:noreply, socket}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world trade-world">
        <header id="trade-header" class="decision-header">
          <.link id="trade-wordmark" navigate={~p"/"}>TCG CHEAP</.link><.link
            id="trade-home-link"
            navigate={~p"/"}
          >Home</.link>
        </header>
        <main id="trade-main" class="decision-main">
          <div class="decision-container">
            <section id="trade-intro" class="decision-intro">
              <div>
                <h1 id="trade-title">Build a trade</h1><p id="trade-task">
                  Add cards to each side, then compare local estimates.
                </p>
              </div>
            </section>
            <section id="trade-search" class="decision-search" aria-labelledby="trade-search-title">
              <h2 id="trade-search-title">Find a card</h2>
              <.form for={@search_form} id="trade-search-form">
                <label for="trade-search-query" class="sr-only">Search for a card to add</label><div class="search-field-wrap">
                  <.input
                    field={@search_form[:query]}
                    type="search"
                    id="trade-search-query"
                    name="search[query]"
                    maxlength="100"
                    autocomplete="off"
                    phx-hook="CardAutocomplete"
                    role="combobox"
                    aria-autocomplete="list"
                    aria-controls="trade-search-results"
                    aria-expanded={to_string(@autocomplete_options != [])}
                    aria-activedescendant={@active_option_id}
                    placeholder="Search for a card"
                  />
                </div>
              </.form>
              <.search_state
                status={@search_status}
                count={@result_count}
                query={@search_query}
              />
              <div
                id="trade-search-results"
                phx-update="stream"
                class="evidence-slips"
                role="listbox"
                aria-label="Trade card search results"
              >
                <div
                  :for={{stream_id, card} <- @streams.card_results}
                  id={stream_id}
                  class={["evidence-slot", @active_option_id == stream_id && "active-option"]}
                  role="option"
                  aria-selected={to_string(@active_option_id == stream_id)}
                  aria-labelledby={option_labelledby(card)}
                  tabindex="-1"
                  phx-click="select_option"
                  phx-value-tcgdex-id={card.tcgdex_id}
                >
                  <article class="evidence-slip">
                    <div class="evidence-art">
                      <%= if url = CardImage.thumbnail_url(card.image_url) do %>
                        <img
                          src={url}
                          alt={card_alt(card)}
                          width="245"
                          height="337"
                          loading="lazy"
                          referrerpolicy="no-referrer"
                        />
                      <% else %>
                        <div
                          class="card-image-missing"
                          role="img"
                          aria-label="No image is available for this card."
                        >
                          <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
                        </div>
                      <% end %>
                    </div><div class="evidence-copy">
                      <p id={"trade-card-name-#{card.id}"} class="evidence-name">{card.name}</p><p
                        id={"trade-card-set-#{card.id}"}
                        class="evidence-set"
                      >
                        {card.set_name} · {card.collector_number}
                      </p><div class="estimate-cell">
                        <strong id={"trade-card-price-#{card.id}"}>{estimate_display(card)}</strong><span id={"trade-card-freshness-#{card.id}"}>{freshness_text(
                          card
                        )}</span>
                      </div>
                    </div>
                  </article>
                </div>
              </div>
            </section>
            <section
              :if={@selected_card}
              id="trade-staging"
              class="trade-staging"
              aria-label="Selected card"
            >
              <strong id="trade-selected-name">{selected_name(@selected_card)}</strong>
              <span id="trade-selected-set">{selected_set(@selected_card)}</span>
              <span id="trade-selected-price">{estimate_display(@selected_card)}</span>
              <span id="trade-selected-freshness">{freshness_text(@selected_card)}</span><button
                :if={not Map.get(@selected_card, :unavailable?, false)}
                id="add-to-left"
                type="button"
                phx-click="add_to_side"
                phx-value-side="left"
                aria-label={"Add #{selected_name(@selected_card)} to left side"}
              >Add to left side</button><button
                :if={not Map.get(@selected_card, :unavailable?, false)}
                id="add-to-right"
                type="button"
                phx-click="add_to_side"
                phx-value-side="right"
                aria-label={"Add #{selected_name(@selected_card)} to right side"}
              >Add to right side</button>
            </section>
            <p :if={@warning} id="trade-url-warning" class="state-note state-error">
              {warning_text(@warning)}
            </p>
            <div id="trade-ledgers" class="trade-ledgers">
              <%= for side <- [:left, :right] do %>
                <section
                  id={"trade-#{side}-side"}
                  class="trade-side"
                  aria-labelledby={"trade-#{side}-title"}
                >
                  <h2 id={"trade-#{side}-title"}>{side_name(side)}</h2><div
                    id={"trade-#{side}-rows"}
                    class="trade-rows"
                  >
                    <div :if={Map.fetch!(@rows, side) == []} class="trade-empty">
                      Add cards to this side.
                    </div><article
                      :for={row <- Map.fetch!(@rows, side)}
                      id={"trade-row-#{side}-#{row.id}"}
                      class="trade-row"
                    >
                      <div class="trade-row-art">
                        <%= if row.card && row.image_url do %>
                          <img
                            src={row.image_url}
                            alt={card_alt(row.card)}
                            width="80"
                            height="110"
                            referrerpolicy="no-referrer"
                          />
                        <% else %>
                          <div
                            class="card-image-missing"
                            role="img"
                            aria-label={
                              if row.card,
                                do: "No image is available for this card.",
                                else: "Card unavailable"
                            }
                          >
                            <svg viewBox="0 0 72 96" aria-hidden="true"><path d="M12 4h38l10 10v78H12zM50 4v12h10M20 28h32M20 38h24M20 70h32M20 78h18" /></svg>
                          </div>
                        <% end %>
                      </div>
                      <div class="trade-row-content">
                        <%= if row.card do %>
                          <h3>{row.name}</h3><p>{row.set_name} · {row.collector_number}</p>
                          <.link
                            id={"trade-detail-#{side}-#{row.id}"}
                            class="trade-row-detail"
                            navigate={trade_detail_path(row.id, @composition)}
                          >View card</.link>
                          <span id={"trade-freshness-#{side}-#{row.id}"}>{row.freshness_display}</span>
                          <span :if={row.acquisition_state == :fetching}>Updating…</span>
                          <span :if={row.acquisition_state == :failed && row.status == :stale}>Update failed; cached estimate kept.</span>
                        <% else %>
                          <h3>Card unavailable</h3><p>{row.id}</p>
                        <% end %>
                        <div class="trade-row-value">
                          <span>Qty {row.quantity}</span><span>{row.unit_display}</span><strong>{row.total_display}</strong><button
                            id={"trade-increment-#{side}-#{row.id}"}
                            type="button"
                            phx-click="increment"
                            phx-value-side={side}
                            phx-value-tcgdex-id={row.id}
                            aria-label={"Add one #{row.name || row.id} to #{side_name(side)}"}
                          >Add one</button><button
                            id={"trade-decrement-#{side}-#{row.id}"}
                            type="button"
                            phx-click="decrement"
                            phx-value-side={side}
                            phx-value-tcgdex-id={row.id}
                            aria-label={"Subtract one #{row.name || row.id} from #{side_name(side)}"}
                          >Subtract one</button><button
                            id={"trade-remove-#{side}-#{row.id}"}
                            type="button"
                            phx-click="remove"
                            phx-value-side={side}
                            phx-value-tcgdex-id={row.id}
                            aria-label={"Remove #{row.name || row.id} from #{side_name(side)}"}
                          >Remove</button>
                        </div>
                      </div>
                    </article>
                  </div><p id={"trade-#{side}-total"} class="trade-total">
                    <span id={"trade-#{side}-total-eur"}>{total_eur_display(
                      Map.fetch!(@totals, side),
                      total_complete?(@totals, side),
                      total_unvalued_quantity(@totals, side)
                    )}</span><span id={"trade-#{side}-total-pln"}>{total_pln_display(
                      Map.fetch!(@totals, side),
                      total_complete?(@totals, side),
                      total_unvalued_quantity(@totals, side),
                      @exchange_rate
                    )}</span>
                  </p>
                </section>
              <% end %>
            </div>
            <section id="trade-comparison" class="trade-comparison" aria-live="polite">
              <p id="trade-comparison-eur">{comparison(@evaluation)}</p>
              <p :if={comparison_complete?(@evaluation)} id="trade-comparison-pln">
                {comparison_pln(@evaluation, @exchange_rate)}
              </p><span>Estimate only.</span>
            </section>
            <section id="trade-rate-evidence" class="trade-rate-evidence" aria-live="polite">
              {rate_evidence(@exchange_rate, @exchange_rate_status)}
            </section>
            <div class="trade-share">
              <button
                id="trade-share"
                type="button"
                phx-hook="TradeShare"
                data-trade-path={Composition.to_path(@composition)}
              >Copy trade link</button>
              <p id="trade-share-status" role="status" aria-live="polite">{@share_status}</p>
            </div>
          </div>
        </main><p id="trade-announcements" class="sr-only" role="status" aria-live="polite">
          {@announcement}
        </p>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true
  attr :count, :integer, required: true
  attr :query, :string, required: true

  def search_state(assigns) do
    ~H"""
    <p id="trade-search-status" class="sr-only" aria-live="polite">
      {status_text(@status, @count, @query)}
    </p>
    <div :if={@status == :short} id="trade-search-short" class="state-note">
      Type at least 2 characters.
    </div>
    <div :if={@status == :empty} id="trade-search-empty" class="state-note">
      No cards found.
    </div>
    <div :if={@status == :invalid} id="trade-search-invalid" class="state-note">
      Search is too long.
    </div>
    <div :if={@status == :error} id="trade-search-error" class="state-note state-error">
      Search unavailable. Try again.
    </div>
    """
  end

  defp rebuild(socket, composition, cards, warning, selected) do
    evaluation = Valuation.evaluate(composition, cards, DateTime.utc_now())

    rows = %{
      left: present_rows(evaluation.left.rows, socket.assigns.acquisition_states),
      right: present_rows(evaluation.right.rows, socket.assigns.acquisition_states)
    }

    totals = %{
      left: evaluation.left.known_total,
      right: evaluation.right.known_total,
      left_complete?: evaluation.left.complete?,
      right_complete?: evaluation.right.complete?,
      left_unvalued_quantity: evaluation.left.unvalued_quantity,
      right_unvalued_quantity: evaluation.right.unvalued_quantity
    }

    assign(socket,
      composition: composition,
      cards: cards,
      rows: rows,
      totals: totals,
      evaluation: evaluation,
      warning: warning,
      selected_card: selected,
      announcement: announcement(composition, evaluation)
    )
  end

  defp rebuild_and_request(socket, composition, cards, warning, selected) do
    socket = rebuild(socket, composition, cards, warning, selected)
    socket = request_exchange_rate(socket)
    socket = request_acquisition(socket)
    rebuild(socket, composition, cards, warning, selected)
  end

  defp local_exchange_rate do
    case ExchangeRateAcquisition.latest(Date.utc_today()) do
      {:ok, rate} ->
        if usable_rate?(rate), do: {rate, :ready}, else: {nil, :unavailable}

      _ ->
        {nil, :unavailable}
    end
  end

  defp request_exchange_rate(%{assigns: %{exchange_rate_requested?: true}} = socket), do: socket

  defp request_exchange_rate(socket) do
    if connected?(socket) do
      socket
      |> exchange_rate_request_result()
      |> assign(:exchange_rate_requested?, true)
    else
      socket
    end
  end

  defp exchange_rate_request_result(socket) do
    case ExchangeRateAcquisition.subscribe_and_request_latest(
           request_admitter: PublicAcquisitionLimiter.admitter(socket.assigns.public_address)
         ) do
      {:fresh, rate} -> fresh_exchange_rate(socket, rate)
      {:enqueued, _job} -> assign(socket, :exchange_rate_status, :pending)
      _ -> assign(socket, :exchange_rate_status, :failed)
    end
  end

  defp fresh_exchange_rate(socket, rate) do
    if usable_rate?(rate) and newer_rate?(rate, socket.assigns.exchange_rate),
      do: assign(socket, exchange_rate: rate, exchange_rate_status: :ready),
      else: assign(socket, :exchange_rate_status, :failed)
  end

  defp request_acquisition(socket) do
    if connected?(socket) do
      ids = composition_ids(socket.assigns.composition)
      new_ids = Enum.reject(ids, &MapSet.member?(socket.assigns.requested_card_ids, &1))
      cards = new_ids |> Enum.map(&Map.get(socket.assigns.cards, &1)) |> Enum.reject(&is_nil/1)
      requested_ids = MapSet.new(new_ids)

      case cards do
        [] ->
          assign(
            socket,
            :requested_card_ids,
            MapSet.union(socket.assigns.requested_card_ids, requested_ids)
          )

        cards ->
          result =
            ValuationAcquisition.subscribe_and_request_many(
              Enum.take(cards, @max_acquisition),
              request_admitter: PublicAcquisitionLimiter.admitter(socket.assigns.public_address)
            )

          states = acquisition_states(result, new_ids)

          assign(socket,
            requested_card_ids: MapSet.union(socket.assigns.requested_card_ids, requested_ids),
            acquisition_states: Map.merge(socket.assigns.acquisition_states, states)
          )
      end
    else
      socket
    end
  end

  defp public_address(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _ -> nil
    end
  end

  defp acquisition_state({:fresh, _}), do: :fresh
  defp acquisition_state({:enqueued, _}), do: :fetching
  defp acquisition_state({:error, _}), do: :failed

  defp acquisition_states({:ok, results}, _ids),
    do: Map.new(results, fn {id, status} -> {id, acquisition_state(status)} end)

  defp acquisition_states({:error, _}, ids), do: Map.new(ids, &{&1, :failed})

  defp composition_ids(composition),
    do: (composition.left ++ composition.right) |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  defp current_card_id?(socket, id),
    do: card_tcgdex_id(socket.assigns.cards, id) in composition_ids(socket.assigns.composition)

  defp selected_after_reload(nil, _cards), do: nil

  defp selected_after_reload(%{tcgdex_id: id}, cards), do: Map.get(cards, id)

  defp selected_after_reload(selected, _cards), do: selected

  defp mapping_changed(socket, id) do
    case mapping_change_target(socket, id) do
      {:ok, tcgdex_id} -> reload_mapping(socket, tcgdex_id)
      :ignore -> {:noreply, socket}
    end
  end

  defp mapping_change_target(socket, id) do
    tcgdex_id = card_tcgdex_id(socket.assigns.cards, id)
    composition_ids = composition_ids(socket.assigns.composition)

    case {tcgdex_id, tcgdex_id in composition_ids} do
      {tcgdex_id, true} when is_binary(tcgdex_id) -> {:ok, tcgdex_id}
      _ -> :ignore
    end
  end

  defp reload_mapping(socket, tcgdex_id) do
    case load_cards(composition_ids(socket.assigns.composition)) do
      {cards, nil} -> reload_mapping_from_cards(socket, cards, tcgdex_id)
      _ -> mapping_read_failed(socket, tcgdex_id)
    end
  end

  defp reload_mapping_from_cards(socket, cards, tcgdex_id) do
    case Map.fetch(cards, tcgdex_id) do
      {:ok, _card} ->
        selected = selected_after_reload(socket.assigns.selected_card, cards)
        reset = reset_mapping_state(socket, tcgdex_id, cards, selected)
        {:noreply, rebuild_after_mapping_request(reset, cards, selected)}

      :error ->
        {:noreply, socket}
    end
  end

  defp reset_mapping_state(socket, tcgdex_id, cards, selected) do
    socket
    |> assign(
      requested_card_ids: MapSet.delete(socket.assigns.requested_card_ids, tcgdex_id),
      acquisition_states: Map.delete(socket.assigns.acquisition_states, tcgdex_id)
    )
    |> rebuild(socket.assigns.composition, cards, socket.assigns.warning, selected)
  end

  defp rebuild_after_mapping_request(socket, cards, selected) do
    socket
    |> request_acquisition()
    |> rebuild(socket.assigns.composition, cards, socket.assigns.warning, selected)
  end

  defp mapping_read_failed(socket, tcgdex_id) do
    cards = Map.delete(socket.assigns.cards, tcgdex_id)

    {:noreply,
     socket
     |> assign(
       cards: cards,
       requested_card_ids: MapSet.delete(socket.assigns.requested_card_ids, tcgdex_id),
       acquisition_states: Map.delete(socket.assigns.acquisition_states, tcgdex_id)
     )
     |> rebuild(
       socket.assigns.composition,
       cards,
       :read_error,
       selected_after_reload(socket.assigns.selected_card, %{})
     )}
  end

  defp card_tcgdex_id(cards, id),
    do: cards |> Map.values() |> Enum.find_value(&(&1.id == id && &1.tcgdex_id))

  defp valid_pick(value) when is_binary(value) do
    if Regex.match?(~r/^[A-Za-z0-9._-]{1,160}$/, value),
      do: {value, nil},
      else: {nil, :pick_malformed}
  end

  defp valid_pick(nil), do: {nil, nil}
  defp valid_pick(_), do: {nil, :pick_malformed}

  defp load_cards([]), do: {%{}, nil}

  defp load_cards(ids) do
    case Core.list_card_printings_by_tcgdex_ids(ids) do
      {:ok, cards} -> {Map.new(cards, &{&1.tcgdex_id, &1}), nil}
      _ -> {%{}, :read_error}
    end
  end

  defp load_pick(cards, nil), do: {cards, nil, nil}

  defp load_pick(cards, pick) when is_binary(pick) do
    if Map.has_key?(cards, pick) do
      {cards, Map.fetch!(cards, pick), nil}
    else
      case Core.list_card_printings_by_tcgdex_ids([pick]) do
        {:ok, [card]} -> {Map.put(cards, pick, card), card, nil}
        {:ok, []} -> {cards, %{tcgdex_id: pick, unavailable?: true}, nil}
        _ -> {cards, %{tcgdex_id: pick, unavailable?: true}, :pick_read_error}
      end
    end
  end

  defp warning_for(meta, pick_warning, read_warning) do
    cond do
      read_warning -> read_warning
      pick_warning -> pick_warning
      meta.truncated? -> :truncated
      meta.malformed? -> :malformed
      true -> nil
    end
  end

  defp warning_text(:malformed), do: "Some malformed trade URL rows were ignored."
  defp warning_text(:truncated), do: "Some trade URL rows were truncated at the safe limit."
  defp warning_text(:pick_malformed), do: "The selected card ID was invalid and was ignored."
  defp warning_text(:read_error), do: "Local card data could not be read. Try again."
  defp warning_text(:pick_read_error), do: "The selected card could not be read locally."

  defp add_side(socket, "left", id, card),
    do: patch_composition(socket, Composition.add(socket.assigns.composition, :left, id), card)

  defp add_side(socket, "right", id, card),
    do: patch_composition(socket, Composition.add(socket.assigns.composition, :right, id), card)

  defp patch_composition(socket, composition, card),
    do:
      {:noreply,
       push_patch(assign(socket, selected_card: card), to: Composition.to_path(composition))}

  defp mutate(socket, action, side, id) when is_binary(id) do
    composition = socket.assigns.composition
    rows = Map.fetch!(composition, side)

    if Enum.any?(rows, &match?({^id, _}, &1)) do
      updated = apply_mutation(action, composition, side, id)
      {:noreply, push_patch(socket, to: Composition.to_path(updated))}
    else
      {:noreply, socket}
    end
  end

  defp mutate(socket, _action, _side, _id), do: {:noreply, socket}

  defp apply_mutation(:increment, composition, :left, id),
    do: Composition.increment(composition, :left, id)

  defp apply_mutation(:increment, composition, :right, id),
    do: Composition.increment(composition, :right, id)

  defp apply_mutation(:decrement, composition, :left, id),
    do: Composition.decrement(composition, :left, id)

  defp apply_mutation(:decrement, composition, :right, id),
    do: Composition.decrement(composition, :right, id)

  defp apply_mutation(:remove, composition, :left, id),
    do: Composition.remove(composition, :left, id)

  defp apply_mutation(:remove, composition, :right, id),
    do: Composition.remove(composition, :right, id)

  defp present_rows(rows, acquisition_states),
    do:
      Enum.map(rows, fn row ->
        card = row.card
        value = row.unit_value

        Map.merge(Map.from_struct(row), %{
          name: card && card.name,
          set_name: card && card.set_name,
          collector_number: card && card.collector_number,
          image_url: card && CardImage.thumbnail_url(card.image_url),
          unit_display: unit_display(row, Map.get(acquisition_states, row.id)),
          total_display: if(row.row_value, do: "€" <> eur(row.row_value), else: "?"),
          freshness_display: freshness_text(row),
          acquisition_state: Map.get(acquisition_states, row.id),
          value: value
        })
      end)

  defp announcement(composition, evaluation) do
    left_count = Enum.reduce(composition.left, 0, fn {_, quantity}, count -> count + quantity end)

    right_count =
      Enum.reduce(composition.right, 0, fn {_, quantity}, count -> count + quantity end)

    "Trade updated: #{left_count} card#{if left_count == 1, do: "", else: "s"} on left and #{right_count} on right. #{comparison(evaluation)}."
  end

  defp estimate_display(%{tcgdex_cardmarket_v1_current_valuation: valuation})
       when not is_nil(valuation), do: "€" <> eur(valuation.value_eur)

  defp estimate_display(%{value_eur: value}) when not is_nil(value), do: "€" <> eur(value)
  defp estimate_display(_), do: "Price unavailable"

  defp unit_display(%{unit_value: value}, _state) when not is_nil(value), do: "€" <> eur(value)
  defp unit_display(%{card: card}, :fetching) when not is_nil(card), do: "Fetching estimate…"

  defp unit_display(%{card: card}, :failed) when not is_nil(card),
    do: "Price unavailable · Update failed"

  defp unit_display(_, _), do: "Price unavailable"

  defp freshness_text(%{tcgdex_cardmarket_v1_current_valuation: valuation})
       when not is_nil(valuation), do: freshness_text(valuation)

  defp freshness_text(%{valuation: nil}), do: "No update available"

  defp freshness_text(%{valuation: valuation}) do
    freshness_label(valuation)
  end

  defp freshness_text(%{fetched_at: _} = valuation), do: freshness_label(valuation)

  defp freshness_text(_), do: "No update available"

  defp freshness_label(valuation) do
    case Map.get(valuation, :fetched_at) do
      %DateTime{} = fetched_at ->
        days = max(DateTime.diff(DateTime.utc_now(), fetched_at, :day), 0)

        updated =
          case days do
            0 -> "Updated today"
            1 -> "Updated yesterday"
            days -> "Updated #{days} days ago"
          end

        if Freshness.status(valuation, DateTime.utc_now()) == :stale,
          do: updated <> " · May be outdated",
          else: updated

      _ ->
        "No update available"
    end
  end

  defp card_alt(card),
    do: "#{card.name}, #{card.set_name}, collector number #{card.collector_number}"

  defp option_labelledby(card),
    do:
      "trade-card-name-#{card.id} trade-card-set-#{card.id} trade-card-price-#{card.id} trade-card-freshness-#{card.id}"

  defp eur(value),
    do:
      value
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> then(fn v ->
        [a, b] = (String.split(v, ".", parts: 2) ++ ["0"]) |> Enum.take(2)
        a <> "." <> String.pad_trailing(b, 2, "0")
      end)

  defp total_eur_display(total, true, 0), do: "Total: €" <> eur(total)

  defp total_eur_display(total, false, quantity),
    do: "Total: €" <> eur(total) <> " + ? (#{quantity} unpriced)"

  defp total_pln_display(total, complete?, _quantity, rate) do
    if usable_rate?(rate) do
      converted = "PLN " <> eur(Decimal.mult(total, rate.rate))
      if complete?, do: converted, else: converted <> " + ?"
    else
      "PLN unavailable"
    end
  end

  defp comparison(%{comparison: :incomplete}), do: "Comparison incomplete"
  defp comparison(%{comparison: :equal}), do: "Equal · difference €0.00"

  defp comparison(%{comparison: {:higher, :left, difference}}),
    do: "Left side higher · difference €#{eur(difference)}"

  defp comparison(%{comparison: {:higher, :right, difference}}),
    do: "Right side higher · difference €#{eur(difference)}"

  defp comparison_complete?(%{comparison: comparison}), do: comparison != :incomplete

  defp comparison_pln(%{comparison: :equal}, rate),
    do: if(usable_rate?(rate), do: "Difference PLN 0.00", else: "PLN unavailable")

  defp comparison_pln(%{comparison: {_, _, difference}}, rate),
    do:
      if(usable_rate?(rate),
        do: "Difference PLN " <> eur(Decimal.mult(difference, rate.rate)),
        else: "PLN unavailable"
      )

  defp comparison_pln(_, _), do: "PLN unavailable"

  defp usable_rate?(%ExchangeRate{} = rate) do
    canonical_rate?(rate) and finite_positive_decimal?(rate.rate) and valid_rate_dates?(rate)
  end

  defp usable_rate?(_), do: false

  defp canonical_rate?(%ExchangeRate{
         source: "nbp",
         table: "A",
         base_currency: "EUR",
         quote_currency: "PLN",
         publication_number: publication
       })
       when is_binary(publication), do: String.trim(publication) != ""

  defp canonical_rate?(_), do: false

  defp finite_positive_decimal?(%Decimal{} = rate) do
    not Decimal.nan?(rate) and not Decimal.inf?(rate) and
      Decimal.compare(rate, Decimal.new(0)) == :gt
  end

  defp finite_positive_decimal?(_), do: false

  defp valid_rate_dates?(%ExchangeRate{
         effective_date: %Date{} = effective_date,
         fetched_at: %DateTime{} = fetched_at
       }) do
    Date.compare(effective_date, Date.utc_today()) != :gt and
      Date.compare(effective_date, DateTime.to_date(fetched_at)) != :gt and
      DateTime.compare(fetched_at, DateTime.utc_now()) != :gt
  end

  defp valid_rate_dates?(_), do: false

  defp newer_rate?(%ExchangeRate{} = candidate, nil), do: usable_rate?(candidate)

  defp newer_rate?(%ExchangeRate{} = candidate, %ExchangeRate{} = current) do
    Date.compare(candidate.effective_date, current.effective_date) in [:gt, :eq] and
      (Date.compare(candidate.effective_date, current.effective_date) == :gt or
         DateTime.compare(candidate.fetched_at, current.fetched_at) in [:gt, :eq])
  end

  defp newer_rate?(_, _), do: false

  defp rate_evidence(rate, status), do: rate_evidence_for(usable_rate?(rate), rate, status)

  defp rate_evidence_for(true, rate, status) do
    "1 EUR = #{Decimal.to_string(rate.rate, :normal)} PLN · NBP · Effective " <>
      Date.to_iso8601(rate.effective_date) <>
      " " <> relative_effective_date(rate) <> "." <> rate_state(status)
  end

  defp rate_evidence_for(false, _rate, :pending),
    do: "Exchange-rate update pending. PLN unavailable."

  defp rate_evidence_for(false, _rate, :failed),
    do: "Exchange-rate update failed. PLN unavailable; no cached NBP rate."

  defp rate_evidence_for(false, _rate, _status), do: "PLN unavailable; no cached NBP rate."

  defp relative_effective_date(%{effective_date: effective_date}) do
    case Date.diff(Date.utc_today(), effective_date) do
      age when age <= 0 -> "(today)"
      1 -> "(yesterday)"
      age -> "(#{age} days ago)"
    end
  end

  defp rate_state(:pending), do: " Update pending."
  defp rate_state(:failed), do: " Update failed; cached rate kept."
  defp rate_state(_), do: ""

  defp side_name(:left), do: "Left side"
  defp side_name(:right), do: "Right side"
  defp selected_name(%{name: name}), do: name
  defp selected_name(%{tcgdex_id: id}), do: "Card unavailable (#{id})"
  defp selected_set(%{set_name: set, collector_number: number}), do: "#{set} · #{number}"
  defp selected_set(%{unavailable?: true, tcgdex_id: id}), do: "Reference #{id}"
  defp selected_set(_), do: ""

  defp total_complete?(totals, :left), do: totals.left_complete?
  defp total_complete?(totals, :right), do: totals.right_complete?
  defp total_unvalued_quantity(totals, :left), do: totals.left_unvalued_quantity
  defp total_unvalued_quantity(totals, :right), do: totals.right_unvalued_quantity

  defp trade_detail_path(id, composition),
    do:
      "/cards/#{URI.encode_www_form(id)}?return_to=" <>
        URI.encode_www_form(Composition.to_path(composition))

  defp status_text(:results, count, query), do: "#{count} cards for #{query}"
  defp status_text(:short, _, query), do: "Type at least 2 characters for #{query}"
  defp status_text(:empty, _, query), do: "No cards found for #{query}"
  defp status_text(:invalid, _, query), do: "Search too long for #{query}"
  defp status_text(:error, _, query), do: "Search unavailable for #{query}"
  defp status_text(_, _, _), do: ""

  defp search(socket, query) do
    case Core.search_card_printings(query) do
      {:ok, results} ->
        options =
          results
          |> Enum.take(@max_options)
          |> Enum.map(&%{dom_id: "trade-card-option-#{&1.id}", tcgdex_id: &1.tcgdex_id, card: &1})

        {:noreply,
         socket
         |> assign(
           search_status: if(options == [], do: :empty, else: :results),
           result_count: length(options),
           autocomplete_options: options,
           active_option_id: List.first(options) && List.first(options).dom_id
         )
         |> stream(:card_results, Enum.map(options, & &1.card), reset: true)}

      _ ->
        {:noreply, clear_results(socket, :error) |> elem(1)}
    end
  end

  defp clear_results(socket, status),
    do:
      {:noreply,
       socket
       |> assign(
         search_status: status,
         result_count: 0,
         autocomplete_options: [],
         active_option_id: nil
       )
       |> stream(:card_results, [], reset: true)}

  defp move_active(socket, key) do
    options = socket.assigns.autocomplete_options

    if options == [] do
      {:noreply, socket}
    else
      index = Enum.find_index(options, &(&1.dom_id == socket.assigns.active_option_id)) || 0

      next =
        if key == "ArrowDown",
          do: rem(index + 1, length(options)),
          else: rem(index - 1 + length(options), length(options))

      selected = Enum.at(options, next)
      previous = Enum.find(options, &(&1.dom_id == socket.assigns.active_option_id))

      {:noreply,
       socket
       |> assign(:active_option_id, selected.dom_id)
       |> stream_insert_options([previous, selected])}
    end
  end

  defp stage_selected(socket, card),
    do:
      assign(socket,
        selected_card: card,
        autocomplete_options: [],
        active_option_id: nil,
        requested_card_ids: MapSet.new(),
        acquisition_states: %{},
        search_status: :idle,
        result_count: 0
      )
      |> then(&stream(&1, :card_results, [], reset: true))

  defp stream_insert_options(socket, options) do
    options
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.dom_id)
    |> Enum.reduce(socket, fn
      nil, socket -> socket
      option, socket -> stream_insert(socket, :card_results, option.card)
    end)
  end
end
