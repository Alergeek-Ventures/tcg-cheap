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
    Shops,
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

  @doc """
  The number as printed at the bottom of the card, "014/159": what people read
  off the card and type into a search. Needs the card's `tcgdex_set`. Black
  Star promos and the basic energy sets print no set total, and subset cards
  ("GG43", "TG05") count against their subset, not the set, so those keep the
  bare number rather than show a total the card doesn't carry.
  """
  def printed_number(%{number: number, tcgdex_set: %{official_card_count: count, name: set_name}})
      when is_integer(count) and count > 0 do
    if number =~ ~r/\A\d+\z/ and not (set_name =~ ~r/Promo|Energy/),
      do: "#{number}/#{count}",
      else: number
  end

  def printed_number(card), do: card.number

  def path(card, expansion_name, expansion_id, collisions \\ nil),
    do:
      "/rozszerzenia/#{Catalogue.slug(expansion_name, expansion_id)}/karty/#{slug(card, collisions || collision_ids())}"

  def expansion_names(required_ids \\ []) do
    Guide.expansion_names(required_ids)
  end

  def find(expansion_slug, card_slug) do
    with [_, id] <- Regex.run(~r/-(\d+)\z/, expansion_slug),
         id = String.to_integer(id),
         name when is_binary(name) <- Map.get(expansion_names([id]), id) do
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
  # Empty discovery only includes in-stock cards, so its other section is
  # necessarily empty. Do not run the catalogue query again to prove that.
  def browse(%{query: "", stock: :out}, _offset), do: {[], false, 0}

  def browse(filters, offset) do
    query = browse_query(filters)
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

    # The sort already reads every matching card, so the window counts them
    # in the same pass.
    rows =
      from([c, s, o, p] in query,
        order_by: ^order,
        offset: ^offset,
        limit: ^(@page_size + 1),
        select: %{card: c, set: s, price: o.price, cardmarket: p, count: over(count())}
      )
      |> Repo.all()

    count =
      case rows do
        [%{count: count} | _] -> count
        [] -> 0
      end

    page = rows |> Enum.take(@page_size) |> Enum.map(&Map.delete(&1, :count))
    ids = Enum.map(page, & &1.set.cardmarket_expansion_id)
    numbers = Enum.map(page, & &1.card.number)
    collisions = collision_ids(ids, numbers)
    names = expansion_names(ids)

    mirrored =
      page
      |> Enum.flat_map(&CardImage.single_sources(&1.set, &1.card.number))
      |> Enum.map(&CardImage.source_hash/1)
      |> Storage.mirrored_image_urls(:thumbnail)

    rate = Guide.eur_pln(Date.utc_today())
    offers = in_stock_prices(Enum.map(page, & &1.card.id))

    results =
      Enum.map(page, fn %{cardmarket: price} = row ->
        name = Map.fetch!(names, row.set.cardmarket_expansion_id)
        card = %{row.card | cardmarket_price: price}
        {variant, offer} = primary_offer(Map.get(offers, card.id, []))

        image =
          row.set
          |> CardImage.single_sources(card.number)
          |> Enum.find_value(&Map.get(mirrored, CardImage.source_hash(&1)))

        row
        |> Map.delete(:cardmarket)
        |> Map.merge(%{
          card: card,
          offer: offer,
          verdict: card_verdict(offer, card, variant, rate),
          cardmarket_trend_pln: Guide.to_pln(price && price.trend, rate),
          expansion_name: name,
          path: path(card, name, row.set.cardmarket_expansion_id, collisions),
          image: image
        })
      end)

    {results, length(rows) > @page_size, count}
  end

  # The offer the card's page answers with (`page/3`): the cheapest in-stock
  # offer of its first variant in stock, normal before reverse before special.
  defp primary_offer(offers) do
    Enum.find_value([:normal, :reverse, :special], {nil, nil}, fn variant ->
      offer = Enum.find(offers, &(&1.variant == variant))
      offer && {variant, offer}
    end)
  end

  # Other printings a card's page offers when nobody stocks it.
  @versions 4
  # The best offer first, as the card list judges it.
  @verdict_ranks %{cheaper: 0, similar: 1, pennies: 1, unknown: 2, expensive: 3}
  # As for sealed deals: this far under its reference, an offer is more often
  # matched to the wrong card than a real bargain.
  @suspect_ratio Decimal.new("0.6")

  @doc """
  Other cards of a card's name in stock now (its other printings: Illustration
  Rare, Special Illustration Rare, reprints in other sets), as `browse/2` rows,
  at most #{@versions}: its own set's first, then the best offers, by verdict
  and by how far the price is under the delivered Cardmarket reference the
  verdict uses.
  """
  def in_stock_versions(card) do
    name = String.downcase(card.name)
    rate = Guide.eur_pln(Date.utc_today())

    # Exact names come first in a search, so the first page holds them; the
    # card itself is out of stock, so `stock: :in` leaves it out.
    {rows, _more?, _count} = browse(%{query: card.name, stock: :in}, 0)

    rows
    |> Enum.filter(&(&1.offer != nil and String.downcase(&1.card.name) == name))
    |> Enum.sort_by(&version_rank(&1, card.tcgdex_set_id, rate))
    |> Enum.take(@versions)
  end

  # A ratio under `@suspect_ratio` ranks as unjudged, after the unjudged
  # honest ones, as a suspect sealed offer does; a missing ratio (nil) sorts
  # after any number.
  defp version_rank(%{card: printing, set: set, offer: offer, verdict: verdict}, set_id, rate) do
    reference = CardReference.pln(printing.cardmarket_price, offer.variant, rate)

    ratio =
      if reference && Decimal.positive?(reference), do: Decimal.div(offer.price, reference)

    suspect? = ratio != nil and Decimal.lt?(ratio, @suspect_ratio)
    rank = if suspect?, do: @verdict_ranks.unknown, else: Map.fetch!(@verdict_ranks, verdict)

    {set.id != set_id, rank, suspect?, ratio && Decimal.to_float(ratio)}
  end

  @doc "How many Polish shop cards a search finds, in stock or not, in an optional expansion."
  def count(query, expansion),
    do: Repo.aggregate(browse_query(%{query: query, expansion: expansion}), :count)

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

  # A search or an expansion picks its cards first, through the cards'
  # indexes, and only their current offers are grouped; a search of a few
  # hundred cards never groups the offers of all of them.
  defp browse_query(filters) do
    words = String.split(filters.query, ~r/\s+/, trim: true)
    expansion = Map.get(filters, :expansion)

    query =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        join: o in subquery(card_offers(words, expansion)),
        on: o.card_id == c.id,
        left_join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id)
      )
      |> stock_filter(Map.get(filters, :stock))

    # Empty discovery lists only cards that can be bought now.
    if filters.query == "", do: where(query, [_, _, o], not is_nil(o.price)), else: query
  end

  # Per card, the lowest in-stock compared price of its current, ungraded offers.
  defp card_offers(words, expansion) do
    offers =
      from(o in subquery(compared_query()),
        where: is_nil(o.grading),
        group_by: o.card_id,
        select: %{card_id: o.card_id, price: min(o.price) |> filter(o.in_stock)}
      )

    # As an array, the matching cards reach their offers through the offers'
    # card index instead of a scan of every offer.
    if words == [] and is_nil(expansion),
      do: offers,
      else:
        where(
          offers,
          [o],
          fragment("? = ANY(ARRAY(?))", o.card_id, subquery(matching_cards(words, expansion)))
        )
  end

  defp matching_cards(words, expansion) do
    typos = typos(words)

    cards =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        select: c.id
      )
      |> expansion_filter(expansion)

    Enum.reduce(words, cards, fn word, query ->
      if word in typos, do: typo_filter(query, word), else: word_filter(query, word)
    end)
  end

  # "161/131" as printed at the bottom of a card: card 161 of a set of 131.
  # Numbers past the count are its secret cards, so the count names the set.
  defp word_filter(query, word) do
    case Regex.run(~r"\A0*(\d{1,4})/0*(\d{1,4})\z", word) do
      [_, number, count] -> printed_number_filter(query, number, String.to_integer(count))
      nil -> text_filter(query, word)
    end
  end

  defp printed_number_filter(query, number, count) do
    sets = from(s in TcgdexSet, where: s.official_card_count == ^count, select: s.id)

    where(
      query,
      [c],
      fragment("ltrim(?, '0') = ?", c.number, ^number) and
        fragment("? = ANY(ARRAY(?))", c.tcgdex_set_id, subquery(sets))
    )
  end

  # Every condition is on the card itself, the set's ones as a list of set
  # ids, so that Postgres combines the cards' trigram and number indexes.
  defp text_filter(query, word) do
    escaped = String.replace(word, ~r/[\\%_]/, fn char -> "\\" <> char end)
    pattern = "%" <> escaped <> "%"
    number = String.trim_leading(word, "0")

    sets =
      from(s in TcgdexSet,
        where:
          ilike(s.name, ^pattern) or ilike(s.abbreviation, ^pattern) or
            ilike(s.tcgdex_id, ^pattern),
        select: s.id
      )

    where(
      query,
      [c],
      ilike(c.name, ^pattern) or ilike(c.number, ^pattern) or
        fragment("ltrim(?, '0') = ?", c.number, ^number) or
        fragment("? = ANY(ARRAY(?))", c.tcgdex_set_id, subquery(sets))
    )
  end

  # A misspelt card name, within one edit of a name word's start ("meoth"
  # finds Meowth), through the names' ParadeDB index.
  defp typo_filter(query, word),
    do: where(query, [c], fragment("? &&& ?::text::pdb.fuzzy(1, t)", c.name, ^word))

  # Shorter words are prefixes still being typed; one edit would match
  # almost anything.
  @min_typo_length 4

  # A letters-only word that no card name and no set name, abbreviation or id
  # holds is a typo. One that some card holds is meant as typed, even when no
  # Polish shop sells that card.
  defp typos(words) do
    case Enum.filter(words, &typo_candidate?/1) do
      [] ->
        []

      candidates ->
        held =
          candidates
          |> Enum.with_index(1)
          |> Enum.map_join(", ", fn {_word, index} ->
            pattern = "'%' || $#{index}::text || '%'"

            "EXISTS (SELECT 1 FROM sealed_tcgdex_cards WHERE name ILIKE #{pattern}) OR " <>
              "EXISTS (SELECT 1 FROM sealed_tcgdex_sets WHERE name ILIKE #{pattern} " <>
              "OR abbreviation ILIKE #{pattern} OR tcgdex_id ILIKE #{pattern})"
          end)

        %{rows: [found]} = Repo.query!("SELECT " <> held, candidates)
        for {word, false} <- Enum.zip(candidates, found), do: word
    end
  end

  defp typo_candidate?(word),
    do: String.length(word) >= @min_typo_length and Regex.match?(~r/\A\p{L}+\z/u, word)

  @doc """
  The expansions of the cards a search finds, for the list's expansion filter:
  newest first, each with its logo and the number of its cards in stock; the
  chosen one stays listed when the search leaves none of it.
  """
  def expansion_facets(filters) do
    logos = Guide.expansion_logos()
    # Named per expansion as the product list names it, not after one of its
    # TCGdex sets ("Brilliant Stars", not "Brilliant Stars Trainer Gallery").
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

    names = expansion_names(Enum.map(counts ++ chosen, & &1.id))

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
    # By the price compared in the answers: a shop abroad's with delivery.
    offers =
      [card.id]
      |> current_offers()
      |> Enum.sort_by(&{not &1.in_stock, Shops.listing_price(&1), &1.shop, &1.id})

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
          |> Shops.compared()
          |> Enum.min_by(& &1.price, Decimal, fn -> nil end)

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
    sources = CardImage.single_sources(card.tcgdex_set, card.number)
    first_mirrored(sources, mirrored_hashes(sources))
  end

  defp mirrored_hashes(sources) do
    sources
    |> Enum.map(&CardImage.source_hash/1)
    |> Storage.list_mirrored_remote_images!()
    |> MapSet.new(& &1.id)
  end

  defp first_mirrored(sources, mirrored),
    do: Enum.find(sources, &MapSet.member?(mirrored, CardImage.source_hash(&1)))

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

  @doc """
  The current offers that count in a card's price, its cheapest shop and the
  shop count, each `price` the compared one (`Shops.compared_price/2`): a
  shop abroad's includes delivery to Poland. Use it as a subquery, and only
  for prices and counts: its other fields lose their types (a UUID comes back
  as raw bytes).
  """
  def compared_query do
    from(o in current_query(), where: o.shop not in ^Shops.listed_only_keys())
    |> select_merge(^%{price: compared_price()})
  end

  # `Shops.compared_price/2` in SQL.
  defp compared_price do
    Enum.reduce(Shops.delivered(), dynamic([o], o.price), fn {shop, {shipping, free_from}}, acc ->
      delivered =
        if free_from,
          do:
            dynamic(
              [o],
              fragment(
                "CASE WHEN ? >= ? THEN ? ELSE ? + ? END",
                o.price,
                type(^free_from, :decimal),
                o.price,
                o.price,
                type(^shipping, :decimal)
              )
            ),
          else: dynamic([o], o.price + type(^shipping, :decimal))

      dynamic([o], fragment("CASE WHEN ? = ? THEN ? ELSE ? END", o.shop, ^shop, ^delivered, ^acc))
    end)
  end

  def current_offers(card_ids) do
    from(o in current_query(),
      where: o.card_id in ^card_ids,
      order_by: [desc: o.in_stock, asc: o.price, asc: o.shop, asc: o.id]
    )
    |> Repo.all()
  end

  def enrich(cards, sets) do
    offers = in_stock_prices(Enum.map(cards, & &1.id))

    names = expansion_names(Enum.map(sets, & &1.cardmarket_expansion_id))
    collisions = collision_ids(Enum.map(sets, & &1.cardmarket_expansion_id))
    sets = Map.new(sets, &{&1.id, &1})
    rate = Guide.eur_pln(Date.utc_today())

    Enum.map(cards, fn card ->
      set = Map.fetch!(sets, card.tcgdex_set_id)
      rows = Map.get(offers, card.id, [])
      name = Map.get(names, set.cardmarket_expansion_id)

      card
      |> with_prices(rows, rate)
      |> with_public_identity(set, name, collisions)
    end)
  end

  defp in_stock_prices(card_ids) do
    from(o in current_query(),
      where: o.card_id in ^card_ids and o.in_stock and is_nil(o.grading),
      select: map(o, [:id, :card_id, :price, :shop, :variant])
    )
    |> Repo.all()
    |> Shops.compared()
    |> Enum.sort_by(&{Decimal.to_float(&1.price), &1.shop, &1.id})
    |> Enum.group_by(& &1.card_id)
  end

  defp with_prices(card, offers, rate) do
    card
    |> Map.put(:polish_price, if(offers != [], do: hd(offers).price))
    |> Map.put(:polish_shop, if(offers != [], do: hd(offers).shop))
    # Only a normal print compares with the Cardmarket trend, as on the card's page.
    |> Map.put(:normal_offer, Enum.find(offers, &(&1.variant == :normal)))
    |> Map.put(
      :cardmarket_trend_pln,
      Guide.to_pln(card.cardmarket_price && card.cardmarket_price.trend, rate)
    )
    |> Map.put(:cardmarket_delivered_pln, CardReference.pln(card.cardmarket_price, :normal, rate))
  end

  defp with_public_identity(card, set, name, collisions) do
    card
    |> Map.put(:image_sources, CardImage.single_sources(set, card.number))
    |> Map.put(:expansion_name, name)
    |> Map.put(
      :public_path,
      if(name, do: path(card, name, set.cardmarket_expansion_id, collisions))
    )
  end

  @doc "Resolves the public identity of the one card selected for the market banner."
  def with_public_identity(card) do
    set = card.tcgdex_set
    name = Map.get(expansion_names([set.cardmarket_expansion_id]), set.cardmarket_expansion_id)
    collisions = collision_ids([set.cardmarket_expansion_id], [card.number])
    with_public_identity(card, set, name, collisions)
  end

  @doc "In-stock card prices for the market banner, without building thousands of links and image URLs."
  def market_cards do
    rows =
      from([c, s, _o, p] in browse_query(%{query: "", expansion: nil}),
        select: {
          struct(c, [:id, :tcgdex_id, :tcgdex_set_id, :name, :number, :variants]),
          struct(s, [
            :id,
            :tcgdex_id,
            :cardmarket_expansion_id,
            :card_images_url,
            :abbreviation,
            :cards_source_url
          ]),
          struct(p, [:cardmarket_id, :trend])
        }
      )
      |> Repo.all()

    offers = in_stock_prices(Enum.map(rows, fn {card, _, _} -> card.id end))

    rate = Guide.eur_pln(Date.utc_today())

    Enum.map(rows, fn {card, set, price} ->
      %{card | cardmarket_price: price, tcgdex_set: set}
      |> with_prices(Map.get(offers, card.id, []), rate)
    end)
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

  @doc "The Cardmarket product ids of the cards in our catalogue."
  def cardmarket_ids do
    from(c in TcgdexCard,
      where: not is_nil(c.cardmarket_id),
      distinct: true,
      select: c.cardmarket_id
    )
    |> Repo.all()
  end

  @doc "How many shops counted in card prices have an ungraded card in stock."
  def shop_count do
    from(o in subquery(compared_query()),
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
    mirrored = cards |> Enum.flat_map(& &1.image_sources) |> mirrored_hashes()
    Map.new(cards, &{&1.id, first_mirrored(&1.image_sources, mirrored)})
  end

  @doc """
  How many of an expansion's English cards have an answer on their page (an
  in-stock, ungraded current offer, as in `sitemap_cards/0`).
  """
  @spec in_stock_count(integer()) :: non_neg_integer()
  def in_stock_count(expansion_id) do
    from(c in TcgdexCard,
      join: o in subquery(compared_query()),
      on: o.card_id == c.id and o.in_stock and is_nil(o.grading),
      join: s in TcgdexSet,
      on: c.tcgdex_set_id == s.id,
      where: s.language == "en" and s.cardmarket_expansion_id == ^expansion_id,
      select: count(c.id, :distinct)
    )
    |> Repo.one()
  end

  # Only cards whose page has an answer: an in-stock, ungraded current offer,
  # the same rule as page/3. The rest stay reachable but noindex. Each comes
  # with its expansion, whose set page lists it, and its Cardmarket product
  # (nil when unknown), whose price history dates its page.
  def sitemap_cards do
    cards =
      from(c in TcgdexCard,
        join: o in subquery(compared_query()),
        on: o.card_id == c.id and o.in_stock and is_nil(o.grading),
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id),
        distinct: true,
        select: {c, s.cardmarket_expansion_id}
      )
      |> Repo.all()

    names = expansion_names(Enum.map(cards, &elem(&1, 1)))
    collisions = collision_ids()

    for {card, id} <- cards,
        name = Map.get(names, id),
        name,
        do: {id, name, path(card, name, id, collisions), card.cardmarket_id}
  end
end
