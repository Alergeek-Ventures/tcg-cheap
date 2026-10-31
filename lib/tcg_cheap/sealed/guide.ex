defmodule TcgCheap.Sealed.Guide do
  @moduledoc "Read models for the public buying-guide pages."

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{PriceGuide, Product}

  @history_days 90
  @page_size 30

  @type summary :: %{
          product: Product.t(),
          verdict: PriceGuide.t(),
          cardmarket_pln: Decimal.t() | nil
        }

  def history_days, do: @history_days

  @doc """
  One page of the public list: products matching the query and kind, in
  stock in Poland first, then newest. Returns the summaries, whether more
  pages follow and the total count.
  """
  @spec browse(String.t(), atom() | nil, non_neg_integer(), DateTime.t()) ::
          {[summary()], boolean(), non_neg_integer()}
  def browse(query, kind, offset, %DateTime{} = now) do
    page =
      Sealed.browse_products!(query, kind, page: [limit: @page_size, offset: offset, count: true])

    {summaries(page.results, now), page.more?, page.count || 0}
  end

  @doc "Summaries for the given products, in order."
  @spec summaries([Product.t()], DateTime.t()) :: [summary()]
  def summaries([], _now), do: []

  def summaries(products, %DateTime{} = now) do
    today = DateTime.to_date(now)
    rate = eur_pln(today)
    ids = Enum.map(products, & &1.id)

    offers = now |> Sealed.current_offers(ids) |> Enum.group_by(& &1.product_id)

    history =
      today
      |> Date.add(-(PriceGuide.window_days() - 1))
      |> Sealed.list_daily_prices_since!(ids)
      |> Enum.group_by(& &1.product_id)

    Enum.map(products, fn product ->
      summary(
        product,
        Map.get(offers, product.id, []),
        Map.get(history, product.id, []),
        today,
        rate
      )
    end)
  end

  @doc "Everything the product page shows: verdict, offers and 90 days of history."
  @spec product(String.t(), DateTime.t()) :: {:ok, map()} | :error
  def product(slug, %DateTime{} = now) do
    case Sealed.get_product_by_slug!(slug) do
      nil ->
        :error

      product ->
        today = DateTime.to_date(now)
        rate = eur_pln(today)

        offers =
          now
          |> Sealed.current_offers([product.id])
          |> Enum.sort_by(&{not &1.in_stock, Decimal.to_float(&1.price), &1.shop})

        since = Date.add(today, -(@history_days - 1))
        history = Sealed.list_price_history!(product.id, since)

        verdict_history = with_last_stocked_day(history, product.id, since)

        {:ok,
         product
         |> summary(offers, verdict_history, today, rate)
         |> Map.merge(%{offers: offers, history: history, today: today, eur_pln: rate})}
    end
  end

  # The last known price shown when out of stock may predate the chart.
  defp with_last_stocked_day(history, product_id, since) do
    case Sealed.get_last_stocked_day!(product_id) do
      %{date: date} = day -> if Date.before?(date, since), do: [day | history], else: history
      nil -> history
    end
  end

  @doc "The latest stored NBP EUR/PLN mid rate on or before `date`, if any."
  @spec eur_pln(Date.t()) :: %{rate: Decimal.t(), date: Date.t()} | nil
  def eur_pln(%Date{} = date) do
    case TcgCheap.Core.get_latest_exchange_rate(date) do
      {:ok, %{rate: rate, effective_date: effective}} -> %{rate: rate, date: effective}
      _ -> nil
    end
  end

  @doc "A Cardmarket EUR amount in PLN at the given rate."
  @spec to_pln(Decimal.t() | nil, map() | nil) :: Decimal.t() | nil
  def to_pln(%Decimal{} = eur, %{rate: rate}), do: eur |> Decimal.mult(rate) |> Decimal.round(2)
  def to_pln(_eur, _rate), do: nil

  defp summary(product, offers, history, today, rate) do
    in_stock = Enum.filter(offers, & &1.in_stock)
    cardmarket_pln = to_pln(product.cardmarket_trend, rate)

    %{
      product: product,
      verdict: PriceGuide.verdict(history, in_stock, today, cardmarket_pln),
      cardmarket_pln: cardmarket_pln
    }
  end
end
