defmodule TcgCheapWeb.OfferComponents do
  @moduledoc "A product's offers: the shop rows, their delivery terms and the wording of where a compared price ships from."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Countries
  alias TcgCheap.Sealed.{Market, Shop, Shops}
  alias TcgCheap.Sealed.ShopFeed.Shopify
  alias TcgCheapWeb.{Format, Region, VisitorLocation}

  @spec shop_name(map()) :: String.t()
  def shop_name(%{shop: shop}), do: Shops.name(shop)

  @doc """
  The shop of a compared price (`Shops.compared/1`), saying when the price
  includes delivery from abroad: "Bangerpack, z wysyłką ze Szwecji".
  """
  @spec priced_shop_name(map()) :: String.t()
  def priced_shop_name(offer) do
    case delivered_term(offer) do
      nil -> shop_name(offer)
      term -> shop_name(offer) <> ", " <> term
    end
  end

  @doc """
  The shop of a card's price. Where the card has no shop at home (an offer's
  `abroad_only?`, see `Guide.for_card/2`) the price is the shop's item price
  and the shop's name says so ("Chasedex, bez dostawy");
  elsewhere `priced_shop_name/1`.
  """
  @spec card_shop_name(map()) :: String.t()
  def card_shop_name(offer) do
    case card_shop_note(offer) do
      nil -> shop_name(offer)
      note -> shop_name(offer) <> ", " <> note
    end
  end

  @doc "What `card_shop_name/1` adds to the shop's name, nil for none."
  @spec card_shop_note(map()) :: String.t() | nil
  def card_shop_note(offer) do
    if item_price?(offer), do: gettext("bez dostawy"), else: delivered_term(offer)
  end

  # Whether a card's price is the item price of a shop abroad, its delivery
  # stated beside it: the card has no shop at home (`Guide.for_card/2`). An
  # offer not read with its card's others goes by the market's rule.
  defp item_price?(%{shop: key} = offer) do
    market = Region.current().market

    with true <- Map.get(offer, :abroad_only?, !Shops.own_singles?(market)),
         {:ok, shop} <- Shops.fetch(key),
         {:delivered, _delivery} <- Market.terms({:ok, shop}, market) do
      true
    else
      _own_or_included -> false
    end
  end

  @doc """
  "z wysyłką ze Szwecji" for a compared price from a shop abroad (its
  delivery is known), else nil.
  """
  @spec delivered_term(map()) :: String.t() | nil
  def delivered_term(%{shop: key}) do
    market = Region.current().market
    shop = Shops.fetch(key)

    case {shop, Market.terms(shop, market)} do
      {{:ok, %{country: country}}, {:delivered, _delivery}} ->
        country |> delivered_from() |> glue_short_words()

      _domestic_or_listed ->
        nil
    end
  end

  # Where a shop ships from, in its country's words (`TcgCheap.Country`).
  defp delivered_from(country), do: Countries.fetch!(country).delivered_from()

  @doc """
  Binds one- and two-letter prepositions ("z", "ze", "w", "we") to the next
  word with a no-break space, so a line never ends with one, and a dash to
  the word before it, so a line never starts with one.
  """
  @spec glue_short_words(String.t() | nil) :: String.t() | nil
  def glue_short_words(nil), do: nil

  def glue_short_words(text) do
    text
    |> then(&Regex.replace(~r/(?<![\p{L}\p{N}])([zwZW]|[zwZW]e) /u, &1, "\\1\u00A0"))
    |> String.replace(" –", "\u00A0–")
  end

  @doc """
  The link to an offer for a buyer in the region's country. A Shopify shop
  shows the prices, currency and delivery of the country its link names
  (`?country=SE`), so the link to a shop abroad names the region's; other
  shops' links stay as they were read.
  """
  @spec offer_url(map()) :: String.t()
  def offer_url(%{shop: key, url: url}) do
    country = Region.current().market.country

    case Shops.fetch(key) do
      {:ok, %Shop{source: Shopify, country: home}} when home != country ->
        url |> URI.parse() |> URI.append_query("country=" <> country) |> URI.to_string()

      _other ->
        url
    end
  end

  @doc "The shop's logo chip, when it has a logo."
  attr :shop, :string, required: true

  def shop_logo(assigns) do
    ~H"""
    <img
      :if={Shops.logo?(@shop)}
      src={~p"/images/shops/#{@shop <> ".webp"}"}
      alt=""
      width="96"
      height="32"
      loading="lazy"
      class="shop-logo"
    />
    """
  end

  attr :id, :string, required: true
  attr :count, :integer, required: true

  def offers_heading(assigns) do
    ~H"""
    <div class="product-section-heading">
      <h2 id={@id}>{gettext("Oferty w sklepach")}</h2>
      <p :if={@count > 0}>
        {gettext("%{offers} na stanie", offers: Format.offers(@count))}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  attr :open, :boolean, default: false

  def offers_disclosure(assigns) do
    ~H"""
    <details id={@id} class="verdict-method offers-out" open={@open}>
      <summary data-track="product_section_opened" data-track-section="out_of_stock_offers">
        {@label}<.fluent_icon name={:chevron_down} class="verdict-method-chevron" />
      </summary>
      {render_slot(@inner_block)}
    </details>
    """
  end

  attr :id, :string, required: true
  attr :offer, :map, required: true
  attr :location, :map, default: nil
  attr :today, Date, required: true
  attr :tags, :list, default: []

  attr :delivery_beside?, :boolean,
    default: false,
    doc:
      "the price is the item price and the row states the shop's delivery beside it (a card where no singles shop is at home), not as included in it"

  attr :compared, :any,
    default: :polish,
    doc:
      "the offer's compared price in the region's market (`TcgCheap.Sealed.ProductPage.read/3`'s `compared`), nil when its shop is only listed; Polish by default"

  # One shop's offer. In stock is the default, so a row only says when it is
  # not (or that it is a pre-order), and when it was checked if that was not
  # today.
  def offer(assigns) do
    assigns =
      assigns
      |> assign(:checked_on, DateTime.to_date(assigns.offer.last_seen_at))
      |> assign(:compared, compared_price(assigns.compared, assigns.offer))
      |> then(&assign(&1, :price, &1.compared || &1.offer.price))

    ~H"""
    <li
      id={@id}
      class={["offer", !@offer.in_stock && !Map.get(@offer, :preorder, false) && "offer-unavailable"]}
    >
      <.shop_logo shop={@offer.shop} />
      <div class="offer-shop">
        <strong>{shop_name(@offer)}</strong>
        <span :if={@tags != []} class="offer-delivery single-offer-tags">{Enum.join(@tags, " · ")}</span>
        <.offer_delivery
          offer={@offer}
          compared={@compared}
          location={@location}
          beside?={@delivery_beside?}
        />
      </div>
      <p class="offer-price">
        <span :if={Map.get(@offer, :preorder, false)} class="offer-preorder-label">{gettext(
          "przedsprzedaż"
        )}</span>
        <strong>{Format.price(@price)}</strong>
        <span
          :if={(!@offer.in_stock and !Map.get(@offer, :preorder, false)) or @checked_on != @today}
          class="offer-checked"
        >
          {offer_note(@offer.in_stock or Map.get(@offer, :preorder, false), @checked_on, @today)}
        </span>
      </p>
      <a
        href={offer_url(@offer)}
        target="_blank"
        rel="noopener nofollow"
        class="offer-link"
        data-track="shop_link_clicked"
        data-track-placement="offers"
        data-track-shop={@offer.shop}
        data-track-price={@price}
        data-track-in-stock={to_string(@offer.in_stock)}
        data-track-preorder={to_string(Map.get(@offer, :preorder, false))}
        data-track-card={Map.get(@offer, :card_id)}
        aria-label={
          gettext("%{shop}: przejdź do sklepu (otwiera się w nowej karcie)", shop: shop_name(@offer))
        }
      >{gettext("Do sklepu")}</a>
    </li>
    """
  end

  defp compared_price(:polish, offer), do: Shops.compared_price(offer.shop, offer.price)
  defp compared_price(compared, _offer), do: compared

  defp offer_note(true, checked_on, today),
    do: gettext("sprawdzono %{when}", when: Format.days_ago(checked_on, today))

  defp offer_note(false, today, today), do: gettext("brak na stanie")

  defp offer_note(false, checked_on, today),
    do: gettext("brak na stanie, sprawdzono %{when}", when: Format.days_ago(checked_on, today))

  attr :offer, :map, required: true
  attr :compared, :any, default: nil, doc: "the offer's compared price, nil when only listed"
  attr :location, :map, default: nil
  attr :beside?, :boolean, default: false, doc: "see `offer/1`'s `delivery_beside?`"

  # What delivery adds to an offer, from the shop's published terms:
  # "dostawa od 14,99 zł · darmowa od 400 zł · odbiór osobisty: Kraków (491 km)".
  # Pickup within the radius stands out on a line of its own.
  def offer_delivery(assigns) do
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
        terms:
          if(shop,
            do:
              delivery_terms(
                shop,
                assigns.offer.price,
                assigns.compared,
                km,
                near?,
                assigns.beside?
              ),
            else: []
          )
      )

    # A no-break space keeps each "·" at the end of a line, never at the start.
    ~H"""
    <span :if={@terms != []} class="offer-delivery">{@terms
    |> Enum.join("\u00A0· ")
    |> glue_short_words()}</span>
    <span :if={@near?} class="offer-pickup-near">
      <.fluent_icon name={:location} />{gettext("odbiór: %{city}, %{distance}",
        city: @shop.pickup_city,
        distance: VisitorLocation.km(@km)
      )}
    </span>
    """
  end

  # Poland's terms come from the shops' published delivery to Poland; another
  # market's from how its prices were compared (`Market.terms/2`).
  defp delivery_terms(shop, price, compared, km, near?, beside?) do
    market = Region.current().market

    cond do
      beside? ->
        beside_delivery_terms(Market.terms({:ok, shop}, market), shop, price, km, near?)

      market == Market.poland() ->
        polish_delivery_terms(shop, price, km, near?)

      true ->
        market_delivery_terms(Market.terms({:ok, shop}, market), shop, price, compared, km, near?)
    end
  end

  # A card's price has no delivery in it: state the shop's delivery to the
  # market as a domestic shop's row does.
  defp beside_delivery_terms({:delivered, _delivery} = terms, shop, price, km, near?) do
    market = Region.current().market

    case Market.delivery_cost(terms, market, Date.utc_today()) do
      nil -> market_delivery_terms(:listed, shop, price, nil, km, near?)
      delivery -> abroad_card_terms(delivery, shop, price)
    end
  end

  defp beside_delivery_terms(terms, shop, price, km, near?),
    do: market_delivery_terms(terms, shop, price, nil, km, near?)

  # Where the parcel ships from and what its delivery costs; a pickup store
  # abroad is of no use to the buyer.
  defp abroad_card_terms(delivery, shop, price \\ Decimal.new(0)) do
    domestic_delivery_terms(
      delivery,
      origin_term(shop.country),
      price,
      nil,
      false,
      %{shop | pickup_city: nil}
    )
  end

  @doc """
  The line above a card list where no singles shop is at home: the prices are
  without delivery, and what delivery costs (the shop's when the list's offers
  are one shop's, else the cheapest), the list's offers being from `shop_keys`. Nil where the prices have delivery in them.
  """
  @spec cards_delivery_note([String.t()]) :: String.t() | nil
  def cards_delivery_note(shop_keys) do
    market = Region.current().market

    if not Shops.own_singles?(market) and Shops.singles?(market) do
      shops = for key <- shop_keys, {:ok, shop} <- [Shops.fetch(key)], do: shop
      Enum.join([gettext("Ceny bez dostawy.") | shops_delivery(shops, market)], " ")
    end
  end

  defp shops_delivery([], _market), do: []

  defp shops_delivery([shop], market) do
    case shop_delivery(shop, market) do
      nil ->
        [Shops.name(shop.key)]

      delivery ->
        ["#{Shops.name(shop.key)}: #{Enum.join(abroad_card_terms(delivery, shop), " · ")}"]
    end
  end

  defp shops_delivery(shops, market) do
    case for(shop <- shops, delivery = shop_delivery(shop, market), do: delivery.shipping_from) do
      [] ->
        []

      costs ->
        [gettext("Dostawa od %{amount}.", amount: Format.shop_price(Enum.min(costs, Decimal)))]
    end
  end

  defp shop_delivery(shop, market),
    do: Market.delivery_cost(Market.terms({:ok, shop}, market), market, Date.utc_today())

  @doc """
  The delivery tile of a set's banner where one shop sells the set's cards and
  no singles shop is at home: `{cheapest delivery, where it ships from and
  from when it is free}`. Nil otherwise or when the delivery is not known.
  """
  @spec delivery_tile(String.t()) :: {String.t(), String.t()} | nil
  def delivery_tile(key) do
    market = Region.current().market

    with false <- Shops.own_singles?(market),
         {:ok, shop} <- Shops.fetch(key),
         %{} = delivery <- shop_delivery(shop, market) do
      free =
        delivery.free_shipping_from &&
          gettext("darmowa od %{amount}", amount: Format.shop_price(delivery.free_shipping_from))

      caption =
        Enum.join(
          Enum.filter([gettext("dostawa"), origin_term(shop.country), free], &is_binary/1),
          " · "
        )

      {Format.shop_price(delivery.shipping_from), caption}
    else
      _own_or_unknown -> nil
    end
  end

  @doc """
  What a shop abroad's delivery to the market comes to, for a card offer's
  row, Markdown and the line under the card's price: where it ships from,
  the cheapest delivery and the order value from which it is free. Empty
  where the price has delivery in it.
  """
  @spec card_delivery_terms(map()) :: [String.t()]
  def card_delivery_terms(%{shop: key} = offer) do
    market = Region.current().market

    with true <- item_price?(offer),
         {:ok, shop} <- Shops.fetch(key),
         %{} = delivery <- shop_delivery(shop, market) do
      abroad_card_terms(delivery, shop, offer.price)
    else
      _included_or_unknown -> []
    end
  end

  @doc "The line under a card's price: `card_delivery_terms/1` joined, nil for none."
  @spec card_delivery_line(map()) :: String.t() | nil
  def card_delivery_line(offer) do
    case card_delivery_terms(offer) do
      [] -> nil
      terms -> Enum.join(terms, " · ")
    end
  end

  # Delivered from abroad: the row's price includes it; say how much.
  defp market_delivery_terms(
         {:delivered, _delivery},
         shop,
         price,
         %Decimal{} = compared,
         _km,
         _near?
       ) do
    market = Region.current().market

    included =
      case Decimal.sub(compared, price) do
        %Decimal{coef: 0} ->
          [gettext("w tym darmowa dostawa")]

        shipping ->
          threshold =
            Market.free_delivery_from(Market.terms({:ok, shop}, market), market, Date.utc_today())

          [
            gettext("w tym dostawa %{amount}", amount: Format.shop_price(shipping)),
            threshold && free_from_term(threshold)
          ]
      end

    Enum.filter([origin_term(shop.country) | included], &is_binary/1)
  end

  defp market_delivery_terms(:domestic, shop, price, _compared, km, near?),
    do: domestic_delivery_terms(shop, nil, price, km, near?, shop)

  # Only listed: its delivery here has no known price.
  defp market_delivery_terms(_listed, shop, _price, _compared, _km, _near?),
    do: [origin_term(shop.country), gettext("koszt dostawy w koszyku")]

  defp origin_term(country), do: Countries.fetch!(country).shipped_from()

  # A shop abroad's row shows its price with delivery: say what that includes.
  defp polish_delivery_terms(
         %{country: country, deliveries: %{"PL" => %{shipping_from: %Decimal{}} = delivery}},
         price,
         _km,
         _near?
       )
       when country != "PL" do
    included =
      case shipping(delivery, price) do
        :free ->
          [gettext("w tym darmowa dostawa")]

        {:from, from} ->
          [
            gettext("w tym dostawa %{amount}", amount: Format.shop_price(from)),
            delivery.free_shipping_from && free_from_term(delivery.free_shipping_from)
          ]
      end

    Enum.filter([abroad_term(country) | included], &is_binary/1)
  end

  defp polish_delivery_terms(shop, price, km, near?),
    do:
      domestic_delivery_terms(to_poland(shop), abroad_term(shop.country), price, km, near?, shop)

  # The order value from which delivery to the buyer's country is free: it
  # tells whether adding to the basket there pays off.
  defp free_from_term(threshold),
    do: gettext("darmowa od %{amount}", amount: Format.shop_price(threshold))

  # The shop's own delivery terms (a shop abroad only listed: none known).
  defp domestic_delivery_terms(delivery, origin, price, km, near?, shop) do
    threshold = delivery.free_shipping_from
    shipping = shipping(delivery, price)

    # The threshold stays visible: shops often grant it for some carriers only.
    cost =
      case shipping do
        :free -> gettext("darmowa dostawa od %{amount}", amount: Format.shop_price(threshold))
        {:from, from} -> gettext("dostawa od %{amount}", amount: Format.shop_price(from))
        :unknown -> gettext("koszt dostawy w koszyku")
      end

    [
      origin,
      cost,
      threshold && shipping != :free &&
        gettext("darmowa od %{amount}", amount: Format.shop_price(threshold)),
      pickup_term(shop.pickup_city, km, near?)
    ]
    |> Enum.filter(&is_binary/1)
  end

  # A Polish shop's own delivery, or a shop abroad's to Poland (none known
  # when it has no entry).
  defp to_poland(%{country: "PL"} = shop), do: shop

  defp to_poland(shop),
    do: Map.get(shop.deliveries, "PL", %{shipping_from: nil, free_shipping_from: nil})

  # Shops abroad (`Shop.country`): their prices are converted to złoty.
  defp abroad_term("PL"), do: nil
  defp abroad_term(country), do: origin_term(country)

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

  @doc """
  What a Polish shop's delivery costs at this price: `:free` from its
  free-delivery threshold, `{:from, amount}` for its cheapest delivery, else `:unknown`.
  """
  @spec shipping(map(), Decimal.t()) :: :free | {:from, Decimal.t()} | :unknown
  def shipping(shop, price) do
    threshold = shop.free_shipping_from

    cond do
      threshold != nil and not Decimal.lt?(price, threshold) -> :free
      shop.shipping_from -> {:from, shop.shipping_from}
      true -> :unknown
    end
  end

  attr :id, :string, default: "offer-disclaimer"

  def offer_disclaimer(assigns) do
    ~H"""
    <p id={@id} class="guide-note offer-disclaimer">
      <.fluent_icon name={:shield_error} />
      {gettext(
        "Jesteśmy niezależnym agregatorem: nie sprzedajemy produktów i nie weryfikujemy sklepów. Zanim zapłacisz, sprawdź sklep – opinie, dane firmy i regulamin."
      )}
    </p>
    """
  end
end
