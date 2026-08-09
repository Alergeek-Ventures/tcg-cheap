defmodule TcgCheap.Pricing.SealedBuyingGuideSnapshot do
  @moduledoc "Persisted sealed-product buying guidance, retaining model versions and dates."
  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_buying_guide_snapshots"
    repo TcgCheap.Repo

    custom_indexes do
      index [:source_aggregate_id]
    end

    references do
      reference :sealed_product, on_delete: :restrict
      reference :source_aggregate, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:model_version], "sealed_buying_guide_snapshots_version_invariant",
        check: "model_version ~ '^sealed_buying_model_v[0-9]+$'"

      check_constraint [:currency], "sealed_buying_guide_snapshots_currency_invariant",
        check: "currency = 'PLN'"

      check_constraint [
                         :status,
                         :limited_reason,
                         :reference_price_pln,
                         :great_price_max_pln,
                         :fair_price_max_pln,
                         :expensive_price_max_pln
                       ],
                       "sealed_buying_guide_snapshots_state_invariant",
                       check:
                         "(status = 'ready' AND limited_reason IS NULL AND reference_price_pln > 0 AND great_price_max_pln > 0 AND fair_price_max_pln > great_price_max_pln AND expensive_price_max_pln > fair_price_max_pln) OR (status = 'limited' AND limited_reason IN ('uncertain_mapping','limited_market_aggregate','stale_market_evidence','insufficient_history','low_confidence','invalid_band_boundaries') AND great_price_max_pln IS NULL AND fair_price_max_pln IS NULL AND expensive_price_max_pln IS NULL)"

      check_constraint [
                         :reference_price_pln,
                         :regular_benchmark_pln,
                         :msrp_pln,
                         :lgs_median_pln,
                         :sold_out_center_pln,
                         :great_price_max_pln,
                         :fair_price_max_pln,
                         :expensive_price_max_pln
                       ],
                       "sealed_buying_guide_snapshots_money_invariant",
                       check:
                         "(reference_price_pln IS NULL OR (reference_price_pln > 0 AND reference_price_pln <> 'NaN'::numeric AND reference_price_pln <> 'Infinity'::numeric AND reference_price_pln <> '-Infinity'::numeric)) AND (regular_benchmark_pln IS NULL OR (regular_benchmark_pln > 0 AND regular_benchmark_pln <> 'NaN'::numeric AND regular_benchmark_pln <> 'Infinity'::numeric AND regular_benchmark_pln <> '-Infinity'::numeric)) AND (msrp_pln IS NULL OR (msrp_pln > 0 AND msrp_pln <> 'NaN'::numeric AND msrp_pln <> 'Infinity'::numeric AND msrp_pln <> '-Infinity'::numeric)) AND (lgs_median_pln IS NULL OR (lgs_median_pln > 0 AND lgs_median_pln <> 'NaN'::numeric AND lgs_median_pln <> 'Infinity'::numeric AND lgs_median_pln <> '-Infinity'::numeric)) AND (sold_out_center_pln IS NULL OR (sold_out_center_pln > 0 AND sold_out_center_pln <> 'NaN'::numeric AND sold_out_center_pln <> 'Infinity'::numeric AND sold_out_center_pln <> '-Infinity'::numeric)) AND (great_price_max_pln IS NULL OR (great_price_max_pln > 0 AND great_price_max_pln <> 'NaN'::numeric AND great_price_max_pln <> 'Infinity'::numeric AND great_price_max_pln <> '-Infinity'::numeric)) AND (fair_price_max_pln IS NULL OR (fair_price_max_pln > 0 AND fair_price_max_pln <> 'NaN'::numeric AND fair_price_max_pln <> 'Infinity'::numeric AND fair_price_max_pln <> '-Infinity'::numeric)) AND (expensive_price_max_pln IS NULL OR (expensive_price_max_pln > 0 AND expensive_price_max_pln <> 'NaN'::numeric AND expensive_price_max_pln <> 'Infinity'::numeric AND expensive_price_max_pln <> '-Infinity'::numeric))"

      check_constraint [:confidence], "sealed_buying_guide_snapshots_confidence_invariant",
        check:
          "confidence >= 0 AND confidence <= 1 AND confidence <> 'NaN'::numeric AND confidence <> 'Infinity'::numeric AND confidence <> '-Infinity'::numeric"

      check_constraint [:trend, :trend_change], "sealed_buying_guide_snapshots_trend_invariant",
        check:
          "(trend = 'insufficient_history' AND trend_change IS NULL) OR (trend IN ('rising','stable','falling') AND trend_change IS NOT NULL AND trend_change > -1 AND trend_change <> 'NaN'::numeric AND trend_change <> 'Infinity'::numeric AND trend_change <> '-Infinity'::numeric)"

      check_constraint [:availability, :availability_trend],
                       "sealed_buying_guide_snapshots_availability_invariant",
                       check:
                         "availability IN ('abundant','balanced','scarce') AND availability_trend IN ('improving','stable','tightening','insufficient_history')"

      check_constraint [:explanation_factors], "sealed_buying_guide_snapshots_factors_invariant",
        check:
          "cardinality(explanation_factors) BETWEEN 1 AND 8 AND explanation_factors <@ ARRAY['market_benchmark','market_data_limited','msrp','lgs','sold_out','trend_rising','trend_stable','trend_falling','trend_insufficient_history','availability_abundant','availability_balanced','availability_scarce','availability_trend_improving','availability_trend_stable','availability_trend_tightening','availability_trend_insufficient_history']::text[]"

      check_constraint [:guide_date, :calculated_at, :source_aggregate_calculated_at],
                       "sealed_buying_guide_snapshots_time_invariant",
                       check:
                         "guide_date <= source_aggregate_calculated_at::date AND source_aggregate_calculated_at <= calculated_at"

      check_constraint [:source_aggregate_fingerprint],
                       "sealed_buying_guide_snapshots_fingerprint_invariant",
                       check: "source_aggregate_fingerprint ~ '^[0-9a-f]{64}$'"

      check_constraint [:source_history_fingerprint],
                       "sealed_buying_guide_snapshots_history_fingerprint_invariant",
                       check: "source_history_fingerprint ~ '^[0-9a-f]{64}$'"
    end
  end

  actions do
    defaults [:read]

    create :record do
      argument :expected_source_aggregate_date, :date, allow_nil?: false
      argument :expected_source_aggregate_calculated_at, :utc_datetime_usec, allow_nil?: false
      argument :expected_source_aggregate_fingerprint, :string, allow_nil?: false
      argument :expected_source_history_fingerprint, :string, allow_nil?: false

      accept [
        :source_aggregate_id,
        :model_version,
        :currency,
        :status,
        :limited_reason,
        :reference_price_pln,
        :great_price_max_pln,
        :fair_price_max_pln,
        :expensive_price_max_pln,
        :confidence,
        :trend,
        :trend_change,
        :availability,
        :availability_trend,
        :regular_benchmark_pln,
        :msrp_pln,
        :lgs_median_pln,
        :sold_out_center_pln,
        :explanation_factors,
        :calculated_at
      ]

      change TcgCheap.Pricing.Changes.DeriveSealedBuyingGuideProduct
      validate TcgCheap.Pricing.Validations.SealedBuyingGuideSnapshot
      upsert? true
      upsert_identity :unique_product_date_version

      upsert_fields [
        :source_aggregate_id,
        :currency,
        :status,
        :limited_reason,
        :reference_price_pln,
        :great_price_max_pln,
        :fair_price_max_pln,
        :expensive_price_max_pln,
        :confidence,
        :trend,
        :trend_change,
        :availability,
        :availability_trend,
        :regular_benchmark_pln,
        :msrp_pln,
        :lgs_median_pln,
        :sold_out_center_pln,
        :explanation_factors,
        :source_aggregate_calculated_at,
        :source_aggregate_fingerprint,
        :source_history_fingerprint,
        :calculated_at
      ]

      upsert_condition expr(upsert_conflict(:calculated_at) >= calculated_at)
    end

    read :latest_as_of do
      argument :sealed_product_id, :uuid, allow_nil?: false
      argument :model_version, :string, allow_nil?: false
      argument :as_of, :date, allow_nil?: false
      get? true

      filter expr(
               sealed_product_id == ^arg(:sealed_product_id) and
                 model_version == ^arg(:model_version) and guide_date <= ^arg(:as_of)
             )

      prepare build(sort: [guide_date: :desc, calculated_at: :desc, id: :desc], limit: 1)
    end

    read :latest_ready_as_of do
      argument :sealed_product_id, :uuid, allow_nil?: false
      argument :model_version, :string, allow_nil?: false
      argument :as_of, :date, allow_nil?: false
      get? true

      filter expr(
               sealed_product_id == ^arg(:sealed_product_id) and
                 model_version == ^arg(:model_version) and status == "ready" and
                 guide_date <= ^arg(:as_of)
             )

      prepare build(sort: [guide_date: :desc, calculated_at: :desc, id: :desc], limit: 1)
    end

    read :history do
      argument :sealed_product_id, :uuid, allow_nil?: false
      argument :model_version, :string, allow_nil?: false
      argument :since, :date, allow_nil?: false
      argument :as_of, :date, allow_nil?: false

      filter expr(
               sealed_product_id == ^arg(:sealed_product_id) and
                 model_version == ^arg(:model_version) and guide_date >= ^arg(:since) and
                 guide_date <= ^arg(:as_of)
             )

      prepare build(sort: [guide_date: :asc, calculated_at: :asc, id: :asc], limit: 30)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :guide_date, :date, allow_nil?: false, public?: true
    attribute :model_version, :string, allow_nil?: false, public?: true
    attribute :currency, :string, allow_nil?: false, public?: true, default: "PLN"
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :limited_reason, :string, public?: true
    attribute :reference_price_pln, :decimal, public?: true
    attribute :great_price_max_pln, :decimal, public?: true
    attribute :fair_price_max_pln, :decimal, public?: true
    attribute :expensive_price_max_pln, :decimal, public?: true
    attribute :confidence, :decimal, allow_nil?: false, public?: true
    attribute :trend, :string, allow_nil?: false, public?: true
    attribute :trend_change, :decimal, public?: true
    attribute :availability, :string, allow_nil?: false, public?: true
    attribute :availability_trend, :string, allow_nil?: false, public?: true
    attribute :regular_benchmark_pln, :decimal, public?: true
    attribute :msrp_pln, :decimal, public?: true
    attribute :lgs_median_pln, :decimal, public?: true
    attribute :sold_out_center_pln, :decimal, public?: true

    attribute :explanation_factors, {:array, :string},
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 8]

    attribute :source_aggregate_calculated_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true

    attribute :source_aggregate_fingerprint, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^[0-9a-f]{64}$/]

    attribute :source_history_fingerprint, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^[0-9a-f]{64}$/]

    attribute :calculated_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :sealed_product, TcgCheap.Catalogue.SealedProduct, allow_nil?: false, public?: true

    belongs_to :source_aggregate, TcgCheap.Pricing.SealedDailyAggregate,
      allow_nil?: false,
      public?: true
  end

  identities do
    identity :unique_product_date_version, [:sealed_product_id, :guide_date, :model_version]
  end
end
