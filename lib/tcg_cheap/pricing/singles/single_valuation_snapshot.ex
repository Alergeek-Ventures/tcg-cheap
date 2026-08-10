defmodule TcgCheap.Pricing.Singles.SingleValuationSnapshot do
  @moduledoc """
  An immutable locally acquired aggregate Cardmarket valuation.

  Snapshots retain provider provenance indefinitely. At most one snapshot per
  card and policy should remain current; the record action archives the prior
  current snapshot and inserts its replacement atomically in one transaction.
  """

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "single_valuation_snapshots"
    repo TcgCheap.Repo

    custom_indexes do
      index [:card_printing_id, :policy_version, :fetched_at]

      index [:policy_version, :fetched_at, :card_printing_id],
        name: "single_valuation_snapshots_homepage_window_index"

      index [:card_printing_id, :policy_version], unique: true, where: "\"current?\" = TRUE"
    end
  end

  actions do
    defaults [:read]

    create :record do
      transaction? true
      touches_resources [TcgCheap.Catalogue.CardPrinting]

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
      change {TcgCheap.Pricing.Singles.Changes.ReplaceCurrentSnapshot, []}
      validate compare(:value_eur, greater_than: 0)
      validate one_of(:currency, ["EUR"])
    end

    update :archive do
      accept []
      change set_attribute(:current?, false)
    end

    read :current_for_card do
      argument :card_printing_id, :uuid, allow_nil?: false
      filter expr(card_printing_id == ^arg(:card_printing_id) and current? == true)
      prepare build(sort: [fetched_at: :desc])
    end

    read :current_for_card_and_policy do
      argument :card_printing_id, :uuid, allow_nil?: false
      argument :policy_version, :string, allow_nil?: false
      get? true

      filter expr(
               card_printing_id == ^arg(:card_printing_id) and
                 policy_version == ^arg(:policy_version) and current? == true
             )
    end

    read :history_for_card_and_policy do
      argument :card_printing_id, :uuid, allow_nil?: false
      argument :policy_version, :string, allow_nil?: false

      filter expr(
               card_printing_id == ^arg(:card_printing_id) and
                 policy_version == ^arg(:policy_version)
             )

      prepare build(sort: [fetched_at: :desc])
    end

    read :history_since_for_card_and_policy do
      argument :card_printing_id, :uuid, allow_nil?: false
      argument :policy_version, :string, allow_nil?: false
      argument :since, :utc_datetime_usec, allow_nil?: false

      filter expr(
               card_printing_id == ^arg(:card_printing_id) and
                 policy_version == ^arg(:policy_version) and fetched_at >= ^arg(:since)
             )

      prepare build(sort: [fetched_at: :asc, id: :asc])
    end

    action :homepage_price_changes, {:array, :struct} do
      constraints items: [instance_of: TcgCheap.Pricing.Singles.HomepagePriceChange]
      argument :as_of, :utc_datetime_usec, allow_nil?: false
      argument :limit, :integer, allow_nil?: false, default: 4, constraints: [min: 1, max: 6]
      run TcgCheap.Pricing.Singles.Actions.HomepagePriceChanges
    end

    read :admin_catalogue do
      prepare build(
                load: [:card_printing],
                sort: [fetched_at: :desc, id: :desc]
              )
    end
  end

  policies do
    bypass action([
             :record,
             :archive,
             :current_for_card,
             :current_for_card_and_policy,
             :history_for_card_and_policy,
             :history_since_for_card_and_policy,
             :homepage_price_changes
           ]) do
      authorize_if always()
    end

    bypass accessing_from(
             TcgCheap.Catalogue.CardPrinting,
             :tcgdex_cardmarket_v1_current_valuation
           ) do
      authorize_if always()
    end

    policy action([:read, :admin_catalogue]) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
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
