defmodule TcgCheapWeb.SealedProductDetailLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.PublicSealedProductProjection
  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedBuyingGuidePublicProjection
  alias TcgCheap.Pricing.SealedDailyAggregateCalculator
  alias TcgCheap.Pricing.SealedDailyAggregatePublic
  alias TcgCheap.Pricing.SealedMarketHistory

  @impl true
  def mount(%{"slug" => slug}, _session, socket) when is_binary(slug) and slug != "" do
    socket = configure_offer_streams(socket)

    case Core.get_public_sealed_product_by_slug(slug) do
      {:ok, nil} ->
        {:ok, assign(socket, page_title: "Sealed product not found", state: :not_found)}

      {:ok, product} ->
        now = DateTime.utc_now()
        {:ok, load_product(socket, product, now)}

      {:error, reason} ->
        {:ok,
         assign(socket,
           page_title: "Sealed product data unavailable",
           state: :data_error,
           read_error: reason
         )}
    end
  end

  def mount(_params, _session, socket),
    do:
      {:ok,
       socket
       |> configure_offer_streams()
       |> assign(page_title: "Sealed product not found", state: :not_found)}

  @impl true
  def render(%{state: :product} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world sealed-detail-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}>TCG CHEAP</.link>
        </header>
        <main id="sealed-detail-main" class="decision-main">
          <div class="decision-container">
            <.link id="sealed-detail-back" navigate={~p"/"}>Back to search</.link>
            <div class="sealed-detail-overview">
              <section id="sealed-detail-identity" aria-labelledby="sealed-detail-title">
                <h1 id="sealed-detail-title">{@product.name}</h1>
                <p id="sealed-detail-type">{human_product_type(@product.product_type)}</p>
                <p :if={@product.series_name || @product.set_name} id="sealed-detail-collection">
                  {collection(@product)}
                </p>
                <p id="sealed-detail-release">
                  {format_release_date(@product.release_date)}
                </p>
                <p id="sealed-detail-status">{human_status(@product.distribution_status)}</p>
                <p id="sealed-detail-msrp">
                  <%= if finite_decimal?(@product.msrp_pln) do %>
                    MSRP: {format_pln(@product.msrp_pln)} PLN
                  <% else %>
                    MSRP unavailable
                  <% end %>
                </p>
              </section>

              <section
                id="sealed-detail-market-snapshot"
                class="state-note"
                aria-labelledby="sealed-detail-market-snapshot-title"
              >
                <h2 id="sealed-detail-market-snapshot-title">Price guide</h2>
                {aggregate_content(@aggregate_state, @aggregate, @aggregate_current?)}
              </section>
            </div>

            <section id="sealed-current-section" aria-labelledby="sealed-current-title">
              <h2 id="sealed-current-title">Offers</h2>
              <p
                :if={@current_offer_count == 0 and is_nil(@read_error)}
                id="sealed-current-empty"
                class="state-note"
              >
                No current local offers yet.
              </p>
              <div id="sealed-current-offers" phx-update="stream" class="sealed-offer-ledger">
                <.offer_card
                  :for={{id, offer} <- @streams.current_offers}
                  id={id}
                  offer={offer}
                  prefix="current"
                />
              </div>
            </section>

            <section
              :if={buying_guide_visible?(@buying_guide_state)}
              id="sealed-detail-buying-guide"
              aria-labelledby="sealed-detail-buying-guide-title"
            >
              <h2 id="sealed-detail-buying-guide-title">Price guide</h2>
              {buying_guide_content(@buying_guide_state)}
            </section>

            <section
              :if={market_history_visible?(@market_history_state, @market_history)}
              id="sealed-market-history-section"
              aria-labelledby="sealed-market-history-title"
            >
              <h2 id="sealed-market-history-title">30-day market history</h2>
              {history_content(@market_history, @market_history_state)}
            </section>

            <p :if={@read_error} id="sealed-detail-read-error" class="state-note state-error">
              Offers unavailable.
            </p>

            <details :if={@sold_out_offer_count > 0} id="sealed-sold-out-section">
              <summary id="sealed-sold-out-title">Sold out at last check</summary>
              <p
                :if={@sold_out_offer_count == 0 and is_nil(@read_error)}
                id="sealed-sold-out-empty"
                class="state-note"
              >
                No sold-out offers yet.
              </p>
              <div id="sealed-sold-out-offers" phx-update="stream" class="sealed-offer-ledger">
                <.offer_card
                  :for={{id, offer} <- @streams.sold_out_offers}
                  id={id}
                  offer={offer}
                  prefix="sold-out"
                />
              </div>
            </details>

            <aside id="sealed-detail-notes">
              <p>Prices exclude shipping.</p>
            </aside>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  def render(%{state: :data_error} = assigns), do: data_error(assigns)
  def render(assigns), do: not_found_render(assigns)

  attr :flash, :map, required: true

  def data_error(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world sealed-detail-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}>TCG CHEAP</.link>
        </header>
        <main id="sealed-detail-main" class="decision-main">
          <div class="decision-container">
            <section id="sealed-detail-data-error" class="state-note state-error">
              <h1>Sealed product data is unavailable</h1>
              <p>We could not load this product right now. Try again later.</p>
              <.link id="sealed-detail-data-error-back" navigate={~p"/"}>Back to search</.link>
            </section>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp offer_card(assigns) do
    ~H"""
    <article id={@id} class="sealed-offer">
      <h3>{@offer.retailer.name}</h3>
      <p
        id={"sealed-#{@prefix}-price-#{@offer.listing.id}"}
        class="sealed-offer-price"
      >
        {price_or_unavailable(@offer.listing.current_price_pln)}
      </p>
      <p
        id={"sealed-#{@prefix}-stock-#{@offer.listing.id}"}
        class="sealed-offer-stock"
      >
        {stock_label(@offer.listing.stock_status)}
      </p>
      <p
        id={"sealed-#{@prefix}-checked-#{@offer.listing.id}"}
        class="sealed-offer-checked"
      >
        {checked_text(@offer.listing.last_checked_at)}
      </p>
      <%= if valid_direct_url?(@offer.listing.direct_url) do %>
        <.link
          id={"sealed-#{@prefix}-direct-link-#{@offer.listing.id}"}
          href={@offer.listing.direct_url}
          target="_blank"
          rel="noopener noreferrer"
          aria-label={direct_link_label(@offer)}
        >View retailer listing</.link>
      <% else %>
        <span id={"sealed-#{@prefix}-direct-link-unavailable-#{@offer.listing.id}"}>Direct link unavailable</span>
      <% end %>
    </article>
    """
  end

  defp load_product(socket, product, now) do
    {projection, read_error} =
      case Core.list_public_listing_mappings_for_product(product.id) do
        {:ok, mappings} when is_list(mappings) ->
          {PublicSealedProductProjection.project(mappings), nil}

        {:error, reason} ->
          {%{current: [], sold_out: []}, reason}

        _ ->
          {%{current: [], sold_out: []}, :invalid_local_read}
      end

    {aggregate_state, aggregate} = load_aggregate(product.id, now)
    today = DateTime.to_date(now)
    {history_state, history} = load_history(product.id, today)

    buying_guide_state =
      SealedBuyingGuidePublicProjection.load(product.id, aggregate_state, aggregate, now)

    socket
    |> assign(
      page_title: product.name,
      state: :product,
      product: product,
      current_offer_count: length(projection.current),
      sold_out_offer_count: length(projection.sold_out),
      read_error: read_error,
      aggregate_state: aggregate_state,
      aggregate: aggregate,
      market_history_state: history_state,
      market_history: SealedMarketHistory.build(history, product.id, now),
      aggregate_current?: aggregate_current?(aggregate_state, aggregate, product.id, now),
      buying_guide_state: buying_guide_state
    )
    |> stream(:current_offers, projection.current, reset: true)
    |> stream(:sold_out_offers, projection.sold_out, reset: true)
  end

  defp load_aggregate(product_id, now) do
    today = DateTime.to_date(now)

    case Core.get_latest_sealed_daily_aggregate(
           product_id,
           SealedDailyAggregateCalculator.version(),
           today
         ) do
      {:ok, nil} -> {:none, nil}
      {:ok, aggregate} -> normalize_latest_aggregate(aggregate, product_id, now, today)
      {:error, _reason} -> {:unavailable, nil}
    end
  end

  defp load_history(product_id, today) do
    case Core.list_sealed_daily_aggregate_history(
           product_id,
           SealedDailyAggregateCalculator.version(),
           Date.add(today, -29),
           today
         ) do
      {:ok, history} when is_list(history) -> {:ok, history}
      _ -> {:error, []}
    end
  end

  defp normalize_latest_aggregate(aggregate, product_id, now, _today) do
    cond do
      SealedDailyAggregatePublic.ready?(aggregate, now, sealed_product_id: product_id) ->
        {:ready, aggregate}

      SealedDailyAggregatePublic.limited?(aggregate, now, sealed_product_id: product_id) ->
        load_cached_ready(aggregate, product_id, now)

      true ->
        {:invalid, nil}
    end
  end

  defp load_cached_ready(limited, product_id, now) do
    case Core.get_latest_ready_sealed_daily_aggregate(
           product_id,
           SealedDailyAggregateCalculator.version(),
           limited.aggregate_date
         ) do
      {:ok, snapshot} when not is_nil(snapshot) ->
        if snapshot.id != limited.id and
             SealedDailyAggregatePublic.ready?(snapshot, now, sealed_product_id: product_id) do
          {:limited_cached, %{limited: limited, snapshot: snapshot}}
        else
          {:limited, limited}
        end

      _ ->
        {:limited, limited}
    end
  end

  defp aggregate_content(:none, aggregate, current?),
    do: aggregate_content_none(aggregate, current?)

  defp aggregate_content(:unavailable, aggregate, current?),
    do: aggregate_content_unavailable(aggregate, current?)

  defp aggregate_content(:limited, aggregate, current?),
    do: aggregate_content_limited(aggregate, current?)

  defp aggregate_content(:limited_cached, aggregate, current?),
    do: aggregate_content_limited_cached(aggregate, current?)

  defp aggregate_content(:ready, aggregate, current?),
    do: aggregate_content_ready(aggregate, current?)

  defp aggregate_content(_, aggregate, current?),
    do: aggregate_content_invalid(aggregate, current?)

  defp aggregate_content_none(_aggregate, _current?) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-empty">
      Limited data.
    </p>
    """
  end

  defp history_content(history, :ok) do
    assigns = %{history: history}

    ~H"""
    <figure id="sealed-market-history-chart-wrap">
      <svg
        id="sealed-market-history-chart"
        viewBox="0 0 300 120"
        role="img"
        aria-labelledby="sealed-market-history-chart-title sealed-market-history-chart-description"
      >
        <title id="sealed-market-history-chart-title">Thirty-day sealed market history</title>
        <desc id="sealed-market-history-chart-description">
          Benchmark and typical price range over the last thirty days.
        </desc>
        <%= for {path, index} <- Enum.with_index(@history.range_paths) do %>
          <path id={"sealed-market-history-range-#{index}"} class="sealed-history-range" d={path} />
        <% end %>
        <%= for {path, index} <- Enum.with_index(@history.benchmark_paths) do %>
          <path
            id={"sealed-market-history-benchmark-#{index}"}
            class="sealed-history-benchmark"
            d={path}
          />
        <% end %>
        <%= for {point, index} <- Enum.with_index(@history.plot_points) do %>
          <circle
            id={"sealed-market-history-point-#{index}"}
            class="sealed-history-point"
            cx={point.x}
            cy={point.benchmark_y}
            r="2.5"
          >
            <title>
              {format_aggregate_date(point.date)}: {format_history_point(point.date, @history.points)}
            </title>
          </circle>
        <% end %>
      </svg>
      <ol id="sealed-market-history-ledger" class="sr-only">
        <li
          :for={point <- @history.points}
          id={"sealed-market-history-day-#{Date.to_iso8601(point.date)}"}
        >
          <strong>{format_aggregate_date(point.date)}</strong>: benchmark {format_pln(
            point.benchmark_pln
          )} PLN; typical range {format_pln(point.typical_low_pln)}–{format_pln(
            point.typical_high_pln
          )} PLN
        </li>
      </ol>
    </figure>
    """
  end

  defp buying_guide_content({:ready, guide}) do
    assigns = %{guide: guide}

    ~H"""
    {ready_buying_bands(@guide)}
    """
  end

  defp buying_guide_content({:stale_ready, guide}) do
    assigns = %{guide: guide}

    ~H"""
    <p id="sealed-detail-guide-stale">
      May be outdated.
    </p>
    {ready_buying_bands(@guide)}
    """
  end

  defp buying_guide_content({:cached_ready, %{cached: guide}}) do
    assigns = %{guide: guide}

    ~H"""
    <p id="sealed-detail-guide-limited">
      Limited data.
    </p>
    <p id="sealed-detail-guide-cached">
      May be outdated.
    </p>
    {ready_buying_bands(@guide)}
    """
  end

  defp ready_buying_bands(guide) do
    assigns = %{guide: guide}

    ~H"""
    <div id="sealed-detail-buying-bands" class="sealed-buying-bands">
      <article id="sealed-detail-buying-band-great">
        <h3>Great price</h3><p>
          At or below {format_pln(@guide.great_price_max_pln)} PLN (inclusive).
        </p>
      </article>
      <article id="sealed-detail-buying-band-fair">
        <h3>Fair price</h3><p>
          Above {format_pln(@guide.great_price_max_pln)} and at or below {format_pln(
            @guide.fair_price_max_pln
          )} PLN.
        </p>
      </article>
      <article id="sealed-detail-buying-band-expensive">
        <h3>Expensive</h3><p>
          Above {format_pln(@guide.fair_price_max_pln)} and at or below {format_pln(
            @guide.expensive_price_max_pln
          )} PLN.
        </p>
      </article>
      <article id="sealed-detail-buying-band-avoid">
        <h3>Avoid</h3><p>Above {format_pln(@guide.expensive_price_max_pln)} PLN.</p>
      </article>
    </div>
    """
  end

  defp format_history_point(date, points),
    do: points |> Enum.find(&(&1.date == date)) |> then(&(format_pln(&1.benchmark_pln) <> " PLN"))

  defp aggregate_content_unavailable(_aggregate, _current?) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-error">
      Limited data.
    </p>
    """
  end

  defp aggregate_content_limited(_aggregate, _current?) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-limited">
      Limited data.
    </p>
    """
  end

  defp aggregate_content_limited_cached(%{snapshot: aggregate}, _current?) do
    assigns = %{aggregate: aggregate}

    ~H"""
    <p id="sealed-detail-aggregate-limited">
      Limited data.
    </p>
    <p id="sealed-detail-aggregate-cached">
      May be outdated.
    </p>
    {ready_snapshot_content(@aggregate)}
    """
  end

  defp aggregate_content_ready(aggregate, current?) do
    assigns = %{aggregate: aggregate, current?: current?}

    ~H"""
    <p :if={!@current?} id="sealed-detail-aggregate-ready">
      <span id="sealed-detail-aggregate-stale">May be outdated.</span>
    </p>
    <dl id="sealed-detail-aggregate-summary" class="sealed-aggregate-summary">
      <div>
        <dt>
          {if(@current?,
            do: "Market price",
            else: "Market price"
          )}
        </dt><dd id="sealed-detail-benchmark">
          {format_pln(@aggregate.benchmark_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>
          {if(@current?,
            do: "Typical range",
            else: "Typical range"
          )}
        </dt><dd id="sealed-detail-range">
          {format_pln(@aggregate.typical_low_pln)}–{format_pln(@aggregate.typical_high_pln)} PLN
        </dd>
      </div>
    </dl>
    """
  end

  defp aggregate_content_invalid(_aggregate, _current?) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-invalid">
      Limited data.
    </p>
    """
  end

  defp ready_snapshot_content(aggregate) do
    assigns = %{aggregate: aggregate}

    ~H"""
    <dl id="sealed-detail-aggregate-summary" class="sealed-aggregate-summary">
      <div>
        <dt>Market price</dt><dd id="sealed-detail-benchmark">
          {format_pln(@aggregate.benchmark_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>Typical range</dt><dd id="sealed-detail-range">
          {format_pln(@aggregate.typical_low_pln)}–{format_pln(@aggregate.typical_high_pln)} PLN
        </dd>
      </div>
    </dl>
    """
  end

  defp format_aggregate_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  defp format_aggregate_date(_), do: "unavailable"

  defp aggregate_current?(:ready, aggregate, product_id, now) do
    SealedDailyAggregatePublic.current_ready?(aggregate, now, sealed_product_id: product_id)
  end

  defp aggregate_current?(_state, _aggregate, _product_id, _now), do: false

  defp buying_guide_visible?({state, _guide}) when state in [:ready, :stale_ready], do: true
  defp buying_guide_visible?({:cached_ready, _guide}), do: true
  defp buying_guide_visible?(_state), do: false

  defp market_history_visible?(:ok, %{points: points}) when points != [], do: true
  defp market_history_visible?(_state, _history), do: false

  defp configure_offer_streams(socket) do
    socket
    |> stream_configure(:current_offers,
      dom_id: fn offer -> "sealed-current-offer-#{offer.listing.id}" end
    )
    |> stream_configure(:sold_out_offers,
      dom_id: fn offer -> "sealed-sold-out-offer-#{offer.listing.id}" end
    )
  end

  defp not_found_render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="decision-world sealed-detail-world">
        <header id="decision-header" class="decision-header">
          <.link id="decision-wordmark" navigate={~p"/"}>TCG CHEAP</.link>
        </header>
        <main id="sealed-detail-main" class="decision-main">
          <div class="decision-container">
            <section id="sealed-detail-not-found" class="state-note state-error">
              <h1>Sealed product not found</h1>
              <p>No public product matches this address.</p>
              <.link id="sealed-detail-not-found-back" navigate={~p"/"}>Back to search</.link>
            </section>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp human_product_type(type),
    do:
      type
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp human_status("discontinued"), do: "Discontinued"
  defp human_status(_), do: "Current"

  defp collection(product),
    do: Enum.filter([product.series_name, product.set_name], & &1) |> Enum.join(" · ")

  defp format_release_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  defp format_release_date(_), do: "unavailable"

  defp finite_decimal?(%Decimal{} = value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt

  defp finite_decimal?(_), do: false

  defp format_pln(value) do
    [whole, fraction] =
      value
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> String.split(".", parts: 2)
      |> Kernel.++(["0"])
      |> Enum.take(2)

    whole <> "." <> String.pad_trailing(fraction, 2, "0")
  end

  defp price_or_unavailable(value) when is_struct(value, Decimal) do
    if finite_decimal?(value), do: format_pln(value) <> " PLN", else: "unavailable"
  end

  defp price_or_unavailable(_), do: "unavailable"
  defp stock_label("in_stock"), do: "In stock"
  defp stock_label("sold_out"), do: "Sold out at last check"
  defp stock_label(_), do: "Stock unavailable"

  defp direct_link_label(offer),
    do: "View #{offer.retailer.name} listing, #{stock_label(offer.listing.stock_status)}"

  defp checked_text(%DateTime{} = checked_at) do
    case max(DateTime.diff(DateTime.utc_now(), checked_at, :day), 0) do
      0 -> "Checked today"
      1 -> "Checked yesterday"
      days -> "Checked #{days} days ago"
    end
  end

  defp checked_text(_), do: "Checked unavailable"

  defp valid_direct_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo)
  rescue
    URI.Error -> false
  end

  defp valid_direct_url?(_), do: false
end
