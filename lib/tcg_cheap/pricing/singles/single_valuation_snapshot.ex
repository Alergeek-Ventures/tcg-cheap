defmodule TcgCheap.Pricing.Singles.SingleValuationSnapshot do
  @moduledoc """
  An immutable locally acquired aggregate Cardmarket valuation.

  Snapshots retain provider provenance indefinitely. At most one snapshot per
  card and policy should remain current; acquisition orchestration archives the
  old current snapshot after a successful replacement is stored.
  """

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "single_valuation_snapshots"
    repo TcgCheap.Repo

    custom_indexes do
      index [:card_printing_id, :policy_version, :fetched_at]
      index [:card_printing_id, :policy_version], unique: true, where: "\"current?\" = TRUE"
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :card_printing_id,
        :value_eur,
        :currency,
        :policy_version,
        :source,
        :source_metric,
        :fetched_at,
        :provider_updated_at,
        :cardmarket_product_id
      ]

      change set_attribute(:current?, true)
      validate compare(:value_eur, greater_than: 0)
      validate one_of(:currency, ["EUR"])
    end

    update :archive do
      accept []
      change set_attribute(:current?, false)
    end

    read :current_for_card do
      argument :card_printing_id, :string, allow_nil?: false
      filter expr(card_printing_id == ^arg(:card_printing_id) and current? == true)
      prepare build(sort: [fetched_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :value_eur, :decimal do
      allow_nil? false
      constraints min: 0
      public? true
    end

    attribute :currency, :string do
      allow_nil? false
      default "EUR"
      public? true
    end

    attribute :policy_version, :string do
      allow_nil? false
      public? true
    end

    attribute :source, :string do
      allow_nil? false
      public? true
    end

    attribute :source_metric, :string do
      allow_nil? false
      public? true
    end

    attribute :fetched_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :provider_updated_at, :utc_datetime_usec do
      public? true
    end

    attribute :cardmarket_product_id, :integer do
      constraints min: 1
      public? true
    end

    attribute :current?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :card_printing, TcgCheap.Catalogue.CardPrinting do
      allow_nil? false
      public? true
    end
  end
end
