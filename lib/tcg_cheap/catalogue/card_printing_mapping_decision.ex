defmodule TcgCheap.Catalogue.CardPrintingMappingDecision do
  @moduledoc "Immutable, scalar-only history of Cardmarket mapping decisions."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_printing_mapping_decisions"
    repo TcgCheap.Repo

    references do
      reference :card_printing, on_delete: :restrict
    end

    custom_indexes do
      index [:card_printing_id, :inserted_at, :id]
    end

    check_constraints do
      check_constraint [:event, :from_status, :to_status, :from_cardmarket_product_id],
                       "card_printing_mapping_decisions_transition_invariant",
                       check:
                         "((from_status = 'matched' AND from_cardmarket_product_id IS NOT NULL AND from_cardmarket_product_id > 0) OR (from_status IS NULL OR from_status IN ('pending', 'unmatched', 'review')) AND from_cardmarket_product_id IS NULL) AND ((event = 'imported' AND from_status IS NULL AND to_status IN ('pending', 'matched', 'unmatched', 'review')) OR (event = 'baseline' AND from_status IS NULL AND to_status IN ('pending', 'matched', 'unmatched', 'review')) OR (event = 'provider_updated' AND from_status IN ('pending', 'matched', 'unmatched', 'review') AND to_status IN ('pending', 'matched', 'unmatched', 'review')) OR (event = 'corrected' AND from_status IN ('pending', 'matched', 'unmatched', 'review') AND to_status = 'matched') OR (event = 'reopened' AND from_status IN ('matched', 'unmatched') AND to_status = 'review'))"

      check_constraint [:event, :to_status, :cardmarket_product_id, :reason],
                       "card_printing_mapping_decisions_state_invariant",
                       check:
                         "((to_status = 'matched' AND cardmarket_product_id IS NOT NULL AND cardmarket_product_id > 0 AND ((event = 'corrected' AND reason IS NOT NULL AND btrim(reason) <> '') OR (event <> 'corrected' AND reason IS NULL))) OR (to_status IN ('pending', 'unmatched') AND cardmarket_product_id IS NULL AND reason IS NULL) OR (to_status = 'review' AND cardmarket_product_id IS NULL AND reason IS NOT NULL AND btrim(reason) <> '')) AND char_length(coalesce(reason, '')) <= 2000"

      check_constraint [:mapping_authority],
                       "card_printing_mapping_decisions_authority_invariant",
                       check: "mapping_authority IN ('provider', 'administrator')"

      check_constraint [:actor_type, :actor_id, :actor_email],
                       "card_printing_mapping_decisions_actor_invariant",
                       check:
                         "(actor_type = 'system' AND actor_id IS NULL AND actor_email IS NULL) OR (actor_type = 'administrator' AND actor_id IS NOT NULL AND actor_email IS NOT NULL AND btrim(actor_email) <> '')"

      check_constraint [:event, :mapping_authority, :actor_type],
                       "card_printing_mapping_decisions_event_authority_actor_invariant",
                       check:
                         "(event IN ('imported', 'provider_updated', 'baseline') AND mapping_authority = 'provider' AND actor_type = 'system') OR (event IN ('corrected', 'reopened') AND mapping_authority = 'administrator' AND actor_type = 'administrator')"
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :card_printing_id,
        :event,
        :from_status,
        :to_status,
        :from_cardmarket_product_id,
        :cardmarket_product_id,
        :mapping_authority,
        :reason,
        :source_mapping_evidence_at,
        :printing_version_at,
        :actor_type,
        :actor_id,
        :actor_email
      ]
    end

    read :history_for_card_printing do
      argument :card_printing_id, :uuid, allow_nil?: false
      filter expr(card_printing_id == ^arg(:card_printing_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :admin_catalogue do
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:card_printing])
    end
  end

  policies do
    policy action(:record), do: forbid_if(always())

    policy action([:read, :history_for_card_printing, :admin_catalogue]) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate one_of(:event, ~w(imported baseline provider_updated corrected reopened))
    validate one_of(:mapping_authority, ~w(provider administrator))
    validate one_of(:actor_type, ~w(system administrator))
    validate compare(:from_cardmarket_product_id, greater_than: 0)
    validate compare(:cardmarket_product_id, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id
    attribute :event, :string, allow_nil?: false, public?: true, constraints: [max_length: 16]
    attribute :from_status, :string, public?: true
    attribute :to_status, :string, allow_nil?: false, public?: true
    attribute :from_cardmarket_product_id, :integer, public?: true, constraints: [min: 1]
    attribute :cardmarket_product_id, :integer, public?: true, constraints: [min: 1]
    attribute :mapping_authority, :string, allow_nil?: false, public?: true
    attribute :reason, :string, public?: true, constraints: [max_length: 2_000]
    attribute :source_mapping_evidence_at, :utc_datetime_usec, public?: true
    attribute :printing_version_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :actor_type, :string, allow_nil?: false, public?: true
    attribute :actor_id, :uuid, public?: true
    attribute :actor_email, :ci_string, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :card_printing, TcgCheap.Catalogue.CardPrinting, allow_nil?: false, public?: true
  end
end
