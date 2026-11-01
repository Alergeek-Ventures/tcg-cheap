defmodule TcgCheap.Sealed.Guide do
  @moduledoc "Read models for the public buying-guide pages."

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{PriceGuide, Product, Regions, TcgdexSet}

  @history_days 90
  @page_size 30

  @type summary :: %{
          product: Product.t(),
          verdict: PriceGuide.t(),
          cardmarket_pln: Decimal.t() | nil,
          in_stock_offers: [%{shop: String.t(), price: Decimal.t()}]
        }

  def history_days, do: @history_days

  @type filters :: %{
          query: String.t(),
          kind: atom() | nil,
          region: atom() | nil,
          expansion: integer() | nil
        }

  @doc """
  One page of the public list: products matching the filters, in stock in
  Poland first, then newest. Returns the summaries, whether more pages follow
  and the total count.
  """
  @spec browse(filters(), non_neg_integer(), DateTime.t()) ::
          {[summary()], boolean(), non_neg_integer()}
  def browse(filters, offset, %DateTime{} = now) do
    page =
      Sealed.browse_products!(filters.query, filters.kind, filters.region, filters.expansion,
        page: [limit: @page_size, offset: offset, count: true]
      )

    {summaries(page.results, now), page.more?, page.count || 0}
  end

  @doc """
  What the language and expansion filters offer under the other filters:
  product counts per language edition, and the named expansions (those with
  a product in stock first, then newest first) with their English TCGdex
  logo when there is one.
  """
  @spec facets(filters()) :: %{
          regions: [{atom(), pos_integer()}],
          expansions: [
            %{
              id: integer(),
              name: String.t(),
              region: atom(),
              logo_url: String.t() | nil,
              count: non_neg_integer()
            }
          ]
        }
  def facets(filters) do
    regions =
      Sealed.list_product_facets!(filters.query, filters.kind, nil, filters.expansion)
      |> Enum.frequencies_by(& &1.region)

    %{
      regions: for(region <- Regions.all(), count = regions[region], do: {region, count}),
      expansions: expansions(filters)
    }
  end

  defp expansions(filters) do
    logos =
      for {id, %{language: "en", logo_url: "" <> url}} <-
            TcgdexSet.by_expansion(Sealed.list_tcgdex_sets!()),
          into: %{},
          do: {id, url <> ".webp"}

    expansions =
      Sealed.list_product_facets!(filters.query, filters.kind, filters.region, nil)
      |> named_expansions(logos)
      |> Enum.sort_by(&(&1.newest || ~D[1990-01-01]), {:desc, Date})
      |> Enum.sort_by(&(!&1.available?))
      |> Enum.map(&Map.drop(&1, [:available?, :newest]))

    expansions ++ chosen_elsewhere(filters.expansion, expansions, logos)
  end

  # The chosen expansion stays listed, with no products, when the other
  # filters leave none of it.
  defp chosen_elsewhere(nil, _expansions, _logos), do: []

  defp chosen_elsewhere(id, expansions, logos) do
    if Enum.any?(expansions, &(&1.id == id)) do
      []
    else
      Sealed.list_product_facets!("", nil, nil, id)
      |> named_expansions(logos)
      |> Enum.map(&(&1 |> Map.drop([:available?, :newest]) |> Map.put(:count, 0)))
    end
  end

  defp named_expansions(products, logos) do
    products
    |> Enum.filter(&(&1.cardmarket_expansion_id && &1.set_name))
    |> Enum.group_by(& &1.cardmarket_expansion_id)
    |> Enum.map(fn {id, products} ->
      %{
        id: id,
        name: most_common(products, & &1.set_name),
        region: most_common(products, & &1.region),
        logo_url: Map.get(logos, id),
        count: length(products),
        available?: Enum.any?(products, & &1.available),
        newest:
          products
          |> Enum.map(& &1.cardmarket_added_on)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(Date, fn -> nil end)
      }
    end)
  end

  defp most_common(products, field),
    do: products |> Enum.frequencies_by(field) |> Enum.max_by(&elem(&1, 1)) |> elem(0)

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

  @doc """
  Everything the product page shows: verdict, offers, 90 days of history and
  REBEL's suggested retail price when one matches.
  """
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
         |> Map.merge(%{
           offers: offers,
           history: history,
           today: today,
           eur_pln: rate,
           suggested_price: Sealed.get_suggested_price_for_product!(product.id)
         })}
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
      cardmarket_pln: cardmarket_pln,
      in_stock_offers: Enum.map(in_stock, &%{shop: &1.shop, price: &1.price})
    }
  end
end
