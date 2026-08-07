defmodule TcgCheap.Catalogue.CardPrinting do
  @moduledoc """
  One exact Pokémon card printing from the canonical TCGdex catalogue.

  The TCGdex ID is the stable external identity used by provider acquisition;
  public display metadata can expand as the catalogue importer is introduced.
  """

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "card_printings"
    repo TcgCheap.Repo

    references do
      reference :card_set, index?: true
    end

    custom_indexes do
      index "search_name gin_trgm_ops",
        name: "card_printings_search_name_trgm_index",
        using: "gin",
        concurrently: true

      index "search_set_name gin_trgm_ops",
        name: "card_printings_search_set_name_trgm_index",
        using: "gin",
        concurrently: true

      index "search_collector_number gin_trgm_ops",
        name: "card_printings_search_collector_number_trgm_index",
        using: "gin",
        concurrently: true

      index "search_tcgdex_id gin_trgm_ops",
        name: "card_printings_search_tcgdex_id_trgm_index",
        using: "gin",
        concurrently: true
    end

    custom_statements do
      statement :backfill_search_text do
        up ~S"""
        UPDATE card_printings SET search_name = btrim(lower(regexp_replace(normalize(name, NFKC) COLLATE "pg_unicode_fast", '[[:space:]]+', ' ', 'g'))), search_set_name = btrim(lower(regexp_replace(normalize(set_name, NFKC) COLLATE "pg_unicode_fast", '[[:space:]]+', ' ', 'g'))), search_collector_number = btrim(lower(regexp_replace(normalize(collector_number, NFKC) COLLATE "pg_unicode_fast", '[[:space:]]+', ' ', 'g'))), search_tcgdex_id = btrim(lower(regexp_replace(normalize(tcgdex_id, NFKC) COLLATE "pg_unicode_fast", '[[:space:]]+', ' ', 'g')));
        """

        down "UPDATE card_printings SET search_name = '', search_set_name = '', search_collector_number = '', search_tcgdex_id = '';"
      end
    end

    check_constraints do
      check_constraint [:mapping_status, :cardmarket_product_id, :mapping_review_reason],
                       "card_printings_mapping_invariant",
                       check:
                         "mapping_status IN ('pending', 'matched', 'unmatched', 'review') AND ((mapping_status IN ('pending', 'unmatched') AND cardmarket_product_id IS NULL AND mapping_review_reason IS NULL) OR (mapping_status = 'matched' AND cardmarket_product_id IS NOT NULL AND cardmarket_product_id > 0 AND mapping_review_reason IS NULL) OR (mapping_status = 'review' AND cardmarket_product_id IS NULL AND mapping_review_reason IS NOT NULL AND btrim(mapping_review_reason) <> ''))",
                       message: "has inconsistent mapping fields"
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:tcgdex_id, :name, :set_name, :collector_number]
      change TcgCheap.Catalogue.Changes.SetSearchText
    end

    create :import do
      accept [
        :tcgdex_id,
        :name,
        :set_name,
        :collector_number,
        :card_set_id,
        :image_url,
        :rarity,
        :category,
        :illustrator,
        :regulation_mark,
        :standard_legal,
        :expanded_legal,
        :variant_data,
        :source_updated_at,
        :mapping_updated_at,
        :source_payload,
        :last_synced_at,
        :cardmarket_product_id,
        :mapping_status,
        :mapping_review_reason
      ]

      change TcgCheap.Catalogue.Changes.SetSearchText

      upsert? true
      upsert_identity :unique_tcgdex_id
    end

    create :seed_brief do
      accept [
        :tcgdex_id,
        :name,
        :set_name,
        :collector_number,
        :image_url,
        :card_set_id,
        :last_synced_at
      ]

      change TcgCheap.Catalogue.Changes.SetSearchText

      upsert? true
      upsert_identity :unique_tcgdex_id

      upsert_fields [
        :name,
        :set_name,
        :collector_number,
        :search_name,
        :search_set_name,
        :search_collector_number,
        :search_tcgdex_id,
        :card_set_id,
        :last_synced_at
      ]

      return_skipped_upsert? true

      upsert_condition expr(
                         mapping_status == "pending" and is_nil(source_updated_at) and
                           is_nil(mapping_updated_at) and is_nil(source_payload) and
                           (is_nil(card_set_id) or card_set_id == upsert_conflict(:card_set_id))
                       )
    end

    read :by_tcgdex_id do
      argument :tcgdex_id, :string, allow_nil?: false
      get? true
      filter expr(tcgdex_id == ^arg(:tcgdex_id))
    end

    read :search do
      argument :query, :string, allow_nil?: false, constraints: [max_length: 100]
      argument :limit, :integer, allow_nil?: false, default: 10, constraints: [min: 1, max: 20]
      prepare TcgCheap.Catalogue.Preparations.Search
    end

    read :lock_for_update_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(lock: :for_update)
    end

    read :lock_for_update_by_tcgdex_id do
      argument :tcgdex_id, :string, allow_nil?: false
      get? true
      filter expr(tcgdex_id == ^arg(:tcgdex_id))
      prepare build(lock: :for_update)
    end
  end

  validations do
    validate one_of(:mapping_status, ["pending", "matched", "unmatched", "review"])
    validate compare(:cardmarket_product_id, greater_than: 0)
    validate TcgCheap.Catalogue.Validations.MappingInvariant
  end

  attributes do
    uuid_primary_key :id

    attribute :tcgdex_id, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :set_name, :string do
      allow_nil? false
      public? true
    end

    attribute :collector_number, :string do
      allow_nil? false
      public? true
    end

    attribute :search_name, :string, allow_nil?: false, default: "", public?: false
    attribute :search_set_name, :string, allow_nil?: false, default: "", public?: false
    attribute :search_collector_number, :string, allow_nil?: false, default: "", public?: false
    attribute :search_tcgdex_id, :string, allow_nil?: false, default: "", public?: false

    attribute :image_url, :string, public?: true
    attribute :rarity, :string, public?: true
    attribute :category, :string, public?: true
    attribute :illustrator, :string, public?: true
    attribute :regulation_mark, :string, public?: true
    attribute :standard_legal, :boolean, public?: true
    attribute :expanded_legal, :boolean, public?: true
    attribute :variant_data, :map, public?: false
    attribute :source_updated_at, :utc_datetime_usec, public?: true
    attribute :mapping_updated_at, :utc_datetime_usec, public?: true
    attribute :source_payload, :map, public?: false
    attribute :last_synced_at, :utc_datetime_usec, public?: true
    attribute :cardmarket_product_id, :integer, public?: true

    attribute :mapping_status, :string do
      public? true
      default "pending"
      allow_nil? false
    end

    attribute :mapping_review_reason, :string, public?: true

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :card_set, TcgCheap.Catalogue.CardSet, public?: true
    has_many :valuation_snapshots, TcgCheap.Pricing.Singles.SingleValuationSnapshot
  end

  identities do
    identity :unique_tcgdex_id, [:tcgdex_id]
  end
end
