defmodule TcgCheap.Sealed.Guide do
  @moduledoc "Read models for the public buying-guide pages."

  alias TcgCheap.Sealed

  alias TcgCheap.Sealed.{
    CardGuide,
    CardImage,
    Kinds,
    PriceGuide,
    Product,
    Rarities,
    Regions,
    TcgdexSet
  }

  alias TcgCheap.Sealed.PullRates.Rate

  @history_days 90
  @cached_for_ms :timer.minutes(10)
  @page_size 30
  # The most products an expansion has is about 55: its page lists them all,
  # so its pull rates and cards follow right after.
  @expansion_page_size 60
  # Sets on the booster price page: about a year of releases.
  @booster_sets 12
  # The cheapest tracked parcel to Poland from Germany, Cardmarket's largest
  # seller country (DHL Paket up to 2 kg, Cardmarket's shipping calculator,
  # 2026-11-02); orders above 25 € must be tracked, which covers most sealed
  # products.
  @cardmarket_shipping_eur Decimal.new("15.49")
  # The product fields a summary and its list row read.
  @summary_fields [
    :slug,
    :name,
    :kind,
    :region,
    :set_name,
    :cardmarket_expansion_id,
    :cardmarket_trend
  ]
  @pack_size ~r/\((\d+) Cards?\)/i
  @card_number ~r/\A(\D*)(\d+)(.*)\z/

  @type summary :: %{
          product: Product.t(),
          verdict: PriceGuide.t(),
          preorder?: boolean(),
          premiere_in: non_neg_integer() | nil,
          premiere: Date.t() | nil,
          cardmarket_pln: Decimal.t() | nil,
          cardmarket_delivered_pln: Decimal.t() | nil
        }

  def history_days, do: @history_days
  def cardmarket_shipping_eur, do: @cardmarket_shipping_eur

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
        page: [limit: page_size(filters), offset: offset, count: true],
        query: [select: @summary_fields],
        load: [
          :stored_photo_small_url,
          :stored_photo_card_url,
          :stored_photo_page_url,
          :photo_placeholder
        ]
      )

    {summaries(page.results, now), page.more?, page.count || 0}
  end

  defp page_size(%{expansion: id}) when is_integer(id), do: @expansion_page_size
  defp page_size(_filters), do: @page_size

  @doc """
  What the language, kind and expansion filters offer under the other filters:
  product counts per language edition and per kind (the chosen kind stays,
  with none), and the named expansions (English ones first, then the other
  language editions in turn; within each, those with a product in stock
  first, then newest first) with their logo when one is
  mirrored: the English TCGdex logo, else the one set for the expansion.
  """
  @spec facets(filters()) :: %{
          regions: [{atom(), pos_integer()}],
          kinds: [{atom(), non_neg_integer()}],
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
    # One grouped read for all three: each count leaves out its own filter.
    groups = Sealed.count_product_facets!(filters.query)

    regions =
      groups
      |> on_shelf(filters.kind)
      |> matching(cardmarket_expansion_id: filters.expansion)
      |> sum_by(& &1.region)

    kinds =
      groups
      |> matching(region: filters.region, cardmarket_expansion_id: filters.expansion)
      |> sum_by(& &1.kind)

    %{
      regions: for(region <- Regions.all(), count = regions[region], do: {region, count}),
      kinds:
        for(
          kind <- Kinds.all(),
          count = kinds[kind] || (filters.kind && kind in Kinds.members(filters.kind) && 0),
          do: {kind, count}
        ),
      expansions:
        groups
        |> on_shelf(filters.kind)
        |> matching(region: filters.region)
        |> expansions(filters)
    }
  end

  defp on_shelf(groups, nil), do: groups
  defp on_shelf(groups, kind), do: Enum.filter(groups, &(&1.kind in Kinds.members(kind)))

  defp matching(groups, filters) do
    Enum.filter(groups, fn group ->
      Enum.all?(filters, fn {field, value} ->
        is_nil(value) or Map.fetch!(group, field) == value
      end)
    end)
  end

  # Products per key, summed over the groups.
  defp sum_by(groups, key) do
    Enum.reduce(
      groups,
      %{},
      &Map.update(&2, key.(&1), &1.count, fn count -> count + &1.count end)
    )
  end

  defp expansions(groups, filters) do
    logos = logos()

    expansions =
      groups
      |> named_expansions(logos)
      |> Enum.sort_by(&(&1.newest || ~D[1990-01-01]), {:desc, Date})
      |> Enum.sort_by(&(!&1.available?))
      |> Enum.sort_by(&Enum.find_index(Regions.all(), fn region -> region == &1.region end))
      |> Enum.map(&Map.drop(&1, [:available?, :newest]))

    expansions ++ chosen_elsewhere(filters.expansion, expansions, logos)
  end

  @doc "The expansions' mirrored logos by Cardmarket expansion id."
  def expansion_logos, do: logos()

  # Cache sources, not object keys: replacing a mirrored image deletes the
  # previous objects, so each render resolves the currently stored variants.
  # Logos show at most ~5.5rem tall, mostly as ~2rem expansion filter tiles:
  # the thumbnail is sharp there, and half the bytes of a large logo's detail.
  defp logos do
    sources = cached(:logo_sources, &read_logo_sources/0)

    mirrored =
      sources
      |> Enum.map(&CardImage.source_hash(elem(&1, 1)))
      |> TcgCheap.Storage.mirrored_image_urls(:thumbnail)

    # TCGdex last, so its mirrored logo replaces a set one.
    for {id, source} <- sources,
        url = Map.get(mirrored, CardImage.source_hash(source)),
        into: %{},
        do: {id, url}
  end

  # Shared by every render for `@cached_for_ms`; the reader that finds it
  # stale reads it again.
  defp cached(key, read) do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, nil) do
      {expires_at, value} when expires_at > now ->
        value

      _missing_or_stale ->
        value = read.()
        :persistent_term.put({__MODULE__, key}, {now + @cached_for_ms, value})
        value
    end
  end

  # Per expansion, the mirrored English TCGdex logo, else the mirrored logo
  # set for it (`TcgCheap.Sealed.ExpansionLogo`, for any edition). Only
  # mirrored images are shown, so a tile never shows a broken image.
  defp read_logo_sources do
    tcgdex =
      for {id, %{language: "en", logo_url: "" <> url}} <-
            TcgdexSet.by_expansion(
              Sealed.list_tcgdex_sets!(
                query: [select: [:cardmarket_expansion_id, :language, :name, :logo_url]]
              )
            ),
          source = CardImage.logo_source_url(url),
          do: {id, source}

    set =
      for logo <- Sealed.list_expansion_logos!(),
          source = CardImage.expansion_logo_source_url(logo.url),
          do: {logo.cardmarket_expansion_id, source}

    set ++ tcgdex
  end

  # The chosen expansion stays listed, with no products, when the other
  # filters leave none of it.
  # Like logos, names change with catalogue syncs, not with a search or page.
  def expansion_names(required_ids \\ []) do
    names = cached(:expansion_names, &read_expansion_names/0)

    if Enum.all?(required_ids, &Map.has_key?(names, &1)) do
      names
    else
      # A catalogue sync can add an expansion while the names are still cached.
      :persistent_term.erase({__MODULE__, :expansion_names})
      cached(:expansion_names, &read_expansion_names/0)
    end
  end

  defp read_expansion_names do
    catalogue =
      Sealed.list_tcgdex_sets!(query: [filter: [language: "en"]])
      |> TcgdexSet.by_expansion()
      |> Map.new(fn {id, set} -> {id, set.name} end)

    sealed =
      facets(%{query: "", kind: nil, region: nil, expansion: nil}).expansions
      |> Map.new(&{&1.id, &1.name})

    Map.merge(catalogue, sealed)
  end

  defp chosen_elsewhere(nil, _expansions, _logos), do: []

  defp chosen_elsewhere(id, expansions, logos) do
    if Enum.any?(expansions, &(&1.id == id)) do
      []
    else
      Sealed.count_product_facets!()
      |> Enum.filter(&(&1.cardmarket_expansion_id == id))
      |> named_expansions(logos)
      |> Enum.map(&(&1 |> Map.drop([:available?, :newest]) |> Map.put(:count, 0)))
    end
  end

  defp named_expansions(groups, logos) do
    groups
    |> Enum.filter(&(&1.cardmarket_expansion_id && &1.set_name))
    |> Enum.group_by(& &1.cardmarket_expansion_id)
    |> Enum.map(fn {id, groups} ->
      %{
        id: id,
        name: most_common(groups, & &1.set_name),
        region: most_common(groups, & &1.region),
        logo_url: Map.get(logos, id),
        count: Enum.sum_by(groups, & &1.count),
        available?: Enum.any?(groups, & &1.available?),
        newest:
          groups
          |> Enum.map(& &1.newest)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(Date, fn -> nil end)
      }
    end)
  end

  defp most_common(groups, field),
    do: groups |> sum_by(field) |> Enum.max_by(&elem(&1, 1)) |> elem(0)

  @doc """
  Summaries for the given products, in order. A product with nothing in
  stock but pre-orders is rated on its pre-orders (`preorder?`), with the
  days until its expansion's premiere when that is still to come.
  """
  @spec summaries([Product.t()], DateTime.t()) :: [summary()]
  def summaries([], _now), do: []

  def summaries(products, %DateTime{} = now) do
    today = DateTime.to_date(now)
    rate = eur_pln(today)
    ids = Enum.map(products, & &1.id)

    offers =
      now
      |> Sealed.current_offers(ids, select: [:product_id, :price, :in_stock, :preorder])
      |> Enum.group_by(& &1.product_id)

    since = Date.add(today, -(PriceGuide.window_days() - 1))

    histories =
      ids
      |> Sealed.list_price_histories!(since,
        query: [select: [:product_id, :date, :lowest_price]]
      )
      |> Enum.group_by(& &1.product_id)

    premieres = premieres(products)

    Enum.map(products, fn product ->
      usual = PriceGuide.usual(Map.get(histories, product.id, []), today)
      summary(product, Map.get(offers, product.id, []), rate, usual, {premieres, now})
    end)
  end

  @doc """
  Everything the product page shows: today's verdict, the comparison with
  the product's history (`past`), offers, 90 days of history, REBEL's
  suggested retail price when one matches, our single booster of the same
  edition for each set the contents name (`boosters`, by set name), their combined odds
  and cards (`booster_odds`) and, for any English single booster, its set's pull rates
  and cards (`booster_set`, nil for other products).
  """
  @spec product(String.t(), DateTime.t()) :: {:ok, map()} | :error
  def product(slug, %DateTime{} = now) do
    case Sealed.get_product_by_slug!(slug, load: [:stored_photo_page_url, :photo_placeholder]) do
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

        summary =
          summary(
            product,
            offers,
            rate,
            PriceGuide.usual(history, today),
            {premieres([product]), now}
          )

        past_history = with_last_stocked_day(history, product.id, since)
        boosters = boosters(product)

        {:ok,
         Map.merge(summary, %{
           past: PriceGuide.past(past_history, summary.verdict.cheapest, today),
           offers: offers,
           history: history,
           today: today,
           eur_pln: rate,
           suggested_price: Sealed.get_suggested_price_for_product!(product.id),
           retail_deals:
             Sealed.list_current_retail_deals!(today, query: [filter: [product_id: product.id]]),
           boosters: boosters,
           booster_odds: booster_odds(product, boosters),
           booster_set: booster_set(product)
         })}
    end
  end

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
    set = expansion_set(id)
    Map.put(set, :smaller_pack?, smaller_pack?(product, set.standard_pack_size))
  end

  defp booster_set(_product), do: nil

  @doc """
  The booster price page: each English single booster a Polish shop has in
  stock (`boosters`, summaries, newest expansion first, at most #{@booster_sets}),
  the cheapest of them (`cheapest`, nil when none) and the retail chains'
  deals running today (`retail_deals`).
  """
  @spec booster_prices(DateTime.t()) :: %{
          boosters: [summary()],
          cheapest: summary() | nil,
          retail_deals: list(),
          today: Date.t()
        }
  def booster_prices(%DateTime{} = now) do
    today = DateTime.to_date(now)

    boosters =
      [
        query: [
          filter: [available: true, kind: :booster, region: :en],
          select: @summary_fields,
          sort: [cardmarket_expansion_id: :desc]
        ],
        load: [:stored_photo_small_url, :stored_photo_card_url, :photo_placeholder]
      ]
      |> Sealed.list_products!()
      # The set's own pack, not its sleeved or smaller ones.
      |> Enum.filter(&(&1.set_name && &1.name == &1.set_name <> " Booster"))
      |> summaries(now)
      # `available` is as of the last refresh: keep the ones in stock now.
      |> Enum.filter(&(&1.verdict.cheapest && not &1.preorder?))
      |> Enum.take(@booster_sets)

    %{
      boosters: boosters,
      cheapest: Enum.min_by(boosters, & &1.verdict.cheapest.price, Decimal, fn -> nil end),
      retail_deals: Sealed.list_current_retail_deals!(today),
      today: today
    }
  end

  @doc """
  What an expansion's page shows besides its products: its English single
  booster (`booster`, a summary, nil when there is none) and the set's pull
  rates and cards as on that booster's page with the card count and the most
  valuable card (`set`, nil when we have neither).
  `name` is the expansion's name.
  """
  @spec expansion(integer(), String.t(), DateTime.t()) :: %{
          set: map() | nil,
          booster: summary() | nil,
          cardmarket: [%{kind: atom(), price: Decimal.t()}]
        }
  def expansion(id, name, %DateTime{} = now) do
    set = expansion_set(id)
    booster = set_booster(id, name, now)

    cards = Enum.flat_map(set.rarities, & &1.cards)

    top_cards =
      cards
      |> Enum.filter(&CardGuide.price/1)
      |> Enum.sort_by(&CardGuide.price/1, {:desc, Decimal})
      |> Enum.take(4)

    deal = best_deal(cards)
    images = CardGuide.images(Enum.uniq_by(List.wrap(deal) ++ top_cards, & &1.id))

    top_cards =
      Enum.map(top_cards, fn card ->
        packs = card_packs(card, set)
        cheapest = booster && !booster.preorder? && booster.verdict.cheapest

        %{
          card: card,
          price: CardGuide.price(card),
          source: CardGuide.price_source(card),
          image: Map.fetch!(images, card.id),
          path: card.public_path,
          packs: packs,
          cost: if(packs && cheapest, do: Decimal.mult(cheapest.price, packs))
        }
      end)

    set =
      Map.merge(set, %{
        card_count: length(cards),
        top_cards: top_cards,
        singles: singles(cards, deal, images)
      })

    %{
      set: if(set.pull_rates || cards != [], do: set),
      booster: booster,
      cardmarket: cardmarket_boxes(id, name, now)
    }
  end

  @doc """
  An expansion's English single booster as a summary with its list row's
  photos, nil when there is none. `name` is the expansion's name.
  """
  @spec set_booster(integer(), String.t(), DateTime.t()) :: summary() | nil
  def set_booster(id, name, %DateTime{} = now) do
    [
      query: [
        filter: [kind: :booster, region: :en, cardmarket_expansion_id: id],
        select: @summary_fields
      ],
      load: [
        :stored_photo_small_url,
        :stored_photo_card_url,
        :stored_photo_page_url,
        :photo_placeholder
      ]
    ]
    |> Sealed.list_products!()
    |> single_booster(name)
    |> List.wrap()
    |> summaries(now)
    |> List.first()
  end

  # The set's own Booster Box and Elite Trainer Box on Cardmarket (trend in
  # PLN, without delivery), for a banner that has no card prices to show.
  defp cardmarket_boxes(id, name, now) do
    rate = eur_pln(DateTime.to_date(now))

    names = %{
      "#{name} Booster Box" => :booster_box,
      "#{name} Elite Trainer Box" => :elite_trainer_box
    }

    [
      query: [
        filter: [cardmarket_expansion_id: id, region: :en, name: [in: Map.keys(names)]],
        select: [:name, :cardmarket_trend]
      ]
    ]
    |> Sealed.list_products!()
    |> Enum.map(&%{kind: Map.fetch!(names, &1.name), price: to_pln(&1.cardmarket_trend, rate)})
    # No trend, or no exchange rate yet, leaves a box without a price.
    |> Enum.filter(& &1.price)
    |> Enum.sort_by(&(&1.kind != :booster_box))
  end

  # Cards under this Cardmarket trend are too cheap for a "deal" to matter.
  @deal_floor Decimal.new(20)
  # More than 40% under its reference, an offer is more often matched to the wrong
  # product (half a booster box, a promo's other print) than a real deal.
  @deal_min_ratio Decimal.new("0.6")

  # The singles banner: the card a Polish shop sells furthest under its
  # Cardmarket price with delivery to Poland (what a singles verdict
  # compares), how many of the set's cards are in stock in Poland and what the
  # whole set costs at the lower of the two prices.
  defp singles(cards, deal, images) do
    priced = Enum.map(cards, &CardGuide.price/1) |> Enum.reject(&is_nil/1)

    %{
      deal: deal && deal_view(deal, images),
      in_stock: Enum.count(cards, & &1.polish_price),
      cheaper: cheaper(cards),
      total: length(cards),
      # A sum missing some cards' prices would understate the set.
      set_price:
        if(priced != [] and length(priced) == length(cards),
          do: Enum.reduce(priced, &Decimal.add/2)
        )
    }
  end

  @doc """
  The singles banner across all expansions, for the card list without one:
  the best deal among the cards in stock in Poland, how many there are of
  the catalogue's cards, how many undercut Cardmarket, the most valuable
  one and how many shops sell them. Shared for a few minutes.
  """
  def singles_market, do: cached(:singles_market, &read_singles_market/0)

  defp read_singles_market do
    cards = CardGuide.market_cards()
    deal = best_deal(cards)
    deal = deal && CardGuide.with_public_identity(deal)
    top = Enum.max_by(cards, &CardGuide.price/1, Decimal, fn -> nil end)

    %{
      deal: deal && deal_view(deal, CardGuide.images([deal])),
      in_stock: length(cards),
      cheaper: cheaper(cards),
      total: CardGuide.catalogue_size(),
      # The whole catalogue has no price of its own, as a set does.
      set_price: nil,
      top: top && %{card: top, price: CardGuide.price(top)},
      shops: CardGuide.shop_count()
    }
  end

  defp deal_view(deal, images) do
    %{
      card: deal,
      price: deal.normal_offer.price,
      shop: deal.normal_offer.shop,
      trend: deal.cardmarket_delivered_pln,
      percent: discount(deal),
      image: Map.fetch!(images, deal.id),
      path: deal.public_path
    }
  end

  defp cheaper(cards), do: Enum.count(cards, &cheaper?/1)

  defp cheaper?(%{
         normal_offer: %{price: price},
         cardmarket_delivered_pln: %Decimal{} = delivered
       }),
       do: Decimal.lt?(price, delivered)

  defp cheaper?(_card), do: false

  @doc """
  The English sets with products in stock, newest first, as the home page's
  set list leads with them (`facets/1`): the sets every page's footer links.
  Shared for a few minutes.
  """
  @spec newest_expansions(pos_integer()) :: [%{id: integer(), name: String.t()}]
  def newest_expansions(count) do
    :newest_expansions
    |> cached(fn ->
      %{query: "", kind: nil, region: :en, expansion: nil}
      |> facets()
      |> Map.fetch!(:expansions)
      |> Enum.map(&Map.take(&1, [:id, :name]))
    end)
    |> Enum.take(count)
  end

  @doc """
  The sealed banner, for the product list without an expansion: the product
  in stock furthest under its typical shop price today (a good price, see
  `PriceGuide`) with its box photo and up to three photos of what it holds,
  how many products are in stock in Poland, how many of them at a good
  price, and in how many shops. Shared for a few minutes.
  """
  def sealed_market, do: cached(:sealed_market, &read_sealed_market/0)

  defp read_sealed_market do
    now = DateTime.utc_now()

    offers =
      Sealed.current_offers(now, :all, select: [:product_id, :in_stock])
      # Unmatched offers (accessories, other games) are no product of ours.
      |> Enum.filter(&(&1.in_stock and &1.product_id))

    summaries =
      [
        query: [
          filter: [id: [in: offers |> Enum.map(& &1.product_id) |> Enum.uniq()]],
          select: @summary_fields
        ]
      ]
      |> Sealed.list_products!()
      |> summaries(now)

    good = Enum.filter(summaries, &(&1.verdict.status == :good))

    # A good price always has a typical shop price to undercut.
    deals =
      good
      |> Enum.map(&{&1, Decimal.div(&1.verdict.cheapest.price, &1.verdict.typical)})
      |> Enum.filter(fn {_summary, ratio} -> Decimal.gte?(ratio, @deal_min_ratio) end)
      |> Enum.sort_by(&elem(&1, 1), Decimal)
      |> Enum.map(&elem(&1, 0))

    %{
      deal: deals |> List.first() |> sealed_deal(),
      in_stock: length(summaries),
      good: length(good),
      offers: length(offers),
      shops: offers |> Enum.map(& &1.shop) |> Enum.uniq() |> length()
    }
  end

  # The deal with its own photos: the box, and what it holds where a checked
  # photo of the contents is mirrored (a deck's cards, its coin, its pin).
  defp sealed_deal(nil), do: nil

  defp sealed_deal(%{verdict: verdict, product: %{slug: slug}}) do
    product = Sealed.get_product_by_slug!(slug, load: [:stored_photo_card_url])

    %{
      product: product,
      contents_photos: contents_photos(product.contents),
      price: verdict.cheapest.price,
      shop: verdict.cheapest.shop,
      typical: verdict.typical,
      shops: length(verdict.shop_prices),
      percent:
        Decimal.new(1)
        |> Decimal.sub(Decimal.div(verdict.cheapest.price, verdict.typical))
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()
    }
  end

  @contents_photos 3

  defp contents_photos(nil), do: []

  defp contents_photos(contents) do
    sources =
      contents.items
      |> Enum.map(&CardImage.photo_source_url(&1.photo))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    mirrored =
      sources
      |> Enum.map(&CardImage.source_hash/1)
      |> TcgCheap.Storage.mirrored_image_urls(:thumbnail)

    sources
    |> Enum.map(&Map.get(mirrored, CardImage.source_hash(&1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@contents_photos)
  end

  # First editions have no reference of their own (see `CardGuide.card_verdict/4`).
  defp best_deal(cards) do
    cards
    |> Enum.filter(
      &(cheaper?(&1) and "firstEdition" not in &1.variants and
          Decimal.gte?(&1.cardmarket_trend_pln, @deal_floor))
    )
    |> Enum.map(&{&1, Decimal.div(&1.normal_offer.price, &1.cardmarket_delivered_pln)})
    |> Enum.filter(fn {_card, ratio} -> Decimal.gte?(ratio, @deal_min_ratio) end)
    |> Enum.min_by(&elem(&1, 1), Decimal, fn -> {nil, nil} end)
    |> elem(0)
  end

  defp discount(card) do
    Decimal.new(1)
    |> Decimal.sub(Decimal.div(card.normal_offer.price, card.cardmarket_delivered_pln))
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  @doc "Average packs for this printing, using only the set's own observed rates."
  def card_packs(%{rarity: nil}, _set), do: nil
  def card_packs(_card, %{pull_rates: nil}), do: nil

  def card_packs(_card, %{pull_rates: %{borrowed_from: borrowed}}) when not is_nil(borrowed),
    do: nil

  def card_packs(card, set) do
    # Rates name rarities and cards ignoring case, as `set_pull_rates` checks
    # them; each rate already points at its rarity's group in the card list.
    rarity = card.rarity |> Rarities.label() |> String.downcase()
    group = Enum.find_index(set.rarities, &(&1.rarity && String.downcase(&1.rarity) == rarity))
    name = String.downcase(card.name)
    rows = if group, do: Enum.filter(set.pull_rates.rates, &(&1.group == group)), else: []

    row =
      Enum.find(rows, &(&1.rate.card && String.downcase(&1.rate.card) == name)) ||
        Enum.find(rows, &is_nil(&1.rate.card))

    if row do
      count = if row.rate.card, do: 1, else: length(Enum.at(set.rarities, group).cards)

      Decimal.new(100)
      |> Decimal.div(Rate.percent(row.rate))
      |> Decimal.mult(count)
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> max(1)
    end
  end

  # "<set> Booster", else the set's only full-size booster ("Trick or Trade
  # BOOster", "EX Emerald Booster"); none when several could be meant.
  defp single_booster(boosters, name) do
    Enum.find(boosters, &(&1.name == name <> " Booster")) ||
      case Enum.reject(boosters, &pack_size/1) do
        [booster] -> booster
        _boosters -> nil
      end
  end

  defp expansion_set(id) do
    sets = sets_with_cards(id)
    pull_rates = set_pull_rates(sets)
    cards = sets |> Enum.flat_map(& &1.cards) |> CardGuide.enrich(sets)
    rarities = by_rarity(cards)

    %{
      pull_rates: pull_rates(pull_rates, rarities),
      standard_pack_size: pull_rates && pull_rates.cards_per_pack,
      rarities: rarities,
      cards_source_url: Enum.find_value(sets, & &1.cards_source_url),
      logo_url: id && Map.get(logos(), id),
      priced_on: priced_on(cards)
    }
  end

  # An expansion's English sets, a set and its gallery subsets, with their cards.
  defp sets_with_cards(nil), do: []

  defp sets_with_cards(expansion_id),
    do: Sealed.list_english_sets_of_expansion!(expansion_id, load: [cards: :cardmarket_price])

  # The main set's pull rates, else a subset's.
  defp set_pull_rates(sets) do
    main = TcgdexSet.by_expansion(sets) |> Map.values() |> List.first()
    Enum.find_value([main | sets], &(&1 && &1.pull_rates))
  end

  defp priced_on(cards) do
    cards
    |> Enum.map(&(&1.cardmarket_price && &1.cardmarket_price.priced_on))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(Date, fn -> nil end)
  end

  defp pack_size(product) do
    case Regex.run(@pack_size, product.name) do
      [_, count] -> String.to_integer(count)
      nil -> nil
    end
  end

  defp smaller_pack?(product, standard) do
    size = pack_size(product)
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

  defp set_odds([], _boosters), do: []

  # Each set's odds across its packs and its cards, so the box's page lists
  # them without a trip to the single booster's page.
  defp set_odds(groups, boosters) do
    Enum.map(groups, fn {name, items} ->
      booster = Map.fetch!(boosters, name)
      sets = sets_with_cards(booster.cardmarket_expansion_id)
      cards = sets |> Enum.flat_map(& &1.cards) |> CardGuide.enrich(sets)
      rarities = by_rarity(cards)

      %{
        name: name,
        slug: booster.slug,
        count: Enum.sum(Enum.map(items, & &1.quantity)),
        pull_rates: pull_rates(set_pull_rates(sets), rarities),
        rarities: rarities,
        cards_source_url: Enum.find_value(sets, & &1.cards_source_url),
        priced_on: priced_on(cards)
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

    %{
      rates: rates,
      sources: pull_rates.sources,
      borrowed_from: pull_rates.borrowed_from,
      checked_on: pull_rates.checked_on
    }
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
    case Regex.run(@card_number, number) do
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

  defp summary(product, offers, rate, usual, {premieres, now}) do
    in_stock = Enum.filter(offers, & &1.in_stock)
    preorders = Enum.filter(offers, & &1.preorder)
    # With nothing in stock, pre-orders are rated the same way.
    preorder? = in_stock == [] and preorders != []
    cardmarket_pln = to_pln(product.cardmarket_trend, rate)
    cardmarket_delivered_pln = product.cardmarket_trend |> with_shipping() |> to_pln(rate)

    {premiere, premiere_in} =
      if preorder?,
        do: upcoming(Map.get(premieres, product.cardmarket_expansion_id), now),
        else: {nil, nil}

    %{
      product: product,
      verdict:
        PriceGuide.verdict(if(preorder?, do: preorders, else: in_stock), cardmarket_pln,
          past: usual,
          cardmarket: cardmarket_delivered_pln
        ),
      preorder?: preorder?,
      premiere: premiere,
      premiere_in: premiere_in,
      cardmarket_pln: cardmarket_pln,
      cardmarket_delivered_pln: cardmarket_delivered_pln
    }
  end

  # The release day of each product's expansion (its set's `released_on`):
  # the street date every shop ships pre-orders on.
  defp premieres(products) do
    case products |> Enum.map(& &1.cardmarket_expansion_id) |> Enum.reject(&is_nil/1) do
      [] ->
        %{}

      ids ->
        Sealed.list_tcgdex_sets!(
          query: [
            filter: [cardmarket_expansion_id: [in: Enum.uniq(ids)]],
            select: [:cardmarket_expansion_id, :language, :name, :released_on]
          ]
        )
        |> TcgdexSet.by_expansion()
        |> Map.new(fn {id, set} -> {id, set.released_on} end)
    end
  end

  # A premiere still to come (or today), with the days left in Poland.
  defp upcoming(nil, _now), do: {nil, nil}

  defp upcoming(%Date{} = premiere, now) do
    case Date.diff(premiere, warsaw_date(now)) do
      days when days >= 0 -> {premiere, days}
      _past -> {nil, nil}
    end
  end

  # The calendar day in Poland: CET, CEST from the last Sunday of March to the
  # last Sunday of October (01:00 UTC both, as everywhere in the EU).
  defp warsaw_date(%DateTime{} = now) do
    year = now.year
    summer_from = DateTime.new!(last_sunday(year, 3), ~T[01:00:00])
    summer_to = DateTime.new!(last_sunday(year, 10), ~T[01:00:00])

    summer? =
      DateTime.compare(now, summer_from) != :lt and DateTime.compare(now, summer_to) == :lt

    now |> DateTime.add(if(summer?, do: 2, else: 1), :hour) |> DateTime.to_date()
  end

  defp last_sunday(year, month) do
    last = Date.end_of_month(Date.new!(year, month, 1))
    Date.add(last, -rem(Date.day_of_week(last), 7))
  end

  defp with_shipping(%Decimal{} = eur), do: Decimal.add(eur, @cardmarket_shipping_eur)
  defp with_shipping(nil), do: nil
end
