defmodule TcgCheap.Sealed.ProductPage do
  @moduledoc """
  What the product page shows, in the market's currency
  (`TcgCheap.Sealed.Market`, Poland by default): its shops' offers at their
  compared prices, the market's own price history and the Cardmarket
  references converted to its currency.
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{CardGuide, ExpansionCards, Market, PriceGuide, Product, Stock, Summary}

  @history_days 90
  # Products an out-of-stock product's page offers instead.
  @in_stock_from_set 4
  # Unrated offers (too few shops, or a Cardmarket comparison) rank between
  # normal and expensive ones.
  @offer_ranks %{good: 0, normal: 1, cardmarket: 2, insufficient_data: 2, expensive: 3}

  @doc "The days of price history the page shows."
  @spec history_days() :: pos_integer()
  def history_days, do: @history_days

  @doc """
  Everything the product page shows: today's verdict, the comparison with
  the product's history (`past`), offers, 90 days of history, REBEL's
  suggested retail price when one matches, our single booster of the same
  edition for each set the contents name (`boosters`, by set name), their combined odds
  and cards (`booster_odds`) and, for any English single booster, its set's pull rates
  and cards (`booster_set`, nil for other products).

  In the market's currency: `offers` are its shops' offers, each `price` the
  item price without delivery; `history` is the market's (only Poland's
  carries the Cardmarket trend) and `eur_rate` the euro's rate in its
  currency.
  """
  @spec read(String.t(), DateTime.t(), Market.t()) :: {:ok, map()} | :error
  def read(slug, %DateTime{} = now, %Market{} = market \\ Market.poland()) do
    case Sealed.get_product_by_slug!(slug, load: [:stored_photo_page_url, :photo_placeholder]) do
      nil ->
        :error

      product ->
        today = DateTime.to_date(now)
        rate = Market.cardmarket_rate(market, today)

        priced =
          now
          |> Sealed.current_offers([product.id])
          |> Market.priced(market, today)
          # By the price compared in the verdict: a shop abroad's with delivery.
          |> Enum.sort_by(fn {offer, item, compared} ->
            {not offer.in_stock, Decimal.to_float(compared || item), offer.shop}
          end)

        offers = for {offer, item, _compared} <- priced, do: %{offer | price: item}
        compared = for {offer, _item, %Decimal{} = price} <- priced, do: %{offer | price: price}

        since = Date.add(today, -(@history_days - 1))
        history = price_history(product.id, market, since)

        summary =
          Summary.of(product, compared, PriceGuide.usual(history, today), {rate, market}, now)

        past_history = with_last_stocked_day(history, product.id, since, market)
        boosters = boosters(product)

        {:ok,
         Map.merge(summary, %{
           past: PriceGuide.past(past_history, summary.verdict.cheapest, today, market),
           offers: offers,
           compared: Map.new(priced, fn {offer, _item, compared} -> {offer.id, compared} end),
           history: history,
           today: today,
           eur_rate: rate,
           market: market,
           suggested_price:
             polish_only(market, fn -> Sealed.get_suggested_price_for_product!(product.id) end),
           retail_deals:
             polish_only(market, [], fn ->
               Sealed.list_current_retail_deals!(today, query: [filter: [product_id: product.id]])
             end),
           boosters: boosters,
           booster_odds: booster_odds(product, boosters),
           booster_set: booster_set(product)
         })}
    end
  end

  @doc """
  What a product nobody has in stock can be swapped for from its own
  expansion: the other products of its edition in stock now with the best
  offers first (`products`, summaries, at most #{@in_stock_from_set}, see
  `best_offer_first/1`) and how many of the set's English cards are
  (`cards`). Nil for a product without an expansion.
  """
  @spec in_stock_from_set(Product.t(), DateTime.t(), Market.t()) ::
          %{products: [Summary.t()], cards: non_neg_integer()} | nil
  def in_stock_from_set(%Product{cardmarket_expansion_id: nil}, _now, _market), do: nil

  def in_stock_from_set(
        %Product{cardmarket_expansion_id: id} = product,
        %DateTime{} = now,
        %Market{} = market
      ) do
    products =
      [
        query: [
          filter:
            Stock.in_stock_filter(market, now) ++
              [
                cardmarket_expansion_id: id,
                region: product.region,
                id: [not_eq: product.id]
              ],
          select: Summary.fields()
        ],
        load: [:stored_photo_small_url, :stored_photo_card_url, :photo_placeholder]
      ]
      |> Sealed.list_products!()
      |> Summary.list(now, market)
      # `available` is as of the last refresh: keep the ones in stock now.
      |> Enum.filter(&(&1.verdict.cheapest && not &1.preorder?))
      |> Enum.sort_by(&best_offer_first/1)
      |> Enum.take(@in_stock_from_set)

    # Singles are priced only in Poland.
    %{products: products, cards: polish_only(market, 0, fn -> CardGuide.in_stock_count(id) end)}
  end

  # The best offer first: by verdict, then by how far the cheapest price is
  # under its reference (`typical`). One too far under it is more often a
  # wrong match than a deal (see `PriceGuide.deal_min_ratio/0`), so it ranks
  # after the unrated ones. Without a reference the ratio is nil, which sorts
  # after any number.
  defp best_offer_first(%{verdict: %{status: status, cheapest: cheapest, typical: typical}}) do
    ratio = if typical && Decimal.positive?(typical), do: Decimal.div(cheapest.price, typical)
    suspect? = ratio != nil and Decimal.lt?(ratio, PriceGuide.deal_min_ratio())
    rank = if suspect?, do: @offer_ranks.cardmarket, else: Map.fetch!(@offer_ranks, status)

    {rank, suspect?, ratio && Decimal.to_float(ratio)}
  end

  defp price_history(product_id, market, since) do
    if market == Market.poland(),
      do: Sealed.list_price_history!(product_id, since),
      else: Sealed.list_market_price_history!(product_id, market.code, since)
  end

  # The last known price shown when out of stock may predate the chart.
  defp with_last_stocked_day(history, product_id, since, market) do
    last_stocked =
      if market == Market.poland(),
        do: Sealed.get_last_stocked_day!(product_id),
        else: Sealed.get_market_last_stocked_day!(product_id, market.code)

    case last_stocked do
      %{date: date} = day -> if Date.before?(date, since), do: [day | history], else: history
      nil -> history
    end
  end

  # REBEL's suggested prices and the retail chains' deals are Polish, in PLN.
  defp polish_only(market, none \\ nil, read),
    do: if(market == Market.poland(), do: read.(), else: none)

  defp boosters(%Product{contents: nil}), do: %{}

  defp boosters(%Product{contents: contents, region: region}) do
    case for(%{type: :booster, name: set} <- contents.items, set, do: set <> " Booster") do
      [] ->
        %{}

      names ->
        names
        |> Sealed.list_boosters_by_name!(region,
          load: [:stored_photo_small_url, :stored_photo_card_url]
        )
        |> Map.new(&{String.replace_suffix(&1.name, " Booster", ""), &1})
    end
  end

  # Smaller English packs share the set's card pool, but not its standard-pack odds.
  defp booster_set(%Product{kind: :booster, region: :en, cardmarket_expansion_id: id} = product) do
    set = ExpansionCards.read(id)
    Map.put(set, :smaller_pack?, smaller_pack?(product, set.standard_pack_size))
  end

  defp booster_set(_product), do: nil

  defp smaller_pack?(product, standard) do
    size = Product.pack_size(product)
    not is_nil(size) and (is_nil(standard) or size < standard)
  end

  # English odds fit English packs only.
  defp booster_odds(%Product{region: :en, contents: %{items: items}}, boosters) do
    items
    |> Enum.filter(&(&1.type == :booster and Map.has_key?(boosters, &1.name)))
    |> Enum.group_by(& &1.name)
    |> Enum.sort_by(&elem(&1, 0))
    |> set_odds(boosters)
  end

  defp booster_odds(_product, _boosters), do: []

  # Each set's odds across its packs and its cards, so the box's page lists
  # them without a trip to the single booster's page.
  defp set_odds(groups, boosters) do
    Enum.map(groups, fn {name, items} ->
      booster = Map.fetch!(boosters, name)

      Map.merge(ExpansionCards.odds(booster.cardmarket_expansion_id), %{
        name: name,
        slug: booster.slug,
        count: Enum.sum(Enum.map(items, & &1.quantity))
      })
    end)
  end
end
