defmodule TcgCheap.Sealed.Guide do
  @moduledoc "Read models for the public buying-guide pages."

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{PriceGuide, Product, Rarities, Regions, TcgdexSet}
  alias TcgCheap.Sealed.PullRates.Rate

  @history_days 90
  @page_size 30

  @type summary :: %{
          product: Product.t(),
          verdict: PriceGuide.t(),
          cardmarket_pln: Decimal.t() | nil
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
        page: [limit: @page_size, offset: offset, count: true],
        load: [:photo_card_url, :photo_page_url]
      )

    {summaries(page.results, now), page.more?, page.count || 0}
  end

  @doc """
  What the language and expansion filters offer under the other filters:
  product counts per language edition, and the named expansions (those with
  a product in stock first, then newest first) with their logo when one is
  mirrored: the English TCGdex logo, else the one set for the expansion.
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
    logos = logos()

    expansions =
      Sealed.list_product_facets!(filters.query, filters.kind, filters.region, nil)
      |> named_expansions(logos)
      |> Enum.sort_by(&(&1.newest || ~D[1990-01-01]), {:desc, Date})
      |> Enum.sort_by(&(!&1.available?))
      |> Enum.map(&Map.drop(&1, [:available?, :newest]))

    expansions ++ chosen_elsewhere(filters.expansion, expansions, logos)
  end

  # Per expansion, the mirrored English TCGdex logo, else the mirrored logo
  # set for it (`TcgCheap.Sealed.ExpansionLogo`, for any edition). Only
  # mirrored images are shown, so a tile never shows a broken image.
  defp logos do
    tcgdex =
      for {id, %{language: "en", logo_url: "" <> url}} <-
            TcgdexSet.by_expansion(Sealed.list_tcgdex_sets!()),
          source = CardImage.logo_source_url(url),
          do: {id, source, CardImage.logo_url(url)}

    set =
      for logo <- Sealed.list_expansion_logos!(),
          source = CardImage.expansion_logo_source_url(logo.url),
          do: {logo.cardmarket_expansion_id, source, CardImage.expansion_logo_url(logo.url)}

    mirrored =
      (tcgdex ++ set)
      |> Enum.map(&CardImage.source_hash(elem(&1, 1)))
      |> TcgCheap.Storage.list_mirrored_remote_images!()
      |> MapSet.new(& &1.id)

    # TCGdex last, so its logo replaces a set one.
    for {id, source, url} <- set ++ tcgdex,
        MapSet.member?(mirrored, CardImage.source_hash(source)),
        into: %{},
        do: {id, url}
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
    rate = now |> DateTime.to_date() |> eur_pln()
    ids = Enum.map(products, & &1.id)
    offers = now |> Sealed.current_offers(ids) |> Enum.group_by(& &1.product_id)

    Enum.map(products, &summary(&1, Map.get(offers, &1.id, []), rate))
  end

  @doc """
  Everything the product page shows: today's verdict, the comparison with
  the product's history (`past`), offers, 90 days of history, REBEL's
  suggested retail price when one matches, our English single booster of
  each set the contents name (`boosters`, by set name), their combined odds
  (`booster_odds`) and, for any English single booster, its set's pull rates
  and cards (`booster_set`, nil for other products).
  """
  @spec product(String.t(), DateTime.t()) :: {:ok, map()} | :error
  def product(slug, %DateTime{} = now) do
    case Sealed.get_product_by_slug!(slug, load: [:photo_page_url]) do
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

        summary = summary(product, offers, rate)
        past_history = with_last_stocked_day(history, product.id, since)
        boosters = boosters(product.contents)

        {:ok,
         Map.merge(summary, %{
           past: PriceGuide.past(past_history, summary.verdict.cheapest, today),
           offers: offers,
           history: history,
           today: today,
           eur_pln: rate,
           suggested_price: Sealed.get_suggested_price_for_product!(product.id),
           boosters: boosters,
           booster_odds: booster_odds(product, boosters),
           booster_set: booster_set(product)
         })}
    end
  end

  defp boosters(nil), do: %{}

  defp boosters(contents) do
    case for(%{type: :booster, name: set} <- contents.items, set, do: set <> " Booster") do
      [] ->
        %{}

      names ->
        names
        |> Sealed.list_english_boosters!(load: [:photo_card_url])
        |> Map.new(&{String.replace_suffix(&1.name, " Booster", ""), &1})
    end
  end

  # Smaller English packs share the set's card pool, but not its standard-pack odds.
  defp booster_set(%Product{kind: :booster, region: :en, cardmarket_expansion_id: id} = product) do
    sets =
      if id,
        do: Sealed.list_english_sets_of_expansion!(id, load: [cards: :cardmarket_price]),
        else: []

    main = TcgdexSet.by_expansion(sets) |> Map.values() |> List.first()
    pull_rates = Enum.find_value([main | sets], &(&1 && &1.pull_rates))
    cards = Enum.flat_map(sets, & &1.cards)
    rarities = by_rarity(cards)

    %{
      pull_rates: pull_rates(pull_rates, rarities),
      cards_per_pack: pack_size(product) || (pull_rates && pull_rates.cards_per_pack),
      standard_pack_size: pull_rates && pull_rates.cards_per_pack,
      smaller_pack?: smaller_pack?(product, pull_rates),
      rarities: rarities,
      logo_url: id && Map.get(logos(), id),
      priced_on:
        cards
        |> Enum.map(&(&1.cardmarket_price && &1.cardmarket_price.priced_on))
        |> Enum.reject(&is_nil/1)
        |> Enum.max(Date, fn -> nil end)
    }
  end

  defp booster_set(_product), do: nil

  defp pack_size(product) do
    case Regex.run(~r/\((\d+) Cards?\)/i, product.name) do
      [_, count] -> String.to_integer(count)
      nil -> nil
    end
  end

  defp smaller_pack?(product, pull_rates) do
    size = pack_size(product)
    standard = pull_rates && pull_rates.cards_per_pack
    not is_nil(size) and (is_nil(standard) or size < standard)
  end

  defp booster_odds(%Product{contents: nil}, _boosters), do: []

  defp booster_odds(product, boosters) do
    product.contents.items
    |> Enum.filter(&(&1.type == :booster and Map.has_key?(boosters, &1.name)))
    |> Enum.group_by(& &1.name)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, items} ->
      booster = Map.fetch!(boosters, name)

      sets =
        if booster.cardmarket_expansion_id,
          do: Sealed.list_english_sets_of_expansion!(booster.cardmarket_expansion_id),
          else: []

      main = TcgdexSet.by_expansion(sets) |> Map.values() |> List.first()
      rates = Enum.find_value([main | sets], &(&1 && &1.pull_rates))
      count = Enum.sum(Enum.map(items, & &1.quantity))

      %{
        name: name,
        slug: booster.slug,
        count: count,
        pull_rates: pull_rates(rates, [])
      }
    end)
  end

  defp pull_rates(nil, _rarities), do: nil

  # Each rate with its rarity as the card list spells it and the index of
  # that list's group, if any (`set_pull_rates` checks the two agree).
  defp pull_rates(pull_rates, rarities) do
    groups =
      rarities
      |> Enum.with_index()
      |> Map.new(fn {group, index} -> {group.rarity && String.downcase(group.rarity), index} end)

    rates =
      pull_rates.rates
      |> Enum.sort_by(&Rate.percent/1, Decimal)
      |> Enum.map(fn rate ->
        rarity = Rarities.label(rate.rarity)
        %{rate: rate, rarity: rarity, group: groups[String.downcase(rarity)]}
      end)

    %{rates: rates, sources: pull_rates.sources, checked_on: pull_rates.checked_on}
  end

  defp by_rarity(cards) do
    cards
    |> Enum.group_by(&(&1.rarity && Rarities.label(&1.rarity)))
    |> Enum.sort_by(fn {rarity, _cards} -> {Rarities.rank(rarity), rarity || ""} end)
    |> Enum.map(fn {rarity, cards} ->
      %{rarity: rarity, cards: Enum.sort_by(cards, &number_order(&1.number))}
    end)
  end

  # "TG05" after "TG04", "010" after "9": a letter prefix, then the number.
  defp number_order(number) do
    case Regex.run(~r/\A(\D*)(\d+)(.*)\z/, number) do
      [_, prefix, digits, rest] -> {prefix, String.to_integer(digits), rest}
      nil -> {number, 0, ""}
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

  defp summary(product, offers, rate) do
    in_stock = Enum.filter(offers, & &1.in_stock)
    cardmarket_pln = to_pln(product.cardmarket_trend, rate)

    %{
      product: product,
      verdict: PriceGuide.verdict(in_stock, cardmarket_pln),
      cardmarket_pln: cardmarket_pln
    }
  end
end
