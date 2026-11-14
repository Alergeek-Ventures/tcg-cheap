defmodule TcgCheap.Sealed.CardValue do
  @moduledoc """
  What the guide "Jak sprawdzić wartość karty Pokémon" reads: every English
  card in stock in a Polish shop today at its cheapest offer there, how those
  prices spread, and a typical card for each of a few prices. Its page, its
  markdown version and its link preview read the same `guide/0`.
  """

  import Ecto.Query

  alias TcgCheap.Repo

  alias TcgCheap.Sealed.{
    CardGuide,
    CardPrice,
    ExpensiveCards,
    Guide,
    Shops,
    TcgdexCard,
    TcgdexSet
  }

  # "Co kupisz za złotówkę, a co za tysiąc?": a card for each price.
  @example_prices [1, 10, 100, 1000]

  # The chart's price ranges in złoty, each from its edge to the next; the
  # last has no end.
  @spread_edges [0, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]

  @doc """
  The spread (nil without stock) and the examples, shared by every reader
  for the cache's lifetime: the stock is a scan of every current offer.
  """
  def guide, do: Guide.cached(:card_value, &read/0)

  defp read do
    stock = polish_stock()
    %{spread: spread(stock), examples: examples(stock, @example_prices)}
  end

  # Every English card in stock in a Polish shop, once, at its cheapest
  # ungraded offer there, with its Cardmarket price in złoty when it has one.
  # Shops abroad are left out: their prices include delivery.
  defp polish_stock do
    polish = for %{key: key, country: "PL"} <- Shops.all(), do: key
    rate = Guide.eur_pln(Date.utc_today())

    from(o in CardGuide.current_query(),
      join: c in TcgdexCard,
      on: c.id == o.card_id,
      join: s in TcgdexSet,
      on: s.id == c.tcgdex_set_id,
      left_join: p in CardPrice,
      on: p.cardmarket_id == c.cardmarket_id,
      where:
        o.in_stock and is_nil(o.grading) and o.shop in ^polish and s.language == "en" and
          not is_nil(s.cardmarket_expansion_id),
      group_by: c.tcgdex_id,
      select: {c.tcgdex_id, min(o.price), max(p.trend)}
    )
    |> Repo.all()
    |> Enum.map(fn {tcgdex_id, price, trend} ->
      %{tcgdex_id: tcgdex_id, price: price, cardmarket: Guide.to_pln(trend, rate)}
    end)
  end

  # Half cost the median or less, nine in ten the ninetieth percentile or
  # less; how many cost over 100 zł and how many fall in each price range.
  defp spread([]), do: nil

  defp spread(stock) do
    prices = stock |> Enum.map(& &1.price) |> Enum.sort(Decimal)
    count = length(prices)
    at = fn share -> Enum.at(prices, min(count - 1, floor(count * share))) end
    ends = tl(@spread_edges) ++ [nil]

    bins =
      for {from, to} <- Enum.zip(@spread_edges, ends) do
        in_range =
          Enum.count(prices, fn price ->
            not Decimal.lt?(price, from) and (is_nil(to) or Decimal.lt?(price, to))
          end)

        %{from: from, to: to, count: in_range}
      end

    %{
      on: Date.utc_today(),
      count: count,
      median: at.(0.5),
      ninetieth: at.(0.9),
      over_100: Enum.count(prices, &Decimal.gt?(&1, 100)),
      bins: bins
    }
  end

  # A card for about each of `prices` (złoty), with a picture. Of the cards a
  # Polish shop sells within 15% of the price, the one priced most like on
  # Cardmarket, so the example is a typical card rather than an odd offer;
  # without any, the nearest. Offers far from their Cardmarket price are
  # never examples, and a price with no card is left out.
  defp examples(stock, prices) do
    candidates = Enum.filter(stock, &comparable?/1)
    nearest = for target <- prices, do: {target, typical(candidates, target)}

    # The article's presented rows: the card's link, picture and cheapest
    # Polish offer of its normal print.
    rows =
      nearest
      |> Enum.flat_map(fn {_target, near} -> Enum.map(near, & &1.tcgdex_id) end)
      |> Enum.uniq()
      |> ExpensiveCards.cards()
      |> Map.new(&{&1.card.tcgdex_id, &1})

    {examples, _used} = Enum.flat_map_reduce(nearest, MapSet.new(), &pick(&1, &2, rows))
    examples
  end

  # A shop price within twice its Cardmarket price either way.
  defp comparable?(%{price: price, cardmarket: %Decimal{} = cardmarket}),
    do: Decimal.positive?(price) and Decimal.positive?(cardmarket) and near?(price, cardmarket, 2)

  defp comparable?(_card), do: false

  defp typical(candidates, target) do
    ordered =
      case Enum.filter(candidates, &near?(&1.price, target, 1.15)) do
        [] -> Enum.sort_by(candidates, &distance(&1.price, target))
        window -> Enum.sort_by(window, &distance(&1.price, &1.cardmarket))
      end

    Enum.take(ordered, 8)
  end

  # The first near card with a picture and an offer near the price, not
  # already an example of another price.
  defp pick({target, near}, used, rows) do
    case Enum.find_value(near, &shown(rows[&1.tcgdex_id], target, used)) do
      nil -> {[], used}
      row -> {[%{price: target, row: row}], MapSet.put(used, row.card.tcgdex_id)}
    end
  end

  defp shown(%{offer: %{price: price}, image: "" <> _, card: card} = row, target, used) do
    if not MapSet.member?(used, card.tcgdex_id) and near?(price, target, 4 / 3), do: row
  end

  defp shown(_row, _target, _used), do: nil

  # Within `factor` of each other either way.
  defp near?(price, other, factor), do: distance(price, other) <= :math.log(factor)

  defp distance(price, other),
    do: abs(:math.log(Decimal.to_float(price) / to_float(other)))

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value), do: value / 1
end
