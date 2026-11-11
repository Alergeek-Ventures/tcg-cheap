defmodule TcgCheap.Sealed.ExpensiveCards do
  @moduledoc """
  The most expensive English Pokémon cards by today's Cardmarket trend, in
  PLN, with what our shops have of each: the read model of the "Najdroższe
  karty Pokémon" article.

  `overview/0` feeds the article (the top cards, what our shops have, each
  new set's top card, what rises and falls); `ranking/3` is the filtered
  list of the 500 most expensive under it.

  Only cards of the Sword & Shield era on are priced: an older card's
  Cardmarket trend mixes played, mint and graded copies, so it is not what
  the card costs. A card shares its Cardmarket product with another card
  only when one of the two is linked wrongly; such cards are left out rather
  than ranked at a price that may not be theirs.
  """

  import Ecto.Query

  alias TcgCheap.{Repo, Storage}

  alias TcgCheap.Sealed.{
    CardGuide,
    CardImage,
    CardPrice,
    CardReference,
    Guide,
    Shops,
    TcgdexCard,
    TcgdexSet
  }

  # The slice the page works with: enough for every list and for paging the
  # ranking, small enough to judge and enrich in one pass.
  @slice 500
  # The top the article describes. Movements are judged only there: a cheap
  # card's weekly average is a handful of sales.
  @top 100
  @movers_floor_pln Decimal.new(100)
  @movers 5
  @highlights 6
  @new_sets 6
  # The Sword & Shield era, from its first promos. Before it, a trend can be
  # many times the cheapest copy on offer: Skyridge's non-holo Gengar trended
  # at 8,549 € while one sold from 325 €; modern cards stay within 6×.
  @since ~D[2019-11-15]

  @type filters :: %{set: integer() | nil, stock: :all | :in}

  @doc "The article's figures, from the whole ranking, shared by every render a while."
  @spec overview() :: map()
  def overview, do: Guide.cached(:expensive_cards_overview, &read_overview/0)

  defp read_overview do
    rate = Guide.eur_pln(Date.utc_today())
    rows = ranked(%{set: nil})
    top = Enum.take(rows, @top)
    movable = movable(top)

    lists = %{
      # One card in several printings of one set (30th Celebration's Mew in
      # red, green and blue) is one entry, with its range.
      highlights: rows |> group_printings() |> Enum.take(@highlights),
      in_stock: rows |> Enum.filter(& &1.offer) |> Enum.take(@highlights),
      new_sets: newest_sets(rate),
      rising:
        movable
        |> Enum.filter(&Decimal.positive?(&1.change))
        |> Enum.sort_by(& &1.change, {:desc, Decimal})
        |> Enum.take(@movers),
      falling:
        movable
        |> Enum.filter(&Decimal.negative?(&1.change))
        |> Enum.sort_by(& &1.change, {:asc, Decimal})
        |> Enum.take(@movers)
    }

    # Every list's cards are presented in one pass.
    show = lists |> Map.values() |> Enum.concat() |> presenter()
    shown = Map.new(lists, fn {key, list} -> {key, Enum.map(list, show)} end)

    %{
      rate: rate,
      priced_on: priced_on(),
      highlights: shown.highlights,
      in_stock: shown.in_stock,
      new_sets: shown.new_sets,
      movers: %{rising: shown.rising, falling: shown.falling},
      top_count: length(top),
      top_in_stock: Enum.count(top, & &1.offer)
    }
  end

  @doc """
  Cards by TCGdex id with their pictures, value and offers, in the order
  asked: the cards an article names by hand. A card without a Cardmarket
  price, or sharing its Cardmarket product with another card, comes with a
  nil value.
  """
  @spec cards([String.t()]) :: [map()]
  def cards(tcgdex_ids) do
    rate = Guide.eur_pln(Date.utc_today())
    shared = shared_ids() |> Repo.all() |> MapSet.new()

    rows =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        left_join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        where: c.tcgdex_id in ^tcgdex_ids and s.language == "en",
        select: {c, s, p}
      )
      |> Repo.all()
      |> Enum.map(fn {card, set, price} ->
        {card, set, if(MapSet.member?(shared, card.cardmarket_id), do: nil, else: price)}
      end)
      |> priced(rate)
      |> present()
      |> Map.new(&{&1.card.tcgdex_id, &1})

    for id <- tcgdex_ids, row = rows[id], do: row
  end

  @doc """
  The filtered ranking: how many cards it holds and `count` of them from
  `offset`, each with its place.
  """
  @spec ranking(filters(), non_neg_integer(), pos_integer()) :: map()
  def ranking(filters, offset, count) do
    rows = filters |> ranked() |> stock_filter(filters.stock)

    cards =
      rows
      |> Enum.with_index(1)
      |> Enum.slice(offset, count)
      |> Enum.map(fn {row, place} -> Map.put(row, :place, place) end)
      |> present()

    %{total: length(rows), cards: cards}
  end

  @doc "The sets with a priced card, newest first, for the set filter."
  def sets do
    sets =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id),
        where: s.released_on >= ^@since and not is_nil(p.trend),
        distinct: s.cardmarket_expansion_id,
        order_by: [s.cardmarket_expansion_id],
        select: {s.cardmarket_expansion_id, s.released_on}
      )
      |> Repo.all()

    names = Guide.expansion_names(Enum.map(sets, &elem(&1, 0)))

    for {id, _released_on} <- Enum.sort_by(sets, &elem(&1, 1), {:desc, Date}),
        name = Map.get(names, id),
        name != nil,
        do: %{id: id, name: name}
  end

  # The slice priced. The whole ranking, which the article and every first
  # visit start with, is shared by every render a while.
  defp ranked(%{set: nil}), do: Guide.cached(:expensive_cards, fn -> read_ranked(nil) end)
  defp ranked(%{set: set}), do: read_ranked(set)

  defp read_ranked(set) do
    rate = Guide.eur_pln(Date.utc_today())
    %{set: set} |> slice(rate) |> priced(rate)
  end

  # Without an exchange rate nothing has a value in złoty to rank by.
  defp slice(_filters, nil), do: []

  defp slice(filters, _rate) do
    from(c in TcgdexCard,
      join: s in TcgdexSet,
      on: c.tcgdex_set_id == s.id,
      join: p in CardPrice,
      on: p.cardmarket_id == c.cardmarket_id,
      where: s.language == "en" and not is_nil(s.cardmarket_expansion_id),
      where: s.released_on >= ^@since,
      where: not is_nil(p.trend) and c.cardmarket_id not in subquery(shared_ids()),
      order_by: [desc: p.trend, asc: c.id],
      limit: @slice,
      select: {c, s, p}
    )
    |> set_filter(filters.set)
    |> Repo.all()
  end

  defp shared_ids do
    from(c in TcgdexCard,
      join: s in TcgdexSet,
      on: c.tcgdex_set_id == s.id,
      where: s.language == "en" and not is_nil(c.cardmarket_id),
      group_by: c.cardmarket_id,
      having: count(c.id) > 1,
      select: c.cardmarket_id
    )
  end

  defp set_filter(query, nil), do: query
  defp set_filter(query, id), do: where(query, [_, s], s.cardmarket_expansion_id == ^id)

  # What the page needs of every row of the slice, cheaply: the value in
  # złoty, the change, and the Polish shops' offer with its verdict. Links and
  # pictures come later, for the rows shown (`present/1`).
  defp priced([], _rate), do: []

  defp priced(rows, rate) do
    offers = rows |> Enum.map(fn {card, _set, _price} -> card.id end) |> polish_offers()

    Enum.map(rows, fn {card, set, price} ->
      card = %{card | cardmarket_price: price, tcgdex_set: set}
      card_offers = Map.get(offers, card.id, [])
      offer = List.first(card_offers)

      %{
        card: card,
        set: set,
        value: price && Guide.to_pln(price.trend, rate),
        change: change(price),
        offer: offer,
        shops: card_offers |> Enum.uniq_by(& &1.shop) |> length(),
        verdict: verdict(offer, card, rate)
      }
    end)
  end

  # The article is about what can be bought in Poland: only Polish shops, and
  # only the card's normal print without a grade, as its value is that
  # print's. Cheapest first, as `CardGuide.current_offers/1` sorts them.
  defp polish_offers(card_ids) do
    card_ids
    |> CardGuide.current_offers()
    |> Enum.filter(
      &(&1.in_stock and is_nil(&1.grading) and &1.variant == :normal and polish?(&1.shop))
    )
    |> Enum.group_by(& &1.card_id)
  end

  # Shops abroad are the ones with a country.
  defp polish?(shop), do: match?({:ok, %{country: nil}}, Shops.fetch(shop))

  # This far under the card's value, an offer is more often matched to the
  # wrong card than a bargain: shown, but not judged, as the card list ranks
  # such an offer.
  @suspect_ratio Decimal.new("0.6")

  defp verdict(nil, _card, _rate), do: nil

  defp verdict(offer, card, rate) do
    reference = CardReference.pln(card.cardmarket_price, :normal, rate)

    if reference && Decimal.positive?(reference) &&
         Decimal.lt?(Decimal.div(offer.price, reference), @suspect_ratio),
       do: :unknown,
       else: CardGuide.card_verdict(offer, card, :normal, rate)
  end

  # The last 7 days' average sale against the last 30 days': two averages of
  # real sales, so like is compared with like.
  defp change(%{avg7: %Decimal{} = week, avg30: %Decimal{} = month}) do
    if Decimal.positive?(month), do: week |> Decimal.div(month) |> Decimal.sub(1)
  end

  defp change(_price), do: nil

  defp stock_filter(rows, :all), do: rows
  defp stock_filter(rows, :in), do: Enum.filter(rows, & &1.offer)

  defp movable(top),
    do: Enum.filter(top, &(&1.change && Decimal.gte?(&1.value, @movers_floor_pln)))

  # Rows are by value, so each group's first row is its most expensive. A
  # group is one card's printings next to each other in the ranking.
  # The group's offer is the cheapest of its printings', so "in shops from"
  # holds for the card in any of them.
  defp group_printings(rows) do
    rows
    |> Enum.chunk_by(&{&1.card.name, &1.set.id})
    |> Enum.map(fn [first | _] = printings ->
      offer =
        printings
        |> Enum.map(& &1.offer)
        |> Enum.reject(&is_nil/1)
        |> Enum.min_by(& &1.price, Decimal, fn -> nil end)

      Map.merge(first, %{printings: printings, offer: offer})
    end)
  end

  # The newest expansions by release, each with its most expensive card: a
  # new set's top card is often far from the overall top 500.
  defp newest_sets(nil), do: []

  defp newest_sets(rate) do
    ranked =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id),
        where: not is_nil(p.trend) and s.released_on >= ^@since,
        where: c.cardmarket_id not in subquery(shared_ids()),
        select: %{
          card_id: c.id,
          released_on: s.released_on,
          place:
            over(row_number(),
              partition_by: s.cardmarket_expansion_id,
              order_by: [desc: p.trend, asc: c.id]
            )
        }
      )

    ids =
      from(r in subquery(ranked),
        where: r.place == 1,
        order_by: [desc: r.released_on, asc: r.card_id],
        limit: @new_sets,
        select: r.card_id
      )
      |> Repo.all()

    rows =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        where: c.id in ^ids,
        select: {c, s, p}
      )
      |> Repo.all()
      |> priced(rate)
      |> Map.new(&{&1.card.id, &1})

    Enum.map(ids, &Map.fetch!(rows, &1))
  end

  # The rows shown, with what they show: the card's link, set name and
  # picture. A grouped row's printings get them too.
  defp present(rows), do: Enum.map(rows, presenter(rows))

  # How to show any of the rows: each card's link, set name and picture, all
  # read at once. A grouped row's printings get them too.
  defp presenter(rows) do
    all = Enum.flat_map(rows, &[&1 | Map.get(&1, :printings, [])])
    sets = all |> Enum.map(& &1.set) |> Enum.uniq_by(& &1.id)
    cards = all |> Enum.map(& &1.card) |> Enum.uniq_by(& &1.id) |> CardGuide.enrich(sets)
    cards = Map.new(cards, &{&1.id, &1})

    hashes =
      cards
      |> Map.values()
      |> Enum.flat_map(& &1.image_sources)
      |> Enum.map(&CardImage.source_hash/1)

    thumbnails = Storage.mirrored_image_urls(hashes, :thumbnail)
    details = Storage.mirrored_image_urls(hashes, :detail)

    show = fn row ->
      card = Map.fetch!(cards, row.card.id)

      hash =
        card.image_sources
        |> Enum.map(&CardImage.source_hash/1)
        |> Enum.find(&Map.has_key?(thumbnails, &1))

      Map.merge(row, %{
        card: card,
        image: hash && thumbnails[hash],
        image_large: hash && details[hash]
      })
    end

    fn
      %{printings: printings} = row -> %{show.(row) | printings: Enum.map(printings, show)}
      row -> show.(row)
    end
  end

  defp priced_on do
    from(p in CardPrice, select: max(p.priced_on)) |> Repo.one()
  end
end
