defmodule TcgCheapWeb.ProductLive do
  @moduledoc "One catalogue product: today's verdict, the offers behind it and 90 days of prices."

  use TcgCheapWeb, :live_view

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{Guide, Kinds, PriceGuide, Shops}
  alias TcgCheapWeb.{Polish, VisitorLocation}

  defmodule NotFound do
    @moduledoc false
    defexception message: "product not found", plug_status: 404
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Guide.product(slug, DateTime.utc_now()) do
      {:ok, page} ->
        {:ok,
         socket
         |> assign(:page_title, page.product.name)
         |> assign(:html_lang, "pl")
         |> assign(:page, page)
         |> assign(:offer_count, length(page.offers))
         |> assign(:in_stock_count, Enum.count(page.offers, & &1.in_stock))
         |> VisitorLocation.assign_location()
         |> stream(:offers, page.offers)}

      :error ->
        raise NotFound
    end
  end

  @impl true
  def handle_event("location-" <> _ = event, params, socket) do
    located = VisitorLocation.handle_event(event, params, socket)

    # Offer rows show the distance to pickup, so they re-render with it.
    if located.assigns.location == socket.assigns.location,
      do: {:noreply, located},
      else: {:noreply, stream(located, :offers, located.assigns.page.offers, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="guide-world">
        <.site_header>
          <VisitorLocation.location_control
            location={@location}
            ready={@location_ready?}
            form={@town_form}
            matches={@town_matches}
            error={@location_error}
          />
        </.site_header>
        <main id="product-main" class="guide-main product-page">
          <.link id="product-back" navigate={~p"/"} class="guide-back">
            <.fluent_icon name={:arrow_left} />Wszystkie produkty
          </.link>

          <div class="product-top">
            <.product_image
              url={@page.product.image_url}
              kind={@page.product.kind}
              alt={@page.product.name}
              class="product-hero-image"
              loading="eager"
            />
            <section id="product-identity" class="product-identity" aria-labelledby="product-name">
              <h1 id="product-name">{@page.product.name}</h1>
              <p class="product-facts">
                <span id="product-kind">{Kinds.label(@page.product.kind)}</span><span
                  :if={@page.product.set_name}
                  id="product-set"
                > · {@page.product.set_name}</span>
              </p>
            </section>
            <.verdict_block
              verdict={@page.verdict}
              nearby={if(@location_ready?, do: nearby(@page, @location))}
            />
          </div>

          <section id="product-offers" class="product-section" aria-labelledby="product-offers-title">
            <div class="product-section-heading">
              <h2 id="product-offers-title">Oferty w sklepach</h2>
              <p :if={@offer_count > 0}>
                {Polish.plural(@offer_count, "oferta", "oferty", "ofert")}, na stanie: {@in_stock_count}
              </p>
            </div>
            <ul id="offer-list" class="offer-list" phx-update="stream">
              <li id="offer-list-empty" class="guide-empty hidden only:block">
                Żaden sklep nie ma teraz tego produktu w ofercie.
              </li>
              <li
                :for={{dom_id, offer} <- @streams.offers}
                id={dom_id}
                class={["offer", !offer.in_stock && "offer-unavailable"]}
              >
                <div class="offer-shop">
                  <strong>{shop_name(offer)}</strong>
                  <span class="offer-title">{offer.title}</span>
                  <.offer_delivery offer={offer} location={@location} />
                </div>
                <strong class="offer-price">{Polish.price(offer.price)}</strong>
                <p class="offer-state">
                  <span class="offer-stock">
                    {if offer.in_stock, do: "Na stanie", else: "Brak na stanie"}
                  </span>
                  <span class="offer-checked">
                    sprawdzono {Polish.days_ago(DateTime.to_date(offer.last_seen_at), @page.today)}
                  </span>
                </p>
                <a
                  href={offer.url}
                  target="_blank"
                  rel="noopener nofollow"
                  class="offer-link"
                  aria-label={"#{shop_name(offer)}: przejdź do sklepu (otwiera się w nowej karcie)"}
                >Do sklepu</a>
              </li>
            </ul>
          </section>

          <section
            id="product-history"
            class="product-section"
            aria-labelledby="product-history-title"
          >
            <div class="product-section-heading">
              <h2 id="product-history-title">Ceny z ostatnich 90 dni</h2>
            </div>
            <.price_chart
              id="price-history"
              series={chart_series(@page)}
              from={Date.add(@page.today, -(Guide.history_days() - 1))}
              to={@page.today}
              typical={@page.verdict.typical}
            />
          </section>

          <.cardmarket_reference
            product={@page.product}
            cardmarket_pln={@page.cardmarket_pln}
            eur_pln={@page.eur_pln}
          />

          <.guide_footnote />
        </main>
      </div>
    </Layouts.app>
    """
  end

  attr :offer, :map, required: true
  attr :location, :map, default: nil

  # What delivery adds to an offer, from the shop's published terms:
  # "dostawa od 14,99 zł · darmowa od 400 zł · odbiór osobisty: Kraków (491 km)".
  # Pickup within the radius stands out on a line of its own.
  defp offer_delivery(assigns) do
    {shop, km} =
      case Shops.fetch(assigns.offer.shop) do
        {:ok, shop} -> {shop, VisitorLocation.pickup_km(shop.key, assigns.location)}
        :error -> {nil, nil}
      end

    near? = km != nil and km <= VisitorLocation.radius_km()

    assigns =
      assign(assigns,
        shop: shop,
        km: km,
        near?: near?,
        terms: if(shop, do: delivery_terms(shop, assigns.offer.price, km, near?), else: [])
      )

    # A no-break space keeps each "·" at the end of a line, never at the start.
    ~H"""
    <span :if={@terms != []} class="offer-delivery">{Enum.join(@terms, "\u00A0· ")}</span>
    <span :if={@near?} class="offer-pickup-near">
      <.fluent_icon name={:location} />odbiór: {@shop.pickup_city}, {VisitorLocation.km(@km)}
    </span>
    """
  end

  defp delivery_terms(shop, price, km, near?) do
    threshold = shop.free_shipping_from
    shipping = shipping(shop, price)

    # The threshold stays visible: shops often grant it for some carriers only.
    cost =
      case shipping do
        :free -> "darmowa dostawa od #{amount(threshold)}"
        {:from, from} -> "dostawa od #{amount(from)}"
        :unknown -> "koszt dostawy w koszyku"
      end

    [
      cost,
      threshold && shipping != :free && "darmowa od #{amount(threshold)}",
      pickup_term(shop.pickup_city, km, near?)
    ]
    |> Enum.filter(&is_binary/1)
  end

  # Pickup within the radius is shown on its own line instead.
  defp pickup_term(nil, _km, _near?), do: nil
  defp pickup_term(_city, _km, true), do: nil
  defp pickup_term(city, nil, false), do: "odbiór osobisty: #{city}"
  defp pickup_term(city, km, false), do: "odbiór osobisty: #{city} (#{VisitorLocation.km(km)})"

  defp shipping(shop, price) do
    threshold = shop.free_shipping_from

    cond do
      threshold != nil and not Decimal.lt?(price, threshold) -> :free
      shop.shipping_from -> {:from, shop.shipping_from}
      true -> :unknown
    end
  end

  # Pickup next to the verdict: without a location, an invitation to set one
  # (only when some shop with stock has pickup); with one, the nearest
  # in-stock pickup within the radius, or else that delivery is needed and
  # what the cheapest offer's shop charges for it.
  defp nearby(%{offers: offers}, nil) do
    if offers |> Enum.filter(& &1.in_stock) |> VisitorLocation.pickup_offered?(),
      do: :invite
  end

  defp nearby(%{verdict: %{cheapest: nil}}, _location), do: nil

  defp nearby(%{offers: offers, verdict: %{cheapest: cheapest}}, location) do
    case offers |> Enum.filter(& &1.in_stock) |> VisitorLocation.nearest_pickup(location) do
      %{} = nearest ->
        Map.put(nearest, :extra, Decimal.sub(nearest.offer.price, cheapest.price))

      nil ->
        delivery =
          case Shops.fetch(cheapest.shop) do
            {:ok, shop} -> shipping(shop, cheapest.price)
            :error -> :unknown
          end

        %{delivery: delivery, shop_name: Shops.name(cheapest.shop)}
    end
  end

  defp amount(value),
    do: if(Decimal.integer?(value), do: Polish.zloty(value), else: Polish.price(value))

  attr :product, :map, required: true
  attr :cardmarket_pln, :any, required: true
  attr :eur_pln, :map, default: nil

  defp cardmarket_reference(assigns) do
    ~H"""
    <section
      id="product-cardmarket"
      class="product-section cardmarket-reference"
      aria-labelledby="product-cardmarket-title"
    >
      <div class="product-section-heading">
        <h2 id="product-cardmarket-title">Cena na Cardmarket</h2>
        <p :if={@product.cardmarket_price_updated_on}>
          z {Polish.date(@product.cardmarket_price_updated_on)}
        </p>
      </div>
      <%= if @product.cardmarket_trend do %>
        <p id="cardmarket-trend" class="cardmarket-trend">
          Trend: <strong>{Polish.eur(@product.cardmarket_trend)}</strong>
          <span :if={@cardmarket_pln}>≈ {Polish.zloty(@cardmarket_pln)}</span>
        </p>
        <p class="guide-note">
          Europejska giełda, bez wysyłki z innych krajów<span :if={@eur_pln}>; kurs NBP {Polish.rate(@eur_pln.rate)} zł z {Polish.date(@eur_pln.date)}</span>.
          <span :if={@product.cardmarket_added_on} id="product-added">
            Na Cardmarket od {Polish.date(@product.cardmarket_added_on)}.
          </span>
        </p>
      <% else %>
        <p id="cardmarket-none" class="guide-note">
          Cardmarket nie podaje jeszcze ceny tego produktu.
        </p>
      <% end %>
    </section>
    """
  end

  defp chart_series(page) do
    [
      %{
        key: "shops",
        label: "Najniższa cena w polskich sklepach",
        class: "shops",
        points: Enum.map(page.history, &{&1.date, &1.lowest_price})
      },
      %{
        key: "cardmarket",
        label: "Cardmarket (w zł)",
        class: "cardmarket",
        points:
          Enum.map(page.history, &{&1.date, Guide.to_pln(&1.cardmarket_trend, page.eur_pln)})
      }
    ]
  end

  attr :nearby, :any, required: true

  defp nearby_line(%{nearby: :invite} = assigns) do
    ~H"""
    <div id="verdict-nearby-invite" class="verdict-nearby">
      <p>
        Odbierzesz gdzieś blisko?
        <button
          type="button"
          id="verdict-nearby-open"
          class="verdict-nearby-open"
          phx-click={JS.dispatch("location:open", to: "#visitor-location")}
        >
          Podaj miejscowość
        </button>
      </p>
    </div>
    """
  end

  defp nearby_line(%{nearby: %{offer: _offer}} = assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby">
      <p class="verdict-nearby-label">Odbiór osobisty najbliżej Ciebie</p>
      <p class="verdict-nearby-value">
        <a href={@nearby.offer.url} target="_blank" rel="noopener nofollow">{@nearby.shop.name}</a>, {@nearby.shop.pickup_city} ·
        <strong>{VisitorLocation.km(@nearby.km)}</strong>
        · <strong>{Polish.price(@nearby.offer.price)}</strong>
        <%= if Decimal.gt?(@nearby.extra, 0) do %>
          (+{extra_zloty(@nearby.extra)})
        <% else %>
          – najtaniej
        <% end %>
      </p>
    </div>
    """
  end

  defp nearby_line(assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby">
      <p class="verdict-nearby-label">Odbiór osobisty</p>
      <p class="verdict-nearby-value verdict-nearby-none">
        brak do {VisitorLocation.radius_km()} km – potrzebna dostawa
      </p>
      <p :if={@nearby.delivery != :unknown} class="guide-note">
        W {@nearby.shop_name} {delivery_note(@nearby.delivery)}
      </p>
    </div>
    """
  end

  defp delivery_note({:from, from}), do: "dostawa od #{amount(from)}"
  defp delivery_note(:free), do: "dostawa gratis"

  # Whole złoty, at least 1: "+110 zł".
  defp extra_zloty(extra),
    do: extra |> Decimal.round(0) |> Decimal.to_integer() |> max(1) |> Polish.zloty()

  attr :verdict, :map, required: true
  attr :nearby, :any, default: nil

  defp verdict_block(assigns) do
    assigns = assign(assigns, :difference, difference(assigns.verdict))

    ~H"""
    <section
      id="product-verdict"
      class={["verdict-block", "verdict-block-#{@verdict.status}"]}
      aria-labelledby="product-verdict-title"
    >
      <h2 id="product-verdict-title" class="sr-only">Ocena ceny</h2>
      <.verdict_badge verdict={@verdict} id="verdict-badge" class="verdict-badge-large" />
      <div class="verdict-body">
        <div :if={@verdict.cheapest} class="verdict-now">
          <p id="verdict-price" class="verdict-price">{Polish.price(@verdict.cheapest.price)}</p>
          <p id="verdict-shop" class="verdict-shop">
            najtaniej teraz w
            <a href={@verdict.cheapest.url} target="_blank" rel="noopener nofollow">{shop_name(
              @verdict.cheapest
            )}</a>
          </p>
        </div>
        <p id="verdict-reason" class="verdict-reason">
          {reason(@verdict)}
          <span :if={@difference} id="verdict-difference">{@difference}</span>
        </p>
        <p :if={@verdict.status == :cardmarket} id="verdict-pending" class="guide-note">
          Ocenę „dobra / normalna / drogo” pokażemy, gdy będziemy mieć {PriceGuide.min_days_with_stock()} dni cen z polskich sklepów.
        </p>
        <.nearby_line :if={@nearby} nearby={@nearby} />
        <div :if={@verdict.good_max} id="verdict-thresholds" class="verdict-thresholds">
          <h3>Widzisz cenę w sklepie?</h3>
          <ol class="verdict-scale">
            <.threshold
              status={:good}
              current={@verdict.status}
              prefix="do"
              amount={Polish.zloty(@verdict.good_max)}
            />
            <.threshold
              status={:normal}
              current={@verdict.status}
              prefix="do"
              amount={Polish.zloty(@verdict.normal_max)}
            />
            <.threshold
              status={:expensive}
              current={@verdict.status}
              prefix="powyżej"
              amount={Polish.zloty(@verdict.normal_max)}
            />
          </ol>
        </div>
        <details id="verdict-method" class="verdict-method">
          <summary>
            <.fluent_icon name={:info} />Jak liczymy typową cenę?<.fluent_icon
              name={:chevron_down}
              class="verdict-method-chevron"
            />
          </summary>
          <p>
            To mediana najniższych cen w polskich sklepach z ostatnich {PriceGuide.window_days()} dni,
            w których produkt był dostępny; potrzebujemy co najmniej {PriceGuide.min_days_with_stock()} takich dni.
            <span :if={@verdict.typical_source == :cardmarket} id="verdict-method-cardmarket">
              Tylu jeszcze nie mamy, więc porównujemy z trendem Cardmarket przeliczonym po kursie NBP.
            </span>
            Dobra cena to do 95% typowej, normalna – do 110%, wyższa – drogo.
            Progi zaokrąglamy w dół do pełnych złotych. Ceny nie obejmują wysyłki.
          </p>
        </details>
      </div>
    </section>
    """
  end

  attr :status, :atom, required: true
  attr :current, :atom, required: true
  attr :prefix, :string, required: true
  attr :amount, :string, required: true

  defp threshold(assigns) do
    ~H"""
    <li
      id={"threshold-#{@status}"}
      class={["verdict-step", "verdict-step-#{@status}"]}
      aria-current={if(@status == @current, do: "true")}
    >
      <span class="verdict-step-label">{threshold_label(@status)}</span>
      <span class="verdict-step-range">{@prefix} <span>{@amount}</span></span>
      <span :if={@status == @current} class="verdict-step-now">teraz</span>
    </li>
    """
  end

  defp threshold_label(:good), do: "Dobra"
  defp threshold_label(:normal), do: "Normalna"
  defp threshold_label(:expensive), do: "Drogo"

  # How far today's cheapest price is from the typical one, in whole złoty.
  defp difference(%{cheapest: %{price: price}, typical: %Decimal{} = typical}) do
    zloty = price |> Decimal.sub(typical) |> Decimal.round(0) |> Decimal.to_integer()
    percent = round(abs(zloty) / Decimal.to_float(typical) * 100)

    amount =
      if percent > 0,
        do: "#{Polish.zloty(abs(zloty))} (#{percent}%)",
        else: Polish.zloty(abs(zloty))

    cond do
      zloty < 0 -> "Teraz o #{amount} taniej."
      zloty > 0 -> "Teraz o #{amount} drożej."
      true -> "Teraz tyle, ile zwykle."
    end
  end

  defp difference(_verdict), do: nil

  defp reason(%{status: status, typical: typical, typical_source: :shops})
       when status in [:good, :normal, :expensive],
       do: "Typowa cena z ostatnich #{PriceGuide.window_days()} dni: #{Polish.zloty(typical)}."

  defp reason(%{status: :cardmarket, typical: typical}), do: cardmarket_typical(typical)

  defp reason(%{status: :insufficient_data, days_with_stock: days}) do
    "Znamy ceny dopiero z #{Polish.plural(days, "dnia", "dni", "dni")}, a potrzebujemy #{PriceGuide.min_days_with_stock()}. " <>
      "Cardmarket nie podaje ceny tego produktu, więc na razie go nie oceniamy."
  end

  defp reason(%{status: :out_of_stock} = verdict) do
    ["Teraz żaden sklep nie ma tego produktu na stanie.", last_known(verdict), typical(verdict)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp last_known(%{last_known: %{price: price, date: date}}),
    do: "Ostatnio najtaniej: #{Polish.price(price)} (#{Polish.date(date)})."

  defp last_known(_verdict), do: nil

  defp typical(%{typical: %Decimal{} = typical, typical_source: :shops}),
    do: "Typowa cena z ostatnich #{PriceGuide.window_days()} dni: #{Polish.zloty(typical)}."

  defp typical(%{typical: %Decimal{} = typical, typical_source: :cardmarket}),
    do: cardmarket_typical(typical)

  defp typical(%{last_known: nil}), do: "Nie znamy jeszcze jego ceny."
  defp typical(_verdict), do: nil

  defp cardmarket_typical(typical),
    do: "Typowa cena na Cardmarket (europejska giełda, bez wysyłki): #{Polish.zloty(typical)}."
end
