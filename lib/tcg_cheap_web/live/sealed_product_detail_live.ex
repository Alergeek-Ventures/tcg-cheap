defmodule TcgCheapWeb.SealedProductDetailLive do
  use TcgCheapWeb, :live_view

  alias TcgCheap.Catalogue.PublicSealedProductProjection
  alias TcgCheap.Core

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
                id="sealed-detail-limited-data"
                class="state-note"
                aria-labelledby="limited-data-title"
              >
                <h2 id="limited-data-title">Limited data</h2>
                <p>
                  Buying bands, benchmark, and price history are not ready. No market claims are shown.
                </p>
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

    socket
    |> assign(
      page_title: product.name,
      state: :product,
      product: product,
      current_offer_count: length(projection.current),
      sold_out_offer_count: length(projection.sold_out),
      read_error: read_error
    )
    |> stream(:current_offers, projection.current, reset: true)
    |> stream(:sold_out_offers, projection.sold_out, reset: true)
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
