defmodule TcgCheap.Sealed.CardGuide do
  @moduledoc "Bounded, local read models for public English single-card pages."
  import Ecto.Query
  alias TcgCheap.{Repo, Sealed, Storage}

  alias TcgCheap.Sealed.{
    CardImage,
    CardOffer,
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
  defp collision_ids(ids \\ nil) do
    query =
      from(c in TcgdexCard,
        join: s in TcgdexSet,
        on: c.tcgdex_set_id == s.id,
        where: s.language == "en",
        select: {s.cardmarket_expansion_id, c}
      )

    query = if ids, do: where(query, [_, s], s.cardmarket_expansion_id in ^ids), else: query

    query
    |> Repo.all()
    |> Enum.group_by(fn {id, c} -> {id, slug(c)} end)
    |> Enum.flat_map(fn {_key, rows} ->
      if length(rows) > 1, do: Enum.map(rows, fn {_, c} -> c.id end), else: []
    end)
    |> MapSet.new()
  end

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
  defp current_query do
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
      |> Map.put(
        :polish_verdict,
        card_verdict(
          List.first(rows),
          card,
          if(rows == [], do: :normal, else: hd(rows).variant),
          rate
        )
      )
      |> Map.put(:polish_price, if(rows != [], do: hd(rows).price))
      |> Map.put(
        :cardmarket_trend_pln,
        Guide.to_pln(card.cardmarket_price && card.cardmarket_price.trend, rate)
      )
      |> Map.put(:polish_shops, rows |> Enum.map(& &1.shop) |> Enum.uniq() |> length())
      |> Map.put(
        :public_path,
        if(name, do: path(card, name, set.cardmarket_expansion_id, collisions))
      )
    end)
  end

  def sitemap_paths do
    cards =
      from(c in TcgdexCard,
        join: o in subquery(current_query()),
        on: o.card_id == c.id,
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
