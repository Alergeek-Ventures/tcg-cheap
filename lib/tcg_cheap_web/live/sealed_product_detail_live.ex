defmodule TcgCheapWeb.SealedProductDetailLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.PublicSealedProductProjection
  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @impl true
  def mount(%{"slug" => slug}, _session, socket) when is_binary(slug) and slug != "" do
    socket = configure_offer_streams(socket)

    case Core.get_public_sealed_product_by_slug(slug) do
      {:ok, nil} ->
        {:ok, assign(socket, page_title: "Sealed product not found", state: :not_found)}

      {:ok, product} ->
        {:ok, load_product(socket, product)}

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
                {aggregate_content(@aggregate_state, @aggregate)}
              </section>
            </div>

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

  defp load_product(socket, product) do
    {projection, read_error} =
      case Core.list_public_listing_mappings_for_product(product.id) do
        {:ok, mappings} when is_list(mappings) ->
          {PublicSealedProductProjection.project(mappings), nil}

        {:error, reason} ->
          {%{current: [], sold_out: []}, reason}

        _ ->
          {%{current: [], sold_out: []}, :invalid_local_read}
      end

    {aggregate_state, aggregate} = load_aggregate(product.id)

    socket
    |> assign(
      page_title: product.name,
      state: :product,
      product: product,
      current_offer_count: length(projection.current),
      sold_out_offer_count: length(projection.sold_out),
      read_error: read_error,
      aggregate_state: aggregate_state,
      aggregate: aggregate
    )
    |> stream(:current_offers, projection.current, reset: true)
    |> stream(:sold_out_offers, projection.sold_out, reset: true)
  end

  defp load_aggregate(product_id) do
    now = DateTime.utc_now()
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

  defp normalize_latest_aggregate(aggregate, product_id, now, today) do
    cond do
      valid_ready_aggregate?(aggregate, now) ->
        {:ready, aggregate}

      valid_limited_aggregate?(aggregate, now, today) ->
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
        if snapshot.id != limited.id and valid_ready_aggregate?(snapshot, now) do
          {:limited_cached, %{limited: limited, snapshot: snapshot}}
        else
          {:limited, limited}
        end

      _ ->
        {:limited, limited}
    end
  end

  defp valid_ready_aggregate?(aggregate, now) when is_map(aggregate) do
    Enum.all?([
      canonical_aggregate?(aggregate),
      Map.get(aggregate, :status) == "ready",
      Map.get(aggregate, :fresh_regular_retailer_count) >=
        SealedDailyAggregateCalculator.minimum_fresh_regular_retailers(),
      valid_ready_values?(aggregate),
      valid_aggregate_times?(aggregate, now, evidence?: true)
    ])
  rescue
    _ -> false
  end

  defp valid_ready_aggregate?(_, _), do: false

  defp valid_limited_aggregate?(aggregate, now, today) when is_map(aggregate) do
    Enum.all?([
      canonical_aggregate?(aggregate),
      Map.get(aggregate, :status) == "limited",
      Map.get(aggregate, :limited_reason) in SealedDailyAggregateCalculator.limited_reasons(),
      limited_reason_counts_valid?(aggregate),
      limited_values_absent?(aggregate),
      nonfuture_date?(Map.get(aggregate, :aggregate_date), today),
      valid_aggregate_times?(aggregate, now, evidence?: false)
    ])
  rescue
    _ -> false
  end

  defp canonical_aggregate?(aggregate) do
    Enum.all?([
      exact_version?(aggregate),
      Map.get(aggregate, :currency) == "PLN",
      match?(%Date{}, Map.get(aggregate, :aggregate_date)),
      nonnegative_counts?(aggregate),
      valid_coverage_counts?(aggregate)
    ])
  end

  defp exact_version?(aggregate),
    do: Map.get(aggregate, :calculation_version) == SealedDailyAggregateCalculator.version()

  defp nonnegative_counts?(aggregate) do
    Enum.all?(
      [
        :fresh_regular_retailer_count,
        :fresh_lgs_count,
        :recent_sold_out_0_14_day_count,
        :sold_out_15_30_day_count,
        :stale_or_future_current_offer_count,
        :unique_source_retailer_count
      ],
      &(is_integer(Map.get(aggregate, &1)) and Map.get(aggregate, &1) >= 0)
    )
  end

  defp valid_coverage_counts?(aggregate) do
    Map.get(aggregate, :unique_source_retailer_count) >=
      Map.get(aggregate, :fresh_regular_retailer_count) +
        Map.get(aggregate, :fresh_lgs_count)
  end

  defp valid_ready_values?(aggregate) do
    values = [aggregate.benchmark_pln, aggregate.typical_low_pln, aggregate.typical_high_pln]

    Enum.all?(values, &finite_decimal?/1) and
      Decimal.compare(aggregate.typical_low_pln, aggregate.benchmark_pln) != :gt and
      Decimal.compare(aggregate.benchmark_pln, aggregate.typical_high_pln) != :gt and
      is_nil(aggregate.limited_reason)
  end

  defp limited_values_absent?(aggregate) do
    Enum.all?(
      [:benchmark_pln, :typical_low_pln, :typical_high_pln],
      &is_nil(Map.get(aggregate, &1))
    )
  end

  defp limited_reason_counts_valid?(aggregate) do
    regular = Map.get(aggregate, :fresh_regular_retailer_count)
    lgs = Map.get(aggregate, :fresh_lgs_count)
    minimum = SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()

    case Map.get(aggregate, :limited_reason) do
      "no_fresh_current_offers" -> regular == 0 and lgs == 0
      "too_few_regular_retailers" -> regular < minimum and regular + lgs > 0
      "insufficient_inliers" -> regular >= minimum
      _ -> false
    end
  end

  defp valid_aggregate_times?(aggregate, %DateTime{} = now, options) do
    aggregate_date = Map.get(aggregate, :aggregate_date)
    calculated_at = Map.get(aggregate, :calculated_at)
    checked_at = Map.get(aggregate, :latest_nonfuture_checked_at)

    with %Date{} <- aggregate_date,
         %DateTime{} <- calculated_at,
         true <- Date.compare(aggregate_date, DateTime.to_date(calculated_at)) != :gt,
         true <- DateTime.compare(calculated_at, now) != :gt,
         true <- valid_optional_checked_at?(checked_at, calculated_at),
         true <- not Keyword.fetch!(options, :evidence?) or match?(%DateTime{}, checked_at) do
      true
    else
      _ -> false
    end
  end

  defp valid_optional_checked_at?(nil, _calculated_at), do: true

  defp valid_optional_checked_at?(%DateTime{} = checked_at, calculated_at),
    do: DateTime.compare(checked_at, calculated_at) != :gt

  defp valid_optional_checked_at?(_, _), do: false

  defp nonfuture_date?(%Date{} = date, %Date{} = today), do: Date.compare(date, today) != :gt
  defp nonfuture_date?(_, _), do: false

  defp aggregate_content(:none, _aggregate) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-empty">
      <strong>Limited data.</strong>
      Market history is being collected from local records. No benchmark or buying bands are shown yet.
    </p>
    """
  end

  defp aggregate_content(:unavailable, _aggregate) do
    assigns = %{}

    ~H"""
    <p id="sealed-detail-aggregate-error">
      Market history could not be read from local records. No benchmark or buying bands are shown.
    </p>
    """
  end

  defp aggregate_content(:limited, %{limited_reason: reason} = aggregate) do
    assigns = %{aggregate: aggregate, reason: reason}

    ~H"""
    <p id="sealed-detail-aggregate-limited">
      <strong>Limited data.</strong> {limited_reason_copy(@reason, @aggregate)}
    </p>
    """
  end

  defp aggregate_content(:limited_cached, %{limited: limited, snapshot: aggregate}) do
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

  defp aggregate_content(:ready, aggregate) do
    assigns = %{aggregate: aggregate}

    ~H"""
    <p id="sealed-detail-aggregate-ready">
      <%= if snapshot_current?(@aggregate) do %>
        Collected prices are sufficient for a current market benchmark. Buying bands and trend still need more real history.
      <% else %>
        <span id="sealed-detail-aggregate-stale">May be outdated: this cached benchmark is from the aggregate date {format_aggregate_iso_date(
          @aggregate.aggregate_date
        )}.</span>
      <% end %>
    </p>
    <dl id="sealed-detail-aggregate-summary" class="sealed-aggregate-summary">
      <div>
        <dt>
          {if(snapshot_current?(@aggregate),
            do: "Current market benchmark",
            else: "Latest stored benchmark"
          )}
        </dt><dd id="sealed-detail-benchmark">
          {format_pln(@aggregate.benchmark_pln)} PLN
        </dd>
      </div>
      <div>
        <dt>
          {if(snapshot_current?(@aggregate),
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

  defp aggregate_content(_state, _aggregate) do
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

  defp snapshot_current?(aggregate) do
    today = Date.utc_today()

    with %Date{} = date <- Map.get(aggregate, :aggregate_date),
         true <- Date.diff(today, date) in 0..1,
         %DateTime{} = checked_at <- Map.get(aggregate, :latest_nonfuture_checked_at),
         now <- DateTime.utc_now(),
         true <- DateTime.compare(checked_at, now) != :gt,
         true <-
           DateTime.diff(now, checked_at, :second) <=
             SealedDailyAggregateCalculator.policy().freshness_days * 86_400 do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

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
