defmodule TcgCheap.Operations.BudgetUsage do
  @moduledoc "UTC request and estimated spend counters for an acquisition provider."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "acquisition_budget_usages"
    repo TcgCheap.Repo

    custom_indexes do
      index [:window_kind, :window_started_at]
    end

    check_constraints do
      check_constraint [:window_kind], "acquisition_budget_usages_window_kind_invariant",
        check: "window_kind IN ('hour', 'day', 'month')"

      check_constraint [:request_count, :estimated_spend_usd],
                       "acquisition_budget_usages_nonnegative_invariant",
                       check:
                         "request_count >= 0 AND estimated_spend_usd >= 0 AND estimated_spend_usd < 1000000000"
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :provider_id, :uuid, allow_nil?: false, public?: true
    attribute :window_kind, :string, allow_nil?: false, public?: true
    attribute :window_started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :request_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :estimated_spend_usd, :decimal, allow_nil?: false, default: 0, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :provider, TcgCheap.Operations.DataProvider,
      define_attribute?: false,
      attribute_type: :uuid,
      allow_nil?: false
  end

  identities do
    identity :unique_provider_window, [:provider_id, :window_kind, :window_started_at]
  end
end
