defmodule TcgCheap.Catalogue.CardmarketCardMappingEvidence do
  @moduledoc "Immutable, batch-scoped Cardmarket card crosswalk evidence."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cardmarket_card_mapping_evidence"
    repo TcgCheap.Repo

    identity_index_names unique_batch_mapping_card_printing:
                           "cm_card_evidence_batch_mapping_printing_idx"

    custom_indexes do
      index [:source_batch_id]
      index [:card_printing_id]
    end

    references do
      reference :source_batch, on_delete: :restrict
      reference :expansion_mapping, on_delete: :restrict
      reference :card_printing, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:decision, :cardmarket_product_id, :review_reason],
                       "cardmarket_card_mapping_evidence_invariant",
                       check:
                         "((decision IN ('anchor','auto_matched') AND cardmarket_product_id IS NOT NULL AND cardmarket_product_id > 0 AND review_reason IS NULL) OR (decision = 'review' AND cardmarket_product_id IS NULL AND review_reason IS NOT NULL AND btrim(review_reason) <> '') OR (decision = 'unmatched' AND cardmarket_product_id IS NULL AND review_reason IS NULL)) AND char_length(coalesce(review_reason, '')) <= 2000"

      check_constraint [:authority], "cardmarket_card_mapping_evidence_authority_invariant",
        check: "authority IN ('system','administrator')"

      check_constraint [:evidence], "cardmarket_card_mapping_evidence_evidence_present",
        check: "evidence <> '{}'::jsonb"
    end
  end

  actions do
    create :record do
      accept [
        :source_batch_id,
        :expansion_mapping_id,
        :card_printing_id,
        :decision,
        :cardmarket_product_id,
        :normalized_card_name,
        :evidence,
        :review_reason,
        :authority
      ]
    end

    read :read

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

    policy action(:by_batch) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end

    policy action([:read, :admin_catalogue]) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate TcgCheap.Catalogue.Validations.NonEmptyEvidence
    validate one_of(:decision, ~w(anchor auto_matched review unmatched))
    validate one_of(:authority, ~w(system administrator))
    validate compare(:cardmarket_product_id, greater_than: 0)
    validate match(:normalized_card_name, ~r/\S+/)
    validate match(:review_reason, ~r/\S+/)
  end

  attributes do
    uuid_primary_key :id
    attribute :decision, :string, allow_nil?: false, public?: true
    attribute :cardmarket_product_id, :integer, public?: true, constraints: [min: 1]

    attribute :normalized_card_name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 500]

    attribute :evidence, :map, allow_nil?: false, default: %{}, public?: true
    attribute :review_reason, :string, public?: true, constraints: [max_length: 2_000]
    attribute :authority, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :source_batch, TcgCheap.Pricing.CardmarketBulk.Batch,
      allow_nil?: false,
      public?: true

    belongs_to :expansion_mapping, TcgCheap.Catalogue.CardmarketExpansionMapping,
      allow_nil?: false,
      public?: true

    belongs_to :card_printing, TcgCheap.Catalogue.CardPrinting, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_batch_mapping_card_printing, [
      :source_batch_id,
      :expansion_mapping_id,
      :card_printing_id
    ]
  end
end
