defmodule TcgCheap.Sealed.Market do
  @moduledoc """
  A country the buying guide prices sealed products for, in its currency:
  Poland, the original market, and Hungary, the first one abroad (a pilot
  without pages yet).

  A shop takes part in a market when its home `country` is the market's
  (domestic: its price counts without delivery, as Polish shops' always has)
  or it has a known delivery to the market's country (`Shop.deliveries`): its
  price then counts with that delivery, none from the free-delivery
  threshold. A shop whose delivery there has no known price is only listed,
  never compared. See `priced/3`.

  An offer's price in a market is its shop's own price (`shop_price`, in
  `currency`) converted at the latest NBP rates, through PLN both ways.
  Poland keeps the offer's `price`, converted to PLN when it was fetched
  (`TcgCheap.Sealed.Refresh`), so Polish prices stay what they were before
  markets. A rate over a week old means its job stopped: an amount that
  needs it has no price in the market rather than a silently wrong one.
  """

  alias TcgCheap.Sealed.{Shop, Shops}

  @enforce_keys [:code, :country, :currency]
  defstruct @enforce_keys

  @type t :: %__MODULE__{code: String.t(), country: String.t(), currency: String.t()}

  # NBP skips weekends and holidays; a rate over a week old means its job stopped.
  @max_rate_age_days 7

  @spec all() :: [t()]
  def all, do: [poland(), %__MODULE__{code: "hu", country: "HU", currency: "HUF"}]

  @spec poland() :: t()
  def poland, do: %__MODULE__{code: "pl", country: "PL", currency: "PLN"}

  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(code) do
    case Enum.find(all(), &(&1.code == code)) do
      nil -> :error
      market -> {:ok, market}
    end
  end

  @typedoc """
  How a shop takes part in a market: at its own price, with a known
  delivery, only listed (its delivery price is unknown), or not at all.
  """
  @type terms :: :domestic | {:delivered, Shop.delivery()} | :listed | :absent

  @doc "How a shop (`Shops.fetch/1`'s result) takes part in the market."
  @spec terms({:ok, Shop.t()} | :error, t()) :: terms()
  def terms({:ok, %Shop{country: country}}, %__MODULE__{country: country}), do: :domestic

  def terms({:ok, %Shop{deliveries: deliveries}}, %__MODULE__{country: country}) do
    case deliveries do
      %{^country => %{shipping_from: %Decimal{}} = delivery} -> {:delivered, delivery}
      %{^country => _unknown_price} -> :listed
      _none -> :absent
    end
  end

  # A shop no longer configured: its old offers were all Polish.
  def terms(:error, %__MODULE__{code: "pl"}), do: :domestic
  def terms(:error, _market), do: :absent

  @typedoc "An offer as `priced/3` reads it; a market abroad also needs its shop's own price."
  @type offer :: %{
          required(:shop) => String.t(),
          required(:price) => Decimal.t(),
          optional(:shop_price) => Decimal.t() | nil,
          optional(:currency) => String.t() | nil,
          optional(atom()) => term()
        }

  @doc """
  The offers of the shops taking part in the market, in their order, each
  as `{offer, item price, compared price}` in the market's currency: the
  compared price includes delivery for a shop abroad and is nil for a shop
  only listed there. An offer without a price in the market (no shop price
  yet, or no recent rate for a currency it needs) is left out.
  """
  @spec priced([offer], t(), Date.t()) :: [{offer, Decimal.t(), Decimal.t() | nil}]
        when offer: offer()
  def priced(offers, %__MODULE__{} = market, %Date{} = today) do
    terms = shop_terms(offers, market)
    rates = rates(offers, terms, market, today)

    for offer <- offers,
        shop_terms = Map.fetch!(terms, offer.shop),
        shop_terms != :absent,
        {:ok, item} <- [item_price(offer, market, rates)],
        do: {offer, item, compared(item, shop_terms, market, rates)}
  end

  @doc """
  The offers that count in the market's prices (verdicts, lowest prices,
  history), each `price` its compared price in the market's currency.
  """
  @spec compared([offer], t(), Date.t()) :: [offer] when offer: offer()
  def compared(offers, market, today) do
    for {offer, _item, %Decimal{} = compared} <- priced(offers, market, today),
        do: %{offer | price: compared}
  end

  @doc """
  The rates `compared/3` needs for these offers that are missing or too old,
  as `{currency, reason}`; empty when every offer can be priced.
  """
  @spec missing_rates([offer()], t(), Date.t()) :: [{String.t(), term()}]
  def missing_rates(offers, market, today) do
    rates = rates(offers, shop_terms(offers, market), market, today)
    for {currency, {:error, reason}} <- rates, do: {currency, reason}
  end

  @doc """
  The PLN value of one unit of the currency at the latest NBP rate on or
  before `today`, with the rate's date; refused when that rate is over
  #{@max_rate_age_days} days old.
  """
  @spec pln_rate(String.t(), Date.t()) ::
          {:ok, %{rate: Decimal.t(), date: Date.t()}}
          | {:error,
             {:no_exchange_rate, String.t()} | {:stale_exchange_rate, String.t(), Date.t()}}
  def pln_rate("PLN", today), do: {:ok, %{rate: Decimal.new(1), date: today}}

  def pln_rate(currency, %Date{} = today) do
    case TcgCheap.Core.get_latest_exchange_rate(today, currency) do
      {:ok, %{rate: rate, effective_date: date}} ->
        if Date.diff(today, date) <= @max_rate_age_days,
          do: {:ok, %{rate: rate, date: date}},
          else: {:error, {:stale_exchange_rate, currency, date}}

      _missing ->
        {:error, {:no_exchange_rate, currency}}
    end
  end

  @doc "An amount rounded as the market's currency is: whole forints, złoty to grosze."
  @spec rounded(Decimal.t(), t()) :: Decimal.t()
  def rounded(amount, %__MODULE__{currency: "HUF"}), do: Decimal.round(amount, 0)
  def rounded(amount, %__MODULE__{}), do: Decimal.round(amount, 2)

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
  defp rates(offers, terms, market, today) do
    item_currencies =
      if market.code == "pl",
        do: [],
        else: for(offer <- offers, terms[offer.shop] != :absent, do: offer.currency)

    delivery_currencies =
      for {_shop, {:delivered, delivery}} <- terms, do: delivery.currency

    currencies = Enum.uniq(item_currencies ++ delivery_currencies) -- [market.currency, nil]

    # Converting into the market's currency needs its own rate too.
    currencies = if currencies == [], do: [], else: [market.currency | currencies]

    Map.new(Enum.uniq(currencies), &{&1, pln_rate(&1, today)})
  end

  defp item_price(offer, %__MODULE__{code: "pl"}, _rates), do: {:ok, offer.price}
  defp item_price(%{shop_price: nil}, _market, _rates), do: :error

  defp item_price(offer, market, rates),
    do: convert(offer.shop_price, offer.currency, market, rates)

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
