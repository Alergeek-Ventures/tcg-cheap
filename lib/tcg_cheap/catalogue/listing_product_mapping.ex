defmodule TcgCheap.Catalogue.ListingProductMapping do
  @moduledoc "Human-reviewable projection from a retailer listing to a sealed product."
  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

  postgres do
    table "listing_product_mappings"
    repo TcgCheap.Repo

    references do
      reference :retailer_listing, on_delete: :delete
      reference :candidate_product, on_delete: :nilify
      reference :confirmed_product, on_delete: :nilify
    end

    check_constraints do
      check_constraint [:status], "listing_product_mappings_status_invariant",
        check: "status IN ('pending', 'matched', 'review', 'rejected')"

      check_constraint [
                         :status,
                         :candidate_product_id,
                         :confirmed_product_id,
                         :confidence,
                         :evidence,
                         :reason,
                         :approved_at,
                         :rejected_at
                       ],
                       "listing_product_mappings_state_invariant",
                       check:
                         "(status = 'pending' AND candidate_product_id IS NULL AND confirmed_product_id IS NULL AND confidence IS NULL AND approved_at IS NULL AND rejected_at IS NULL AND (evidence IS NULL OR evidence = '{}'::jsonb) AND reason IS NULL) OR (status = 'matched' AND candidate_product_id IS NULL AND confirmed_product_id IS NOT NULL AND confidence > 0 AND confidence <= 1 AND confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric AND evidence IS NOT NULL AND evidence <> '{}'::jsonb AND approved_at IS NOT NULL AND rejected_at IS NULL AND reason IS NULL) OR (status = 'review' AND confirmed_product_id IS NULL AND rejected_at IS NULL AND approved_at IS NULL AND reason IS NOT NULL AND btrim(reason) <> '' AND (confidence IS NULL OR (confidence > 0 AND confidence <= 1 AND confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric))) OR (status = 'rejected' AND candidate_product_id IS NULL AND confirmed_product_id IS NULL AND confidence IS NULL AND evidence IS NULL AND reason IS NOT NULL AND btrim(reason) <> '' AND rejected_at IS NOT NULL AND approved_at IS NULL)"

      check_constraint [:confidence], "listing_product_mappings_confidence_finite_invariant",
        check:
          "confidence IS NULL OR (confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric)"

      custom_indexes do
        index "retailer_listing_id", name: "listing_product_mappings_listing_index"
        index "candidate_product_id", name: "listing_product_mappings_candidate_index"
        index "confirmed_product_id", name: "listing_product_mappings_confirmed_index"
      end
    end
  end

  actions do
    defaults [:read]

    create :create_pending do
      accept [:retailer_listing_id]
      validate {TcgCheap.Catalogue.Validations.ListingProductMapping, state: :pending}
    end

    create :create_review do
      accept [:retailer_listing_id, :candidate_product_id, :confidence, :evidence, :reason]
      change set_attribute(:status, "review")
      validate {TcgCheap.Catalogue.Validations.ListingProductMapping, state: :review}
    end

    create :create_matched do
      accept [:retailer_listing_id, :confirmed_product_id, :confidence, :evidence]
      change set_attribute(:status, "matched")
      change atomic_update(:approved_at, expr(now()))
      change TcgCheap.Catalogue.Changes.ValidateConfirmedProduct
      validate {TcgCheap.Catalogue.Validations.ListingProductMapping, state: :matched}
    end

    create :import do
      accept [
        :retailer_listing_id,
        :candidate_product_id,
        :confidence,
        :evidence,
        :reason,
        :status
      ]

      change set_attribute(:status, "review")
      validate {TcgCheap.Catalogue.Validations.ListingProductMapping, state: :review}
      upsert? true
      upsert_identity :unique_listing
      upsert_fields [:status, :candidate_product_id, :confidence, :evidence, :reason]

      upsert_condition expr(status in ["pending", "review"])

      return_skipped_upsert? true
    end

    update :approve do
      accept [:confirmed_product_id, :confidence, :evidence]
      # Required only because the latest-state row lock runs before the update.
      require_atomic? false
      change set_attribute(:status, "matched")
      change set_attribute(:candidate_product_id, nil)
      change set_attribute(:reason, nil)
      change set_attribute(:rejected_at, nil)
      change atomic_update(:approved_at, expr(now()))
      change TcgCheap.Catalogue.Changes.LockAndValidateListingMapping
      change TcgCheap.Catalogue.Changes.ValidateConfirmedProduct
      validate {TcgCheap.Catalogue.Validations.ListingProductMapping, state: :matched}
    end

    update :reject do
      accept [:reason]
      # Required only because the latest-state row lock runs before the update.
      require_atomic? false
      change set_attribute(:status, "rejected")
      change set_attribute(:candidate_product_id, nil)
      change set_attribute(:confirmed_product_id, nil)
      change set_attribute(:confidence, nil)
      change set_attribute(:evidence, nil)
      change set_attribute(:approved_at, nil)
      change atomic_update(:rejected_at, expr(now()))
      change TcgCheap.Catalogue.Changes.LockAndValidateListingMapping
      validate {TcgCheap.Catalogue.Validations.ListingProductMapping, state: :rejected}
    end

    read :review_queue do
      filter expr(status in ["pending", "review"])
      prepare build(sort: [inserted_at: :asc])
    end

    read :matched_by_listing do
      argument :retailer_listing_id, :uuid, allow_nil?: false
      get? true
      filter expr(retailer_listing_id == ^arg(:retailer_listing_id) and status == "matched")
    end

    read :by_listing do
      argument :retailer_listing_id, :uuid, allow_nil?: false
      get? true
      filter expr(retailer_listing_id == ^arg(:retailer_listing_id))
    end

    read :lock_for_update_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(lock: :for_update)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :status, :string, allow_nil?: false, default: "pending", public?: true
    attribute :confidence, :decimal, public?: true
    attribute :evidence, :map, public?: true
    attribute :reason, :string, public?: true
    attribute :approved_at, :utc_datetime_usec, public?: true
    attribute :rejected_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :retailer_listing, TcgCheap.Catalogue.RetailerListing,
      allow_nil?: false,
      public?: true

    belongs_to :candidate_product, TcgCheap.Catalogue.SealedProduct, public?: true
    belongs_to :confirmed_product, TcgCheap.Catalogue.SealedProduct, public?: true
  end

  identities do
    identity :unique_listing, [:retailer_listing_id]
  end
end
