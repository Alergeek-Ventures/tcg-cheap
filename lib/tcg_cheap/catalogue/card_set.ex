defmodule TcgCheap.Catalogue.CardSet do
  @moduledoc "An imported TCGdex set and its source metadata."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_sets"
    repo TcgCheap.Repo

    check_constraints do
      check_constraint [:official_count, :total_count], "card_sets_counts_invariant",
        check:
          "(official_count IS NULL OR official_count >= 0) AND (total_count IS NULL OR total_count >= 0) AND (official_count IS NULL OR total_count IS NULL OR official_count <= total_count)",
        message: "counts must be nonnegative and official_count cannot exceed total_count"
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
  end

  validations do
    validate compare(:official_count, greater_than_or_equal_to: 0)
    validate compare(:total_count, greater_than_or_equal_to: 0)
    validate compare(:official_count, less_than_or_equal_to: :total_count)
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
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :card_printings, TcgCheap.Catalogue.CardPrinting
  end

  identities do
    identity :unique_tcgdex_id, [:tcgdex_id]
  end
end
