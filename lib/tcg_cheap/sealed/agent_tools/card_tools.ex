defmodule TcgCheap.Sealed.AgentTools.CardTools do
  @moduledoc """
  Compact daily singles review: current offers, candidate evidence, price
  outliers and reversible decisions. Reference prices are raw-card trends;
  grading, condition and special variants remain explicit offer attributes.
  """
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  import Ecto.Query
  alias TcgCheap.Repo

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json

  alias TcgCheap.Sealed.{
    CardMatcher,
    CardOffer,
    CardPrice,
    CardReference,
    CardRefresh,
    Guide,
    Matcher,
    TcgdexCard,
    TcgdexSet
  }

  @impl true
  def run(input, opts, _context), do: perform(opts[:operation], input.arguments)

  defp perform(:explain, args) do
    if args[:offer_id] do
      with {:ok, offer} <- Sealed.get_card_offer(args.offer_id),
           do: {:ok, explanation(offer, CardRefresh.index())}
    else
      if args[:title],
        do:
          {:ok, explanation(%{title: args.title, category: args[:category]}, CardRefresh.index())},
        else: invalid(:title, "give offer_id or title")
    end
  end

  defp perform(:search, args) do
    rate = Guide.eur_pln(Date.utc_today())

    query =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        where: s.language == "en",
        select: c
      )

    query =
      if args[:name],
        do:
          Enum.reduce(String.split(Matcher.normalize(args.name)), query, fn word, query ->
            where(
              query,
              [c],
              like(
                fragment(
                  "trim(regexp_replace(translate(replace(lower(?), '&', ' and '), 'ąćęłńóśźżéáàâäãåçèêëíìîïñòôöõúùûüýÿ', 'acelnoszzeaaaaaaceeeiiiinoooouuuuyy'), '[^a-z0-9]+', ' ', 'g'))",
                  c.name
                ),
                ^("%" <> word <> "%")
              )
            )
          end),
        else: query

    query = filter_set(query, args[:set])

    query =
      if args[:number],
        do:
          where(
            query,
            [c],
            fragment(
              "regexp_replace(regexp_replace(lower(?), '^0+([0-9])', '\\1'), '([a-z])0+([0-9])', '\\1\\2', 'g')",
              c.number
            ) == ^CardMatcher.number(args.number)
          ),
        else: query

    {:ok,
     db_page(
       query,
       args,
       fn cards ->
         cards |> Ash.load!([:tcgdex_set, :cardmarket_price]) |> Enum.map(&Json.card(&1, rate))
       end,
       asc: :tcgdex_id,
       asc: :number,
       asc: :id
     )}
  end

  defp perform(operation, args) when operation in [:assign, :exclude, :clear] do
    with {:ok, args} <- resolve_card(operation, args),
         {:ok, offer} <- CardRefresh.decide(args.offer_id, operation, args) do
      {:ok, Json.card_offer(offer)}
    end
  end

  defp perform(operation, args) when operation in [:unmatched, :matched, :decisions] do
    latest = Sealed.latest_card_fetches!(DateTime.add(DateTime.utc_now(), -3 * 86_400, :second))

    current =
      Enum.reduce(latest, dynamic(false), fn {shop, time}, acc ->
        dynamic([o], ^acc or (o.shop == ^shop and o.last_seen_at == ^time))
      end)

    query = from(o in CardOffer)

    query =
      if operation == :decisions,
        do: where(query, [o], o.manual? == true),
        else: where(query, ^current)

    query =
      case operation do
        :unmatched -> where(query, [o], is_nil(o.card_id) and not o.manual?)
        :matched -> where(query, [o], not is_nil(o.card_id) and not o.manual?)
        :decisions -> query
      end

    query = offer_filters(query, args)
    rate = Guide.eur_pln(Date.utc_today())
    list_query(operation, query, args, %{rate: rate, latest: latest})
  end

  defp offer_filters(query, args) do
    query = if args[:shop], do: where(query, [o], o.shop == ^args.shop), else: query

    query =
      if args[:title],
        do:
          where(
            query,
            [o],
            like(
              fragment(
                "trim(regexp_replace(translate(replace(lower(?), '&', ' and '), 'ąćęłńóśźżéáàâäãåçèêëíìîïñòôöõúùûüýÿ', 'acelnoszzeaaaaaaceeeiiiinoooouuuuyy'), '[^a-z0-9]+', ' ', 'g'))",
                o.title
              ),
              ^("%" <> Matcher.normalize(args.title) <> "%")
            )
          ),
        else: query

    query = offer_set(query, args[:set])
    query
  end

  defp filter_set(query, nil), do: query

  defp filter_set(query, value) do
    text = "%" <> String.downcase(value) <> "%"

    where(
      query,
      [_c, s],
      s.tcgdex_id == ^value or ilike(s.name, ^text) or ilike(s.abbreviation, ^text)
    )
  end

  defp offer_set(query, nil), do: query

  defp offer_set(query, value) do
    text = "%" <> String.downcase(value) <> "%"

    sets =
      from(s in TcgdexSet,
        where: s.tcgdex_id == ^value or ilike(s.name, ^text) or ilike(s.abbreviation, ^text),
        select: s.tcgdex_id
      )

    cards =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        where: s.tcgdex_id == ^value or ilike(s.name, ^text) or ilike(s.abbreviation, ^text),
        select: c.id
      )

    where(
      query,
      [o],
      o.card_id in subquery(cards) or fragment("? && ARRAY(?)", o.match_set_ids, subquery(sets))
    )
  end

  defp list_query(:unmatched, query, args, _context) do
    excluded = where(query, [o], like(o.match_note, "excluded:%"))

    reasons =
      from(o in excluded, group_by: o.match_note, select: {o.match_note, count(o.id)})
      |> Repo.all()
      |> Map.new()

    query =
      if args.include_excluded,
        do: query,
        else: where(query, [o], is_nil(o.match_note) or not like(o.match_note, "excluded:%"))

    query =
      if args[:reason],
        do:
          where(
            query,
            [o],
            o.match_note == ^args.reason or
              like(o.match_note, ^("excluded:" <> args.reason <> "%"))
          ),
        else: query

    page =
      db_page(query, args, fn offers ->
        index = CardRefresh.index()

        Enum.map(offers, fn offer ->
          explain = explanation(offer, index)

          offer
          |> Json.card_offer()
          |> Map.merge(Map.take(explain, [:matcher, :reason, :candidates]))
          |> Map.update!(:candidates, &Enum.take(&1, 3))
        end)
      end)

    {:ok,
     Map.merge(page, %{excluded_total: Enum.sum(Map.values(reasons)), excluded_by_reason: reasons})}
  end

  defp list_query(:matched, query, args, context) do
    query =
      if args[:card] do
        value = args.card

        ids =
          from(c in TcgdexCard,
            where: c.tcgdex_id == ^value or fragment("?::text", c.id) == ^value,
            select: c.id
          )

        where(query, [o], o.card_id in subquery(ids))
      else
        query
      end

    query = if args.suspicious, do: suspicious_query(query, context.rate), else: query

    {:ok,
     db_page(query, args, fn offers ->
       cards = card_details(offers)
       Enum.map(offers, &matched_json(&1, Map.put(context, :cards, cards)))
     end)}
  end

  defp list_query(:decisions, query, args, context) do
    {:ok,
     db_page(query, args, fn offers ->
       cards = card_details(offers)

       Enum.map(offers, fn offer ->
         offer
         |> Json.card_offer()
         |> Map.put(:current, Map.get(context.latest, offer.shop) == offer.last_seen_at)
         |> Map.put(:card, cards[offer.card_id] && Json.card(cards[offer.card_id], context.rate))
       end)
     end)}
  end

  defp suspicious_query(query, rate) do
    fx = if rate, do: rate.rate, else: Decimal.new(0)

    query =
      from(o in query,
        join: c in TcgdexCard,
        on: o.card_id == c.id,
        left_join: p in CardPrice,
        on: p.cardmarket_id == c.cardmarket_id,
        select: o
      )

    trend =
      dynamic(
        [o, _c, p],
        fragment("CASE WHEN ? = 'reverse' THEN ? ELSE ? END", o.variant, p.trend_holo, p.trend)
      )

    reference =
      dynamic(
        [_o, _c, _p],
        fragment(
          "round((? + CASE WHEN ? > 25 THEN 2.80 ELSE 1.55 END) * ?::numeric, 2)",
          ^trend,
          ^trend,
          ^fx
        )
      )

    ratio = dynamic([o], fragment("round(? / NULLIF(?, 0), 3)", o.price, ^reference))

    suspicious =
      dynamic(
        [o, c],
        (o.variant == :reverse and
           fragment("cardinality(?) > 0 AND NOT ('reverse' = ANY(?))", c.variants, c.variants)) or
          (o.variant != :special and ^trend > 0 and (^ratio < 0.3 or ^ratio > 3))
      )

    where(query, ^suspicious)
  end

  defp db_page(query, args, render, sort \\ [asc: :shop, asc: :title, asc: :id]) do
    total = Repo.aggregate(query, :count)

    items =
      query
      |> order_by(^sort)
      |> limit(^args.limit)
      |> offset(^args.offset)
      |> Repo.all()
      |> render.()

    %{total: total, limit: args.limit, offset: args.offset, items: items}
  end

  defp resolve_card(:assign, args) do
    value = args.card

    query =
      case Ecto.UUID.cast(value) do
        {:ok, id} ->
          Ash.Query.filter(TcgdexCard, id == ^id and tcgdex_set.language == "en")

        :error ->
          Ash.Query.filter(TcgdexCard, tcgdex_id == ^value and tcgdex_set.language == "en")
      end

    case Ash.read_one(query, domain: Sealed) do
      {:ok, nil} -> invalid(:card, "no synced English card with this id")
      {:ok, card} -> {:ok, Map.put(args, :card_id, card.id)}
      {:error, error} -> {:error, error}
    end
  end

  defp resolve_card(_operation, args), do: {:ok, args}

  defp card_details(offers) do
    ids = offers |> Enum.map(& &1.card_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    TcgdexCard
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(domain: Sealed, load: [:tcgdex_set, :cardmarket_price])
    |> Map.new(&{&1.id, &1})
  end

  defp matched_json(offer, context) do
    card = Map.fetch!(context.cards, offer.card_id)
    reference = CardReference.pln(card.cardmarket_price, offer.variant, context.rate)
    ratio = price_ratio(offer.price, reference)

    variants = card.variants || []

    mismatch =
      offer.variant == :reverse and variants != [] and "reverse" not in variants

    offer
    |> Json.card_offer()
    |> Map.merge(%{
      card: Json.card(card, context.rate),
      reference_pln: reference,
      price_ratio: ratio,
      variant_mismatch: mismatch,
      suspicious: mismatch or outlier?(ratio)
    })
  end

  defp price_ratio(price, %Decimal{} = reference),
    do: Decimal.div(price, reference) |> Decimal.round(3)

  defp price_ratio(_price, nil), do: nil
  defp outlier?(nil), do: false
  defp outlier?(ratio), do: Decimal.lt?(ratio, "0.3") or Decimal.gt?(ratio, 3)

  defp explanation(offer, index) do
    explain = CardMatcher.explain(offer, index)

    {matcher, reason, card_id} =
      case explain.result do
        {:matched, id, _variant} -> {:matched, nil, id}
        {:ambiguous, _ids} -> {:ambiguous, :ambiguous, nil}
        {:excluded, {:language, lang}} -> {:excluded, "language:" <> lang, nil}
        {status, reason} -> {status, reason, nil}
      end

    explain
    |> Map.drop([
      :result,
      :text,
      :normalized_title,
      :not_a_card,
      :compact_text,
      :compact_title,
      :category_segments,
      :category_tokens
    ])
    |> Map.merge(%{matcher: matcher, reason: reason, card_id: card_id})
  end

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
