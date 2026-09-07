defmodule TcgCheap.Catalogue.CardmarketExpansionMapping do
  @moduledoc "Immutable, batch-scoped evidence relating a CardSet to a Cardmarket expansion."

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cardmarket_expansion_mappings"
    repo TcgCheap.Repo
    identity_index_names unique_batch_set_expansion: "cm_expansion_map_batch_set_expansion_idx"

    custom_indexes do
      index [:source_batch_id]
      index [:card_set_id]
    end

    references do
      reference :source_batch, on_delete: :restrict
      reference :card_set, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:status, :review_reason, :expansion_id, :anchor_count],
                       "cardmarket_expansion_mappings_invariant",
                       check:
                         "expansion_id > 0 AND anchor_count > 0 AND ((status = 'approved' AND review_reason IS NULL) OR (status = 'review' AND review_reason IS NOT NULL AND btrim(review_reason) <> '')) AND char_length(coalesce(review_reason, '')) <= 2000"

      check_constraint [:authority], "cardmarket_expansion_mappings_authority_invariant",
        check: "authority IN ('system', 'administrator')"

      check_constraint [:evidence], "cardmarket_expansion_mappings_evidence_present",
        check: "evidence <> '{}'::jsonb"
    end
  end

  actions do
    create :record do
      accept [
        :source_batch_id,
        :card_set_id,
        :expansion_id,
        :status,
        :authority,
        :anchor_count,
        :evidence,
        :review_reason
      ]
    end

    read :read

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      prepare build(load: [:card_set])
      filter expr(id == ^arg(:id))
    end

    read :by_batch do
      argument :source_batch_id, :uuid, allow_nil?: false
      filter expr(source_batch_id == ^arg(:source_batch_id))
    end

    read :admin_catalogue do
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end
  end

  policies do
    policy action(:record) do
      forbid_if always()
    end

    policy action([:by_id, :by_batch]) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end

    policy action(:admin_catalogue) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end

    policy action(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate TcgCheap.Catalogue.Validations.NonEmptyEvidence
    validate one_of(:status, ~w(approved review))
    validate one_of(:authority, ~w(system administrator))
    validate compare(:expansion_id, greater_than: 0)
    validate compare(:anchor_count, greater_than: 0)
    validate match(:review_reason, ~r/\S+/)
  end

  attributes do
    uuid_primary_key :id
    attribute :expansion_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :authority, :string, allow_nil?: false, public?: true
    attribute :anchor_count, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :evidence, :map, allow_nil?: false, default: %{}, public?: true
    attribute :review_reason, :string, public?: true, constraints: [max_length: 2_000]
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :source_batch, TcgCheap.Pricing.CardmarketBulk.Batch,
      allow_nil?: false,
      public?: true

    belongs_to :card_set, TcgCheap.Catalogue.CardSet, allow_nil?: false, public?: true

    has_many :cardmarket_card_mapping_evidence, TcgCheap.Catalogue.CardmarketCardMappingEvidence,
      destination_attribute: :expansion_mapping_id
  end

  identities do
    identity :unique_batch_set_expansion, [:source_batch_id, :card_set_id, :expansion_id]
  end
end
