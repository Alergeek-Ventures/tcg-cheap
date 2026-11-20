defmodule TcgCheap.Sealed.Market do
  @moduledoc """
  A country the buying guide prices sealed products for, in its currency:
  one per region (`TcgCheap.Countries.regions/0`). Poland is the original
  market; the others record their own daily prices.

  A shop takes part in a market when its home `country` is the market's
  and it sells there (`Shop.home_market`; domestic: its price counts without
  delivery, as Polish shops' always has)
  or it has a known delivery to the market's country (`Shop.deliveries`): its
  price then counts with that delivery, none from the free-delivery
  threshold. A shop whose delivery there has no known price is only listed,
  never compared. See `priced/3`.

  An offer's price in a market is what its shop charges a buyer there. A
  shop that prices the market's country apart (`price_currency` of its
  delivery there: another VAT, its own exchange rate) has that price read
  with every fetch (`market_prices` of the offer, by country), and it is
  taken as it is, converted only when the shop states it in another currency
  than the market's; an offer the shop does not sell to that country has no
  price there. Any other shop's own price (`shop_price`, in `currency`) is
  converted at the latest NBP rates, through PLN both ways. Poland keeps the
  offer's `price`, which a fetch stores in PLN by the same rule
  (`TcgCheap.Sealed.Refresh`). A rate a week older than its next publication means its job
  stopped: an amount that needs it has no price in the market rather than a
  silently wrong one.
  """

  alias TcgCheap.Countries
  alias TcgCheap.Pricing.ExchangeRate
  alias TcgCheap.Sealed.{Shop, Shops}

  @enforce_keys [
    :code,
    :country,
    :currency,
    :decimals,
    :cardmarket_letter_tiers,
    :cardmarket_shipping_eur
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          code: String.t(),
          country: String.t(),
          currency: String.t(),
          decimals: non_neg_integer(),
          cardmarket_letter_tiers: [TcgCheap.Cards.Reference.tier()],
          cardmarket_shipping_eur: Decimal.t()
        }

  @doc "Every region's market, Poland's first."
  @spec all() :: [t()]
  def all, do: Enum.map(Countries.regions(), &market/1)

  defp market(region),
    do: %__MODULE__{
      code: region.code,
      country: region.country,
      currency: region.currency,
      decimals: region.decimals,
      cardmarket_letter_tiers: region.cardmarket_letter_tiers,
      cardmarket_shipping_eur: region.cardmarket_shipping_eur
    }

  @spec poland() :: t()
  def poland, do: hd(all())

  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(code) do
    case Enum.find(all(), &(&1.code == code)) do
      nil -> :error
      market -> {:ok, market}
    end
  end

  @doc """
  The currencies whose NBP rate the guide needs, but the złoty: the euro
  for Cardmarket, every market's and every shop's prices and deliveries.
  """
  @spec currencies() :: [String.t()]
  def currencies do
    shops =
      Enum.flat_map(Shops.all(), fn shop ->
        [shop.currency | Enum.map(Map.values(shop.deliveries), & &1.currency)]
      end)

    (["EUR" | Enum.map(all(), & &1.currency)] ++ shops)
    |> Enum.uniq()
    |> List.delete("PLN")
    |> Enum.sort()
  end

  @typedoc """
  How a shop takes part in a market: at its own price, with a known
  delivery, only listed (its delivery price is unknown), or not at all.
  """
  @type terms :: :domestic | {:delivered, Shop.delivery()} | :listed | :absent

  @doc "How a shop (`Shops.fetch/1`'s result) takes part in the market."
  @spec terms({:ok, Shop.t()} | :error, t()) :: terms()
  def terms({:ok, %Shop{country: country, home_market: true}}, %__MODULE__{country: country}),
    do: :domestic

  def terms({:ok, %Shop{deliveries: deliveries}}, %__MODULE__{country: country}) do
    case deliveries do
      %{^country => %{shipping_from: %Decimal{}} = delivery} -> {:delivered, delivery}
      %{^country => _unknown_price} -> :listed
      _none -> :absent
    end
  end

  # A shop no longer configured has only Polish offers left.
  def terms(:error, %__MODULE__{code: "pl"}), do: :domestic
  def terms(:error, _market), do: :absent

  @doc "Whether the shop's offers are priced as the market's own, without delivery (`terms/2`)."
  @spec domestic?(String.t(), t()) :: boolean()
  def domestic?(shop_key, %__MODULE__{} = market),
    do: terms(Shops.fetch(shop_key), market) == :domestic

  @typedoc """
  An offer as `priced/3` reads it; a market abroad also needs its shop's own
  price and its prices by country.
  """
  @type offer :: %{
          required(:shop) => String.t(),
          required(:price) => Decimal.t(),
          optional(:shop_price) => Decimal.t() | nil,
          optional(:currency) => String.t() | nil,
          optional(:market_prices) => %{String.t() => map()} | nil,
          optional(atom()) => term()
        }

  @doc """
  The offers of the shops taking part in the market, in their order, each
  as `{offer, item price, compared price}` in the market's currency: the
  compared price includes delivery for a shop abroad and is nil for a shop
  only listed there. An offer without a price in the market (no shop price
  yet, not sold to its country by a shop that prices it apart, or no recent
  rate for a currency it needs) is left out.
  """
  @spec priced([offer], t(), Date.t()) :: [{offer, Decimal.t(), Decimal.t() | nil}]
        when offer: offer()
  def priced(offers, %__MODULE__{} = market, %Date{} = today) do
    terms = shop_terms(offers, market)
    apart = priced_apart(terms, market)
    rates = rates(offers, {terms, apart}, market, today)

    for offer <- offers,
        shop_terms = Map.fetch!(terms, offer.shop),
        shop_terms != :absent,
        {:ok, item} <- [item_price(offer, market, apart, rates)],
        do: {offer, item, compared(item, shop_terms, market, rates)}
  end

  @doc """
  The offers that count in the market's prices (verdicts, lowest prices,
  history), each `price` its compared price in the market's currency and
  `item_price` the product alone, without delivery (see `compared_offer/3`).
  """
  @spec compared([offer], t(), Date.t()) :: [offer] when offer: offer()
  def compared(offers, market, today) do
    for {offer, item, %Decimal{} = compared} <- priced(offers, market, today),
        do: compared_offer(offer, item, compared)
  end

  @typedoc """
  How `price_terms/2` prices a shop's offers: the item price (`:price`, the
  offer's stored PLN price, for Poland; `:shop_price`, the shop's own price,
  already in the market's currency; `{:shop_price, from_pln, to_pln}`, the
  shop's own price converted at these PLN rates and rounded as the market's
  currency is; `{:market_price, apart, shops_own}`, for a shop that prices
  the market's country apart, how the offer's `market_prices` for it become
  the market's currency and, for an offer without `market_prices` yet, how
  its `shop_price` does, each as the two above or nil when its rate is
  missing) and its delivery to the market, `{shipping, free from}` in the
  market's currency, nil for a domestic shop.
  """
  @type item_terms :: :shop_price | {:shop_price, Decimal.t(), Decimal.t()}
  @type price_terms ::
          {:price
           | item_terms()
           | {:market_price, item_terms() | nil, item_terms() | nil},
           {Decimal.t(), Decimal.t() | nil} | nil}

  @doc """
  `compared/3`'s terms for every configured shop whose offers count in the
  market, by key, for a query that prices many offers in the database
  (`TcgCheap.Cards.Guide`). Offers there carry no prices by country, so a
  shop abroad counts at its own price, converted, as `compared/3` prices an
  offer without `market_prices`. A shop only listed or absent there, or
  needing a rate that is missing or too old, is left out, as `compared/3`
  leaves its offers out. A shop that prices the market's country apart has
  its offers' `market_prices` for it read in the query as `compared/3` does
  (`shop_price/3`).
  """
  @spec price_terms(t(), Date.t()) :: %{String.t() => price_terms()}
  def price_terms(%__MODULE__{} = market, %Date{} = today) do
    terms =
      for shop <- Shops.all(),
          shop_terms = terms({:ok, shop}, market),
          shop_terms == :domestic or match?({:delivered, _delivery}, shop_terms),
          do: {shop, shop_terms}

    currencies =
      Enum.flat_map(terms, fn
        {shop, {:delivered, delivery}} ->
          [shop.currency, delivery.currency, apart_currency(shop, market)]

        {shop, :domestic} ->
          [shop.currency, apart_currency(shop, market)]
      end)
      |> Enum.reject(&is_nil/1)

    rates =
      if market.code == "pl",
        do: %{},
        else: Map.new(Enum.uniq([market.currency | currencies]), &{&1, pln_rate(&1, today)})

    for {shop, shop_terms} <- terms,
        {:ok, item} <- [item_terms(shop, market, rates)],
        {:ok, delivery} <- [delivery_terms(shop_terms, market, rates)],
        into: %{},
        do: {shop.key, {item, delivery}}
  end

  # Poland's price is the offer's `price`, stored in PLN.
  defp item_terms(_shop, %__MODULE__{code: "pl"}, _rates), do: {:ok, :price}

  defp item_terms(shop, market, rates) do
    shops_own = currency_terms(shop.currency, market, rates)

    case apart_currency(shop, market) do
      nil ->
        if shops_own, do: {:ok, shops_own}, else: :error

      currency ->
        apart = currency_terms(currency, market, rates)
        if apart || shops_own, do: {:ok, {:market_price, apart, shops_own}}, else: :error
    end
  end

  # How a price in the currency becomes one in the market's: as it is in the
  # market's own currency, else converted; nil when a rate is missing.
  defp currency_terms(currency, %{currency: currency}, _rates), do: :shop_price

  defp currency_terms(currency, market, rates) do
    with {:ok, %{rate: from_pln}} <- Map.fetch!(rates, currency),
         {:ok, %{rate: to_pln}} <- Map.fetch!(rates, market.currency) do
      {:shop_price, from_pln, to_pln}
    else
      {:error, _reason} -> nil
    end
  end

  # The currency a shop states the market's country's prices in, when it
  # prices that country apart.
  defp apart_currency(shop, market), do: Shops.price_currencies(shop)[market.country]

  defp delivery_terms(:domestic, _market, _rates), do: {:ok, nil}

  defp delivery_terms({:delivered, delivery}, market, rates) do
    with {:ok, shipping} <- convert(delivery.shipping_from, delivery.currency, market, rates),
         {:ok, free_from} <-
           convert(delivery.free_shipping_from, delivery.currency, market, rates),
         do: {:ok, {shipping, free_from}}
  end

  @doc """
  An offer as the market compares it: `price` is its compared price,
  `item_price` its item price. `PriceGuide.verdict/4` takes the typical price
  from the item prices and rates the cheapest offer at the compared one.
  """
  @spec compared_offer(offer, Decimal.t(), Decimal.t()) :: offer when offer: offer()
  def compared_offer(offer, item, compared),
    do: offer |> Map.put(:item_price, item) |> Map.put(:price, compared)

  @doc """
  The order value from which a shop's delivery to the market is free, in the
  market's currency; nil when it has none there or it cannot be converted.
  """
  @spec free_delivery_from(terms(), t(), Date.t()) :: Decimal.t() | nil
  def free_delivery_from(
        {:delivered, %{free_shipping_from: %Decimal{} = from} = delivery},
        market,
        today
      ) do
    rates = Map.new([delivery.currency, market.currency], &{&1, pln_rate(&1, today)})

    case convert(from, delivery.currency, market, rates) do
      {:ok, converted} -> converted
      :error -> nil
    end
  end

  def free_delivery_from(_terms, _market, _today), do: nil

  @doc """
  A shop's delivery to the market in the market's currency, as the shop's
  terms give it (`terms/2`): `%{shipping_from: cheapest delivery,
  free_shipping_from: order value from which it is free or nil}`. Nil for a
  shop that is not delivering or whose delivery cannot be converted.
  """
  @spec delivery_cost(terms(), t(), Date.t()) ::
          %{shipping_from: Decimal.t(), free_shipping_from: Decimal.t() | nil} | nil
  def delivery_cost({:delivered, delivery}, market, today) do
    rates = Map.new([delivery.currency, market.currency], &{&1, pln_rate(&1, today)})

    with {:ok, shipping} <- convert(delivery.shipping_from, delivery.currency, market, rates),
         {:ok, free_from} <-
           convert(delivery.free_shipping_from, delivery.currency, market, rates) do
      %{shipping_from: shipping, free_shipping_from: free_from}
    else
      :error -> nil
    end
  end

  def delivery_cost(_terms, _market, _today), do: nil

  @doc """
  The rates `compared/3` needs for these offers that are missing or too old,
  as `{currency, reason}`; empty when every offer can be priced.
  """
  @spec missing_rates([offer()], t(), Date.t()) :: [{String.t(), term()}]
  def missing_rates(offers, market, today) do
    terms = shop_terms(offers, market)
    rates = rates(offers, {terms, priced_apart(terms, market)}, market, today)
    for {currency, {:error, reason}} <- rates, do: {currency, reason}
  end

  @doc """
  The PLN value of one unit of the currency at the latest NBP rate on or
  before `today`, with the rate's date; refused when that rate is too old:
  over 7 days for NBP's daily table A, over 14 for its weekly table B
  (`ExchangeRate.table/1`), a week after its next publication.
  """
  @spec pln_rate(String.t(), Date.t()) ::
          {:ok, %{rate: Decimal.t(), date: Date.t()}}
          | {:error,
             {:no_exchange_rate, String.t()} | {:stale_exchange_rate, String.t(), Date.t()}}
  def pln_rate("PLN", today), do: {:ok, %{rate: Decimal.new(1), date: today}}

  def pln_rate(currency, %Date{} = today) do
    case TcgCheap.Pricing.get_latest_exchange_rate(today, currency) do
      {:ok, %{rate: rate, effective_date: date}} ->
        if Date.diff(today, date) <= max_rate_age_days(currency),
          do: {:ok, %{rate: rate, date: date}},
          else: {:error, {:stale_exchange_rate, currency, date}}

      _missing ->
        {:error, {:no_exchange_rate, currency}}
    end
  end

  # NBP skips weekends and holidays.
  defp max_rate_age_days(currency),
    do: if(ExchangeRate.table(currency) == "A", do: 7, else: 14)

  @doc "The latest stored NBP EUR/PLN mid rate on or before `date`, if any."
  @spec eur_pln(Date.t()) :: %{rate: Decimal.t(), date: Date.t()} | nil
  def eur_pln(%Date{} = date) do
    case TcgCheap.Pricing.get_latest_exchange_rate(date) do
      {:ok, %{rate: rate, effective_date: effective}} -> %{rate: rate, date: effective}
      _ -> nil
    end
  end

  @doc "A Cardmarket EUR amount in PLN at the given rate."
  @spec to_pln(Decimal.t() | nil, map() | nil) :: Decimal.t() | nil
  def to_pln(eur, rate), do: in_market(eur, rate, poland())

  @doc """
  The euro's rate in the market's currency on `today` (`eur_pln/1` for
  Poland, 1 for a market in euro), nil when unknown. Elsewhere it goes
  through PLN, at NBP rates no older than a week (`pln_rate/2`), and
  is as old as the older one.
  """
  @spec cardmarket_rate(t(), Date.t()) :: %{rate: Decimal.t(), date: Date.t()} | nil
  def cardmarket_rate(%__MODULE__{currency: "EUR"}, %Date{} = today),
    do: %{rate: Decimal.new(1), date: today}

  def cardmarket_rate(%__MODULE__{} = market, %Date{} = today) do
    if market == poland() do
      eur_pln(today)
    else
      with {:ok, eur} <- pln_rate("EUR", today),
           {:ok, local} <- pln_rate(market.currency, today) do
        %{rate: Decimal.div(eur.rate, local.rate), date: Enum.min([eur.date, local.date], Date)}
      else
        {:error, _reason} -> nil
      end
    end
  end

  @doc "A Cardmarket EUR amount in the market's currency at its `cardmarket_rate/2`."
  @spec in_market(Decimal.t() | nil, map() | nil, t()) :: Decimal.t() | nil
  def in_market(%Decimal{} = eur, %{rate: rate}, market),
    do: eur |> Decimal.mult(rate) |> rounded(market)

  def in_market(_eur, _rate, _market), do: nil

  @doc """
  An amount rounded as the market's currency is: whole forints, złoty to
  grosze. Below one whole unit a whole-unit currency keeps its hundredths
  ("0,30 Kč", not "0 Kč"; 0,996 is 1 Kč), as `TcgCheapWeb.Format.price/1`
  writes it.
  """
  @spec rounded(Decimal.t(), t()) :: Decimal.t()
  def rounded(amount, %__MODULE__{decimals: 0}) do
    hundredths = Decimal.round(amount, 2)

    if Decimal.positive?(hundredths) and Decimal.lt?(hundredths, 1),
      do: hundredths,
      else: Decimal.round(amount, 0)
  end

  def rounded(amount, %__MODULE__{decimals: decimals}), do: Decimal.round(amount, decimals)

  @doc """
  A threshold set in złoty, in the market's currency at the latest NBP rate
  (`pln_rate/2`), rounded down to the step of its verdict limits
  (`limit_step/1`); nil when that rate is unknown. Poland's is the amount
  itself.
  """
  @spec pln_limit(Decimal.t(), t(), Date.t()) :: Decimal.t() | nil
  def pln_limit(%Decimal{} = pln, %__MODULE__{} = market, %Date{} = today) do
    case pln_rate(market.currency, today) do
      {:ok, %{rate: rate}} ->
        step = limit_step(market)

        pln
        |> Decimal.div(rate)
        |> Decimal.div(step)
        |> Decimal.round(0, :floor)
        |> Decimal.mult(step)

      {:error, _reason} ->
        nil
    end
  end

  @doc "The step of a market's verdict limits: 0.10 euro, else a whole currency unit."
  @spec limit_step(t()) :: Decimal.t() | 1
  def limit_step(%__MODULE__{currency: "EUR"}), do: Decimal.new("0.1")
  def limit_step(%__MODULE__{}), do: 1

  # Each shop is looked up once, not once per offer: the singles banner
  # prices every card offer in stock.
  defp shop_terms(offers, market) do
    offers
    |> Enum.map(& &1.shop)
    |> Enum.uniq()
    |> Map.new(&{&1, terms(Shops.fetch(&1), market)})
  end

  # The rates of every currency the offers' prices and deliveries are in,
  # besides the market's own; none for Polish prices with deliveries in PLN.
  defp rates(offers, {terms, apart}, market, today) do
    item_currencies =
      if market.code == "pl" do
        []
      else
        for offer <- offers,
            terms[offer.shop] != :absent,
            {_price, currency} <- [shop_price(offer, market, apart)],
            do: currency
      end

    delivery_currencies =
      for {_shop, {:delivered, delivery}} <- terms, do: delivery.currency

    currencies = Enum.uniq(item_currencies ++ delivery_currencies) -- [market.currency, nil]

    # Converting into the market's currency needs its own rate too.
    currencies = if currencies == [], do: [], else: [market.currency | currencies]

    Map.new(Enum.uniq(currencies), &{&1, pln_rate(&1, today)})
  end

  # The shops among `terms` that price the market's country apart.
  defp priced_apart(terms, %__MODULE__{country: country}) do
    for {key, shop_terms} <- terms,
        shop_terms != :absent,
        {:ok, %Shop{deliveries: %{^country => %{price_currency: _currency}}}} <-
          [Shops.fetch(key)],
        into: MapSet.new(),
        do: key
  end

  # Poland's price is the offer's `price`, stored in PLN by the same rule.
  defp item_price(offer, %__MODULE__{code: "pl"} = market, apart, _rates) do
    if shop_price(offer, market, apart), do: {:ok, offer.price}, else: :error
  end

  defp item_price(offer, market, apart, rates) do
    case shop_price(offer, market, apart) do
      {price, currency} -> convert(price, currency, market, rates)
      nil -> :error
    end
  end

  # What the shop charges a buyer in the market and in which currency, before
  # any conversion; nil when it has no price there. An offer last stored
  # before its shop's prices were read by country (no `market_prices` at all)
  # keeps the shop's own price until its next fetch.
  defp shop_price(offer, %__MODULE__{country: country}, apart) do
    case {MapSet.member?(apart, offer.shop), Map.get(offer, :market_prices)} do
      {true, %{^country => %{"price" => price, "currency" => currency}}} ->
        {Decimal.new(price), currency}

      {true, %{}} ->
        nil

      # Polish prices are also read from offers that carry only `price`.
      {_shops_own, _prices} when country == "PL" ->
        {offer.price, "PLN"}

      {_shops_own, _prices} ->
        offer.shop_price && {offer.shop_price, offer.currency}
    end
  end

  defp compared(item, :domestic, _market, _rates), do: item
  defp compared(_item, :listed, _market, _rates), do: nil

  defp compared(item, {:delivered, delivery}, market, rates) do
    with {:ok, shipping} <- convert(delivery.shipping_from, delivery.currency, market, rates),
         {:ok, free_from} <-
           convert(delivery.free_shipping_from, delivery.currency, market, rates) do
      if free_from && not Decimal.lt?(item, free_from),
        do: item,
        else: Decimal.add(item, shipping)
    else
      # A delivery that cannot be priced leaves the shop only listed.
      :error -> nil
    end
  end

  defp convert(nil, _from, _market, _rates), do: {:ok, nil}
  defp convert(amount, currency, %{currency: currency}, _rates), do: {:ok, amount}

  defp convert(amount, from, market, rates) do
    with {:ok, %{rate: from_pln}} <- Map.fetch!(rates, from),
         {:ok, %{rate: to_pln}} <- Map.fetch!(rates, market.currency) do
      {:ok, amount |> Decimal.mult(from_pln) |> Decimal.div(to_pln) |> rounded(market)}
    else
      {:error, _reason} -> :error
    end
  end
end
