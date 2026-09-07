defmodule TcgCheap.Catalogue.CardSet do
  @moduledoc "An imported TCGdex set and its source metadata."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_sets"
    repo TcgCheap.Repo

    custom_indexes do
      index [:cardmarket_expansion_id],
        unique: true,
        where: "cardmarket_mapping_authority = 'administrator'"
    end

    check_constraints do
      check_constraint [:official_count, :total_count], "card_sets_counts_invariant",
        check:
          "(official_count IS NULL OR official_count >= 0) AND (total_count IS NULL OR total_count >= 0) AND (official_count IS NULL OR total_count IS NULL OR official_count <= total_count)",
        message: "counts must be nonnegative and official_count cannot exceed total_count"

      check_constraint [
                         :cardmarket_mapping_status,
                         :cardmarket_expansion_id,
                         :cardmarket_mapping_authority,
                         :cardmarket_mapping_reason
                       ],
                       "card_sets_cardmarket_mapping_invariant",
                       check:
                         "cardmarket_mapping_status IN ('pending', 'matched') AND ((cardmarket_mapping_status = 'pending' AND cardmarket_expansion_id IS NULL AND cardmarket_mapping_authority IS NULL AND cardmarket_mapping_reason IS NULL) OR (cardmarket_mapping_status = 'matched' AND cardmarket_expansion_id > 0 AND cardmarket_mapping_authority = 'administrator' AND cardmarket_mapping_reason IS NOT NULL AND btrim(cardmarket_mapping_reason) <> ''))"
    end
  end

  actions do
    defaults [:read]

    create :import do
      accept [
        :tcgdex_id,
        :name,
        :series_id,
        :series_name,
        :release_date,
        :logo_url,
        :symbol_url,
        :official_count,
        :total_count,
        :standard_legal,
        :expanded_legal,
        :source_payload,
        :last_synced_at
      ]

      upsert? true
      upsert_identity :unique_tcgdex_id
    end

    read :by_tcgdex_id do
      argument :tcgdex_id, :string, allow_nil?: false
      get? true
      filter expr(tcgdex_id == ^arg(:tcgdex_id))
    end

    read :admin_catalogue do
      prepare build(sort: [series_name: :asc, release_date: :asc, tcgdex_id: :asc, id: :asc])
    end

    read :lock_for_update_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      prepare build(lock: :for_update)
      filter expr(id == ^arg(:id))
    end

    update :approve_cardmarket_expansion do
      argument :source_mapping_id, :uuid, allow_nil?: false

      argument :reason, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 2_000]

      argument :expected_updated_at, :utc_datetime_usec, allow_nil?: false
      accept []
      require_atomic? false
      transaction? true
      touches_resources [TcgCheap.Catalogue.CardSetCardmarketMappingDecision]
      change TcgCheap.Catalogue.Changes.LockAndValidateCardmarketExpansion
      change TcgCheap.Catalogue.Changes.RecordCardSetCardmarketMappingDecision
    end
  end

  policies do
    bypass action([:import, :by_tcgdex_id]) do
      authorize_if always()
    end

    bypass accessing_from(TcgCheap.Catalogue.CardPrinting, :card_set) do
      authorize_if always()
    end

    policy action([:read, :admin_catalogue]) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end

    policy action(:approve_cardmarket_expansion) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate compare(:official_count, greater_than_or_equal_to: 0)
    validate compare(:total_count, greater_than_or_equal_to: 0)
    validate compare(:official_count, less_than_or_equal_to: :total_count)
    validate one_of(:cardmarket_mapping_status, ["pending", "matched"])
    validate one_of(:cardmarket_mapping_authority, ["administrator"])
    validate compare(:cardmarket_expansion_id, greater_than: 0)
    validate match(:cardmarket_mapping_reason, ~r/\S+/)
  end

  attributes do
    uuid_primary_key :id
    attribute :tcgdex_id, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :series_id, :string, public?: true
    attribute :series_name, :string, public?: true
    attribute :release_date, :date, public?: true
    attribute :logo_url, :string, public?: true
    attribute :symbol_url, :string, public?: true
    attribute :official_count, :integer, public?: true
    attribute :total_count, :integer, public?: true
    attribute :standard_legal, :boolean, public?: true
    attribute :expanded_legal, :boolean, public?: true
    attribute :source_payload, :map, public?: false, select_by_default?: false
    attribute :last_synced_at, :utc_datetime_usec, public?: true
    attribute :cardmarket_expansion_id, :integer, public?: true, constraints: [min: 1]

    attribute :cardmarket_mapping_status, :string,
      allow_nil?: false,
      default: "pending",
      public?: true

    attribute :cardmarket_mapping_authority, :string, public?: true
    attribute :cardmarket_mapping_evidence_at, :utc_datetime_usec, public?: true
    attribute :cardmarket_mapping_reason, :string, public?: true, constraints: [max_length: 2_000]
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :card_printings, TcgCheap.Catalogue.CardPrinting
    has_many :cardmarket_mapping_decisions, TcgCheap.Catalogue.CardSetCardmarketMappingDecision
  end

  aggregates do
    count :imported_printings, :card_printings, public?: true
  end

  identities do
    identity :unique_tcgdex_id, [:tcgdex_id]
  end
end
