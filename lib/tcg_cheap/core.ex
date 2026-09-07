defmodule TcgCheap.Core do
  @moduledoc """
  The catalogue and pricing resources that back public, locally cached data.
  """

  use Ash.Domain,
    otp_app: :tcg_cheap

  import Ash.Query

  alias TcgCheap.Catalogue.{CardmarketExpansionMapping, CardSet}

  @cardmarket_review_queue_limit 26
  # A batch is expected to contain one mapping per CardSet/expansion pair. Keep
  # the administrative queue fail-closed if corrupt or unexpectedly huge input
  # would otherwise require an unbounded read.
  @cardmarket_review_scan_cap 1_000

  @doc false
  def list_cardmarket_expansion_review_queue(batch_id, actor: actor) do
    with {:ok, batch_mappings} <- list_cardmarket_batch_mappings(batch_id, actor),
         {:ok, card_sets} <- load_cardmarket_review_card_sets(batch_mappings, actor),
         resolved_set_ids <- resolved_card_set_ids(batch_mappings, card_sets),
         {:ok, mappings} <-
           list_unresolved_cardmarket_review_mappings(batch_id, resolved_set_ids, actor) do
      {:ok, attach_cardmarket_card_sets(mappings, card_sets)}
    end
  end

  defp list_cardmarket_batch_mappings(batch_id, actor) do
    result =
      CardmarketExpansionMapping
      |> for_read(:by_batch, %{source_batch_id: batch_id}, actor: actor)
      |> limit(@cardmarket_review_scan_cap + 1)
      |> Ash.read(actor: actor)

    case result do
      {:ok, mappings} when length(mappings) > @cardmarket_review_scan_cap ->
        {:error, {:cardmarket_review_queue_overflow, @cardmarket_review_scan_cap}}

      result ->
        result
    end
  end

  defp load_cardmarket_review_card_sets(mappings, actor) do
    ids = mappings |> Enum.map(& &1.card_set_id) |> Enum.uniq()

    case ids do
      [] ->
        {:ok, %{}}

      _ ->
        CardSet
        |> for_read(:read, %{}, actor: actor)
        |> filter(id in ^ids)
        |> limit(@cardmarket_review_scan_cap)
        |> Ash.read(actor: actor)
        |> case do
          {:ok, card_sets} -> {:ok, Map.new(card_sets, &{&1.id, &1})}
          error -> error
        end
    end
  end

  defp resolved_card_set_ids(mappings, card_sets) do
    mappings
    |> Enum.filter(fn mapping ->
      case Map.fetch(card_sets, mapping.card_set_id) do
        {:ok, card_set} ->
          card_set.cardmarket_mapping_authority == "administrator" and
            card_set.cardmarket_expansion_id == mapping.expansion_id

        :error ->
          false
      end
    end)
    |> MapSet.new(& &1.card_set_id)
  end

  defp list_unresolved_cardmarket_review_mappings(batch_id, %MapSet{} = resolved_set_ids, actor) do
    query =
      CardmarketExpansionMapping
      |> for_read(:by_batch, %{source_batch_id: batch_id}, actor: actor)
      |> filter(status == "review")
      |> sort(inserted_at: :asc, id: :asc)
      |> limit(@cardmarket_review_queue_limit)

    query =
      case MapSet.to_list(resolved_set_ids) do
        [] -> query
        ids -> filter(query, card_set_id not in ^ids)
      end

    Ash.read(query, actor: actor)
  end

  defp attach_cardmarket_card_sets(mappings, card_sets) do
    Enum.flat_map(mappings, fn mapping ->
      case Map.fetch(card_sets, mapping.card_set_id) do
        {:ok, card_set} -> [Map.put(mapping, :card_set, card_set)]
        :error -> []
      end
    end)
  end

  resources do
    resource TcgCheap.Catalogue.CardSet do
      define :import_card_set, action: :import
      define :get_card_set_by_tcgdex_id, action: :by_tcgdex_id, args: [:tcgdex_id]
      define :list_admin_card_sets, action: :admin_catalogue
      define :approve_cardmarket_expansion, action: :approve_cardmarket_expansion
    end

    resource TcgCheap.Catalogue.CardPrinting do
      define :create_card_printing, action: :create
      define :seed_card_printing_brief, action: :seed_brief
      define :get_card_printing_by_tcgdex_id, action: :by_tcgdex_id, args: [:tcgdex_id]
      define :cardmarket_bulk_auto_match_card_printing, action: :cardmarket_bulk_auto_match
      define :cardmarket_bulk_review_card_printing, action: :cardmarket_bulk_review
      define :list_cardmarket_anchors, action: :cardmarket_anchors
      define :list_cardmarket_cards_by_set, action: :cardmarket_by_set, args: [:card_set_id]

      define :mark_card_printing_pricing_checked,
        action: :mark_pricing_checked,
        args: [:checked_at]

      define :mark_card_printing_details_enrichment_failed,
        action: :mark_details_enrichment_failed,
        args: [:failed_at]

      define :list_card_printings_by_tcgdex_ids, action: :by_tcgdex_ids, args: [:tcgdex_ids]

      define :list_singles_valuation_candidates,
        action: :singles_valuation_candidates,
        args: [:cursor, :limit]

      define :list_detail_enrichment_candidates,
        action: :detail_enrichment_candidates,
        args: [:cursor, :limit]

      define :get_public_card_printing_by_tcgdex_id,
        action: :public_by_tcgdex_id,
        args: [:tcgdex_id],
        not_found_error?: false

      define :list_public_card_printings_by_tcgdex_ids,
        action: :public_by_tcgdex_ids,
        args: [:tcgdex_ids]

      define :list_recently_tracked_card_printings, action: :recently_tracked
      define :list_public_recently_tracked_card_printings, action: :public_recently_tracked

      define :search_card_printings,
        action: :search,
        args: [:query, {:optional, :limit}]

      define :search_public_card_printings,
        action: :public_search,
        args: [:query, {:optional, :limit}]

      define :add_card_printing_collection_scopes,
        action: :add_collection_scopes,
        args: [:incoming_scopes, :incoming_expires_on, :scoped_at]

      define :lock_card_printing_for_update, action: :lock_for_update_by_id, args: [:id]

      define :lock_card_printing_for_update_by_tcgdex_id,
        action: :lock_for_update_by_tcgdex_id,
        args: [:tcgdex_id],
        not_found_error?: false

      define :list_admin_card_printings, action: :admin_catalogue
      define :correct_cardmarket_mapping, action: :correct_cardmarket_mapping
      define :reopen_cardmarket_mapping, action: :reopen_cardmarket_mapping
    end

    resource TcgCheap.Catalogue.CardPrintingMappingDecision do
      define :record_card_printing_mapping_decision, action: :record

      define :list_card_printing_mapping_decision_history,
        action: :history_for_card_printing,
        args: [:card_printing_id]

      define :list_admin_card_printing_mapping_decisions, action: :admin_catalogue
    end

    resource TcgCheap.Catalogue.CardSetCardmarketMappingDecision do
      define :record_card_set_cardmarket_mapping_decision, action: :record
    end

    resource TcgCheap.Pricing.Singles.SingleValuationSnapshot do
      define :record_single_valuation, action: :record
      define :archive_single_valuation, action: :archive
      define :list_current_single_valuations, action: :current_for_card, args: [:card_printing_id]

      define :get_current_single_valuation,
        action: :current_for_card_and_policy,
        args: [:card_printing_id, :policy_version],
        not_found_error?: false

      define :list_single_valuation_history,
        action: :history_for_card_and_policy,
        args: [:card_printing_id, :policy_version]

      define :list_single_valuation_history_since,
        action: :history_since_for_card_and_policy,
        args: [:card_printing_id, :policy_version, :cardmarket_product_id, :since]

      define :list_homepage_price_changes,
        action: :homepage_price_changes,
        args: [:as_of, {:optional, :limit}]

      define :list_homepage_price_changes_for_policy,
        action: :homepage_price_changes,
        args: [:as_of, {:optional, :limit}, :policy_version]

      define :list_admin_single_valuation_snapshots, action: :admin_catalogue
    end

    resource TcgCheap.Pricing.ExchangeRate do
      define :record_exchange_rate, action: :record
      define :get_latest_exchange_rate, action: :latest, args: [:as_of], not_found_error?: false

      define :list_exchange_rate_history,
        action: :history,
        args: [:as_of, {:optional, :limit}]
    end

    resource TcgCheap.Pricing.SealedDailyAggregate do
      define :record_sealed_daily_aggregate, action: :record

      define :list_homepage_sealed_price_changes,
        action: :homepage_sealed_price_changes,
        args: [:as_of, {:optional, :limit}]

      define :get_sealed_daily_aggregate,
        action: :by_id,
        args: [:id],
        not_found_error?: false

      define :get_latest_sealed_daily_aggregate,
        action: :latest_as_of,
        args: [:sealed_product_id, :calculation_version, :as_of],
        not_found_error?: false

      define :get_latest_ready_sealed_daily_aggregate,
        action: :latest_ready_as_of,
        args: [:sealed_product_id, :calculation_version, :as_of],
        not_found_error?: false

      define :list_sealed_daily_aggregate_history,
        action: :history,
        args: [:sealed_product_id, :calculation_version, :since, :as_of]

      define :list_sealed_daily_aggregate_guide_dependents,
        action: :guide_dependents,
        args: [:sealed_product_id, :calculation_version, :from_date, :through_date]
    end

    resource TcgCheap.Pricing.SealedBuyingGuideSnapshot do
      define :record_sealed_buying_guide_snapshot, action: :record

      define :get_latest_sealed_buying_guide_snapshot,
        action: :latest_as_of,
        args: [:sealed_product_id, :model_version, :as_of],
        not_found_error?: false

      define :get_latest_ready_sealed_buying_guide_snapshot,
        action: :latest_ready_as_of,
        args: [:sealed_product_id, :model_version, :as_of],
        not_found_error?: false

      define :list_sealed_buying_guide_snapshot_history,
        action: :history,
        args: [:sealed_product_id, :model_version, :since, :as_of]
    end

    resource TcgCheap.Catalogue.SealedProduct do
      define :create_sealed_product_draft, action: :create_draft

      define :create_sealed_product_draft_from_listing,
        action: :create_draft_from_listing,
        args: [:retailer_listing_id]

      define :import_sealed_product_draft, action: :import_draft
      define :revise_sealed_product_draft, action: :revise_draft
      define :enrich_approved_sealed_product, action: :enrich_approved
      define :approve_sealed_product, action: :approve
      define :archive_sealed_product, action: :archive
      define :mark_sealed_product_discontinued, action: :mark_discontinued
      define :get_sealed_product_by_slug, action: :by_slug, args: [:slug]

      define :get_public_sealed_product_by_id,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :get_public_sealed_product_by_slug,
        action: :public_by_slug,
        args: [:slug],
        not_found_error?: false

      define :list_public_sealed_products, action: :public_catalogue

      define :list_approved_sealed_products, action: :approved_catalogue

      define :list_recent_public_sealed_products,
        action: :recent_public_releases,
        args: [:since, :as_of]

      define :search_public_sealed_products,
        action: :search_public,
        args: [:query, {:optional, :limit}]

      define :list_sealed_product_draft_review_queue, action: :draft_review_queue

      define :get_sealed_product_draft_for_review,
        action: :draft_review_by_id,
        args: [:id],
        not_found_error?: false

      define :lock_sealed_product_for_update,
        action: :lock_for_update_by_id,
        args: [:id],
        not_found_error?: false
    end

    resource TcgCheap.Catalogue.SealedProductAlias do
      define :create_sealed_product_alias, action: :create
      define :admin_create_sealed_product_alias, action: :admin_create
      define :admin_revise_pending_sealed_product_alias, action: :admin_revise_pending
      define :list_admin_sealed_product_aliases, action: :admin_catalogue
      define :import_sealed_product_alias, action: :import
      define :approve_sealed_product_alias, action: :approve
      define :reject_sealed_product_alias, action: :reject
      define :list_sealed_product_alias_pending_queue, action: :pending_queue
      define :list_sealed_product_alias_rejected_queue, action: :rejected_queue

      define :get_pending_sealed_product_alias_for_review,
        action: :pending_review_by_id,
        args: [:id],
        not_found_error?: false

      define :lock_sealed_product_alias_for_update,
        action: :lock_for_update_by_id,
        args: [:id],
        not_found_error?: false

      define :list_approved_sealed_product_aliases,
        action: :approved_for_product,
        args: [:sealed_product_id]

      define :list_approved_ean_aliases, action: :approved_ean_aliases, args: [:normalized_value]
    end

    resource TcgCheap.Catalogue.Retailer do
      define :register_retailer, action: :register
      define :disable_retailer, action: :disable
      define :enable_retailer, action: :enable

      define :get_retailer_by_source_key,
        action: :by_source_key,
        args: [:source_key]

      define :find_retailer_by_source_key,
        action: :by_source_key,
        args: [:source_key],
        not_found_error?: false

      define :list_active_retailers, action: :active
    end

    resource TcgCheap.Catalogue.RetailerListing do
      define :ingest_retailer_listing, action: :ingest
      define :disable_retailer_listing, action: :disable

      define :get_retailer_listing,
        action: :by_source_listing,
        args: [:retailer_id, :source_listing_id]

      define :get_retailer_listing_by_id,
        action: :by_id,
        args: [:id],
        not_found_error?: false

      define :list_active_retailer_listings, action: :active_for_retailer, args: [:retailer_id]
    end

    resource TcgCheap.Pricing.SealedListingObservation do
      define :record_sealed_listing_observation, action: :record

      define :get_latest_sealed_listing_observation,
        action: :latest_for_listing,
        args: [:retailer_listing_id],
        not_found_error?: false

      define :list_sealed_listing_observation_history,
        action: :history_for_listing,
        args: [:retailer_listing_id]
    end

    resource TcgCheap.Catalogue.ListingProductMapping do
      define :create_pending_listing_mapping, action: :create_pending
      define :create_review_listing_mapping, action: :create_review
      define :create_matched_listing_mapping, action: :create_matched
      define :import_listing_mapping, action: :import
      define :approve_listing_mapping, action: :approve
      define :reject_listing_mapping, action: :reject
      define :reopen_listing_mapping, action: :reopen
      define :list_listing_mapping_review_queue, action: :review_queue
      define :list_admin_listing_mappings, action: :admin_catalogue

      define :get_listing_mapping_for_review,
        action: :review_by_id,
        args: [:id],
        not_found_error?: false

      define :get_matched_listing_mapping,
        action: :matched_by_listing,
        args: [:retailer_listing_id],
        not_found_error?: false

      define :get_listing_mapping,
        action: :by_listing,
        args: [:retailer_listing_id],
        not_found_error?: false

      define :list_public_listing_mappings_for_product,
        action: :public_for_product,
        args: [:confirmed_product_id]

      define :lock_listing_mapping_for_update,
        action: :lock_for_update_by_id,
        args: [:id],
        not_found_error?: false
    end

    resource TcgCheap.Catalogue.ListingProductMappingDecision do
      define :record_listing_mapping_decision, action: :record

      define :list_listing_mapping_decision_history,
        action: :history_for_mapping,
        args: [:mapping_id]

      define :list_admin_listing_mapping_decisions, action: :admin_catalogue
    end

    resource TcgCheap.Catalogue.CardmarketExpansionMapping do
      define :record_cardmarket_expansion_mapping, action: :record

      define :get_cardmarket_expansion_mapping,
        action: :by_id,
        args: [:id],
        not_found_error?: false

      define :list_cardmarket_expansion_mappings_for_batch,
        action: :by_batch,
        args: [:source_batch_id]

      define :list_admin_cardmarket_expansion_mappings, action: :admin_catalogue
    end

    resource TcgCheap.Catalogue.CardmarketCardMappingEvidence do
      define :record_cardmarket_card_mapping_evidence, action: :record

      define :list_cardmarket_card_mapping_evidence_for_batch,
        action: :by_batch,
        args: [:source_batch_id]

      define :list_admin_cardmarket_card_mapping_evidence, action: :admin_catalogue
    end

    resource TcgCheap.Pricing.CardmarketBulk.Batch do
      define :get_latest_successful_cardmarket_bulk_batch,
        action: :latest_successful,
        not_found_error?: false

      define :complete_cardmarket_bulk_batch, action: :complete
      define :get_latest_cardmarket_bulk_batch, action: :latest, not_found_error?: false

      define :get_cardmarket_bulk_batch_by_identity,
        action: :by_identity,
        args: [
          :policy_version,
          :product_created_at,
          :price_created_at,
          :product_sha256,
          :price_sha256
        ],
        not_found_error?: false
    end

    resource TcgCheap.Pricing.CardmarketBulk.RawResponse do
      define :store_cardmarket_bulk_raw_response, action: :store
      define :list_cardmarket_bulk_raw_responses_for_batch, action: :for_batch, args: [:batch_id]
    end

    resource TcgCheap.Pricing.CardmarketBulk.Product do
      define :upsert_cardmarket_bulk_product, action: :upsert

      define :list_cardmarket_bulk_products_by_product_ids,
        action: :by_product_ids,
        args: [:cardmarket_product_ids]

      define :list_cardmarket_bulk_products_for_batch_and_expansion,
        action: :for_batch_and_expansion,
        args: [:batch_id, :expansion_id]
    end

    resource TcgCheap.Pricing.CardmarketBulk.Price do
      define :upsert_cardmarket_bulk_price, action: :upsert

      define :list_cardmarket_bulk_prices_by_product_ids,
        action: :by_product_ids,
        args: [:cardmarket_product_ids]
    end
  end
end
