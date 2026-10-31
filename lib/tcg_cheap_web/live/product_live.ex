defmodule TcgCheapWeb.ProductLive do
  @moduledoc "One catalogue product: today's verdict, the offers behind it and 90 days of prices."

  use TcgCheapWeb, :live_view

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{Guide, Kinds, PriceGuide, Shops}
  alias TcgCheapWeb.Polish

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
         |> stream(:offers, page.offers)}

      :error ->
        raise NotFound
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="guide-world">
        <.site_header />
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
            <.verdict_block verdict={@page.verdict} />
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
                  <.offer_delivery offer={offer} />
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

  # What delivery adds to an offer, from the shop's published terms:
  # "dostawa od 14,99 zł · darmowa od 400 zł · odbiór osobisty: Gdynia".
  defp offer_delivery(assigns) do
    # A no-break space keeps each "·" at the end of a line, never at the start.
    assigns = assign(assigns, :terms, delivery(assigns.offer))

    ~H"""
    <span :if={@terms != []} class="offer-delivery">{Enum.join(@terms, "\u00A0· ")}</span>
    """
  end

  defp delivery(%{shop: key, price: price}) do
    case Shops.fetch(key) do
      {:ok, shop} -> delivery_terms(shop, price)
      :error -> []
    end
  end

  defp delivery_terms(shop, price) do
    threshold = shop.free_shipping_from
    free? = threshold != nil and not Decimal.lt?(price, threshold)

    # The threshold stays visible: shops often grant it for some carriers only.
    cost =
      cond do
        free? -> "darmowa dostawa od #{amount(threshold)}"
        shop.shipping_from -> "dostawa od #{amount(shop.shipping_from)}"
        true -> "koszt dostawy w koszyku"
      end

    [
      cost,
      threshold && !free? && "darmowa od #{amount(threshold)}",
      shop.pickup_city && "odbiór osobisty: #{shop.pickup_city}"
    ]
    |> Enum.filter(&is_binary/1)
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

  attr :verdict, :map, required: true

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
