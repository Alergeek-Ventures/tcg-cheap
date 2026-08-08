defmodule TcgCheap.Catalogue.SealedProductAlias do
  @moduledoc "A normalized name or GTIN alias awaiting catalogue review."
  alias TcgCheap.Catalogue.SealedIdentifier
  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_product_aliases"
    repo TcgCheap.Repo

    references do
      reference :sealed_product, on_delete: :delete
    end

    check_constraints do
      check_constraint [:kind, :original_value, :normalized_value],
                       "sealed_product_aliases_identity_invariant",
                       check:
                         "kind IN ('name', 'ean') AND btrim(original_value) <> '' AND ((kind = 'name' AND btrim(normalized_value) <> '') OR (kind = 'ean' AND normalized_value ~ '^[0-9]+$' AND ((length(normalized_value) = 8 AND mod(10 - mod(3 * substring(normalized_value, 1, 1)::integer + substring(normalized_value, 2, 1)::integer + 3 * substring(normalized_value, 3, 1)::integer + substring(normalized_value, 4, 1)::integer + 3 * substring(normalized_value, 5, 1)::integer + substring(normalized_value, 6, 1)::integer + 3 * substring(normalized_value, 7, 1)::integer, 10), 10) = substring(normalized_value, 8, 1)::integer) OR (length(normalized_value) = 12 AND mod(10 - mod(3 * substring(normalized_value, 1, 1)::integer + substring(normalized_value, 2, 1)::integer + 3 * substring(normalized_value, 3, 1)::integer + substring(normalized_value, 4, 1)::integer + 3 * substring(normalized_value, 5, 1)::integer + substring(normalized_value, 6, 1)::integer + 3 * substring(normalized_value, 7, 1)::integer + substring(normalized_value, 8, 1)::integer + 3 * substring(normalized_value, 9, 1)::integer + substring(normalized_value, 10, 1)::integer + 3 * substring(normalized_value, 11, 1)::integer, 10), 10) = substring(normalized_value, 12, 1)::integer) OR (length(normalized_value) = 13 AND mod(10 - mod(substring(normalized_value, 1, 1)::integer + 3 * substring(normalized_value, 2, 1)::integer + substring(normalized_value, 3, 1)::integer + 3 * substring(normalized_value, 4, 1)::integer + substring(normalized_value, 5, 1)::integer + 3 * substring(normalized_value, 6, 1)::integer + substring(normalized_value, 7, 1)::integer + 3 * substring(normalized_value, 8, 1)::integer + substring(normalized_value, 9, 1)::integer + 3 * substring(normalized_value, 10, 1)::integer + substring(normalized_value, 11, 1)::integer + 3 * substring(normalized_value, 12, 1)::integer, 10), 10) = substring(normalized_value, 13, 1)::integer) OR (length(normalized_value) = 14 AND mod(10 - mod(3 * substring(normalized_value, 1, 1)::integer + substring(normalized_value, 2, 1)::integer + 3 * substring(normalized_value, 3, 1)::integer + substring(normalized_value, 4, 1)::integer + 3 * substring(normalized_value, 5, 1)::integer + substring(normalized_value, 6, 1)::integer + 3 * substring(normalized_value, 7, 1)::integer + substring(normalized_value, 8, 1)::integer + 3 * substring(normalized_value, 9, 1)::integer + substring(normalized_value, 10, 1)::integer + 3 * substring(normalized_value, 11, 1)::integer + substring(normalized_value, 12, 1)::integer + 3 * substring(normalized_value, 13, 1)::integer, 10), 10) = substring(normalized_value, 14, 1)::integer))))"

      check_constraint [:review_status], "sealed_product_aliases_status_invariant",
        check: "review_status IN ('pending', 'approved', 'rejected')"

      check_constraint [:review_status, :approved_at, :rejected_at],
                       "sealed_product_aliases_review_timestamps_invariant",
                       check:
                         "(review_status = 'pending' AND approved_at IS NULL AND rejected_at IS NULL) OR (review_status = 'approved' AND approved_at IS NOT NULL AND rejected_at IS NULL) OR (review_status = 'rejected' AND rejected_at IS NOT NULL AND approved_at IS NULL)"

      custom_indexes do
        index "sealed_product_id", name: "sealed_product_aliases_product_id_index"

        index "normalized_value",
          name: "sealed_product_aliases_unique_ean_index",
          unique: true,
          where: "kind = 'ean'"
      end

      check_constraint [:kind, :normalized_value], "sealed_product_aliases_gtin_check",
        check: "kind <> 'ean' OR #{SealedIdentifier.postgres_gtin_check("normalized_value")}"
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:sealed_product_id, :kind, :original_value, :source, :source_id, :source_payload]
      change TcgCheap.Catalogue.Changes.NormalizeSealedIdentifier
      validate TcgCheap.Catalogue.Validations.SealedIdentifier
    end

    create :import do
      accept [:sealed_product_id, :kind, :original_value, :source, :source_id, :source_payload]
      change TcgCheap.Catalogue.Changes.NormalizeSealedIdentifier
      validate TcgCheap.Catalogue.Validations.SealedIdentifier
      upsert? true
      upsert_identity :unique_product_kind_value
      upsert_fields [:original_value, :normalized_value, :source, :source_id, :source_payload]

      upsert_condition expr(
                         review_status == "pending" and
                           review_status == upsert_conflict(:review_status)
                       )

      return_skipped_upsert? true
    end

    update :approve do
      accept []
      # Transaction-local row lock and latest pending-state check require a non-atomic action.
      require_atomic? false
      change set_attribute(:review_status, "approved")
      change atomic_update(:approved_at, expr(now()))

      change {TcgCheap.Catalogue.Changes.LockAndValidateReview,
              resource: __MODULE__,
              lock_action: :lock_for_update_by_id,
              status_attribute: :review_status,
              expected_status: "pending"}
    end

    update :reject do
      accept []
      # Transaction-local row lock and latest pending-state check require a non-atomic action.
      require_atomic? false
      change set_attribute(:review_status, "rejected")
      change atomic_update(:rejected_at, expr(now()))

      change {TcgCheap.Catalogue.Changes.LockAndValidateReview,
              resource: __MODULE__,
              lock_action: :lock_for_update_by_id,
              status_attribute: :review_status,
              expected_status: "pending"}
    end

    read :pending_queue do
      filter expr(review_status == "pending")
      prepare build(sort: [inserted_at: :asc, normalized_value: :asc])
    end

    read :approved_for_product do
      argument :sealed_product_id, :uuid, allow_nil?: false
      filter expr(sealed_product_id == ^arg(:sealed_product_id) and review_status == "approved")
      prepare build(sort: [kind: :asc, normalized_value: :asc])
    end

    read :approved_ean_aliases do
      argument :normalized_value, :string, allow_nil?: false

      filter expr(
               kind == "ean" and review_status == "approved" and
                 normalized_value == ^arg(:normalized_value) and
                 sealed_product.publication_status == "approved" and
                 sealed_product.officially_distributed == true and
                 sealed_product.market == "PL" and sealed_product.language == "en" and
                 sealed_product.release_date <= today()
             )

      prepare build(load: [:sealed_product])
    end

    read :rejected_queue do
      filter expr(review_status == "rejected")
      prepare build(sort: [inserted_at: :asc, normalized_value: :asc])
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
    attribute :kind, :string, allow_nil?: false, public?: true

    attribute :original_value, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :normalized_value, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :source, :string, public?: false
    attribute :source_id, :string, public?: false
    attribute :source_payload, :map, public?: false
    attribute :review_status, :string, allow_nil?: false, default: "pending", public?: true
    attribute :approved_at, :utc_datetime_usec, public?: true
    attribute :rejected_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :sealed_product, TcgCheap.Catalogue.SealedProduct, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_product_kind_value, [:sealed_product_id, :kind, :normalized_value]
  end
end
