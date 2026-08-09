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
                  Release date: {format_release_date(@product.release_date)}
                </p>
                <p id="sealed-detail-status">Status: {human_status(@product.distribution_status)}</p>
                <p id="sealed-detail-msrp">
                  <%= if finite_decimal?(@product.msrp_pln) do %>
                    MSRP: {format_pln(@product.msrp_pln)} PLN
                    <span :if={@product.msrp_source} id="sealed-detail-msrp-provenance">
                      · Source: {@product.msrp_source}
                    </span>
                  <% else %>
                    MSRP: unavailable from local records
                  <% end %>
                </p>
              </section>

              <section
                id="sealed-detail-market-snapshot"
                class="state-note"
                aria-labelledby="sealed-detail-market-snapshot-title"
              >
                <h2 id="sealed-detail-market-snapshot-title">Market snapshot</h2>
                {aggregate_content(@aggregate_state, @aggregate, @aggregate_current?)}
              </section>
            </div>

            <section
              id="sealed-detail-buying-guide"
              aria-labelledby="sealed-detail-buying-guide-title"
            >
              <h2 id="sealed-detail-buying-guide-title">Buying guide</h2>
              {buying_guide_content(@buying_guide_state)}
            </section>

            <section id="sealed-market-history-section" aria-labelledby="sealed-market-history-title">
              <h2 id="sealed-market-history-title">30-day market history</h2>
              <p>
                The line is the daily market benchmark; the band is the typical daily price range. Gaps mean no daily snapshot was available.
              </p>
              {history_content(@market_history, @market_history_state)}
            </section>

            <p :if={@read_error} id="sealed-detail-read-error" class="state-note state-error">
              Offers could not be read from local records. Product identity is retained; offer sections are empty.
            </p>

            <section id="sealed-current-section" aria-labelledby="sealed-current-title">
              <h2 id="sealed-current-title">Current in-stock offers</h2>
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

            <section id="sealed-sold-out-section" aria-labelledby="sealed-sold-out-title">
              <h2 id="sealed-sold-out-title">Sold out at last check</h2>
              <p
                :if={@sold_out_offer_count == 0 and is_nil(@read_error)}
                id="sealed-sold-out-empty"
                class="state-note"
              >
                No sold-out local evidence yet.
              </p>
              <div id="sealed-sold-out-offers" phx-update="stream" class="sealed-offer-ledger">
                <.offer_card
                  :for={{id, offer} <- @streams.sold_out_offers}
                  id={id}
                  offer={offer}
                  prefix="sold-out"
                />
              </div>
            </section>

            <aside id="sealed-detail-notes">
              <p>Prices exclude shipping.</p>
              <p>
                TCG Cheap is unofficial and not affiliated with Pokémon, Nintendo, or any listed company.
              </p>
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
              <p>Local records could not be read. Try again; no provider was contacted.</p>
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
      <p>Category: {human_category(@offer.retailer.category)}</p>
      <p id={"sealed-#{@prefix}-price-#{@offer.listing.id}"}>
        <%= if @offer.listing.stock_status == "sold_out" do %>
          Price at last check: {price_or_unavailable(@offer.listing.current_price_pln)}
        <% else %>
          {price_or_unavailable(@offer.listing.current_price_pln)}
        <% end %>
      </p>
      <p id={"sealed-#{@prefix}-stock-#{@offer.listing.id}"}>
        {stock_label(@offer.listing.stock_status)}
      </p>
      <p id={"sealed-#{@prefix}-checked-#{@offer.listing.id}"}>
        Last checked: {utc_timestamp(@offer.listing.last_checked_at)}
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
      <strong>Limited data.</strong>
      Market history is being collected from local records. No benchmark or buying bands are shown yet.
    </p>
    """
  end

  defp history_content(_history, :error) do
    assigns = %{}

    ~H"""
    <p id="sealed-market-history-error" class="state-note state-error">
      Market history could not be read from local records. No graph is shown.
    </p>
    """
  end

  defp history_content(%{points: []}, :ok) do
    assigns = %{}

    ~H"""
    <p id="sealed-market-history-empty" class="state-note">
      Daily snapshots are still being collected locally. A chart will appear when valid snapshots exist.
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
          Benchmark points connected by lines with typical price ranges. Missing dates are left as gaps.
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
      <figcaption id="sealed-market-history-legend">
        <span><i class="sealed-history-swatch sealed-history-swatch-line" aria-hidden="true"></i>Benchmark line</span><span><i
          class="sealed-history-swatch sealed-history-swatch-band"
          aria-hidden="true"
        ></i>Typical range band</span><span><i
          class="sealed-history-swatch sealed-history-swatch-point"
          aria-hidden="true"
        ></i>Daily snapshot point</span>
      </figcaption>
    </figure>
    <ol id="sealed-market-history-ledger" class="sealed-history-ledger">
      <li
        :for={point <- @history.points}
        id={"sealed-market-history-day-#{Date.to_iso8601(point.date)}"}
      >
        <strong>{format_aggregate_date(point.date)}</strong>: benchmark {format_pln(
          point.benchmark_pln
        )} PLN; typical range {format_pln(point.typical_low_pln)}–{format_pln(point.typical_high_pln)} PLN
      </li>
    </ol>
    """
  end

  defp buying_guide_content({:ready, guide}) do
    assigns = %{guide: guide}

    ~H"""
    <p id="sealed-detail-guide-ready">
      Guidance from a matching local market snapshot; no purchase action is implied.
    </p>
    {ready_buying_bands(@guide)}
    {guide_reasons(@guide)}
    """
  end

  defp buying_guide_content({:stale_ready, guide}) do
    assigns = %{guide: guide}

    ~H"""
    <p id="sealed-detail-guide-stale">
      <strong>Previous guidance.</strong>
      This guide matches an older local market snapshot and may be outdated; it is not current-ready guidance.
    </p>
    {ready_buying_bands(@guide)}
    {guide_reasons(@guide)}
    """
  end

  defp buying_guide_content({:cached_ready, %{latest: latest, cached: guide}}) do
    assigns = %{latest: latest, guide: guide}

    ~H"""
    <p id="sealed-detail-guide-limited">
      <strong>Limited data.</strong>
      The newest saved guide is limited: {limited_guide_reason(@latest.limited_reason)}.
    </p>
    <p id="sealed-detail-guide-cached">
      Previous guidance from an older matching local market snapshot is shown below and may be outdated.
    </p>
    {ready_buying_bands(@guide)}
    {guide_reasons(@guide)}
    """
  end

  defp buying_guide_content({:limited, guide}) do
    assigns = %{guide: guide}

    ~H"""
    <p id="sealed-detail-guide-limited">
      <strong>Limited data.</strong> {limited_guide_reason(@guide.limited_reason)}
    </p>
    {guide_reasons(@guide)}
    """
  end

  defp buying_guide_content(:missing) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-guide-missing">
      No saved buying guide is available yet; local calculations are still being collected.
    </p>
    """
  end

  defp buying_guide_content(:calculating) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-guide-calculating">
      The local buying guide is calculating. No price bands are shown.
    </p>
    """
  end

  defp buying_guide_content(:invalid) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-guide-invalid">
      The local buying guide could not be verified, so no price bands are shown.
    </p>
    """
  end

  defp buying_guide_content(:read_error) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-guide-read-error" class="state-note state-error">
      The buying guide could not be read from local records. No price bands are shown.
    </p>
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

  defp guide_reasons(guide) do
    assigns = %{guide: guide}

    ~H"""
    <div id="sealed-detail-guide-reasons">
      <h3>Why this guidance</h3><ul>
        <li :for={factor <- @guide.explanation_factors}>{factor_copy(factor)}</li>
      </ul>
    </div>
    """
  end

  defp factor_copy("market_benchmark"),
    do: "The guide uses the saved regular-retailer market benchmark."

  defp factor_copy("market_data_limited"), do: "Some local market data is limited."
  defp factor_copy("msrp"), do: "The product's saved MSRP informs this guidance."
  defp factor_copy("lgs"), do: "Local game-store evidence informs this guidance."
  defp factor_copy("sold_out"), do: "Recent sold-out evidence informs this guidance."

  defp factor_copy("trend_rising"), do: "Recent local snapshots indicate prices are rising."
  defp factor_copy("trend_falling"), do: "Recent local snapshots indicate prices are falling."
  defp factor_copy("trend_stable"), do: "Recent local snapshots indicate stable prices."

  defp factor_copy("trend_insufficient_history"),
    do: "There is not enough history to establish a price trend."

  defp factor_copy("availability_abundant"),
    do: "Local evidence suggests abundant availability."

  defp factor_copy("availability_balanced"),
    do: "Local evidence suggests balanced availability."

  defp factor_copy("availability_scarce"), do: "Local evidence suggests scarce availability."
  defp factor_copy("availability_trend_improving"), do: "Availability appears to be improving."

  defp factor_copy("availability_trend_tightening"),
    do: "Availability appears to be tightening."

  defp factor_copy("availability_trend_stable"), do: "Availability appears stable."

  defp factor_copy("availability_trend_insufficient_history"),
    do: "There is not enough history to establish an availability trend."

  defp limited_guide_reason(:uncertain_mapping),
    do: "There is not enough trustworthy product evidence yet."

  defp limited_guide_reason(:limited_market_aggregate),
    do: "The latest local market snapshot has limited data."

  defp limited_guide_reason(:stale_market_evidence),
    do: "The available local market evidence is stale."

  defp limited_guide_reason(:insufficient_history),
    do: "More daily history is needed for a reliable guide."

  defp limited_guide_reason(:low_confidence),
    do: "There is not enough trustworthy evidence for a dependable guide yet."

  defp limited_guide_reason(:invalid_band_boundaries),
    do: "Price ranges could not be formed safely from the available evidence."

  defp limited_guide_reason(reason) when is_binary(reason),
    do: limited_guide_reason(String.to_existing_atom(reason))

  defp format_history_point(date, points),
    do: points |> Enum.find(&(&1.date == date)) |> then(&(format_pln(&1.benchmark_pln) <> " PLN"))

  defp aggregate_content_unavailable(_aggregate, _current?) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-error">
      Market history could not be read from local records. No benchmark or buying bands are shown.
    </p>
    """
  end

  defp aggregate_content_limited(%{limited_reason: reason} = aggregate, _current?) do
    assigns = %{aggregate: aggregate, reason: reason}

    ~H"""
    <p id="sealed-detail-aggregate-limited">
      <strong>Limited data.</strong> {limited_reason_copy(@reason, @aggregate)}
    </p>
    """
  end

  defp aggregate_content_limited_cached(%{limited: limited, snapshot: aggregate}, _current?) do
    assigns = %{aggregate: aggregate, limited: limited, reason: limited.limited_reason}

    ~H"""
    <p id="sealed-detail-aggregate-limited">
      <strong>Limited data.</strong> {limited_reason_copy(@reason, @limited)}
    </p>
    <p id="sealed-detail-aggregate-cached">
      The latest check has limited data. The last usable market snapshot is shown below and may be outdated.
    </p>
    {ready_snapshot_content(@aggregate)}
    """
  end

  defp aggregate_content_ready(aggregate, current?) do
    assigns = %{aggregate: aggregate, current?: current?}

    ~H"""
    <p id="sealed-detail-aggregate-ready">
      <%= if @current? do %>
        Collected prices are sufficient for a current market benchmark. See the buying guide below.
      <% else %>
        <span id="sealed-detail-aggregate-stale">May be outdated: this cached benchmark is from the aggregate date {format_aggregate_iso_date(
          @aggregate.aggregate_date
        )}.</span>
      <% end %>
    </p>
    <dl id="sealed-detail-aggregate-summary" class="sealed-aggregate-summary">
      <div>
        <dt>
          {if(@current?,
            do: "Current market benchmark",
            else: "Latest stored benchmark"
          )}
        </dt><dd id="sealed-detail-benchmark">
          {format_pln(@aggregate.benchmark_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>
          {if(@current?,
            do: "Typical current range",
            else: "Typical range at that snapshot"
          )}
        </dt><dd id="sealed-detail-range">
          {format_pln(@aggregate.typical_low_pln)}–{format_pln(@aggregate.typical_high_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>Fresh regular retailers</dt><dd id="sealed-detail-fresh-regular-count">
          {@aggregate.fresh_regular_retailer_count}
        </dd>
      </div>
      <div :if={@aggregate.fresh_lgs_count > 0}>
        <dt>Fresh LGS</dt><dd id="sealed-detail-fresh-lgs-count">{@aggregate.fresh_lgs_count}</dd>
      </div>
      <div>
        <dt>Recent sold-out evidence (0–30 days)</dt><dd id="sealed-detail-sold-out-evidence-count">
          {@aggregate.recent_sold_out_0_14_day_count + @aggregate.sold_out_15_30_day_count}
        </dd>
      </div>
      <div>
        <dt>Aggregate date</dt><dd id="sealed-detail-aggregate-date">
          {format_aggregate_date(@aggregate.aggregate_date)}
        </dd>
      </div>
      <div>
        <dt>Evidence last checked</dt><dd id="sealed-detail-evidence-checked-at">
          {utc_timestamp(@aggregate.latest_nonfuture_checked_at)}
        </dd>
      </div>
    </dl>
    <details id="sealed-detail-methodology" class="sealed-aggregate-methodology">
      <summary>How this local benchmark is made</summary>
      <p>
        Median of fresh current regular-retailer prices after Tukey-style obvious-outlier removal. At least five current regular retailers are required. LGS and sold-out evidence are tracked separately. Shipping is excluded.
      </p>
    </details>
    """
  end

  defp aggregate_content_invalid(_aggregate, _current?) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-invalid">
      Market history is being collected from local records. No benchmark or buying bands are shown yet.
    </p>
    """
  end

  defp ready_snapshot_content(aggregate) do
    assigns = %{aggregate: aggregate}

    ~H"""
    <dl id="sealed-detail-aggregate-summary" class="sealed-aggregate-summary">
      <div>
        <dt>Latest stored benchmark</dt><dd id="sealed-detail-benchmark">
          {format_pln(@aggregate.benchmark_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>Typical range at that snapshot</dt><dd id="sealed-detail-range">
          {format_pln(@aggregate.typical_low_pln)}–{format_pln(@aggregate.typical_high_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>Aggregate date</dt><dd id="sealed-detail-aggregate-date">
          {format_aggregate_date(@aggregate.aggregate_date)}
        </dd>
      </div>
      <div>
        <dt>Evidence last checked</dt><dd id="sealed-detail-evidence-checked-at">
          {utc_timestamp(@aggregate.latest_nonfuture_checked_at)}
        </dd>
      </div>
    </dl>
    """
  end

  defp limited_reason_copy("no_fresh_current_offers", _aggregate),
    do:
      "No fresh current offers were available in collected data, so market history is still being built."

  defp limited_reason_copy("too_few_regular_retailers", %{fresh_regular_retailer_count: 1}),
    do:
      "Only 1 fresh regular retailer was available; more are needed before a benchmark can be shown."

  defp limited_reason_copy("too_few_regular_retailers", aggregate),
    do:
      "Only #{aggregate.fresh_regular_retailer_count} fresh regular retailers were available; more are needed before a benchmark can be shown."

  defp limited_reason_copy("insufficient_inliers", _aggregate),
    do:
      "Fresh prices did not leave enough comparable offers after obvious-outlier removal; market history is still being collected."

  defp limited_reason_copy(_, _aggregate),
    do: "Market history is still being collected; no benchmark is shown yet."

  defp format_aggregate_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  defp format_aggregate_date(_), do: "unavailable"

  defp format_aggregate_iso_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_aggregate_iso_date(_), do: "unavailable"

  defp aggregate_current?(:ready, aggregate, product_id, now) do
    SealedDailyAggregatePublic.current_ready?(aggregate, now, sealed_product_id: product_id)
  end

  defp aggregate_current?(_state, _aggregate, _product_id, _now), do: false

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
              <p>No public local product matches this address. No provider was contacted.</p>
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

  defp human_category("lgs"), do: "Local game store (LGS)"
  defp human_category("regular_retailer"), do: "Regular retailer"
  defp human_category(category), do: category
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

  defp utc_timestamp(%DateTime{} = value),
    do: Calendar.strftime(DateTime.shift_zone!(value, "Etc/UTC"), "%Y-%m-%d %H:%M:%S UTC")

  defp utc_timestamp(_), do: "unavailable"

  defp valid_direct_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo)
  rescue
    URI.Error -> false
  end

  defp valid_direct_url?(_), do: false
end
