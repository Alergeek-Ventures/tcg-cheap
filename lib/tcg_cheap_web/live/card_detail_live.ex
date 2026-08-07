defmodule TcgCheapWeb.CardDetailLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{Freshness, ValuationAcquisition, ValuationHistory}

  @impl true
  def mount(%{"tcgdex_id" => tcgdex_id}, _session, socket) do
    case Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, card} ->
        socket =
          socket
          |> assign(
            page_title: card.name,
            card: card,
            card_image_url: CardImage.detail_url(card.image_url),
            tcgdex_id: tcgdex_id,
            policy_version: ValuationAcquisition.policy_version()
          )
          |> assign_valuation(:disconnected)
          |> reload_valuation(card)

        if connected?(socket) do
          socket =
            handle_acquisition_result(socket, ValuationAcquisition.subscribe_and_request(card))

          {:ok, reload_valuation(socket, card)}
        else
          {:ok, socket}
        end

      _ ->
        {:ok, assign(socket, page_title: "Printing not found", tcgdex_id: tcgdex_id)}
    end
  end

  @impl true
  def handle_info(
        {:valuation_completed, %{card_printing_id: id}},
        %{assigns: %{card: %{id: id} = card}} = socket
      ) do
    {:noreply,
     reload_valuation(assign(socket, refresh_failure: nil, acquisition_state: :completed), card)}
  end

  def handle_info({:valuation_completed, _event}, socket), do: {:noreply, socket}

  def handle_info(
        {:valuation_failed, %{card_printing_id: id, reason: _reason}},
        %{assigns: %{card: %{id: id} = card}} = socket
      ) do
    {:noreply,
     socket
     |> assign(acquisition_state: :failed)
     |> reload_valuation(card)
     |> assign(refresh_failure: true)}
  end

  def handle_info({:valuation_failed, _event}, socket), do: {:noreply, socket}

  @impl true
  def render(%{card: _card} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="archive-world card-detail-world">
        <header id="archive-header" class="archive-header">
          <.link id="archive-wordmark" navigate={~p"/"} class="archive-wordmark">TCG CHEAP</.link>
          <div class="archive-header-meta">
            <span>PRINTING ARCHIVE</span><span>SINGLE / VALUE</span>
          </div>
        </header>
        <main id="card-detail-main" class="archive-main">
          <div class="archive-container">
            <.link id="card-detail-back" navigate={~p"/"} class="archive-back">Back to printing wall</.link>
            <div id="card-detail-overview">
              <section
                id="card-detail-identity"
                class="card-detail-identity"
                aria-labelledby="card-detail-title"
              >
                <div class="card-detail-heading">
                  <h1 id="card-detail-title">{@card.name}</h1>
                  <p class="card-detail-set">{@card.set_name} · NO. {@card.collector_number}</p>
                </div>
                <section id="card-valuation" class="valuation-panel" aria-labelledby="valuation-title">
                  <div class="section-rule">
                    <h2 id="valuation-title">Current value</h2><span>EUR / 7-DAY FRESHNESS</span>
                  </div>
                  <div id="valuation-live-region" role="status" aria-live="polite" aria-atomic="true">
                    <div id="valuation-state" class="valuation-state">
                      <span :if={@valuation_status == :fresh} id="valuation-fresh">Fresh · updated within seven days</span>
                      <span :if={@valuation_status == :stale} id="valuation-stale">Stale</span>
                      <span :if={@acquisition_state == :enqueued} id="valuation-fetching">Fetching a local valuation…</span>
                      <span
                        :if={@valuation_status in [:missing, :disconnected]}
                        id="valuation-unpriced"
                      >No valuation yet</span>
                      <span
                        :if={@valuation_status == :local_read_failure}
                        id="valuation-local-read-failure"
                      >Local valuation read failed</span>
                      <span :if={@refresh_failure} id="valuation-refresh-failed">
                        <%= if @valuation do %>
                          Refresh failed; cached estimate retained.
                        <% else %>
                          Refresh failed; no local estimate is available.
                        <% end %>
                      </span>
                    </div>
                    <p id="valuation-value" class="valuation-value">
                      <%= if @valuation do %>
                        €{@valuation_display}
                      <% else %>
                        ?
                      <% end %>
                    </p>
                  </div>
                  <%= if @valuation do %>
                    <dl id="valuation-provenance" class="valuation-provenance">
                      <div>
                        <dt>SOURCE</dt><dd>{@valuation.source}</dd>
                      </div>
                      <div>
                        <dt>METRIC</dt><dd>{@valuation.source_metric}</dd>
                      </div>
                      <div>
                        <dt>POLICY</dt><dd>{@valuation.policy_version}</dd>
                      </div>
                      <div>
                        <dt>FETCHED</dt><dd>{utc_timestamp(@valuation.fetched_at)}</dd>
                      </div>
                    </dl>
                  <% end %>
                  <p class="methodology">
                    Aggregate Cardmarket estimate from TCGdex under policy {@policy_version}. Language, condition, seller identity/count, finish-specific exactness, and Poland shipping are not verified. Shipping is not calculated.
                  </p>
                  <p id="card-detail-disclaimer" class="disclaimer">
                    TCG Cheap is unofficial and not affiliated with Pokémon, Nintendo, TCGdex, Cardmarket, or any listed company. This is an estimate, not a guaranteed resale value or investment advice.
                  </p>
                </section>
                <figure class="card-detail-placeholder card-detail-figure">
                  <%= if @card_image_url do %>
                    <img
                      id="card-detail-image"
                      src={@card_image_url}
                      alt={card_image_alt(@card)}
                      width="600"
                      height="825"
                      loading="eager"
                      fetchpriority="high"
                      decoding="async"
                      referrerpolicy="no-referrer"
                    />
                    <figcaption id="card-image-source-note">Image supplied by TCGdex.</figcaption>
                  <% else %>
                    <div
                      id="card-detail-image-missing"
                      class="card-image-missing"
                      role="img"
                      aria-label="TCGdex has no image for this printing."
                    >
                      <svg viewBox="0 0 160 220" aria-hidden="true"><path d="M18 8h102l22 22v182H18zM120 8v25h22M30 58h100M30 74h74M30 184h100M42 104h76M42 120h76M42 136h50" /></svg>
                      <span>TCGDEX HAS NO IMAGE FOR THIS PRINTING</span>
                    </div>
                  <% end %>
                </figure>
                <div class="card-detail-secondary">
                  <dl id="card-detail-metadata" class="card-detail-metadata">
                    <div :if={@card.rarity}>
                      <dt>RARITY</dt><dd>{@card.rarity}</dd>
                    </div>
                    <div :if={@card.category}>
                      <dt>CATEGORY</dt><dd>{@card.category}</dd>
                    </div>
                    <div :if={@card.illustrator}>
                      <dt>ILLUSTRATOR</dt><dd>{@card.illustrator}</dd>
                    </div>
                    <div :if={@card.regulation_mark}>
                      <dt>REGULATION</dt><dd>{@card.regulation_mark}</dd>
                    </div>
                    <div :if={@card.standard_legal}>
                      <dt>LEGALITY</dt><dd>STANDARD</dd>
                    </div>
                    <div :if={@card.expanded_legal}>
                      <dt>LEGALITY</dt><dd>EXPANDED</dd>
                    </div>
                    <div>
                      <dt>TCGDEX ID</dt><dd>{@card.tcgdex_id}</dd>
                    </div>
                  </dl>
                </div>
              </section>
            </div>

            <section class="valuation-history" aria-labelledby="history-title">
              <div class="section-rule">
                <h2 id="history-title">Thirty-day ledger</h2><span>UTC / DAILY SNAPSHOTS</span>
              </div>
              <p id="valuation-history-description" class="history-description">
                Each day uses its last successful snapshot. Gaps mean no observation.
              </p>
              <p
                :if={@history_load_failed}
                id="valuation-history-error"
                class="state-note state-error"
              >
                History could not be refreshed. Any ledger shown is the last local read.
              </p>
              <p
                :if={not @history_load_failed and length(@history_points) < 2}
                id="valuation-history-collecting"
                class="state-note"
              >
                History is still being collected; there are not enough observations to show a trend.
              </p>
              <%= if @history_points == [] do %>
                <p :if={not @history_load_failed} id="valuation-history-empty" class="state-note">
                  No successful observations in the last 30 days.
                </p>
              <% else %>
                <svg
                  id="valuation-history-chart"
                  viewBox="0 0 300 120"
                  role="img"
                  aria-labelledby="valuation-history-title valuation-history-description"
                >
                  <title id="valuation-history-title">Thirty-day valuation history</title>
                  <%= for {path, index} <- Enum.with_index(@history_paths) do %>
                    <path id={"valuation-history-segment-#{index}"} class="history-line" d={path} />
                  <% end %>
                  <%= for point <- @history_plot_points do %>
                    <circle cx={point.x} cy={point.y} r="3" aria-hidden="true" />
                  <% end %>
                </svg>
                <ol id="valuation-history-ledger" class="history-ledger">
                  <%= for point <- @history_points do %>
                    <li id={"valuation-history-day-#{point.date}"}>
                      <time datetime={Date.to_iso8601(point.date)}>{Date.to_iso8601(point.date)}</time><strong>€{format_eur(
                        point.value_eur
                      )}</strong><span>{utc_timestamp(point.fetched_at)}</span>
                    </li>
                  <% end %>
                </ol>
              <% end %>
            </section>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns), do: not_found_render(assigns)

  defp not_found_render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="archive-world card-detail-world">
        <header id="archive-header" class="archive-header">
          <.link id="archive-wordmark" navigate={~p"/"} class="archive-wordmark">TCG CHEAP</.link>
        </header><main class="archive-main">
          <section id="card-detail-not-found" class="state-note state-error">
            <h1>Printing not found</h1><p>
              No local card matches TCGdex ID <strong>{@tcgdex_id}</strong>. No provider was contacted.
            </p><.link id="card-detail-not-found-back" navigate={~p"/"} class="archive-back">Back to archive</.link>
          </section>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp assign_valuation(socket, mode) do
    assign(socket,
      valuation: nil,
      valuation_display: "?",
      valuation_status: mode,
      history_points: [],
      history_paths: [],
      history_plot_points: [],
      refresh_failure: nil,
      acquisition_state: :idle,
      history_origin: nil,
      history_load_failed: false
    )
  end

  defp reload_valuation(socket, card) do
    now = DateTime.utc_now()
    policy_version = socket.assigns.policy_version
    current = Core.get_current_single_valuation(card.id, policy_version)

    history =
      Core.list_single_valuation_history_since(
        card.id,
        policy_version,
        ValuationHistory.window_start(now)
      )

    socket
    |> apply_current_read(current, now)
    |> apply_history_read(history, now)
  end

  defp handle_acquisition_result(socket, {:ok, _card, {:enqueued, _job}}),
    do: assign(socket, acquisition_state: :enqueued)

  defp handle_acquisition_result(socket, {:ok, _card, {:fresh, _valuation}}),
    do: assign(socket, acquisition_state: :completed)

  defp handle_acquisition_result(socket, {:ok, _card, {:error, _reason}}),
    do: acquisition_failed(socket)

  defp handle_acquisition_result(socket, {:error, _reason}), do: acquisition_failed(socket)

  defp acquisition_failed(socket),
    do: assign(socket, acquisition_state: :failed, refresh_failure: true)

  defp card_image_alt(card),
    do: "#{card.name}, #{card.set_name}, collector number #{card.collector_number}"

  defp apply_current_read(socket, {:ok, nil}, _now),
    do: assign(socket, valuation: nil, valuation_display: "?", valuation_status: :missing)

  defp apply_current_read(socket, {:ok, valuation}, now),
    do:
      assign(socket,
        valuation: valuation,
        valuation_display: format_eur(valuation.value_eur),
        valuation_status: Freshness.status(valuation, now)
      )

  defp apply_current_read(socket, {:error, _reason}, _now),
    do: assign(socket, valuation_status: :local_read_failure)

  defp apply_history_read(socket, {:ok, snapshots}, now) do
    points = ValuationHistory.daily_points(snapshots, now)

    socket
    |> assign(
      history_points: points,
      history_origin: ValuationHistory.window_start(now),
      history_load_failed: false
    )
    |> assign_history_plot(points)
  end

  defp apply_history_read(socket, {:error, _reason}, _now),
    do: assign(socket, history_load_failed: true)

  defp assign_history_plot(socket, points) do
    origin = socket.assigns.history_origin || ValuationHistory.window_start(DateTime.utc_now())

    assign(socket,
      history_paths: plot_paths(points, origin),
      history_plot_points: plot_points(points, origin)
    )
  end

  defp format_eur(%Decimal{} = value) do
    parts = value |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.split(".", parts: 2)
    [whole, fraction] = Enum.take(parts ++ ["0"], 2)
    whole <> "." <> String.pad_trailing(fraction, 2, "0")
  end

  defp utc_timestamp(%DateTime{} = dt),
    do: Calendar.strftime(DateTime.shift_zone!(dt, "Etc/UTC"), "%Y-%m-%d %H:%M:%S UTC")

  defp plot_points([], _origin), do: []

  defp plot_points(points, origin) do
    {min, max} = min_max(points)

    Enum.map(points, fn point ->
      %{
        x: Date.diff(point.date, DateTime.to_date(origin)) * 10 + 5,
        y: y_for(point.value_eur, min, max)
      }
    end)
  end

  defp plot_paths([], _origin), do: []

  defp plot_paths(points, origin) do
    {min, max} = min_max(points)

    points
    |> Enum.chunk_while([], &chunk_points/2, &finish_chunk/1)
    |> Enum.map(fn chunk ->
      chunk
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {point, index} ->
        path_command(index, point, origin, min, max)
      end)
    end)
  end

  defp path_command(0, point, origin, min, max),
    do: "M #{path_coordinate(point, origin, min, max)}"

  defp path_command(_index, point, origin, min, max),
    do: "L #{path_coordinate(point, origin, min, max)}"

  defp path_coordinate(point, origin, min, max) do
    "#{Date.diff(point.date, DateTime.to_date(origin)) * 10 + 5},#{y_for(point.value_eur, min, max)}"
  end

  defp chunk_points(point, []), do: {:cont, [point]}

  defp chunk_points(point, [last | _] = acc) do
    if Date.diff(point.date, last.date) == 1,
      do: {:cont, [point | acc]},
      else: {:cont, Enum.reverse(acc), [point]}
  end

  defp finish_chunk([]), do: {:cont, []}
  defp finish_chunk(acc), do: {:cont, Enum.reverse(acc), []}

  defp min_max([first | rest]) do
    Enum.reduce(rest, {first.value_eur, first.value_eur}, fn p, {min, max} ->
      next_min = if Decimal.compare(p.value_eur, min) == :lt, do: p.value_eur, else: min
      next_max = if Decimal.compare(p.value_eur, max) == :gt, do: p.value_eur, else: max
      {next_min, next_max}
    end)
  end

  defp y_for(value, min, max) do
    if Decimal.compare(min, max) == :eq,
      do: 60,
      else:
        Decimal.div(
          Decimal.mult(Decimal.sub(max, value), Decimal.new(100)),
          Decimal.sub(max, min)
        )
        |> Decimal.add(10)
        |> Decimal.round(0)
        |> Decimal.to_integer()
  end
end
