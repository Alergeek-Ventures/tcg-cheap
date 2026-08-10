defmodule TcgCheap.Catalogue.ListingProductMappingDecision do
  @moduledoc "Immutable decision history for an explicit listing-product mapping transition."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "listing_product_mapping_decisions"
    repo TcgCheap.Repo

    references do
      reference :mapping, on_delete: :restrict
      reference :candidate_product, on_delete: :restrict
      reference :confirmed_product, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:event, :from_status, :to_status],
                       "listing_product_mapping_decisions_transition_invariant",
                       check:
                         "(event = 'created' AND from_status IS NULL AND to_status IN ('pending', 'review', 'matched')) OR (event = 'baseline' AND from_status IS NULL AND to_status IN ('pending', 'review', 'matched', 'rejected')) OR (event = 'approved' AND from_status IN ('pending', 'review') AND to_status = 'matched') OR (event = 'rejected' AND from_status IN ('pending', 'review') AND to_status = 'rejected') OR (event = 'reopened' AND from_status IN ('matched', 'rejected') AND to_status = 'review')"

      check_constraint [
                         :to_status,
                         :candidate_product_id,
                         :confirmed_product_id,
                         :confidence,
                         :reason,
                         :evidence_method,
                         :evidence_gtin
                       ],
                       "listing_product_mapping_decisions_snapshot_invariant",
                       check:
                         "(to_status = 'pending' AND candidate_product_id IS NULL AND confirmed_product_id IS NULL AND confidence IS NULL AND reason IS NULL AND evidence_method IS NULL AND evidence_gtin IS NULL) OR (to_status = 'review' AND confirmed_product_id IS NULL AND reason IS NOT NULL AND btrim(reason) <> '' AND (confidence IS NULL OR (confidence > 0 AND confidence <= 1 AND confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric))) OR (to_status = 'matched' AND confirmed_product_id IS NOT NULL AND candidate_product_id IS NULL AND confidence > 0 AND confidence <= 1 AND confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric AND reason IS NULL AND evidence_method IS NOT NULL AND btrim(evidence_method) <> '') OR (to_status = 'rejected' AND candidate_product_id IS NULL AND confirmed_product_id IS NULL AND confidence IS NULL AND reason IS NOT NULL AND btrim(reason) <> '' AND evidence_method IS NULL AND evidence_gtin IS NULL)"

      check_constraint [:confidence],
                       "listing_product_mapping_decisions_confidence_finite_invariant",
                       check:
                         "confidence IS NULL OR (confidence > 0 AND confidence <= 1 AND confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric)"

      check_constraint [:actor_type, :actor_id, :actor_email],
                       "listing_product_mapping_decisions_actor_invariant",
                       check:
                         "(actor_type = 'system' AND actor_id IS NULL AND actor_email IS NULL) OR (actor_type = 'administrator' AND actor_id IS NOT NULL AND actor_email IS NOT NULL AND btrim(actor_email) <> '')"

      check_constraint [:evidence_method, :evidence_gtin],
                       "listing_product_mapping_decisions_evidence_invariant",
                       check:
                         "(evidence_method IS NULL AND evidence_gtin IS NULL) OR (evidence_method IS NOT NULL AND btrim(evidence_method) <> '')"

      custom_indexes do
        index [:mapping_id, :inserted_at, :id]
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :mapping_id,
        :event,
        :from_status,
        :to_status,
        :candidate_product_id,
        :confirmed_product_id,
        :confidence,
        :reason,
        :evidence_method,
        :evidence_gtin,
        :actor_type,
        :actor_id,
        :actor_email,
        :mapping_updated_at
      ]
    end

    read :history_for_mapping do
      argument :mapping_id, :uuid, allow_nil?: false
      filter expr(mapping_id == ^arg(:mapping_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :admin_catalogue do
      prepare build(
                sort: [inserted_at: :desc, id: :desc],
                load: [:mapping, :candidate_product, :confirmed_product]
              )
    end
  end

  policies do
    policy action(:record) do
      forbid_if always()
    end

    policy action([:read, :history_for_mapping, :admin_catalogue]) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :event, :string, allow_nil?: false, public?: true, constraints: [max_length: 16]
    attribute :from_status, :string, public?: true, constraints: [max_length: 16]
    attribute :to_status, :string, allow_nil?: false, public?: true, constraints: [max_length: 16]
    attribute :confidence, :decimal, public?: true
    attribute :reason, :string, public?: true, constraints: [max_length: 2_000]
    attribute :evidence_method, :string, public?: true, constraints: [max_length: 64]
    attribute :evidence_gtin, :string, public?: true, constraints: [max_length: 14]

    attribute :actor_type, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 16]

    attribute :actor_id, :uuid, public?: true
    attribute :actor_email, :ci_string, public?: true, constraints: [max_length: 320]
    attribute :mapping_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :mapping, TcgCheap.Catalogue.ListingProductMapping,
      allow_nil?: false,
      public?: true

    belongs_to :candidate_product, TcgCheap.Catalogue.SealedProduct, public?: true
    belongs_to :confirmed_product, TcgCheap.Catalogue.SealedProduct, public?: true
  end
end
