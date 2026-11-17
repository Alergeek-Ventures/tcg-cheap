defmodule TcgCheapWeb.ProductLive.VerdictBlock do
  @moduledoc "The verdict at the top of a product page: today's price against the usual ones, the pickup next to it, the price history and the method."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.OfferComponents
  import TcgCheapWeb.PriceChart
  import TcgCheapWeb.VerdictComponents

  alias TcgCheap.Sealed.{Market, PriceGuide, ProductPage, Shops}
  alias TcgCheapWeb.{Format, Region, RegionText, VisitorLocation}

  # Pickup next to the verdict once the visitor has set a location in the
  # header: the cheapest in-stock pickup within the radius, or else that
  # delivery is needed and what the cheapest offer's shop charges for it.
  @doc false
  def nearby(_page, nil), do: nil
  def nearby(%{verdict: %{cheapest: nil}}, _location), do: nil

  def nearby(%{offers: offers, verdict: %{cheapest: cheapest}}, location) do
    case offers |> Enum.filter(& &1.in_stock) |> VisitorLocation.cheapest_pickup(location) do
      %{} = pickup ->
        Map.put(pickup, :extra, Decimal.sub(pickup.offer.price, cheapest.price))

      nil ->
        # A shop abroad's compared price already includes its delivery.
        delivery =
          case Shops.fetch(cheapest.shop) do
            {:ok, %{country: "PL"} = shop} -> shipping(shop, cheapest.price)
            {:ok, _abroad} -> :included
            :error -> :unknown
          end

        %{delivery: delivery, shop_name: Shops.name(cheapest.shop)}
    end
  end

  # Only Poland's history keeps the Cardmarket trend.
  defp chart_series(page) do
    shops = %{
      key: "shops",
      label: gettext("Najniższa cena w sklepach"),
      class: "shops",
      points: Enum.map(page.history, &{&1.date, &1.lowest_price})
    }

    if page.market == Market.poland(), do: [shops, cardmarket_series(page)], else: [shops]
  end

  defp cardmarket_series(page) do
    %{
      key: "cardmarket",
      label: gettext("Cardmarket (w zł)"),
      class: "cardmarket",
      points:
        Enum.map(page.history, &{&1.date, Market.to_pln(&1.cardmarket_trend, page.eur_rate)})
    }
  end

  attr :nearby, :any, required: true

  defp nearby_line(%{nearby: %{offer: _offer}} = assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby ph-no-capture">
      <p class="verdict-nearby-label">
        {gettext("Najtaniej z odbiorem osobistym do %{radius} km",
          radius: VisitorLocation.radius_km()
        )}
      </p>
      <p class="verdict-nearby-value">
        <a
          href={offer_url(@nearby.offer)}
          target="_blank"
          rel="noopener nofollow"
          data-track="shop_link_clicked"
          data-track-placement="nearby"
          data-track-shop={@nearby.offer.shop}
          data-track-price={@nearby.offer.price}
          data-track-in-stock={to_string(@nearby.offer.in_stock)}
        >{@nearby.shop.name}</a>, {@nearby.shop.pickup_city} ·
        <strong>{VisitorLocation.km(@nearby.km)}</strong>
        · <strong>{Format.price(@nearby.offer.price)}</strong>
        <%= if Decimal.gt?(@nearby.extra, 0) do %>
          (+{extra_price(@nearby.extra)})
        <% else %>
          {gettext("– najtaniej")}
        <% end %>
      </p>
    </div>
    """
  end

  defp nearby_line(assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby ph-no-capture">
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

  defp delivery_note({:from, from}),
    do: gettext("dostawa od %{amount}", amount: Format.shop_price(from))

  defp delivery_note(:free), do: gettext("dostawa gratis")
  defp delivery_note(:included), do: gettext("cena z wysyłką")

  # At least the market's limit step: "+110 zł", "+0,30 €".
  defp extra_price(extra),
    do: extra |> Decimal.max(Market.limit_step(Region.current().market)) |> Format.limit_price()

  attr :page, :map, required: true
  attr :nearby, :any, default: nil

  # The whole answer in one place, the way flight search does it: the
  # verdict, today's price marked on a bar of the good, normal and expensive
  # ranges, one line on how it compares with the product's history, and the
  # history chart and the method behind a click.
  def verdict_block(assigns) do
    %{verdict: verdict, past: past} = assigns.page

    assigns =
      assign(assigns,
        verdict: verdict,
        past: past,
        range: price_range(verdict),
        reason: reason(verdict, past),
        good_bound: good_bound(verdict, assigns.page.cardmarket_delivered_price)
      )

    ~H"""
    <.verdict_panel id="product-verdict" status={@verdict.status}>
      <:header>
        <%= if @verdict.status in [:cardmarket, :insufficient_data] do %>
          <.few_shops_badge verdict={@verdict} id="verdict-badge" badge_class="verdict-badge-large" />
        <% else %>
          <.verdict_badge verdict={@verdict} id="verdict-badge" class="verdict-badge-large" />
        <% end %>
      </:header>
      <.verdict_now :if={@verdict.cheapest} offer={@verdict.cheapest} preorder?={@page.preorder?} />
      <p :if={@page.preorder?} id="verdict-preorder" class="verdict-preorder-note">
        <.verdict_icon status={:preorder} />
        <span>{preorder_note(@page.premiere, @page.premiere_in)}</span>
      </p>
      <div :if={@range} id="verdict-range" class="verdict-range" aria-hidden="true">
        <div class="verdict-range-bar">
          <span class="verdict-range-good" style={"--to: #{@range.good_at}%"}></span>
          <span
            class="verdict-range-normal"
            style={"--from: #{@range.good_at}%; --to: #{@range.normal_at}%"}
          ></span>
          <span class="verdict-range-expensive" style={"--from: #{@range.normal_at}%"}></span>
          <span class="verdict-range-now" style={"--at: #{@range.cheapest_at}%"}></span>
        </div>
        <div class="verdict-range-limits">
          <span style={"--at: #{@range.good_at}%"}>{Format.limit_price(@verdict.good_max)}</span>
          <span style={"--at: #{@range.normal_at}%"}>{Format.limit_price(@verdict.normal_max)}</span>
        </div>
      </div>
      <p :if={@reason} id="verdict-reason" class="verdict-reason">{@reason}</p>
      <p :if={@good_bound} id="verdict-good-bound" class="verdict-reason">{@good_bound}</p>
      <p :if={@verdict.status == :cardmarket} id="verdict-cardmarket" class="verdict-cardmarket">
        <.cardmarket_price
          price={@verdict.typical}
          href={cardmarket_url(@page.product.cardmarket_id)}
          placement="verdict"
          cardmarket_id={@page.product.cardmarket_id}
        />
        <span>{gettext("na Cardmarket, bez wysyłki")}</span>
      </p>
      <p
        :if={@past.status in [:low, :usual, :high]}
        id="verdict-past"
        class={["verdict-past", "verdict-past-#{@past.status}"]}
      >
        <.verdict_icon status={past_tone(@past.status)} />
        <span>
          <strong>{past_label(@past.status)}</strong>
          {gettext("(zwykle %{price})", price: Format.limit_price(@past.typical))}
        </span>
      </p>
      <p :if={@verdict.status == :cardmarket} id="verdict-pending" class="guide-note">
        {if(@page.preorder?,
          do:
            gettext(
              "Ocenę pokażemy, gdy produkt będzie w przedsprzedaży w co najmniej %{count} sklepach.",
              count: PriceGuide.min_shops()
            ),
          else:
            gettext(
              "Ocenę pokażemy, gdy produkt będzie na stanie w co najmniej %{count} sklepach.",
              count: PriceGuide.min_shops()
            )
        )}
      </p>
      <.nearby_line :if={@nearby} nearby={@nearby} />
      <div class="verdict-more">
        <details id="verdict-history" class="verdict-method">
          <summary data-track="product_section_opened" data-track-section="price_history">
            {gettext("Historia cen")}<.fluent_icon
              name={:chevron_down}
              class="verdict-method-chevron"
            />
          </summary>
          <.price_chart
            id="price-history"
            series={chart_series(@page)}
            from={Date.add(@page.today, -(ProductPage.history_days() - 1))}
            to={@page.today}
            typical={@past.typical}
          />
        </details>
        <.verdict_method id="verdict-method">
          <p>
            {gettext(
              "Typowa cena to środek stawki: z każdego sklepu, który ma produkt na stanie, bierzemy cenę samego produktu, bez dostawy (potrzebujemy co najmniej %{minimum} sklepów).",
              minimum: PriceGuide.min_shops()
            )}
            <span :if={@verdict.typical_source == :cardmarket} id="verdict-method-cardmarket">
              {if(euro_region?(),
                do: gettext("Tylu jeszcze nie ma, więc porównujemy z trendem Cardmarket."),
                else:
                  gettext(
                    "Tylu jeszcze nie ma, więc porównujemy z trendem Cardmarket przeliczonym po kursie NBP."
                  )
              )}
            </span>
            <span :if={@page.preorder?} id="verdict-method-preorder">
              {gettext(
                "Gdy żaden sklep nie ma produktu na stanie, liczymy tak samo z ofert przedsprzedaży."
              )}
            </span>
          </p>
          <p>
            {gettext(
              "Dobra cena jest co najmniej 5% niższa od typowej, od zwykłej z ostatnich %{window} dni i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo.",
              window: PriceGuide.window_days()
            )}
          </p>
          <p>
            {RegionText.shop_prices_note(cardmarket_shipping(@page))}
          </p>
          <p :if={RegionText.foreign_shops_note()} id="verdict-method-currency">
            {RegionText.foreign_shops_note()}
          </p>
        </.verdict_method>
      </div>
    </.verdict_panel>
    """
  end

  # The parcel added to Cardmarket, among the page's prices: in euro in
  # Poland; elsewhere in the market's currency at its Cardmarket rate.
  defp cardmarket_shipping(%{market: market, eur_rate: rate}) do
    eur = market.cardmarket_shipping_eur

    case market != Market.poland() && Market.in_market(eur, rate, market) do
      %Decimal{} = converted -> Format.price(converted)
      _euro -> Format.eur(eur)
    end
  end

  # Where the bar's limits and today's price sit, in % of the bar: every
  # range stays wide enough to read. A price far above the limits (a shop
  # abroad's with delivery against a typical price without it) stays at the
  # bar's end.
  defp price_range(%{typical_source: :shops, cheapest: %{price: cheapest}} = verdict) do
    good_max = to_float(verdict.good_max)
    normal_max = to_float(verdict.normal_max)
    cheapest = Decimal.to_float(cheapest)
    margin = (normal_max - good_max) / 2
    low = min(cheapest, good_max - margin)
    high = max(normal_max + margin, low + 1)
    pad = (high - low) * 0.06
    {low, high} = {low - pad, high + pad}
    at = &Float.round((&1 - low) / (high - low) * 100, 2)

    %{
      good_at: at.(good_max),
      normal_at: at.(normal_max),
      cheapest_at: min(at.(cheapest), 100.0)
    }
  end

  defp price_range(_verdict), do: nil

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_integer(value), do: value / 1

  defp today_missing(%{shop_prices: []}),
    do: gettext("Teraz żaden sklep nie ma tego produktu na stanie.")

  defp today_missing(%{shop_prices: shops, cheapest: %{preorder: true}}),
    do:
      gettext(
        "Produkt jest teraz w przedsprzedaży w %{shops}. Porównamy ceny, gdy będzie w co najmniej %{minimum} sklepach.",
        shops: Format.in_shops(length(shops)),
        minimum: PriceGuide.min_shops()
      )

  defp today_missing(%{shop_prices: shops}),
    do:
      gettext(
        "Produkt jest teraz na stanie w %{shops}. Porównamy ceny, gdy będzie w co najmniej %{minimum} sklepach.",
        shops: Format.in_shops(length(shops)),
        minimum: PriceGuide.min_shops()
      )

  defp past_tone(:low), do: :good
  defp past_tone(:usual), do: :normal
  defp past_tone(:high), do: :expensive

  defp past_label(status) do
    days = PriceGuide.window_days()

    case status do
      :low -> gettext("Taniej niż w ostatnich %{days} dniach", days: days)
      :usual -> gettext("Tyle co w ostatnich %{days} dniach", days: days)
      :high -> gettext("Drożej niż w ostatnich %{days} dniach", days: days)
    end
  end

  defp reason(%{status: status, typical_source: :shops} = verdict, _past)
       when status in [:good, :normal, :expensive],
       do:
         gettext("Typowa cena dziś w %{shops}, bez dostawy: %{price}",
           shops: Format.in_shops(length(verdict.shop_prices)),
           price: Format.limit_price(verdict.typical)
         )

  # Shown as the Cardmarket price with its logo instead.
  defp reason(%{status: :cardmarket}, _past), do: nil

  defp reason(%{status: :insufficient_data} = verdict, _past) do
    today_missing(verdict) <>
      " " <>
      gettext("Cardmarket nie podaje ceny tego produktu, więc na razie go nie oceniamy.")
  end

  defp reason(%{status: :out_of_stock} = verdict, past) do
    [
      gettext("Teraz żaden sklep nie ma tego produktu na stanie."),
      last_known(past),
      usual(verdict, past)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # Buying is a pre-order: the shops ship on the premiere, the same day for all.
  defp preorder_note(nil, nil), do: gettext("To przedsprzedaż: sklep wyśle produkt po premierze.")

  defp preorder_note(premiere, days),
    do:
      gettext("Przedsprzedaż: premiera %{when} (%{date}), wtedy sklepy wyślą zamówienia.",
        when: Format.days_until(days),
        date: Format.day_month(premiere)
      )

  # Why the good limit is below the shops' one, when the history or
  # Cardmarket lowers it.
  defp good_bound(%{good_limits: %{shops: shops} = limits, good_max: good_max}, cardmarket) do
    if Decimal.compare(good_max, shops) == :lt do
      case Enum.find([:past, :cardmarket], &same_limit?(limits[&1], good_max)) do
        :past ->
          gettext("Dobra cena: do %{price}, bo w ostatnich %{days} dniach bywało taniej.",
            price: Format.limit_price(good_max),
            days: PriceGuide.window_days()
          )

        :cardmarket ->
          gettext(
            "Dobra cena: do %{price}, bo na Cardmarket z wysyłką wychodzi ok. %{cardmarket}.",
            price: Format.limit_price(good_max),
            cardmarket: Format.limit_price(cardmarket)
          )
      end
    end
  end

  defp good_bound(_verdict, _cardmarket), do: nil

  defp same_limit?(nil, _good_max), do: false
  defp same_limit?(limit, good_max), do: Decimal.compare(limit, good_max) == :eq

  defp last_known(%{last_known: %{price: price, date: date}}),
    do:
      gettext("Ostatnio najtaniej: %{price} (%{date}).",
        price: Format.price(price),
        date: Format.date(date)
      )

  defp last_known(_past), do: nil

  defp usual(_verdict, %{typical: %Decimal{} = typical}),
    do:
      gettext("Zwykle najtaniej %{price} w ostatnich %{days} dniach.",
        price: Format.limit_price(typical),
        days: PriceGuide.window_days()
      )

  defp usual(%{typical: %Decimal{} = typical, typical_source: :cardmarket}, _past),
    do: cardmarket_typical(typical)

  defp usual(_verdict, %{last_known: nil}), do: gettext("Nie znamy jeszcze jego ceny.")
  defp usual(_verdict, _past), do: nil

  defp cardmarket_typical(typical),
    do:
      gettext("Na Cardmarket %{price} (bez wysyłki).",
        price: Format.limit_price(typical)
      )
end
