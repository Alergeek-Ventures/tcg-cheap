defmodule TcgCheap.Pricing.SealedDailyAggregate do
  @moduledoc "Persisted daily sealed-market aggregate, retaining calculation versions."
  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  postgres do
    table "sealed_daily_aggregates"
    repo TcgCheap.Repo

    references do
      reference :sealed_product, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:calculation_version], "sealed_daily_aggregates_version_invariant",
        check: "calculation_version ~ '^sealed_market_daily_v[0-9]+$'"

      check_constraint [:currency], "sealed_daily_aggregates_currency_invariant",
        check: "currency = 'PLN'"

      check_constraint [
                         :status,
                         :limited_reason,
                         :benchmark_pln,
                         :typical_low_pln,
                         :typical_high_pln,
                         :fresh_regular_retailer_count,
                         :latest_nonfuture_checked_at
                       ],
                       "sealed_daily_aggregates_state_invariant",
                       check:
                         "(status = 'ready' AND limited_reason IS NULL AND benchmark_pln IS NOT NULL AND typical_low_pln IS NOT NULL AND typical_high_pln IS NOT NULL AND fresh_regular_retailer_count >= #{SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()} AND latest_nonfuture_checked_at IS NOT NULL) OR (status = 'limited' AND limited_reason IN ('no_fresh_current_offers', 'too_few_regular_retailers', 'insufficient_inliers') AND benchmark_pln IS NULL AND typical_low_pln IS NULL AND typical_high_pln IS NULL)"

      check_constraint [
                         :status,
                         :limited_reason,
                         :fresh_regular_retailer_count,
                         :fresh_lgs_count
                       ],
                       "sealed_daily_aggregates_reason_invariant",
                       check:
                         "status = 'ready' OR (limited_reason = 'no_fresh_current_offers' AND fresh_regular_retailer_count = 0 AND fresh_lgs_count = 0) OR (limited_reason = 'too_few_regular_retailers' AND fresh_regular_retailer_count < #{SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()} AND fresh_regular_retailer_count + fresh_lgs_count > 0) OR (limited_reason = 'insufficient_inliers' AND fresh_regular_retailer_count >= #{SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()})"

      check_constraint [:benchmark_pln, :typical_low_pln, :typical_high_pln],
                       "sealed_daily_aggregates_price_invariant",
                       check:
                         "(benchmark_pln IS NULL OR (benchmark_pln > 0 AND benchmark_pln <> 'NaN'::numeric AND benchmark_pln <> 'Infinity'::numeric AND benchmark_pln <> '-Infinity'::numeric)) AND (typical_low_pln IS NULL OR (typical_low_pln > 0 AND typical_low_pln <> 'NaN'::numeric AND typical_low_pln <> 'Infinity'::numeric AND typical_low_pln <> '-Infinity'::numeric)) AND (typical_high_pln IS NULL OR (typical_high_pln > 0 AND typical_high_pln <> 'NaN'::numeric AND typical_high_pln <> 'Infinity'::numeric AND typical_high_pln <> '-Infinity'::numeric)) AND (benchmark_pln IS NULL OR (typical_low_pln <= benchmark_pln AND benchmark_pln <= typical_high_pln))"

      check_constraint [
                         :fresh_regular_retailer_count,
                         :fresh_lgs_count,
                         :recent_sold_out_0_14_day_count,
                         :sold_out_15_30_day_count,
                         :stale_or_future_current_offer_count,
                         :unique_source_retailer_count
                       ],
                       "sealed_daily_aggregates_counts_invariant",
                       check:
                         "fresh_regular_retailer_count >= 0 AND fresh_lgs_count >= 0 AND recent_sold_out_0_14_day_count >= 0 AND sold_out_15_30_day_count >= 0 AND stale_or_future_current_offer_count >= 0 AND unique_source_retailer_count >= 0"

      check_constraint [
                         :fresh_regular_retailer_count,
                         :fresh_lgs_count,
                         :unique_source_retailer_count
                       ],
                       "sealed_daily_aggregates_coverage_invariant",
                       check:
                         "unique_source_retailer_count >= fresh_regular_retailer_count + fresh_lgs_count"

      check_constraint [:latest_nonfuture_checked_at, :calculated_at],
                       "sealed_daily_aggregates_checked_at_invariant",
                       check:
                         "latest_nonfuture_checked_at IS NULL OR latest_nonfuture_checked_at <= calculated_at"

      check_constraint [:aggregate_date, :calculated_at],
                       "sealed_daily_aggregates_time_invariant",
                       check: "aggregate_date <= calculated_at::date"
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :sealed_product_id,
        :aggregate_date,
        :calculation_version,
        :currency,
        :status,
        :limited_reason,
        :benchmark_pln,
        :typical_low_pln,
        :typical_high_pln,
        :fresh_regular_retailer_count,
        :fresh_lgs_count,
        :recent_sold_out_0_14_day_count,
        :sold_out_15_30_day_count,
        :stale_or_future_current_offer_count,
        :unique_source_retailer_count,
        :latest_nonfuture_checked_at,
        :calculated_at
      ]

      validate TcgCheap.Pricing.Validations.SealedDailyAggregate
      upsert? true
      upsert_identity :unique_product_date_version

      upsert_fields [
        :currency,
        :status,
        :limited_reason,
        :benchmark_pln,
        :typical_low_pln,
        :typical_high_pln,
        :fresh_regular_retailer_count,
        :fresh_lgs_count,
        :recent_sold_out_0_14_day_count,
        :sold_out_15_30_day_count,
        :stale_or_future_current_offer_count,
        :unique_source_retailer_count,
        :latest_nonfuture_checked_at,
        :calculated_at
      ]

      upsert_condition expr(upsert_conflict(:calculated_at) >= calculated_at)
    end

    read :latest_as_of do
      argument :sealed_product_id, :uuid, allow_nil?: false
      argument :calculation_version, :string, allow_nil?: false
      argument :as_of, :date, allow_nil?: false
      get? true

      filter expr(
               sealed_product_id == ^arg(:sealed_product_id) and
                 calculation_version == ^arg(:calculation_version) and
                 aggregate_date <= ^arg(:as_of)
             )

      prepare build(sort: [aggregate_date: :desc, calculated_at: :desc, id: :desc], limit: 1)
    end

    read :latest_ready_as_of do
      argument :sealed_product_id, :uuid, allow_nil?: false
      argument :calculation_version, :string, allow_nil?: false
      argument :as_of, :date, allow_nil?: false
      get? true

      filter expr(
               sealed_product_id == ^arg(:sealed_product_id) and
                 calculation_version == ^arg(:calculation_version) and status == "ready" and
                 aggregate_date <= ^arg(:as_of)
             )

      prepare build(sort: [aggregate_date: :desc, calculated_at: :desc, id: :desc], limit: 1)
    end

    read :history do
      argument :sealed_product_id, :uuid, allow_nil?: false
      argument :calculation_version, :string, allow_nil?: false
      argument :since, :date, allow_nil?: false
      argument :as_of, :date, allow_nil?: false

      filter expr(
               sealed_product_id == ^arg(:sealed_product_id) and
                 calculation_version == ^arg(:calculation_version) and
                 aggregate_date >= ^arg(:since) and aggregate_date <= ^arg(:as_of)
             )

      prepare build(sort: [aggregate_date: :asc, calculated_at: :asc, id: :asc], limit: 30)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :aggregate_date, :date, allow_nil?: false, public?: true

    attribute :calculation_version, :string,
      allow_nil?: false,
      public?: true,
      default: "sealed_market_daily_v1"

    attribute :currency, :string, allow_nil?: false, public?: true, default: "PLN"
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :limited_reason, :string, public?: true
    attribute :benchmark_pln, :decimal, public?: true
    attribute :typical_low_pln, :decimal, public?: true
    attribute :typical_high_pln, :decimal, public?: true
    attribute :fresh_regular_retailer_count, :integer, allow_nil?: false, public?: true
    attribute :fresh_lgs_count, :integer, allow_nil?: false, public?: true
    attribute :recent_sold_out_0_14_day_count, :integer, allow_nil?: false, public?: true
    attribute :sold_out_15_30_day_count, :integer, allow_nil?: false, public?: true
    attribute :stale_or_future_current_offer_count, :integer, allow_nil?: false, public?: true
    attribute :unique_source_retailer_count, :integer, allow_nil?: false, public?: true
    attribute :latest_nonfuture_checked_at, :utc_datetime_usec, public?: true
    attribute :calculated_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :sealed_product, TcgCheap.Catalogue.SealedProduct, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_product_date_version, [
      :sealed_product_id,
      :aggregate_date,
      :calculation_version
    ]
  end
end
