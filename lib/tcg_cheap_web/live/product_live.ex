defmodule TcgCheapWeb.ProductLive do
  @moduledoc "One catalogue product: today's verdict, the offers behind it and 90 days of prices."

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.{Guide, Kinds, PriceGuide, Regions, Shops}
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
        <.site_header locale={@locale} return_to={@locale_return_to}>
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
            <.fluent_icon name={:arrow_left} />{gettext("Wszystkie produkty")}
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
                > · {@page.product.set_name}</span><span id="product-region">
                  {gettext("· wersja %{edition}",
                    edition:
                      if(@locale == "pl",
                        do: String.downcase(Regions.label(@page.product.region)),
                        else: Regions.label(@page.product.region)
                      )
                  )}
                </span>
              </p>
              <p :if={@page.suggested_price} id="product-suggested" class="product-facts">
                {gettext("Cena sugerowana (REBEL): %{price}",
                  price: Polish.price(@page.suggested_price.price)
                )} · <a href="#product-suggested-price">{gettext("skąd ta cena?")}</a>
              </p>
              <p :if={@page.product.contents} id="product-inside" class="product-facts">
                <a href="#product-contents">{gettext("Co jest w środku")} ↓</a>
              </p>
            </section>
            <.verdict_block
              verdict={@page.verdict}
              nearby={if(@location_ready?, do: nearby(@page, @location))}
            />
          </div>

          <section id="product-offers" class="product-section" aria-labelledby="product-offers-title">
            <div class="product-section-heading">
              <h2 id="product-offers-title">{gettext("Oferty w sklepach")}</h2>
              <p :if={@offer_count > 0}>
                {gettext("%{offers}, na stanie: %{count}",
                  offers: Polish.plural(@offer_count, "oferta", "oferty", "ofert"),
                  count: @in_stock_count
                )}
              </p>
            </div>
            <ul id="offer-list" class="offer-list" phx-update="stream">
              <li id="offer-list-empty" class="guide-empty hidden only:block">
                {gettext("Żaden sklep nie ma teraz tego produktu w ofercie.")}
              </li>
              <li
                :for={{dom_id, offer} <- @streams.offers}
                id={dom_id}
                class={["offer", !offer.in_stock && "offer-unavailable"]}
              >
                <.shop_logo shop={offer.shop} />
                <div class="offer-shop">
                  <strong>{shop_name(offer)}</strong>
                  <.offer_delivery offer={offer} location={@location} />
                </div>
                <strong class="offer-price">{Polish.price(offer.price)}</strong>
                <p class="offer-state">
                  <span class="offer-stock">
                    {if offer.in_stock, do: gettext("Na stanie"), else: gettext("Brak na stanie")}
                  </span>
                  <span class="offer-checked">
                    {gettext("sprawdzono %{when}",
                      when: Polish.days_ago(DateTime.to_date(offer.last_seen_at), @page.today)
                    )}
                  </span>
                </p>
                <a
                  href={offer.url}
                  target="_blank"
                  rel="noopener nofollow"
                  class="offer-link"
                  aria-label={
                    gettext("%{shop}: przejdź do sklepu (otwiera się w nowej karcie)",
                      shop: shop_name(offer)
                    )
                  }
                >{gettext("Do sklepu")}</a>
              </li>
            </ul>
            <p id="offer-disclaimer" class="guide-note offer-disclaimer">
              <.fluent_icon name={:shield_error} />
              {gettext(
                "Jesteśmy niezależnym agregatorem: nie sprzedajemy produktów i nie weryfikujemy sklepów. Zanim zapłacisz, sprawdź sklep – opinie, dane firmy i regulamin."
              )}
            </p>
          </section>

          <.contents :if={@page.product.contents} contents={@page.product.contents} />

          <section
            id="product-history"
            class="product-section"
            aria-labelledby="product-history-title"
          >
            <div class="product-section-heading">
              <h2 id="product-history-title">{gettext("Ceny z ostatnich 90 dni")}</h2>
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

          <.suggested_price :if={@page.suggested_price} suggested={@page.suggested_price} />
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
      <.fluent_icon name={:location} />{gettext("odbiór: %{city}, %{distance}",
        city: @shop.pickup_city,
        distance: VisitorLocation.km(@km)
      )}
    </span>
    """
  end

  defp delivery_terms(shop, price, km, near?) do
    threshold = shop.free_shipping_from
    shipping = shipping(shop, price)

    # The threshold stays visible: shops often grant it for some carriers only.
    cost =
      case shipping do
        :free -> gettext("darmowa dostawa od %{amount}", amount: amount(threshold))
        {:from, from} -> gettext("dostawa od %{amount}", amount: amount(from))
        :unknown -> gettext("koszt dostawy w koszyku")
      end

    [
      cost,
      threshold && shipping != :free && gettext("darmowa od %{amount}", amount: amount(threshold)),
      pickup_term(shop.pickup_city, km, near?)
    ]
    |> Enum.filter(&is_binary/1)
  end

  # Pickup within the radius is shown on its own line instead.
  defp pickup_term(nil, _km, _near?), do: nil
  defp pickup_term(_city, _km, true), do: nil
  defp pickup_term(city, nil, false), do: gettext("odbiór osobisty: %{city}", city: city)

  defp pickup_term(city, km, false),
    do:
      gettext("odbiór osobisty: %{city} (%{distance})",
        city: city,
        distance: VisitorLocation.km(km)
      )

  defp shipping(shop, price) do
    threshold = shop.free_shipping_from

    cond do
      threshold != nil and not Decimal.lt?(price, threshold) -> :free
      shop.shipping_from -> {:from, shop.shipping_from}
      true -> :unknown
    end
  end

  # Pickup next to the verdict: without a location, an invitation to set one
  # (only when some shop with stock has pickup); with one, the cheapest
  # in-stock pickup within the radius, or else that delivery is needed and
  # what the cheapest offer's shop charges for it.
  defp nearby(%{offers: offers}, nil) do
    if offers |> Enum.filter(& &1.in_stock) |> VisitorLocation.pickup_offered?(),
      do: :invite
  end

  defp nearby(%{verdict: %{cheapest: nil}}, _location), do: nil

  defp nearby(%{offers: offers, verdict: %{cheapest: cheapest}}, location) do
    case offers |> Enum.filter(& &1.in_stock) |> VisitorLocation.cheapest_pickup(location) do
      %{} = pickup ->
        Map.put(pickup, :extra, Decimal.sub(pickup.offer.price, cheapest.price))

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
        <h2 id="product-cardmarket-title">{gettext("Cena na Cardmarket")}</h2>
        <p :if={@product.cardmarket_price_updated_on}>
          {gettext("z %{date}", date: Polish.date(@product.cardmarket_price_updated_on))}
        </p>
      </div>
      <%= if @product.cardmarket_trend do %>
        <p id="cardmarket-trend" class="cardmarket-trend">
          {gettext("Trend:")} <strong>{Polish.eur(@product.cardmarket_trend)}</strong>
          <span :if={@cardmarket_pln}>≈ {Polish.zloty(@cardmarket_pln)}</span>
        </p>
        <p class="guide-note">
          {gettext("Europejska giełda, bez wysyłki z innych krajów")}<span :if={@eur_pln}>{gettext("; kurs NBP %{rate} zł z %{date}" , rate: Polish.rate(@eur_pln.rate), date: Polish.date(@eur_pln.date))}</span>.
          <span :if={@product.cardmarket_added_on} id="product-added">
            {gettext("Na Cardmarket od %{date}.", date: Polish.date(@product.cardmarket_added_on))}
          </span>
        </p>
      <% else %>
        <p id="cardmarket-none" class="guide-note">
          {gettext("Cardmarket nie podaje jeszcze ceny tego produktu.")}
        </p>
      <% end %>
    </section>
    """
  end

  attr :contents, :map, required: true

  defp contents(assigns) do
    items = Enum.sort_by(assigns.contents.items, &item_rank(&1.type))

    assigns =
      assign(assigns,
        items: items,
        rows: ceil(length(items) / 2),
        deck_size: assigns.contents.deck |> Enum.map(& &1.quantity) |> Enum.sum(),
        categories: Enum.group_by(assigns.contents.deck, & &1.category)
      )

    ~H"""
    <section id="product-contents" class="product-section" aria-labelledby="product-contents-title">
      <div class="product-section-heading">
        <h2 id="product-contents-title">{gettext("Co jest w środku")}</h2>
        <p>{gettext("sprawdzono %{date}", date: Polish.date(@contents.checked_on))}</p>
      </div>
      <ul id="contents-items" class="contents-items" style={"--rows: #{@rows}"}>
        <li :for={item <- @items}>
          <span class="contents-quantity">{item.quantity}×</span>
          <span class="contents-label">{item_label(item)}</span>
          <img
            :if={item.image}
            src={item.image <> "/low.webp"}
            alt=""
            width="34"
            height="48"
            loading="lazy"
          />
        </li>
      </ul>
      <div :if={@contents.deck != []} id="contents-deck" class="contents-deck">
        <h3>{gettext("Karty w talii (%{count})", count: @deck_size)}</h3>
        <div :for={category <- [:pokemon, :trainer, :energy]} :if={@categories[category]}>
          <h4>
            {category_label(category)} ({@categories[category]
            |> Enum.map(& &1.quantity)
            |> Enum.sum()})
          </h4>
          <ul>
            <li :for={card <- @categories[category]}>
              <span class="contents-quantity">{card.quantity}</span>
              {card.name}
              <span :if={card.set} class="contents-card-set">{card.set} {card.number}</span>
            </li>
          </ul>
        </div>
      </div>
      <p class="guide-note">
        {gettext("Źródła:")}
        <%= for {url, index} <- Enum.with_index(@contents.sources) do %>
          <span :if={index > 0}>·</span>
          <a href={url} target="_blank" rel="noopener nofollow">{URI.parse(url).host}</a>
        <% end %>
      </p>
    </section>
    """
  end

  defp item_label(%{type: :booster, name: nil}), do: gettext("booster")
  defp item_label(%{type: :booster, name: set}), do: gettext("booster %{set}", set: set)
  defp item_label(%{type: :promo_card, name: nil}), do: gettext("karta promo")

  defp item_label(%{type: :promo_card, name: card}),
    do: gettext("karta promo %{card}", card: card)

  defp item_label(%{type: :oversize_card, name: nil}), do: gettext("duża karta")

  defp item_label(%{type: :oversize_card, name: card}),
    do: gettext("duża karta %{card}", card: card)

  defp item_label(%{type: :card, name: nil}), do: gettext("karta")
  defp item_label(%{type: :card, name: card}), do: gettext("karta %{card}", card: card)
  defp item_label(%{type: :deck, name: nil}), do: gettext("talia gotowa do gry")
  defp item_label(%{type: :deck, name: deck}), do: gettext("talia %{deck}", deck: deck)
  defp item_label(%{type: :sleeves}), do: gettext("koszulki na karty")
  defp item_label(%{type: :energy_cards}), do: gettext("karty energii")
  defp item_label(%{type: :dice}), do: gettext("kość do gry")
  defp item_label(%{type: :damage_counters}), do: gettext("kości do liczenia obrażeń")
  defp item_label(%{type: :coin}), do: gettext("moneta")
  defp item_label(%{type: :condition_markers}), do: gettext("znaczniki stanów")
  defp item_label(%{type: :deck_box}), do: gettext("pudełko na talię")
  defp item_label(%{type: :storage_box}), do: gettext("pudełko na karty")
  defp item_label(%{type: :card_dividers}), do: gettext("przekładki")
  defp item_label(%{type: :player_guide}), do: gettext("przewodnik gracza")
  defp item_label(%{type: :rule_sheet}), do: gettext("zasady gry")
  defp item_label(%{type: :code_card}), do: gettext("karta z kodem do Pokémon TCG Live")
  defp item_label(%{type: :sticker}), do: gettext("naklejki")
  defp item_label(%{type: :pin}), do: gettext("przypinka")
  defp item_label(%{type: :figure}), do: gettext("figurka")
  defp item_label(%{type: :binder}), do: gettext("album")
  defp item_label(%{type: :playmat}), do: gettext("mata do gry")
  defp item_label(%{type: :other, name: name}), do: name

  # What a buyer opens comes first, the accessories after it.
  @item_order ~w(deck booster promo_card oversize_card card energy_cards)a
  defp item_rank(type), do: Enum.find_index(@item_order, &(&1 == type)) || length(@item_order)

  defp category_label(:pokemon), do: "Pokémon"
  defp category_label(:trainer), do: gettext("Trenerzy")
  defp category_label(:energy), do: gettext("Energia")

  attr :suggested, :map, required: true

  defp suggested_price(assigns) do
    ~H"""
    <section
      id="product-suggested-price"
      class="product-section cardmarket-reference"
      aria-labelledby="product-suggested-price-title"
    >
      <div class="product-section-heading">
        <h2 id="product-suggested-price-title">{gettext("Cena sugerowana")}</h2>
        <p>
          {gettext("stan na %{date}", date: Polish.date(DateTime.to_date(@suggested.last_seen_at)))}
        </p>
      </div>
      <p id="suggested-price" class="cardmarket-trend">
        {gettext("Hurtownia REBEL:")} <strong>{Polish.price(@suggested.price)}</strong>
      </p>
      <p class="guide-note">
        {gettext(
          "Cena detaliczna sugerowana w katalogu hurtowni REBEL. Sklepy ustalają ceny same, więc nie bierzemy jej pod uwagę w ocenie. Pokazujemy ją tylko dla porównania."
        )}
      </p>
    </section>
    """
  end

  defp chart_series(page) do
    [
      %{
        key: "shops",
        label: gettext("Najniższa cena w polskich sklepach"),
        class: "shops",
        points: Enum.map(page.history, &{&1.date, &1.lowest_price})
      },
      %{
        key: "cardmarket",
        label: gettext("Cardmarket (w zł)"),
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
        {gettext("Odbierzesz gdzieś blisko?")}
        <button
          type="button"
          id="verdict-nearby-open"
          class="verdict-nearby-open"
          phx-click={JS.dispatch("location:open", to: "#visitor-location")}
        >
          {gettext("Podaj miejscowość")}
        </button>
      </p>
    </div>
    """
  end

  defp nearby_line(%{nearby: %{offer: _offer}} = assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby">
      <p class="verdict-nearby-label">
        {gettext("Najtaniej z odbiorem osobistym do %{radius} km",
          radius: VisitorLocation.radius_km()
        )}
      </p>
      <p class="verdict-nearby-value">
        <a href={@nearby.offer.url} target="_blank" rel="noopener nofollow">{@nearby.shop.name}</a>, {@nearby.shop.pickup_city} ·
        <strong>{VisitorLocation.km(@nearby.km)}</strong>
        · <strong>{Polish.price(@nearby.offer.price)}</strong>
        <%= if Decimal.gt?(@nearby.extra, 0) do %>
          (+{extra_zloty(@nearby.extra)})
        <% else %>
          {gettext("– najtaniej")}
        <% end %>
      </p>
    </div>
    """
  end

  defp nearby_line(assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby">
      <p class="verdict-nearby-label">{gettext("Odbiór osobisty")}</p>
      <p class="verdict-nearby-value verdict-nearby-none">
        {gettext("brak do %{radius} km – potrzebna dostawa", radius: VisitorLocation.radius_km())}
      </p>
      <p :if={@nearby.delivery != :unknown} class="guide-note">
        {gettext("W %{shop} %{delivery}",
          shop: @nearby.shop_name,
          delivery: delivery_note(@nearby.delivery)
        )}
      </p>
    </div>
    """
  end

  defp delivery_note({:from, from}), do: gettext("dostawa od %{amount}", amount: amount(from))
  defp delivery_note(:free), do: gettext("dostawa gratis")

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
      <h2 id="product-verdict-title" class="sr-only">{gettext("Ocena ceny")}</h2>
      <.verdict_badge verdict={@verdict} id="verdict-badge" class="verdict-badge-large" />
      <div class="verdict-body">
        <div :if={@verdict.cheapest} class="verdict-now">
          <p id="verdict-price" class="verdict-price">{Polish.price(@verdict.cheapest.price)}</p>
          <p id="verdict-shop" class="verdict-shop">
            {gettext("najtaniej teraz w")}
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
          {gettext(
            "Ocenę „dobra / normalna / drogo” pokażemy, gdy będziemy mieć %{days} dni cen z polskich sklepów.",
            days: PriceGuide.min_days_with_stock()
          )}
        </p>
        <.nearby_line :if={@nearby} nearby={@nearby} />
        <div :if={@verdict.good_max} id="verdict-thresholds" class="verdict-thresholds">
          <h3>{gettext("Widzisz cenę w sklepie?")}</h3>
          <ol class="verdict-scale">
            <.threshold
              status={:good}
              current={@verdict.status}
              prefix={gettext("do")}
              amount={Polish.zloty(@verdict.good_max)}
            />
            <.threshold
              status={:normal}
              current={@verdict.status}
              prefix={gettext("do")}
              amount={Polish.zloty(@verdict.normal_max)}
            />
            <.threshold
              status={:expensive}
              current={@verdict.status}
              prefix={gettext("powyżej")}
              amount={Polish.zloty(@verdict.normal_max)}
            />
          </ol>
        </div>
        <details id="verdict-method" class="verdict-method">
          <summary>
            <.fluent_icon name={:info} />{gettext("Jak liczymy typową cenę?")}<.fluent_icon
              name={:chevron_down}
              class="verdict-method-chevron"
            />
          </summary>
          <p>
            {gettext(
              "To mediana najniższych cen w polskich sklepach z ostatnich %{window} dni, w których produkt był dostępny; potrzebujemy co najmniej %{minimum} takich dni.",
              window: PriceGuide.window_days(),
              minimum: PriceGuide.min_days_with_stock()
            )}
            <span :if={@verdict.typical_source == :cardmarket} id="verdict-method-cardmarket">
              {gettext(
                "Tylu jeszcze nie mamy, więc porównujemy z trendem Cardmarket przeliczonym po kursie NBP."
              )}
            </span>
            {gettext(
              "Dobra cena to do 95% typowej, normalna – do 110%, wyższa – drogo. Progi zaokrąglamy w dół do pełnych złotych. Ceny nie obejmują wysyłki."
            )}
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
      <span :if={@status == @current} class="verdict-step-now">{gettext("teraz")}</span>
    </li>
    """
  end

  defp threshold_label(:good), do: gettext("Dobra")
  defp threshold_label(:normal), do: gettext("Normalna")
  defp threshold_label(:expensive), do: gettext("Drogo")

  # How far today's cheapest price is from the typical one, in whole złoty.
  defp difference(%{cheapest: %{price: price}, typical: %Decimal{} = typical}) do
    zloty = price |> Decimal.sub(typical) |> Decimal.round(0) |> Decimal.to_integer()
    percent = round(abs(zloty) / Decimal.to_float(typical) * 100)

    amount =
      if percent > 0,
        do: "#{Polish.zloty(abs(zloty))} (#{percent}%)",
        else: Polish.zloty(abs(zloty))

    cond do
      zloty < 0 -> gettext("Teraz o %{amount} taniej.", amount: amount)
      zloty > 0 -> gettext("Teraz o %{amount} drożej.", amount: amount)
      true -> gettext("Teraz tyle, ile zwykle.")
    end
  end

  defp difference(_verdict), do: nil

  defp reason(%{status: status, typical: typical, typical_source: :shops})
       when status in [:good, :normal, :expensive],
       do:
         gettext("Typowa cena z ostatnich %{days} dni: %{price}.",
           days: PriceGuide.window_days(),
           price: Polish.zloty(typical)
         )

  defp reason(%{status: :cardmarket, typical: typical}), do: cardmarket_typical(typical)

  defp reason(%{status: :insufficient_data, days_with_stock: days}) do
    gettext("Znamy ceny dopiero z %{days}, a potrzebujemy %{minimum}. ",
      days: Polish.plural(days, "dnia", "dni", "dni"),
      minimum: PriceGuide.min_days_with_stock()
    ) <>
      gettext("Cardmarket nie podaje ceny tego produktu, więc na razie go nie oceniamy.")
  end

  defp reason(%{status: :out_of_stock} = verdict) do
    [
      gettext("Teraz żaden sklep nie ma tego produktu na stanie."),
      last_known(verdict),
      typical(verdict)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp last_known(%{last_known: %{price: price, date: date}}),
    do:
      gettext("Ostatnio najtaniej: %{price} (%{date}).",
        price: Polish.price(price),
        date: Polish.date(date)
      )

  defp last_known(_verdict), do: nil

  defp typical(%{typical: %Decimal{} = typical, typical_source: :shops}),
    do:
      gettext("Typowa cena z ostatnich %{days} dni: %{price}.",
        days: PriceGuide.window_days(),
        price: Polish.zloty(typical)
      )

  defp typical(%{typical: %Decimal{} = typical, typical_source: :cardmarket}),
    do: cardmarket_typical(typical)

  defp typical(%{last_known: nil}), do: gettext("Nie znamy jeszcze jego ceny.")
  defp typical(_verdict), do: nil

  defp cardmarket_typical(typical),
    do:
      gettext("Typowa cena na Cardmarket (europejska giełda, bez wysyłki): %{price}.",
        price: Polish.zloty(typical)
      )
end
