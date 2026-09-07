defmodule TcgCheap.Catalogue.CardSetCardmarketMappingDecision do
  @moduledoc "Immutable administrator history for CardSet Cardmarket expansion decisions."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_set_cardmarket_mapping_decisions"
    repo TcgCheap.Repo

    references do
      reference :card_set, on_delete: :restrict
      reference :source_mapping, on_delete: :restrict
      reference :source_batch, on_delete: :restrict
      reference :actor, on_delete: :restrict
    end

    custom_indexes do
      index [:card_set_id, :inserted_at, :id]
      index [:source_batch_id]
    end

    check_constraints do
      check_constraint [:event, :reason, :actor_email, :card_set_version_at],
                       "card_set_cardmarket_mapping_decisions_invariant",
                       check:
                         "event IN ('approved', 'corrected') AND btrim(reason) <> '' AND char_length(reason) <= 2000 AND btrim(actor_email) <> ''"

      check_constraint [:from_expansion_id, :to_expansion_id],
                       "card_set_cardmarket_mapping_decisions_expansions_positive",
                       check:
                         "(from_expansion_id IS NULL OR from_expansion_id > 0) AND to_expansion_id > 0"
    end
  end

  actions do
    read :read

    create :record do
      accept [
        :card_set_id,
        :source_mapping_id,
        :source_batch_id,
        :event,
        :from_expansion_id,
        :to_expansion_id,
        :reason,
        :card_set_version_at,
        :actor_id,
        :actor_email
      ]
    end
  end

  policies do
    policy action(:record), do: forbid_if(always())

    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate one_of(:event, ["approved", "corrected"])
    validate compare(:to_expansion_id, greater_than: 0)
    validate match(:reason, ~r/\S+/)
    validate match(:actor_email, ~r/\S+/)
  end

  attributes do
    uuid_primary_key :id
    attribute :event, :string, allow_nil?: false, public?: true
    attribute :from_expansion_id, :integer, public?: true
    attribute :to_expansion_id, :integer, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true, constraints: [max_length: 2_000]
    attribute :card_set_version_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :actor_email, :ci_string, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :card_set, TcgCheap.Catalogue.CardSet, allow_nil?: false, public?: true

    belongs_to :source_mapping, TcgCheap.Catalogue.CardmarketExpansionMapping,
      allow_nil?: false,
      public?: true

    belongs_to :source_batch, TcgCheap.Pricing.CardmarketBulk.Batch,
      allow_nil?: false,
      public?: true

    belongs_to :actor, TcgCheap.Accounts.Admin, allow_nil?: false, public?: true
  end
end
