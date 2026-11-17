defmodule TcgCheap.Cards.Guide do
  @moduledoc "Bounded, local read models for public English single-card pages."
  import Ecto.Query
  alias TcgCheap.Cards
  alias TcgCheap.Cards.{Card, Image, Offer, Price, Reference, Set}
  alias TcgCheap.{Repo, Storage}

  alias TcgCheap.Sealed.{Cache, Catalogue, ExpansionLogo, Expansions, Market, PriceGuide, Shops}

  def slug(card, collisions \\ MapSet.new()) do
    name = Catalogue.slug(card.name, 0) |> String.replace_suffix("-0", "")
    base = "#{card.number}-#{name}"
    if MapSet.member?(collisions, card.id), do: base <> "-" <> card.tcgdex_id, else: base
  end

  @doc """
  The number as printed at the bottom of the card, "014/159": what people read
  off the card and type into a search. Needs the card's `tcgdex_set`. Black
  Star promos and the basic energy sets print no set total, subset cards
  ("GG43", "TG05") count against their subset, not the set, and Classic
  Collection reprints may carry their original set's number, so those keep the
  bare number rather than show a total the card may not carry.
  """
  def printed_number(%{number: number, tcgdex_set: %{official_card_count: count, name: set_name}})
      when is_integer(count) and count > 0 do
    if number =~ ~r/\A\d+\z/ and not ((set_name || "") =~ ~r/Promo|Energy|Classic Collection/),
      do: "#{number}/#{count}",
      else: number
  end

  def printed_number(card), do: card.number

  def path(card, expansion_name, expansion_id, collisions \\ nil),
    do:
      "/rozszerzenia/#{Catalogue.slug(expansion_name, expansion_id)}/karty/#{slug(card, collisions || collision_ids())}"

  def find(expansion_slug, card_slug) do
    with [_, id] <- Regex.run(~r/-(\d+)\z/, expansion_slug),
         id = String.to_integer(id),
         name when is_binary(name) <- Map.get(Expansions.names([id]), id) do
      # Every slug form starts with "<number>-", so only cards whose number
      # prefixes the slug can match, and only they can collide with it. The
      # slug is the prefix-tested argument, so the number needs no escaping.
      cards =
        from(c in Card,
          join: s in Set,
          on: c.tcgdex_set_id == s.id,
          where: s.language == "en" and s.cardmarket_expansion_id == ^id,
          where: fragment("starts_with(?, ? || '-')", ^card_slug, c.number)
        )
        |> Repo.all()
        |> Ash.load!([:tcgdex_set, :cardmarket_price])

      collisions = collision_ids([id], Enum.map(cards, & &1.number))
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
      from(c in Card,
        join: s in Set,
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

  @doc """
  The cards the market's shops sell (`compared_query/1`), searched, counted
  and paged in SQL, each with its cheapest offer and verdict in the market's
  currency. A market where no shop sells singles (`Shops.singles?/1`) lists
  every card of the catalogue instead, with its Cardmarket trend alone.
  """
  # Empty discovery only includes in-stock cards, so its other section is
  # necessarily empty. Do not run the catalogue query again to prove that.
  def browse(%{query: "", stock: :out}, _offset, _market), do: {[], false, 0}

  def browse(filters, offset, %Market{} = market) do
    query = browse_query(filters, market)
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
    names = Expansions.names(ids)

    mirrored =
      page
      |> Enum.flat_map(&Image.single_sources(&1.set, &1.card.number))
      |> Enum.map(&Image.source_hash/1)
      |> Storage.mirrored_image_urls(:thumbnail)

    context = context(market)
    offers = in_stock_prices(Enum.map(page, & &1.card.id), market)

    results =
      Enum.map(page, fn %{cardmarket: price} = row ->
        name = Map.fetch!(names, row.set.cardmarket_expansion_id)
        card = %{row.card | cardmarket_price: price}
        {variant, variant_offers} = primary_offers(Map.get(offers, card.id, []))
        offer = List.first(variant_offers)

        image =
          row.set
          |> Image.single_sources(card.number)
          |> Enum.find_value(&Map.get(mirrored, Image.source_hash(&1)))

        row
        |> Map.delete(:cardmarket)
        |> Map.merge(%{
          card: card,
          offer: offer,
          verdict: card_verdict(variant_offers, card, variant, context),
          cardmarket_trend: Market.in_market(price && price.trend, context.rate, market),
          expansion_name: name,
          path: path(card, name, row.set.cardmarket_expansion_id, collisions),
          image: image
        })
      end)

    {results, length(rows) > @page_size, count}
  end

  # The offers the card's page answers with (`page/3`): those of its first
  # variant in stock, normal before reverse before special, cheapest first.
  defp primary_offers(offers) do
    Enum.find_value([:normal, :reverse, :special], {nil, []}, fn variant ->
      case Enum.filter(offers, &(&1.variant == variant)) do
        [] -> nil
        in_variant -> {variant, in_variant}
      end
    end)
  end

  # Other printings a card's page offers when nobody stocks it.
  @versions 4
  # The best offer first, as the card list judges it.
  @verdict_ranks %{cheaper: 0, similar: 1, pennies: 1, unknown: 2, few_shops: 2, expensive: 3}
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
  def in_stock_versions(card, %Market{} = market) do
    name = String.downcase(card.name)
    context = context(market)

    # Exact names come first in a search, so the first page holds them; the
    # card itself is out of stock, so `stock: :in` leaves it out.
    {rows, _more?, _count} = browse(%{query: card.name, stock: :in}, 0, market)

    rows
    |> Enum.filter(&(&1.offer != nil and String.downcase(&1.card.name) == name))
    |> Enum.sort_by(&version_rank(&1, card.tcgdex_set_id, context))
    |> Enum.take(@versions)
  end

  # A ratio under `@suspect_ratio` ranks as unjudged, after the unjudged
  # honest ones, as a suspect sealed offer does; a missing ratio (nil) sorts
  # after any number.
  defp version_rank(
         %{card: printing, set: set, offer: offer, verdict: verdict},
         set_id,
         context
       ) do
    reference = reference(printing.cardmarket_price, offer.variant, context)

    ratio =
      if reference && Decimal.positive?(reference), do: Decimal.div(offer.price, reference)

    suspect? = ratio != nil and Decimal.lt?(ratio, @suspect_ratio)
    rank = if suspect?, do: @verdict_ranks.unknown, else: Map.fetch!(@verdict_ranks, verdict)

    {set.id != set_id, rank, suspect?, ratio && Decimal.to_float(ratio)}
  end

  @doc "How many cards of the market's shops a search finds, in stock or not, in an optional expansion."
  def count(query, expansion, %Market{} = market),
    do: Repo.aggregate(browse_query(%{query: query, expansion: expansion}, market), :count)

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
  defp browse_query(filters, market) do
    words = String.split(filters.query, ~r/\s+/, trim: true)
    expansion = Map.get(filters, :expansion)

    if Shops.singles?(market),
      do: offered_cards(filters, words, expansion, market),
      else: catalogue_cards(filters, words, expansion, market)
  end

  defp offered_cards(filters, words, expansion, market) do
    query =
      from(c in Card,
        join: s in Set,
        on: c.tcgdex_set_id == s.id,
        join: o in subquery(card_offers(words, expansion, market)),
        on: o.card_id == c.id,
        left_join: p in Price,
        on: p.cardmarket_id == c.cardmarket_id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id)
      )
      |> stock_filter(Map.get(filters, :stock))

    # Empty discovery lists only cards that can be bought now.
    if filters.query == "", do: where(query, [_, _, o], not is_nil(o.price)), else: query
  end

  # Without singles shops every card is listed as the list's first part (its
  # "in stock" one) and none as out of stock, so the list and its expansions'
  # counts hold every card of a set. The offers' join stays for the list's
  # shape; it finds none.
  defp catalogue_cards(filters, words, expansion, market) do
    query =
      from(c in Card,
        join: s in Set,
        on: c.tcgdex_set_id == s.id,
        left_join: o in subquery(card_offers([], nil, market)),
        on: o.card_id == c.id,
        left_join: p in Price,
        on: p.cardmarket_id == c.cardmarket_id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id)
      )

    query =
      if words == [] and is_nil(expansion),
        do: query,
        else:
          where(
            query,
            [c],
            fragment("? = ANY(ARRAY(?))", c.id, subquery(matching_cards(words, expansion)))
          )

    if Map.get(filters, :stock) == :out, do: where(query, false), else: query
  end

  # Per card, the lowest in-stock compared price of its current, ungraded offers.
  defp card_offers(words, expansion, market) do
    offers =
      from(o in subquery(compared_query(market)),
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
      from(c in Card,
        join: s in Set,
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
    sets = from(s in Set, where: s.official_card_count == ^count, select: s.id)

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
      from(s in Set,
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
  # shop sells that card.
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
  The market's card list without a search or an expansion: its first page
  (the cards in stock, `browse/3`) and its expansion filter. The same for
  every visitor of the market, so shared for a few minutes; later pages are
  read as they are asked for.
  """
  def discovery(%Market{} = market) do
    Cache.fetch({:card_discovery, market.code}, fn ->
      filters = %{query: "", expansion: nil}

      %{
        available: browse(Map.put(filters, :stock, :in), 0, market),
        expansions: expansion_facets(filters, market)
      }
    end)
  end

  @doc """
  The expansions of the cards a search finds, for the list's expansion filter:
  newest first, each with its logo and the number of its cards in stock; the
  chosen one stays listed when the search leaves none of it.
  """
  def expansion_facets(filters, %Market{} = market) do
    logos = ExpansionLogo.mirrored_urls()
    # Named per expansion as the product list names it, not after one of its
    # TCGdex sets ("Brilliant Stars", not "Brilliant Stars Trainer Gallery").
    counts =
      from([c, s] in browse_query(%{filters | expansion: nil} |> Map.put(:stock, :in), market),
        group_by: s.cardmarket_expansion_id,
        order_by: [desc_nulls_last: max(s.released_on)],
        select: %{id: s.cardmarket_expansion_id, count: count(c.id, :distinct)}
      )
      |> Repo.all()

    chosen =
      if filters.expansion && !Enum.any?(counts, &(&1.id == filters.expansion)),
        do: [%{id: filters.expansion, count: 0}],
        else: []

    names = Expansions.names(Enum.map(counts ++ chosen, & &1.id))

    for expansion <- counts ++ chosen,
        name = Map.get(names, expansion.id),
        do:
          Map.merge(expansion, %{name: name, edition: :en, logo_url: Map.get(logos, expansion.id)})
  end

  defp stock_filter(query, :in), do: where(query, [_, _, o], not is_nil(o.price))
  defp stock_filter(query, :out), do: where(query, [_, _, o], is_nil(o.price))
  defp stock_filter(query, nil), do: query

  defp expansion_filter(query, nil), do: query
  defp expansion_filter(query, id), do: where(query, [_, s], s.cardmarket_expansion_id == ^id)

  # Shipping dominates when trend is below the shipping component of the
  # backend reference. Reference alone owns shipping thresholds/amounts.
  def shipping_dominates?(price, variant) do
    trend = price && if(variant == :reverse, do: price.trend_holo, else: price.trend)
    delivered = variant != :special && Reference.delivered_eur(trend)
    !!(delivered && Decimal.lt?(trend, Decimal.sub(delivered, trend)))
  end

  # "Pennies": a card at most 3 zł, or as much in another market's currency
  # (`Market.pln_limit/3`).
  @pennies_pln Decimal.new(3)

  @doc """
  What a market's card prices are judged with on `today`: the market, the
  euro's rate there (`Market.cardmarket_rate/2`) and the most a card may cost
  to be "pennies" (`judge/4`), nil when a rate is unknown.
  """
  @spec context(Market.t(), Date.t()) :: %{
          market: Market.t(),
          rate: %{rate: Decimal.t(), date: Date.t()} | nil,
          pennies_max: Decimal.t() | nil
        }
  def context(%Market{} = market, %Date{} = today \\ Date.utc_today()),
    do: %{
      market: market,
      rate: Market.cardmarket_rate(market, today),
      pennies_max: pennies_max(market, today)
    }

  defp pennies_max(market, today), do: Market.pln_limit(@pennies_pln, market, today)

  defp reference(price, variant, context),
    do: Reference.in_market(price, variant, context.rate, context.market)

  @doc """
  A card's verdict from its in-stock, ungraded offers of one printing (each
  `price` the compared one in the `context`'s market, `Market.compared/3`),
  cheapest judged. As for sealed products (`PriceGuide.verdict/4`): the
  typical price is the median of the market's own shops' lowest prices,
  needing at least `PriceGuide.min_shops/0` shops, and a good price must also
  be under the delivered Cardmarket reference. Shops abroad, whose delivery
  is dear, stay out of the median. With fewer shops there is no verdict
  (`:few_shops`).
  """
  def card_verdict(offers, card, variant, context),
    do: offers |> judge(card, variant, context) |> elem(0)

  @doc """
  `card_verdict/4` with the market's own shops' `PriceGuide` answer, nil when
  they set no typical price (also for pennies, whose page still shows it).
  """
  def judge([], _card, _variant, _context), do: {:unavailable, nil}

  def judge(offers, card, variant, context) do
    cheapest = Enum.min_by(offers, & &1.price, Decimal)
    reference = reference(card.cardmarket_price, variant, context)

    cond do
      # Special patterns and first editions have no reference of their own.
      variant == :special or "firstEdition" in card.variants ->
        {:unknown, nil}

      pennies?(cheapest, reference, card.cardmarket_price, variant, context.pennies_max) ->
        # Still with the shops' typical price, which the page shows.
        {:pennies, shops_guide(offers, reference, context.market)}

      true ->
        case shops_guide(offers, reference, context.market) do
          nil -> {:few_shops, nil}
          guide -> {typical_verdict(cheapest, guide), guide}
        end
    end
  end

  # "Pennies in both places" requires a cheap shop price too: at most
  # `@pennies_pln` and no more than the delivered reference. Never mask an
  # expensive offer.
  defp pennies?(_cheapest, nil, _price, _variant, _max), do: false
  defp pennies?(_cheapest, _reference, _price, _variant, nil), do: false

  defp pennies?(cheapest, reference, price, variant, max) do
    Decimal.lte?(cheapest.price, max) and Decimal.lte?(cheapest.price, reference) and
      shipping_dominates?(price, variant)
  end

  # The market's own shops' `PriceGuide` answer, nil when too few shops set a typical price.
  defp shops_guide(offers, reference, market) do
    guide =
      offers
      |> Enum.filter(&Shops.domestic?(&1.shop, market))
      |> PriceGuide.verdict(nil, [cardmarket: reference], market)

    if guide.typical_source == :shops, do: guide
  end

  # The cheapest offer may be a shop abroad's, which the median leaves out.
  # The limits are whole units of the currency, so under a few of them one
  # can fall below the typical price itself: the cheapest offer is never
  # dearer than the typical shop, so never expensive.
  defp typical_verdict(cheapest, guide) do
    case PriceGuide.rate(cheapest.price, guide, {:cheaper, :similar, :expensive}) do
      :expensive -> if Decimal.lte?(cheapest.price, guide.typical), do: :similar, else: :expensive
      verdict -> verdict
    end
  end

  @doc """
  A card's page in the market: every current offer of its shops there, each
  `price` the item price in the market's currency, with `compared` (by offer
  id) its compared price, nil for a shop only listed; and an answer per
  variant from the in-stock, ungraded offers.
  """
  def page(card, name, path, %Market{} = market) do
    today = Date.utc_today()
    context = context(market, today)

    # By the price compared in the answers: a shop abroad's with delivery.
    priced =
      [card.id]
      |> current_offers()
      |> Market.priced(market, today)
      |> Enum.sort_by(fn {offer, item, compared} ->
        {not offer.in_stock, Decimal.to_float(compared || item), offer.shop, offer.id}
      end)

    offers = for {offer, item, _compared} <- priced, do: %{offer | price: item}
    compared = for {offer, _item, %Decimal{} = price} <- priced, do: %{offer | price: price}

    variants =
      Enum.uniq(
        [:normal | Enum.map(offers, & &1.variant)] ++
          if("reverse" in card.variants, do: [:reverse], else: [])
      )

    answers =
      variants
      |> Enum.sort_by(&Enum.find_index([:normal, :reverse, :special], fn v -> v == &1 end))
      |> Enum.map(fn variant ->
        in_stock =
          Enum.filter(
            compared,
            &(&1.in_stock and is_nil(&1.grading) and &1.variant == variant)
          )

        {verdict, guide} = judge(in_stock, card, variant, context)

        %{
          variant: variant,
          cheapest: Enum.min_by(in_stock, & &1.price, Decimal, fn -> nil end),
          reference: reference(card.cardmarket_price, variant, context),
          verdict: verdict,
          # What the verdict compares with, when the market's own shops set it.
          typical: guide && guide.typical,
          shops: guide && length(guide.shop_prices)
        }
      end)

    %{
      card: card,
      expansion_name: name,
      path: path,
      market: market,
      rate: context.rate,
      pennies_max: context.pennies_max,
      answers: answers,
      offers: offers,
      compared: Map.new(priced, fn {offer, _item, compared} -> {offer.id, compared} end),
      image: image(card),
      price: card.cardmarket_price
    }
  end

  defp image(card) do
    sources = Image.single_sources(card.tcgdex_set, card.number)
    first_mirrored(sources, mirrored_hashes(sources))
  end

  defp mirrored_hashes(sources) do
    sources
    |> Enum.map(&Image.source_hash/1)
    |> Storage.list_mirrored_remote_images!()
    |> MapSet.new(& &1.id)
  end

  defp first_mirrored(sources, mirrored),
    do: Enum.find(sources, &MapSet.member?(mirrored, Image.source_hash(&1)))

  # Keep freshness (including successful empty fetches) owned by Sealed.
  # The OR predicate is bounded by shop count, and card_id remains in SQL.
  @doc false
  def current_query do
    since = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
    latest = Cards.latest_fetches!(since)

    current =
      Enum.reduce(latest, dynamic(false), fn {shop, seen}, acc ->
        dynamic([o], ^acc or (o.shop == ^shop and o.last_seen_at == ^seen))
      end)

    from(o in Offer,
      where: ^current,
      where: is_nil(o.language) or o.language == "en"
    )
  end

  @doc """
  The current offers that count in the market's card prices, its cheapest
  shop and the shop count, each `price` the compared one in the market's
  currency (`Market.price_terms/2`, `Market.compared/3` in SQL): a shop
  abroad's includes its delivery to the market. Use it as a subquery, and
  only for prices and counts: its other fields lose their types (a UUID
  comes back as raw bytes).
  """
  def compared_query(%Market{} = market) do
    terms = Market.price_terms(market, Date.utc_today())

    from(o in current_query(), where: ^counted(market, Map.keys(terms)))
    |> select_merge(^%{price: compared_price(terms, market)})
  end

  # A shop no longer configured has only Polish offers left, which Poland
  # still counts as its own (`Market.terms/2`).
  defp counted(%Market{code: "pl"}, keys),
    do: dynamic([o], o.shop in ^keys or o.shop not in ^Shops.keys())

  defp counted(_market, keys), do: dynamic([o], o.shop in ^keys and not is_nil(o.shop_price))

  # One branch per kind of terms, not per shop: most shops of a market share
  # theirs. Poland's own shops keep the offer's stored price, the default.
  defp compared_price(terms, market) do
    terms
    |> Enum.group_by(fn {_shop, shop_terms} -> shop_terms end, fn {shop, _terms} -> shop end)
    |> Enum.reject(fn {shop_terms, _shops} -> shop_terms == {:price, nil} end)
    |> Enum.reduce(dynamic([o], o.price), fn {{item, delivery}, shops}, acc ->
      price = delivered(item_price(item, market), delivery)
      dynamic([o], fragment("CASE WHEN ? THEN ? ELSE ? END", o.shop in ^shops, ^price, ^acc))
    end)
  end

  defp item_price(:price, _market), do: dynamic([o], o.price)
  defp item_price(:shop_price, _market), do: dynamic([o], o.shop_price)

  defp item_price({:shop_price, from_pln, to_pln}, market),
    do:
      rounded(
        dynamic(
          [o],
          o.shop_price * type(^from_pln, :decimal) / type(^to_pln, :decimal)
        ),
        market
      )

  # `Market.rounded/2` in SQL: a whole-unit currency keeps its hundredths
  # below one unit.
  defp rounded(amount, %Market{decimals: 0}),
    do:
      dynamic(
        fragment(
          "CASE WHEN round(?, 2) > 0 AND round(?, 2) < 1 THEN round(?, 2) ELSE round(?, 0) END",
          ^amount,
          ^amount,
          ^amount,
          ^amount
        )
      )

  defp rounded(amount, %Market{decimals: decimals}),
    do: dynamic(fragment("round(?, ?::integer)", ^amount, ^decimals))

  defp delivered(item, nil), do: item

  defp delivered(item, {shipping, nil}), do: dynamic(^item + type(^shipping, :decimal))

  defp delivered(item, {shipping, free_from}),
    do:
      dynamic(
        fragment(
          "CASE WHEN ? >= ? THEN ? ELSE ? + ? END",
          ^item,
          type(^free_from, :decimal),
          ^item,
          ^item,
          type(^shipping, :decimal)
        )
      )

  def current_offers(card_ids) do
    from(o in current_query(),
      where: o.card_id in ^card_ids,
      order_by: [desc: o.in_stock, asc: o.price, asc: o.shop, asc: o.id]
    )
    |> Repo.all()
  end

  @doc """
  The cards of these sets with their prices in the market: the cheapest
  in-stock offer (`offer_price`, `offer_shop`; `normal_offer`, the normal
  print's) and the Cardmarket trend, alone and with delivery, in its currency.
  """
  def enrich(cards, sets, %Market{} = market) do
    offers = in_stock_prices(Enum.map(cards, & &1.id), market)

    names = Expansions.names(Enum.map(sets, & &1.cardmarket_expansion_id))
    collisions = collision_ids(Enum.map(sets, & &1.cardmarket_expansion_id))
    sets = Map.new(sets, &{&1.id, &1})
    context = context(market)

    Enum.map(cards, fn card ->
      set = Map.fetch!(sets, card.tcgdex_set_id)
      rows = Map.get(offers, card.id, [])
      name = Map.get(names, set.cardmarket_expansion_id)

      card
      |> with_prices(rows, context)
      |> with_public_identity(set, name, collisions)
    end)
  end

  defp in_stock_prices(card_ids, market) do
    from(o in current_query(),
      where: o.card_id in ^card_ids and o.in_stock and is_nil(o.grading),
      select: map(o, [:id, :card_id, :price, :shop_price, :currency, :shop, :variant])
    )
    |> Repo.all()
    |> Market.compared(market, Date.utc_today())
    |> Enum.sort_by(&{Decimal.to_float(&1.price), &1.shop, &1.id})
    |> Enum.group_by(& &1.card_id)
  end

  defp with_prices(card, offers, context) do
    trend = card.cardmarket_price && card.cardmarket_price.trend

    card
    |> Map.put(:offer_price, if(offers != [], do: hd(offers).price))
    |> Map.put(:offer_shop, if(offers != [], do: hd(offers).shop))
    # Only a normal print compares with the Cardmarket trend, as on the card's page.
    |> Map.put(:normal_offer, Enum.find(offers, &(&1.variant == :normal)))
    |> Map.put(:cardmarket_trend, Market.in_market(trend, context.rate, context.market))
    |> Map.put(:cardmarket_delivered, reference(card.cardmarket_price, :normal, context))
  end

  defp with_public_identity(card, set, name, collisions) do
    card
    |> Map.put(:image_sources, Image.single_sources(set, card.number))
    |> Map.put(:expansion_name, name)
    |> Map.put(
      :public_path,
      if(name, do: path(card, name, set.cardmarket_expansion_id, collisions))
    )
  end

  @doc "Resolves the public identity of the one card selected for the market banner."
  def with_public_identity(card) do
    set = card.tcgdex_set
    name = Map.get(Expansions.names([set.cardmarket_expansion_id]), set.cardmarket_expansion_id)
    collisions = collision_ids([set.cardmarket_expansion_id], [card.number])
    with_public_identity(card, set, name, collisions)
  end

  @doc "In-stock card prices for the market banner, without building thousands of links and image URLs."
  def market_cards(%Market{} = market) do
    rows =
      from([c, s, _o, p] in browse_query(%{query: "", expansion: nil}, market),
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

    offers = in_stock_prices(Enum.map(rows, fn {card, _, _} -> card.id end), market)

    context = context(market)

    Enum.map(rows, fn {card, set, price} ->
      %{card | cardmarket_price: price, tcgdex_set: set}
      |> with_prices(Map.get(offers, card.id, []), context)
    end)
  end

  @doc "How many cards the English sets of named expansions hold."
  def catalogue_size do
    from(c in Card,
      join: s in Set,
      on: c.tcgdex_set_id == s.id,
      where: s.language == "en" and not is_nil(s.cardmarket_expansion_id)
    )
    |> Repo.aggregate(:count)
  end

  @doc "The Cardmarket product ids of the cards in our catalogue."
  def cardmarket_ids do
    from(c in Card,
      where: not is_nil(c.cardmarket_id),
      distinct: true,
      select: c.cardmarket_id
    )
    |> Repo.all()
  end

  @doc "How many shops counted in the market's card prices have an ungraded card in stock."
  def shop_count(%Market{} = market) do
    from(o in subquery(compared_query(market)),
      where: o.in_stock and is_nil(o.grading),
      select: count(o.shop, :distinct)
    )
    |> Repo.one()
  end

  @doc "The lower available card price, excluding delivery."
  def price(card) do
    case {Map.get(card, :offer_price), Map.get(card, :cardmarket_trend)} do
      {nil, trend} -> trend
      {offer, nil} -> offer
      {offer, trend} -> Decimal.min(offer, trend)
    end
  end

  @doc "The source of the chosen price; shops win ties."
  def price_source(card) do
    offer = Map.get(card, :offer_price)
    trend = Map.get(card, :cardmarket_trend)

    if offer && (is_nil(trend) || Decimal.lte?(offer, trend)),
      do: {:shop, card.offer_shop},
      else: :cardmarket
  end

  @doc "The mirrored source image of each card by id (nil when not mirrored yet), in one query."
  def images(cards) do
    mirrored = cards |> Enum.flat_map(& &1.image_sources) |> mirrored_hashes()
    Map.new(cards, &{&1.id, first_mirrored(&1.image_sources, mirrored)})
  end

  @doc """
  How many of an expansion's English cards have an answer on their page in
  the market (an in-stock, ungraded current offer, as in `sitemap_cards/1`).
  """
  @spec in_stock_count(integer(), Market.t()) :: non_neg_integer()
  def in_stock_count(expansion_id, %Market{} = market) do
    from(c in Card,
      join: o in subquery(compared_query(market)),
      on: o.card_id == c.id and o.in_stock and is_nil(o.grading),
      join: s in Set,
      on: c.tcgdex_set_id == s.id,
      where: s.language == "en" and s.cardmarket_expansion_id == ^expansion_id,
      select: count(c.id, :distinct)
    )
    |> Repo.one()
  end

  # Only the market's cards whose page has an answer: an in-stock, ungraded
  # current offer there, the same rule as page/4. The rest stay reachable but
  # noindex. Each comes with its expansion, whose set page lists it. Paths are
  # Polish (`Paths.localize/2` gives the region's).
  @spec sitemap_cards(Market.t()) :: [{integer(), String.t(), String.t()}]
  def sitemap_cards(%Market{} = market) do
    cards =
      from(c in Card,
        join: o in subquery(compared_query(market)),
        on: o.card_id == c.id and o.in_stock and is_nil(o.grading),
        join: s in Set,
        on: c.tcgdex_set_id == s.id,
        where: s.language == "en" and not is_nil(s.cardmarket_expansion_id),
        distinct: true,
        select: {c, s.cardmarket_expansion_id}
      )
      |> Repo.all()

    names = Expansions.names(Enum.map(cards, &elem(&1, 1)))
    collisions = collision_ids()

    for {card, id} <- cards,
        name = Map.get(names, id),
        name,
        do: {id, name, path(card, name, id, collisions)}
  end
end
