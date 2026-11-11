defmodule TcgCheap.Sealed do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue, shop offers matched to
  it, and daily prices.

  An offer is *current* when it was seen in its shop's latest successful
  fetch and that fetch happened within the last 3 days. Offers a shop no
  longer lists stop counting as soon as the shop is fetched again.
  """

  use Ash.Domain, otp_app: :tcg_cheap, extensions: [AshAi]

  alias TcgCheap.Sealed.{AgentTools, Offer, Product, RetailDeal, SuggestedPrice}

  @current_for_seconds 3 * 86_400

  tools do
    tool(:list_unmatched_card_offers, AgentTools, :list_unmatched_card_offers,
      annotations: [read_only_hint: true]
    )

    tool(:list_matched_card_offers, AgentTools, :list_matched_card_offers,
      annotations: [read_only_hint: true]
    )

    tool(:list_card_decisions, AgentTools, :list_card_decisions,
      annotations: [read_only_hint: true]
    )

    tool(:explain_card_match, AgentTools, :explain_card_match,
      annotations: [read_only_hint: true]
    )

    tool(:search_cards, AgentTools, :search_cards, annotations: [read_only_hint: true])

    tool(:assign_card_offer, AgentTools, :assign_card_offer,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:exclude_card_offer, AgentTools, :exclude_card_offer,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:clear_card_decision, AgentTools, :clear_card_decision,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:shop_status, AgentTools, :shop_status, annotations: [read_only_hint: true])

    tool(:list_unmatched_offers, AgentTools, :unmatched_offers,
      annotations: [read_only_hint: true]
    )

    tool(:list_matched_offers, AgentTools, :matched_offers, annotations: [read_only_hint: true])

    tool(:list_manual_decisions, AgentTools, :manual_decisions,
      annotations: [read_only_hint: true]
    )

    tool :search_products, Product, :browse do
      description """
      Searches the sealed catalogue: every word of query must start a word of the product name or
      set (case and accents ignored); a word of 4+ letters that no product holds is read as a typo
      and matched within one edit. Optionally of one kind. Products in stock come first, then the
      best matches, then the newest. Use the returned id with assign_offer or set_product_eans.
      Pages use limit (at most 100) and offset.
      """

      action_parameters([:limit, :offset])

      select [
        :id,
        :slug,
        :name,
        :kind,
        :set_name,
        :cardmarket_id,
        :cardmarket_expansion_id,
        :eans,
        :available,
        :lowest_price,
        :lowest_preorder_price
      ]

      annotations(read_only_hint: true)
    end

    tool(:get_product, AgentTools, :product, annotations: [read_only_hint: true])
    tool(:explain_match, AgentTools, :explain_match, annotations: [read_only_hint: true])

    tool(:assign_offer, AgentTools, :assign_offer,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:exclude_offer, AgentTools, :exclude_offer,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:clear_manual_decision, AgentTools, :clear_manual_decision,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:set_product_eans, AgentTools, :set_product_eans,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:set_product_contents, AgentTools, :set_product_contents,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:set_product_photo, AgentTools, :set_product_photo,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:set_pull_rates, AgentTools, :set_pull_rates,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:record_unofficial_set_cards, AgentTools, :record_unofficial_set_cards,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:set_expansion_logo, AgentTools, :set_expansion_logo,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:enqueue_shop_fetch, AgentTools, :enqueue_shop_fetch,
      annotations: [read_only_hint: false, destructive_hint: false, open_world_hint: true]
    )

    tool(:enqueue_catalogue_import, AgentTools, :enqueue_catalogue_import,
      annotations: [read_only_hint: false, destructive_hint: false, open_world_hint: true]
    )

    tool(:enqueue_card_sync, AgentTools, :enqueue_card_sync,
      annotations: [read_only_hint: false, destructive_hint: false, open_world_hint: true]
    )

    tool(:enqueue_exchange_rate_fetch, AgentTools, :enqueue_exchange_rate_fetch,
      annotations: [read_only_hint: false, destructive_hint: false, open_world_hint: true]
    )

    tool(:list_suggested_prices, AgentTools, :suggested_prices,
      annotations: [read_only_hint: true]
    )

    tool(:decide_suggested_price, AgentTools, :decide_suggested_price,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:enqueue_suggested_price_fetch, AgentTools, :enqueue_suggested_price_fetch,
      annotations: [read_only_hint: false, destructive_hint: false, open_world_hint: true]
    )

    tool :list_retail_deals, RetailDeal, :read do
      description """
      Lists the recorded retail chain deals (Lidl, Rossmann, Żabka…), past ones included; filter
      and sort them, e.g. by starts_on. Pages use limit and offset.
      """

      action_parameters([:filter, :sort, :limit, :offset])
      annotations(read_only_hint: true)
    end

    tool :record_retail_deal, RetailDeal, :record do
      description """
      Records a Pokémon TCG price in a retail chain's shops from the chain's leaflet or a deal
      post you checked: chain, the leaflet's title, the price in PLN, its days and the https
      source. Set product_id (search_products) only to the exact product the leaflet names; a
      chain's own set stays without one. Leave ends_on null when the source gives no end; never
      guess one. Shown on the product page, the home page and the booster price page, never in
      the price verdict. To correct a deal, remove it and record it again.
      """

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)
    end

    tool :remove_retail_deal, RetailDeal, :destroy do
      description "Removes a recorded retail chain deal (wrong, or withdrawn by the chain)."
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
    end
  end

  resources do
    resource TcgCheap.Sealed.Product do
      define :import_product, action: :import
      define :list_products, action: :read
      define :get_product_by_slug, action: :by_slug, args: [:slug], not_found_error?: false
      define :list_boosters_by_name, action: :boosters_by_name, args: [:names, :region]

      define :browse_products,
        action: :browse,
        args: [
          {:optional, :query},
          {:optional, :kind},
          {:optional, :region},
          {:optional, :expansion}
        ]

      define :list_product_facets,
        action: :facets,
        args: [
          {:optional, :query},
          {:optional, :kind},
          {:optional, :region},
          {:optional, :expansion}
        ]

      define :count_product_facets, action: :facet_counts, args: [{:optional, :query}]

      define :set_product_availability, action: :set_availability
      define :set_product_eans, action: :set_eans, args: [:eans]
      define :set_product_contents, action: :set_contents, args: [:contents]
      define :set_product_photo, action: :set_photo, args: [:checked_photo_url]
      define :list_photos_to_mirror, action: :photos_to_mirror, args: [:limit]
      define :list_photos_missing_variants, action: :photos_missing_variants, args: [:limit]
      define :record_photo_source, action: :record_photo_source, args: [:photo_source_url]
      define :record_photo_attempt, action: :record_photo_attempt
      define :get_product, action: :read, get_by: [:id], not_found_error?: false
      define :list_products_with_eans, action: :with_eans
    end

    resource TcgCheap.Sealed.Offer do
      define :upsert_offer, action: :upsert
      define :match_offer, action: :match, args: [:product_id]
      define :assign_offer_manually, action: :assign_manually, args: [:product_id]
      define :exclude_offer_manually, action: :exclude_manually
      define :clear_manual_offer, action: :clear_manual
      define :get_offer, action: :read, get_by: [:id]
      define :list_offers, action: :read
      define :list_offers_seen_since, action: :seen_since, args: [:since]

      define :list_offers_seen_since_for_products,
        action: :seen_since_for_products,
        args: [:since, :product_ids]

      define :latest_shop_fetches, action: :latest_fetches, args: [:since]
      define :list_manual_offers, action: :manual
    end

    resource TcgCheap.Sealed.TcgdexSet do
      define :list_tcgdex_sets, action: :read
      define :record_tcgdex_set, action: :record
      define :list_english_tcgdex_sets, action: :english

      define :list_english_sets_of_expansion,
        action: :english_of_expansion,
        args: [:expansion_id]

      define :list_sets_due_for_cards,
        action: :cards_due,
        args: [:released_since, :checked_before]

      define :set_tcgdex_set_pull_rates, action: :set_pull_rates, args: [:pull_rates]
      define :record_tcgdex_set_cards, action: :record_cards, args: [:cards]
      define :record_unofficial_set_cards, action: :record_unofficial_cards
    end

    resource TcgCheap.Sealed.TcgdexCard do
      define :list_cards, action: :read
      define :list_cards_due_for_cardmarket, action: :cardmarket_due, args: [:checked_before]
      define :record_card_cardmarket_id, action: :record_cardmarket_id, args: [:cardmarket_id]
    end

    resource TcgCheap.Sealed.ShopFetch do
      define :record_shop_fetch, action: :record
    end

    resource TcgCheap.Sealed.CardOffer do
      define :upsert_card_offer, action: :upsert
      define :list_card_offers, action: :read
      define :get_card_offer, action: :read, get_by: [:id]
      define :match_card_offer, action: :match
      define :assign_card_offer_manually, action: :assign_manually
      define :exclude_card_offer_manually, action: :exclude_manually
      define :clear_manual_card_offer, action: :clear_manual
      define :list_card_offers_seen_since, action: :seen_since, args: [:since]
      define :latest_card_fetches, action: :latest_fetches, args: [:since]
      define :list_manual_card_offers, action: :manual
    end

    resource TcgCheap.Sealed.CardPrice
    resource TcgCheap.Sealed.CardDailyPrice

    resource TcgCheap.Sealed.ExpansionLogo do
      define :list_expansion_logos, action: :read
      define :set_expansion_logo, action: :set
      define :destroy_expansion_logo, action: :destroy

      define :get_expansion_logo,
        action: :read,
        get_by: [:cardmarket_expansion_id],
        not_found_error?: false
    end

    resource TcgCheap.Sealed.SuggestedPrice do
      define :list_suggested_prices, action: :read
      define :get_suggested_price, action: :read, get_by: [:id], not_found_error?: false
      define :match_suggested_price, action: :match, args: [:product_id]
      define :decide_suggested_price, action: :decide_manually, args: [:product_id]

      define :get_suggested_price_for_product,
        action: :for_product,
        args: [:product_id],
        not_found_error?: false
    end

    resource TcgCheap.Sealed.RetailDeal do
      define :list_current_retail_deals, action: :current, args: [:today]
    end

    resource AgentTools

    resource TcgCheap.Sealed.DailyPrice do
      define :record_shop_price, action: :record_shop_price
      define :record_cardmarket_trend, action: :record_cardmarket_trend
      define :list_daily_prices_on, action: :on, args: [:date]
      define :list_price_history, action: :history, args: [:product_id, :since]
      define :list_price_histories, action: :histories, args: [:product_ids, :since]

      define :get_last_stocked_day,
        action: :last_stocked,
        args: [:product_id],
        get?: true,
        not_found_error?: false
    end
  end

  @doc """
  Every current offer, or only those of the given products (see the module
  documentation). `select:` reads only these offer fields (besides `id`,
  `shop` and `last_seen_at`).
  """
  @spec current_offers(DateTime.t(), [Ecto.UUID.t()] | :all, keyword()) :: [Offer.t()]
  def current_offers(%DateTime{} = now, product_ids \\ :all, opts \\ []) do
    since = DateTime.add(now, -@current_for_seconds, :second)
    latest = latest_shop_fetches!(since)

    read =
      case Keyword.fetch(opts, :select) do
        {:ok, fields} -> [query: [select: [:shop, :last_seen_at | fields]]]
        :error -> []
      end

    offers =
      case product_ids do
        :all -> list_offers_seen_since!(since, read)
        ids -> list_offers_seen_since_for_products!(since, ids, read)
      end

    Enum.filter(offers, &(DateTime.compare(&1.last_seen_at, Map.fetch!(latest, &1.shop)) == :eq))
  end

  @doc "Current singles, using each shop's latest card fetch within three days."
  def current_card_offers(now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -@current_for_seconds, :second)
    latest = latest_card_fetches!(since)

    require Ash.Query
    require Ash.Expr
    query = TcgCheap.Sealed.CardOffer |> Ash.Query.filter(is_nil(language) or language == "en")

    filter =
      Enum.reduce(latest, false, fn {shop, time}, acc ->
        Ash.Expr.expr(^acc or (shop == ^shop and last_seen_at == ^time))
      end)

    query |> Ash.Query.filter(^filter) |> Ash.read!(domain: __MODULE__)
  end

  @doc """
  Every known barcode and its product. A product's own EANs win; the EANs of
  offers and REBEL items assigned manually identify a product only for a code
  no product owns, since shops sometimes send another product's barcode. A code
  claimed by two products, or learned for two products, identifies neither and
  is left out; assignments never decide a code products claim.
  """
  @spec known_eans() :: %{String.t() => Ecto.UUID.t()}
  def known_eans do
    owned =
      for product <- list_products_with_eans!(query: [select: [:eans]]),
          ean <- product.eans,
          do: {ean, product.id}

    from_offers =
      for %Offer{ean: ean, product_id: id} <- list_manual_offers!(),
          is_binary(ean) and not is_nil(id),
          do: {ean, id}

    from_rebel =
      for %SuggestedPrice{ean: ean, product_id: id, manual?: true} <- list_suggested_prices!(),
          is_binary(ean) and not is_nil(id),
          do: {ean, id}

    owned_eans = MapSet.new(owned, &elem(&1, 0))
    learned = Enum.reject(from_offers ++ from_rebel, &MapSet.member?(owned_eans, elem(&1, 0)))

    Map.merge(unique_eans(owned), unique_eans(learned))
  end

  defp unique_eans(pairs) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {ean, ids} ->
      case Enum.uniq(ids) do
        [id] -> [{ean, id}]
        _conflict -> []
      end
    end)
    |> Map.new()
  end
end
