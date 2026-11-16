defmodule TcgCheap.Sealed.Summary do
  @moduledoc """
  A product with its verdict in a market, as the lists, banners and set pages
  show it: its shops' offers at their compared prices, its price history and
  the Cardmarket references converted to the market's currency
  (`TcgCheap.Sealed.Market`). `cardmarket_price` and `cardmarket_delivered_price`
  are in the market's currency.
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Market, PriceGuide, Product, TcgdexSet}

  @type t :: %{
          product: Product.t(),
          verdict: PriceGuide.t(),
          preorder?: boolean(),
          premiere_in: non_neg_integer() | nil,
          premiere: Date.t() | nil,
          cardmarket_price: Decimal.t() | nil,
          cardmarket_delivered_price: Decimal.t() | nil
        }

  # The product fields a summary and its list row read.
  @fields [
    :slug,
    :name,
    :kind,
    :region,
    :set_name,
    :cardmarket_expansion_id,
    :cardmarket_trend
  ]

  @doc "The product fields a summary reads."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc """
  Summaries for the given products, in order. A product with nothing in
  stock but pre-orders is rated on its pre-orders (`preorder?`), with the
  days until its expansion's premiere when that is still to come.
  """
  @spec list([Product.t()], DateTime.t(), Market.t()) :: [t()]
  def list(products, now, market \\ Market.poland())
  def list([], _now, _market), do: []

  def list(products, %DateTime{} = now, %Market{} = market) do
    today = DateTime.to_date(now)
    rate = Market.cardmarket_rate(market, today)
    ids = Enum.map(products, & &1.id)

    offers =
      now
      |> Sealed.current_offers(ids,
        select: [:product_id, :price, :in_stock, :preorder | shop_price_fields(market)]
      )
      |> Market.compared(market, today)
      |> Enum.group_by(& &1.product_id)

    since = Date.add(today, -(PriceGuide.window_days() - 1))

    histories =
      ids
      |> price_histories(market, since)
      |> Enum.group_by(& &1.product_id)

    premieres = premieres(products)

    Enum.map(products, fn product ->
      usual = PriceGuide.usual(Map.get(histories, product.id, []), today)

      build(
        product,
        Map.get(offers, product.id, []),
        {rate, market},
        usual,
        {premieres, now}
      )
    end)
  end

  @doc """
  The summary of one product from its compared `offers` (`Market.compared/3`)
  and the usual price of its history (`PriceGuide.usual/2`).
  """
  @spec of(
          Product.t(),
          [Market.offer()],
          Decimal.t() | nil,
          {map() | nil, Market.t()},
          DateTime.t()
        ) ::
          t()
  def of(product, offers, usual, {rate, market}, now),
    do: build(product, offers, {rate, market}, usual, {premieres([product]), now})

  # Poland compares the PLN price stored at fetch; another market reads what
  # the shop charges there, or converts the shop's own price.
  # Both leave out an offer its shop does not sell to the country.
  defp shop_price_fields(market) do
    if market == Market.poland(),
      do: [:market_prices],
      else: [:shop_price, :currency, :market_prices]
  end

  defp price_histories(ids, market, since) do
    select = [query: [select: [:product_id, :date, :lowest_price]]]

    if market == Market.poland(),
      do: Sealed.list_price_histories!(ids, since, select),
      else: Sealed.list_market_price_histories!(ids, market.code, since, select)
  end

  # The verdict judges each shop at its compared price (`Market.compared/3`):
  # a shop abroad's includes delivery to the market.
  defp build(product, offers, {rate, market}, usual, {premieres, now}) do
    in_stock = Enum.filter(offers, & &1.in_stock)
    preorders = Enum.filter(offers, & &1.preorder)
    # With nothing in stock, pre-orders are rated the same way.
    preorder? = in_stock == [] and preorders != []
    cardmarket_price = Market.in_market(product.cardmarket_trend, rate, market)

    cardmarket_delivered_price =
      product.cardmarket_trend |> with_shipping(market) |> Market.in_market(rate, market)

    {premiere, premiere_in} =
      if preorder?,
        do: upcoming(Map.get(premieres, product.cardmarket_expansion_id), now),
        else: {nil, nil}

    %{
      product: product,
      verdict:
        PriceGuide.verdict(
          if(preorder?, do: preorders, else: in_stock),
          cardmarket_price,
          [past: usual, cardmarket: cardmarket_delivered_price],
          market
        ),
      preorder?: preorder?,
      premiere: premiere,
      premiere_in: premiere_in,
      cardmarket_price: cardmarket_price,
      cardmarket_delivered_price: cardmarket_delivered_price
    }
  end

  # The release day of each product's expansion (its set's `released_on`):
  # the street date every shop ships pre-orders on.
  defp premieres(products) do
    case products |> Enum.map(& &1.cardmarket_expansion_id) |> Enum.reject(&is_nil/1) do
      [] ->
        %{}

      ids ->
        Sealed.list_tcgdex_sets!(
          query: [
            filter: [cardmarket_expansion_id: [in: Enum.uniq(ids)]],
            select: [:cardmarket_expansion_id, :language, :name, :released_on]
          ]
        )
        |> TcgdexSet.by_expansion()
        |> Map.new(fn {id, set} -> {id, set.released_on} end)
    end
  end

  # A premiere still to come (or today), with the days left in Poland.
  defp upcoming(nil, _now), do: {nil, nil}

  defp upcoming(%Date{} = premiere, now) do
    case Date.diff(premiere, warsaw_date(now)) do
      days when days >= 0 -> {premiere, days}
      _past -> {nil, nil}
    end
  end

  # The calendar day in Poland: CET, CEST from the last Sunday of March to the
  # last Sunday of October (01:00 UTC both, as everywhere in the EU).
  defp warsaw_date(%DateTime{} = now) do
    year = now.year
    summer_from = DateTime.new!(last_sunday(year, 3), ~T[01:00:00])
    summer_to = DateTime.new!(last_sunday(year, 10), ~T[01:00:00])

    summer? =
      DateTime.compare(now, summer_from) != :lt and DateTime.compare(now, summer_to) == :lt

    now |> DateTime.add(if(summer?, do: 2, else: 1), :hour) |> DateTime.to_date()
  end

  defp last_sunday(year, month) do
    last = Date.end_of_month(Date.new!(year, month, 1))
    Date.add(last, -rem(Date.day_of_week(last), 7))
  end

  defp with_shipping(%Decimal{} = eur, market),
    do: Decimal.add(eur, market.cardmarket_shipping_eur)

  defp with_shipping(nil, _market), do: nil
end
