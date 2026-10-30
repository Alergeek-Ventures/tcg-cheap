defmodule TcgCheapWeb.ProductLive do
  @moduledoc "One catalogue product: today's verdict, the offers behind it and 90 days of prices."

  use TcgCheapWeb, :live_view

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{Guide, Kinds, PriceGuide}
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
        <.site_header current={:buying} />
        <main id="product-main" class="guide-main product-page">
          <.link id="product-back" navigate={~p"/"} class="guide-back">
            <.fluent_icon name={:arrow_left} />Wszystkie produkty
          </.link>

          <section id="product-identity" class="product-identity" aria-labelledby="product-name">
            <.product_image
              url={@page.product.image_url}
              kind={@page.product.kind}
              alt={@page.product.name}
              class="product-hero-image"
              loading="eager"
            />
            <div class="product-identity-copy">
              <h1 id="product-name">{@page.product.name}</h1>
              <dl class="product-facts">
                <div>
                  <dt>Rodzaj</dt>
                  <dd id="product-kind">{Kinds.label(@page.product.kind)}</dd>
                </div>
                <div :if={@page.product.set_name}>
                  <dt>Dodatek</dt>
                  <dd id="product-set">{@page.product.set_name}</dd>
                </div>
                <div :if={@page.product.cardmarket_added_on}>
                  <dt>Na Cardmarket od</dt>
                  <dd id="product-added">{Polish.date(@page.product.cardmarket_added_on)}</dd>
                </div>
              </dl>
            </div>
          </section>

          <.verdict_block verdict={@page.verdict} eur_pln={@page.eur_pln} />

          <.cardmarket_reference
            product={@page.product}
            cardmarket_pln={@page.cardmarket_pln}
            eur_pln={@page.eur_pln}
          />

          <section id="product-offers" class="product-section" aria-labelledby="product-offers-title">
            <div class="product-section-heading">
              <h2 id="product-offers-title">Oferty w sklepach</h2>
              <p>{Polish.plural(@offer_count, "oferta", "oferty", "ofert")}</p>
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
                </div>
                <div class="offer-state">
                  <strong class="offer-price">{Polish.price(offer.price)}</strong>
                  <span class="offer-stock">
                    {if offer.in_stock, do: "Dostępny", else: "Niedostępny"}
                  </span>
                  <span class="offer-checked">
                    sprawdzono {Polish.days_ago(DateTime.to_date(offer.last_seen_at), @page.today)}
                  </span>
                </div>
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
              <h2 id="product-history-title">Ceny – ostatnie 90 dni</h2>
            </div>
            <.price_chart
              id="price-history"
              series={chart_series(@page)}
              from={Date.add(@page.today, -(Guide.history_days() - 1))}
              to={@page.today}
              typical={@page.verdict.typical}
            />
          </section>

          <.guide_footnote />
        </main>
      </div>
    </Layouts.app>
    """
  end

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
      <%= if @product.cardmarket_trend || @product.cardmarket_low do %>
        <dl class="cardmarket-prices">
          <div :if={@product.cardmarket_trend} id="cardmarket-trend">
            <dt>Trend</dt>
            <dd>
              {Polish.eur(@product.cardmarket_trend)}
              <span :if={@cardmarket_pln}>≈ {Polish.zloty(@cardmarket_pln)}</span>
            </dd>
          </div>
          <div :if={@product.cardmarket_low} id="cardmarket-low">
            <dt>Najniższa oferta</dt>
            <dd>{Polish.eur(@product.cardmarket_low)}</dd>
          </div>
          <div :if={@product.cardmarket_avg} id="cardmarket-avg">
            <dt>Średnia sprzedaży</dt>
            <dd>{Polish.eur(@product.cardmarket_avg)}</dd>
          </div>
        </dl>
        <p class="guide-note">
          Cardmarket to europejska giełda – ceny w euro, bez wysyłki z innych krajów.
          <span :if={@eur_pln}>
            Przeliczenie po kursie NBP {Polish.rate(@eur_pln.rate)} zł z {Polish.date(@eur_pln.date)}.
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
        label: "Trend Cardmarket (w zł)",
        class: "cardmarket",
        points:
          Enum.map(page.history, &{&1.date, Guide.to_pln(&1.cardmarket_trend, page.eur_pln)})
      }
    ]
  end

  attr :verdict, :map, required: true
  attr :eur_pln, :map, default: nil

  defp verdict_block(assigns) do
    ~H"""
    <section
      id="product-verdict"
      class={["verdict-block", "verdict-block-#{@verdict.status}"]}
      aria-labelledby="product-verdict-title"
    >
      <h2 id="product-verdict-title" class="sr-only">Ocena ceny</h2>
      <div class="verdict-now">
        <%= if @verdict.cheapest do %>
          <p class="verdict-label">Najtaniej teraz</p>
          <p id="verdict-price" class="verdict-price">{Polish.price(@verdict.cheapest.price)}</p>
          <p id="verdict-shop" class="verdict-shop">
            w sklepie
            <a href={@verdict.cheapest.url} target="_blank" rel="noopener nofollow">{shop_name(
              @verdict.cheapest
            )}</a>
          </p>
        <% else %>
          <p class="verdict-label">Najtaniej teraz</p>
          <p id="verdict-price" class="verdict-price verdict-price-none">—</p>
        <% end %>
      </div>
      <div class="verdict-judgement">
        <.verdict_badge status={@verdict.status} id="verdict-badge" class="verdict-badge-large" />
        <p id="verdict-reason" class="verdict-reason">{reason(@verdict)}</p>
        <p :if={@verdict.good_max} id="verdict-thresholds" class="verdict-thresholds">
          <strong>Widzisz cenę w sklepie?</strong>
          Do {Polish.zloty(@verdict.good_max)} – dobra, {Polish.number(@verdict.good_max + 1)}–{Polish.zloty(
            @verdict.normal_max
          )} – normalna, powyżej – drogo.
        </p>
        <p id="verdict-method" class="verdict-method">
          Typowa cena to mediana najniższej ceny w polskich sklepach z dni, w których produkt był dostępny
          w ostatnich {PriceGuide.window_days()} dniach (potrzeba co najmniej {PriceGuide.min_days_with_stock()} takich dni).
          Gdy tylu dni jeszcze nie ma, korzystamy z trendu cen na Cardmarket przeliczonego na złote.
          Dobra cena: do 95% typowej, normalna: do 110%.
        </p>
      </div>
    </section>
    """
  end

  defp reason(%{status: status, typical: typical, typical_source: :shops})
       when status in [:good, :normal, :expensive],
       do: "Typowa cena z ostatnich #{PriceGuide.window_days()} dni: #{Polish.zloty(typical)}."

  defp reason(%{status: status, typical: typical, typical_source: :cardmarket})
       when status in [:good, :normal, :expensive],
       do: "Typowa cena według Cardmarket: #{Polish.zloty(typical)}."

  defp reason(%{status: :insufficient_data, days_with_stock: days}) do
    "Mamy ceny z #{Polish.plural(days, "dnia", "dni", "dni")} z ostatnich #{PriceGuide.window_days()}, " <>
      "i nie mamy ceny referencyjnej z Cardmarket. Ocenimy cenę, gdy zbierzemy co najmniej #{PriceGuide.min_days_with_stock()} dni."
  end

  defp reason(%{status: :out_of_stock, last_known: %{price: price, date: date}}),
    do:
      "Żaden sklep nie ma go teraz na stanie. Ostatnio najtaniej: #{Polish.price(price)} (#{Polish.date(date)})."

  defp reason(%{
         status: :out_of_stock,
         typical: %Decimal{} = typical,
         typical_source: :cardmarket
       }),
       do:
         "Żaden sklep nie ma go teraz na stanie. Typowa cena według Cardmarket: #{Polish.zloty(typical)}."

  defp reason(%{status: :out_of_stock}),
    do: "Żaden sklep nie ma go teraz na stanie i nie znamy jeszcze jego ceny."
end
