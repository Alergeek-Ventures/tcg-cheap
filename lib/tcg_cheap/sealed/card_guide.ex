defmodule TcgCheap.Sealed.CardGuide do
  @moduledoc "Bounded, local read models for public English single-card pages."
  import Ecto.Query
  alias TcgCheap.{Repo, Sealed, Storage}

  alias TcgCheap.Sealed.{
    CardImage,
    CardOffer,
    CardPrice,
    CardReference,
    Catalogue,
    Guide,
    TcgdexCard,
    TcgdexSet
  }

  # ±15% is effectively the same delivered price; graded and special prints
  # never inherit a raw normal/reverse reference.
  @similar_low Decimal.new("0.85")
  @similar_high Decimal.new("1.15")

  def slug(card, collisions \\ MapSet.new()) do
    name = Catalogue.slug(card.name, 0) |> String.replace_suffix("-0", "")
    base = "#{card.number}-#{name}"
    if MapSet.member?(collisions, card.id), do: base <> "-" <> card.tcgdex_id, else: base
  end

  def path(card, expansion_name, expansion_id, collisions \\ nil),
    do:
      "/rozszerzenia/#{Catalogue.slug(expansion_name, expansion_id)}/karty/#{slug(card, collisions || collision_ids())}"

  def expansion_names do
    Guide.expansion_names()
  end

  def find(expansion_slug, card_slug) do
    with [_, id] <- Regex.run(~r/-(\d+)\z/, expansion_slug),
         id = String.to_integer(id),
         name when is_binary(name) <- Map.get(expansion_names(), id) do
      cards =
        from(c in TcgdexCard,
          join: s in TcgdexSet,
          on: c.tcgdex_set_id == s.id,
          where: s.language == "en" and s.cardmarket_expansion_id == ^id
        )
        |> Repo.all()
        |> Ash.load!([:tcgdex_set, :cardmarket_price])

      collisions = collision_ids([id])
      exact = Enum.find(cards, &(slug(&1, collisions) == card_slug))

      identified =
        Enum.find(cards, fn card ->
          String.starts_with?(card_slug, card.number <> "-") and
            String.ends_with?(card_slug, "-" <> card.tcgdex_id)
        end)

      legacy = Enum.filter(cards, &String.starts_with?(card_slug, &1.number <> "-"))

      card =
        exact || identified ||
          case legacy do
            [only] -> only
            _ -> nil
          end

      if card, do: {:ok, card, name, path(card, name, id, collisions)}, else: :error
    else
      _ -> :error
    end
  end

  # Collisions use the stable TCGdex id, including subset, only where necessary.
  # One bounded catalogue query per read model, never one query per link.
  defp collision_ids(ids \\ nil, numbers \\ nil) do
    query =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        where: s.language == "en",
        select: {s.cardmarket_expansion_id, c}
      )

    query = if ids, do: where(query, [_, s], s.cardmarket_expansion_id in ^ids), else: query

    query = if numbers, do: where(query, [c], c.number in ^numbers), else: query

    query
    |> Repo.all()
    |> Enum.group_by(fn {id, c} -> {id, slug(c)} end)
    |> Enum.flat_map(fn {_key, rows} ->
      if length(rows) > 1, do: Enum.map(rows, fn {_, c} -> c.id end), else: []
    end)
    |> MapSet.new()
  end

  @page_size 30

  @doc "Current Polish shop cards, searched, counted and paged in SQL."
  def browse(filters, offset) do
    query = browse_query(filters)
    count = Repo.aggregate(query, :count)
    search = String.downcase(filters.query)
    relevance = relevance(filters.query)

    order = [
      desc: dynamic([_, s], fragment("lower(?) = ?", s.name, ^search)),
      desc: dynamic([_, _, o], not is_nil(o.price)),
      desc: dynamic([c], fragment("lower(?) = ?", c.name, ^search)),
      desc: dynamic([c], fragment("ltrim(?, '0') = ltrim(?, '0')", c.number, ^search)),
      desc: relevance,
      desc_nulls_last: dynamic([_, s], s.released_on),
      asc: dynamic([c], c.number),
      asc: dynamic([c], c.id)
    ]

    order =
      if filters.query == "",
        do: [desc_nulls_last: dynamic([_, _, _, p], p.trend)] ++ order,
        else: order

    rows =
      from([c, s, o, p] in query,
        order_by: ^order,
        offset: ^offset,
        limit: ^(@page_size + 1),
        select: %{card: c, set: s, price: o.price, trend: p.trend}
      )
      |> Repo.all()

    page = Enum.take(rows, @page_size)
    ids = Enum.map(page, & &1.set.cardmarket_expansion_id)
    numbers = Enum.map(page, & &1.card.number)
    collisions = collision_ids(ids, numbers)
    names = expansion_names()
    sources = Enum.map(page, &CardImage.single_source_url(&1.set, &1.card.number))

    mirrored =
      sources
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&CardImage.source_hash/1)
      |> Storage.list_mirrored_remote_images!()
      |> MapSet.new(& &1.id)

    rate = Guide.eur_pln(Date.utc_today())

    results =
      Enum.map(page, fn row ->
        name = Map.fetch!(names, row.set.cardmarket_expansion_id)
        source = CardImage.single_source_url(row.set, row.card.number)

        image =
          if source && MapSet.member?(mirrored, CardImage.source_hash(source)),
            do: CardImage.thumbnail_url(source)

        Map.merge(row, %{
          cardmarket_trend_pln: Guide.to_pln(row.trend, rate),
          expansion_name: name,
          path: path(row.card, name, row.set.cardmarket_expansion_id, collisions),
          image: image
        })
      end)

    {results, length(rows) > @page_size, count}
  end

  # Exact collector numbers and name/set words outrank incidental substrings,
  # including when the query combines several identity fields.
  defp relevance(query) do
    query
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce(dynamic(fragment("0 + 0")), fn word, score ->
      number = String.trim_leading(word, "0")

      dynamic(
        [c, s],
        ^score +
          fragment(
            "CASE WHEN lower(?) = ? OR ltrim(?, '0') = ? OR lower(?) = ? OR ? = ANY(regexp_split_to_array(lower(?), '[^[:alnum:]]+')) THEN 1 ELSE 0 END",
            c.name,
            ^word,
            c.number,
            ^number,
            s.abbreviation,
            ^word,
            ^word,
            c.name
          )
      )
    end)
  end

  defp browse_query(filters) do
    offers =
      from(o in current_query(),
        where: is_nil(o.grading),
        group_by: o.card_id,
        select: %{card_id: o.card_id, price: min(o.price) |> filter(o.in_stock)}
      )

    query =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        join: o in subquery(offers),
        on: o.card_id == c.id,
        left_join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id)
      )

    query =
      query
      |> stock_filter(Map.get(filters, :stock))
      |> expansion_filter(Map.get(filters, :expansion))

    # Empty discovery lists only cards that can be bought now.
    query = if filters.query == "", do: where(query, [_, _, o], not is_nil(o.price)), else: query

    filters.query
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce(query, fn word, query ->
      escaped = String.replace(word, ~r/[\\%_]/, fn char -> "\\" <> char end)
      pattern = "%" <> escaped <> "%"
      number = String.trim_leading(word, "0")

      where(
        query,
        [c, s],
        ilike(c.name, ^pattern) or ilike(c.number, ^pattern) or
          fragment("ltrim(?, '0') = ?", c.number, ^number) or
          ilike(s.name, ^pattern) or ilike(s.abbreviation, ^pattern) or
          ilike(s.tcgdex_id, ^pattern)
      )
    end)
  end

  @doc """
  The expansions of the cards a search finds, for the list's expansion filter:
  newest first, each with its logo and the number of its cards in stock; the
  chosen one stays listed when the search leaves none of it.
  """
  def expansion_facets(filters) do
    logos = Guide.expansion_logos()
    # Named per expansion as the product list names it, not after one of its
    # TCGdex sets ("Brilliant Stars", not "Brilliant Stars Trainer Gallery").
    names = Guide.expansion_names()

    counts =
      from([c, s] in browse_query(%{filters | expansion: nil} |> Map.put(:stock, :in)),
        group_by: s.cardmarket_expansion_id,
        order_by: [desc_nulls_last: max(s.released_on)],
        select: %{id: s.cardmarket_expansion_id, count: count(c.id, :distinct)}
      )
      |> Repo.all()

    chosen =
      if filters.expansion && !Enum.any?(counts, &(&1.id == filters.expansion)),
        do: [%{id: filters.expansion, count: 0}],
        else: []

    for expansion <- counts ++ chosen,
        name = Map.get(names, expansion.id),
        do:
          Map.merge(expansion, %{name: name, region: :en, logo_url: Map.get(logos, expansion.id)})
  end

  defp stock_filter(query, :in), do: where(query, [_, _, o], not is_nil(o.price))
  defp stock_filter(query, :out), do: where(query, [_, _, o], is_nil(o.price))
  defp stock_filter(query, nil), do: query

  defp expansion_filter(query, nil), do: query
  defp expansion_filter(query, id), do: where(query, [_, s], s.cardmarket_expansion_id == ^id)

  # Shipping dominates when trend is below the shipping component of the
  # backend reference. CardReference alone owns shipping thresholds/amounts.
  def shipping_dominates?(price, variant) do
    trend = price && if(variant == :reverse, do: price.trend_holo, else: price.trend)
    delivered = variant != :special && CardReference.delivered_eur(trend)
    !!(delivered && Decimal.lt?(trend, Decimal.sub(delivered, trend)))
  end

  def card_verdict(nil, _, _, _), do: :unavailable

  def card_verdict(offer, card, variant, rate) do
    reference = CardReference.pln(card.cardmarket_price, variant, rate)
    normal = verdict(offer, reference)

    cond do
      "firstEdition" in card.variants ->
        :unknown

      # "Pennies in both places" requires a cheap Polish price too: at most
      # 3 zł and no more than the delivered reference. Never mask an expensive offer.
      normal in [:cheaper, :similar] and Decimal.lte?(offer.price, 3) and
        Decimal.lte?(offer.price, reference) and
          shipping_dominates?(card.cardmarket_price, variant) ->
        :pennies

      true ->
        normal
    end
  end

  def page(card, name, path) do
    rate = Guide.eur_pln(Date.utc_today())
    offers = current_offers([card.id])

    variants =
      Enum.uniq(
        [:normal | Enum.map(offers, & &1.variant)] ++
          if("reverse" in card.variants, do: [:reverse], else: [])
      )

    answers =
      variants
      |> Enum.sort_by(&Enum.find_index([:normal, :reverse, :special], fn v -> v == &1 end))
      |> Enum.map(fn variant ->
        cheapest =
          offers
          |> Enum.filter(&(&1.in_stock and is_nil(&1.grading) and &1.variant == variant))
          |> List.first()

        reference = CardReference.pln(card.cardmarket_price, variant, rate)

        %{
          variant: variant,
          cheapest: cheapest,
          reference: reference,
          verdict: card_verdict(cheapest, card, variant, rate)
        }
      end)

    %{
      card: card,
      expansion_name: name,
      path: path,
      rate: rate,
      answers: answers,
      offers: offers,
      image: image(card),
      price: card.cardmarket_price
    }
  end

  defp image(card) do
    source = CardImage.single_source_url(card.tcgdex_set, card.number)

    if source &&
         Storage.list_mirrored_remote_images!([CardImage.source_hash(source)]) != [],
       do: source
  end

  def verdict(nil, _), do: :unavailable
  def verdict(_, nil), do: :unknown

  def verdict(offer, reference) do
    ratio = Decimal.div(offer.price, reference)

    cond do
      Decimal.lt?(ratio, @similar_low) -> :cheaper
      Decimal.gt?(ratio, @similar_high) -> :expensive
      true -> :similar
    end
  end

  # Keep freshness (including successful empty fetches) owned by Sealed.
  # The OR predicate is bounded by shop count, and card_id remains in SQL.
  @doc false
  def current_query do
    since = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
    latest = Sealed.latest_card_fetches!(since)

    current =
      Enum.reduce(latest, dynamic(false), fn {shop, seen}, acc ->
        dynamic([o], ^acc or (o.shop == ^shop and o.last_seen_at == ^seen))
      end)

    from(o in CardOffer,
      where: ^current,
      where: is_nil(o.language) or o.language == "en"
    )
  end

  def current_offers(card_ids) do
    from(o in current_query(),
      where: o.card_id in ^card_ids,
      order_by: [desc: o.in_stock, asc: o.price, asc: o.shop, asc: o.id]
    )
    |> Repo.all()
  end

  def enrich(cards, sets) do
    offers =
      current_offers(Enum.map(cards, & &1.id))
      |> Enum.filter(&(&1.in_stock and is_nil(&1.grading)))
      |> Enum.group_by(& &1.card_id)

    names = expansion_names()
    collisions = collision_ids(Enum.map(sets, & &1.cardmarket_expansion_id))
    sets = Map.new(sets, &{&1.id, &1})
    rate = Guide.eur_pln(Date.utc_today())

    Enum.map(cards, fn card ->
      set = Map.fetch!(sets, card.tcgdex_set_id)
      rows = Map.get(offers, card.id, [])
      name = Map.get(names, set.cardmarket_expansion_id)

      card
      |> Map.put(:polish_price, if(rows != [], do: hd(rows).price))
      |> Map.put(:polish_shop, if(rows != [], do: hd(rows).shop))
      # Only a normal print compares with the Cardmarket trend, as on the card's page.
      |> Map.put(:normal_offer, Enum.find(rows, &(&1.variant == :normal)))
      |> Map.put(:image_source, CardImage.single_source_url(set, card.number))
      |> Map.put(
        :cardmarket_trend_pln,
        Guide.to_pln(card.cardmarket_price && card.cardmarket_price.trend, rate)
      )
      |> Map.put(
        :cardmarket_delivered_pln,
        CardReference.pln(card.cardmarket_price, :normal, rate)
      )
      |> Map.put(:expansion_name, name)
      |> Map.put(
        :public_path,
        if(name, do: path(card, name, set.cardmarket_expansion_id, collisions))
      )
    end)
  end

  @doc "Every card in stock in a Polish shop, enriched as by `enrich/2`."
  def in_stock do
    rows =
      from([c, s, _o, p] in browse_query(%{query: "", expansion: nil}), select: {c, s, p})
      |> Repo.all()

    rows
    |> Enum.map(fn {card, _set, price} -> %{card | cardmarket_price: price} end)
    |> enrich(rows |> Enum.map(&elem(&1, 1)) |> Enum.uniq_by(& &1.id))
  end

  @doc "How many cards the English sets of named expansions hold."
  def catalogue_size do
    from(c in TcgdexCard,
      join: s in TcgdexSet,
      on: c.tcgdex_set_id == s.id,
      where: s.language == "en" and not is_nil(s.cardmarket_expansion_id)
    )
    |> Repo.aggregate(:count)
  end

  @doc "How many shops have an ungraded card in stock."
  def shop_count do
    from(o in current_query(),
      where: o.in_stock and is_nil(o.grading),
      select: count(o.shop, :distinct)
    )
    |> Repo.one()
  end

  @doc "The lower available card price, excluding delivery."
  def price(card) do
    case {Map.get(card, :polish_price), Map.get(card, :cardmarket_trend_pln)} do
      {nil, trend} -> trend
      {polish, nil} -> polish
      {polish, trend} -> Decimal.min(polish, trend)
    end
  end

  @doc "The source of the chosen price; Polish shops win ties."
  def price_source(card) do
    polish = Map.get(card, :polish_price)
    trend = Map.get(card, :cardmarket_trend_pln)

    if polish && (is_nil(trend) || Decimal.lte?(polish, trend)),
      do: {:shop, card.polish_shop},
      else: :cardmarket
  end

  @doc "The mirrored source image of each card by id (nil when not mirrored yet), in one query."
  def images(cards) do
    mirrored =
      cards
      |> Enum.map(& &1.image_source)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&CardImage.source_hash/1)
      |> Storage.list_mirrored_remote_images!()
      |> MapSet.new(& &1.id)

    Map.new(cards, fn %{image_source: source} = card ->
      {card.id, if(source && MapSet.member?(mirrored, CardImage.source_hash(source)), do: source)}
    end)
  end

  # Only cards whose page has an answer: an in-stock, ungraded current offer,
  # the same rule as page/3. The rest stay reachable but noindex.
  def sitemap_paths do
    cards =
      from(c in TcgdexCard,
        join: o in subquery(current_query()),
        on: o.card_id == c.id and o.in_stock and is_nil(o.grading),
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id),
        distinct: true,
        select: {c, s.cardmarket_expansion_id}
      )
      |> Repo.all()

    names = expansion_names()
    collisions = collision_ids()
    for {card, id} <- cards, name = Map.get(names, id), name, do: path(card, name, id, collisions)
  end
end
