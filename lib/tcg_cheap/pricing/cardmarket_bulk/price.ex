defmodule TcgCheap.Pricing.CardmarketBulk.Price do
  @moduledoc "Latest Pokémon single price row imported from Cardmarket bulk data."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cardmarket_bulk_prices"
    repo TcgCheap.Repo

    custom_indexes do
      index [:last_batch_id]
    end

    references do
      reference :last_batch, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:cardmarket_product_id, :category_id],
                       "cardmarket_bulk_prices_pokemon_category",
                       check: "cardmarket_product_id > 0 AND category_id = 51"

      check_constraint [:selected_metric, :selected_value_eur],
                       "cardmarket_bulk_prices_selected_metric_coherence",
                       check:
                         "((selected_metric IS NULL AND selected_value_eur IS NULL) OR (selected_metric IS NOT NULL AND selected_value_eur IS NOT NULL)) AND (selected_metric IS NULL OR selected_metric IN ('avg7', 'avg30', 'trend', 'avg', 'low'))"

      check_constraint [
                         :avg,
                         :low,
                         :trend,
                         :avg1,
                         :avg7,
                         :avg30,
                         :avg_holo,
                         :low_holo,
                         :trend_holo,
                         :avg1_holo,
                         :avg7_holo,
                         :avg30_holo,
                         :selected_value_eur
                       ],
                       "cardmarket_bulk_prices_values_positive_finite",
                       check:
                         "(avg IS NULL OR (avg > 0 AND avg <> 'NaN' AND avg <> 'Infinity' AND avg <> '-Infinity')) AND (low IS NULL OR (low > 0 AND low <> 'NaN' AND low <> 'Infinity' AND low <> '-Infinity')) AND (trend IS NULL OR (trend > 0 AND trend <> 'NaN' AND trend <> 'Infinity' AND trend <> '-Infinity')) AND (avg1 IS NULL OR (avg1 > 0 AND avg1 <> 'NaN' AND avg1 <> 'Infinity' AND avg1 <> '-Infinity')) AND (avg7 IS NULL OR (avg7 > 0 AND avg7 <> 'NaN' AND avg7 <> 'Infinity' AND avg7 <> '-Infinity')) AND (avg30 IS NULL OR (avg30 > 0 AND avg30 <> 'NaN' AND avg30 <> 'Infinity' AND avg30 <> '-Infinity')) AND (avg_holo IS NULL OR (avg_holo > 0 AND avg_holo <> 'NaN' AND avg_holo <> 'Infinity' AND avg_holo <> '-Infinity')) AND (low_holo IS NULL OR (low_holo > 0 AND low_holo <> 'NaN' AND low_holo <> 'Infinity' AND low_holo <> '-Infinity')) AND (trend_holo IS NULL OR (trend_holo > 0 AND trend_holo <> 'NaN' AND trend_holo <> 'Infinity' AND trend_holo <> '-Infinity')) AND (avg1_holo IS NULL OR (avg1_holo > 0 AND avg1_holo <> 'NaN' AND avg1_holo <> 'Infinity' AND avg1_holo <> '-Infinity')) AND (avg7_holo IS NULL OR (avg7_holo > 0 AND avg7_holo <> 'NaN' AND avg7_holo <> 'Infinity' AND avg7_holo <> '-Infinity')) AND (avg30_holo IS NULL OR (avg30_holo > 0 AND avg30_holo <> 'NaN' AND avg30_holo <> 'Infinity' AND avg30_holo <> '-Infinity')) AND (selected_value_eur IS NULL OR (selected_value_eur > 0 AND selected_value_eur <> 'NaN' AND selected_value_eur <> 'Infinity' AND selected_value_eur <> '-Infinity'))"
    end
  end

  actions do
    read :read

    create :upsert do
      accept [
        :cardmarket_product_id,
        :category_id,
        :avg,
        :low,
        :trend,
        :avg1,
        :avg7,
        :avg30,
        :avg_holo,
        :low_holo,
        :trend_holo,
        :avg1_holo,
        :avg7_holo,
        :avg30_holo,
        :selected_metric,
        :selected_value_eur,
        :last_batch_id,
        :source_updated_at
      ]

      upsert? true
      upsert_identity :unique_cardmarket_product_id

      upsert_fields [
        :category_id,
        :avg,
        :low,
        :trend,
        :avg1,
        :avg7,
        :avg30,
        :avg_holo,
        :low_holo,
        :trend_holo,
        :avg1_holo,
        :avg7_holo,
        :avg30_holo,
        :selected_metric,
        :selected_value_eur,
        :last_batch_id,
        :source_updated_at
      ]

      upsert_condition expr(source_updated_at <= upsert_conflict(:source_updated_at))
    end

    read :by_product_ids do
      argument :cardmarket_product_ids, {:array, :integer}, allow_nil?: false
      filter expr(cardmarket_product_id in ^arg(:cardmarket_product_ids))
    end
  end

  policies do
    bypass action([:upsert, :by_product_ids]) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate one_of(:category_id, [51])

    validate one_of(:selected_metric, [
               "avg",
               "low",
               "trend",
               "avg7",
               "avg30"
             ])

    validate compare(:avg, greater_than: 0)
    validate compare(:low, greater_than: 0)
    validate compare(:trend, greater_than: 0)
    validate compare(:avg1, greater_than: 0)
    validate compare(:avg7, greater_than: 0)
    validate compare(:avg30, greater_than: 0)
    validate compare(:avg_holo, greater_than: 0)
    validate compare(:low_holo, greater_than: 0)
    validate compare(:trend_holo, greater_than: 0)
    validate compare(:avg1_holo, greater_than: 0)
    validate compare(:avg7_holo, greater_than: 0)
    validate compare(:avg30_holo, greater_than: 0)
    validate compare(:selected_value_eur, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :cardmarket_product_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :category_id, :integer, allow_nil?: false, default: 51, public?: true

    for metric <- [
          :avg,
          :low,
          :trend,
          :avg1,
          :avg7,
          :avg30,
          :avg_holo,
          :low_holo,
          :trend_holo,
          :avg1_holo,
          :avg7_holo,
          :avg30_holo
        ] do
      attribute metric, :decimal, public?: true
    end

    attribute :selected_metric, :string, public?: true, constraints: [max_length: 16]
    attribute :selected_value_eur, :decimal, public?: true
    attribute :source_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :last_batch, TcgCheap.Pricing.CardmarketBulk.Batch,
      allow_nil?: false,
      public?: true
  end

  identities do
    identity :unique_cardmarket_product_id, [:cardmarket_product_id]
  end
end
