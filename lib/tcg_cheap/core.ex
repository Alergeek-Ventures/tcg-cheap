defmodule TcgCheap.Core do
  @moduledoc """
  The catalogue and pricing resources that back public, locally cached data.
  """

  use Ash.Domain,
    otp_app: :tcg_cheap

  resources do
    resource TcgCheap.Catalogue.CardSet do
      define :import_card_set, action: :import
      define :get_card_set_by_tcgdex_id, action: :by_tcgdex_id, args: [:tcgdex_id]
    end

    resource TcgCheap.Catalogue.CardPrinting do
      define :create_card_printing, action: :create
      define :import_card_printing, action: :import
      define :seed_card_printing_brief, action: :seed_brief
      define :get_card_printing_by_tcgdex_id, action: :by_tcgdex_id, args: [:tcgdex_id]
      define :list_card_printings_by_tcgdex_ids, action: :by_tcgdex_ids, args: [:tcgdex_ids]

      define :search_card_printings,
        action: :search,
        args: [:query, {:optional, :limit}]

      define :lock_card_printing_for_update, action: :lock_for_update_by_id, args: [:id]

      define :lock_card_printing_for_update_by_tcgdex_id,
        action: :lock_for_update_by_tcgdex_id,
        args: [:tcgdex_id],
        not_found_error?: false
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
        args: [:card_printing_id, :policy_version, :since]
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
    end

    resource TcgCheap.Catalogue.SealedProduct do
      define :create_sealed_product_draft, action: :create_draft
      define :import_sealed_product_draft, action: :import_draft
      define :revise_sealed_product_draft, action: :revise_draft
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
      define :get_retailer_by_source_key, action: :by_source_key, args: [:source_key]
      define :list_active_retailers, action: :active
    end

    resource TcgCheap.Catalogue.RetailerListing do
      define :ingest_retailer_listing, action: :ingest
      define :disable_retailer_listing, action: :disable

      define :get_retailer_listing,
        action: :by_source_listing,
        args: [:retailer_id, :source_listing_id]

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
      define :list_listing_mapping_review_queue, action: :review_queue

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
  end
end
