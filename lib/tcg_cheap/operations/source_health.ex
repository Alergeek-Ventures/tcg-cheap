defmodule TcgCheap.Operations.SourceHealth do
  @moduledoc "Persisted lifecycle counters for configured acquisition providers."
  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "acquisition_source_health"
    repo TcgCheap.Repo

    check_constraints do
      check_constraint [:consecutive_failures], "source_health_failures_nonnegative",
        check: "consecutive_failures >= 0"

      check_constraint [
                         :last_status,
                         :last_failure_category,
                         :last_started_at,
                         :last_succeeded_at,
                         :last_failed_at
                       ],
                       "source_health_state_invariant",
                       check:
                         "last_started_at IS NOT NULL AND ((last_status IS NULL AND last_succeeded_at IS NULL AND last_failed_at IS NULL AND last_failure_category IS NULL AND consecutive_failures = 0) OR (last_status IS NOT NULL AND last_status = 'succeeded' AND last_succeeded_at IS NOT NULL AND (last_failed_at IS NULL OR last_succeeded_at >= last_failed_at) AND last_failure_category IS NULL AND consecutive_failures = 0) OR (last_status IS NOT NULL AND last_status IN ('retryable_failure','failed','cancelled') AND last_failed_at IS NOT NULL AND (last_succeeded_at IS NULL OR last_failed_at >= last_succeeded_at) AND last_failure_category IS NOT NULL AND consecutive_failures > 0))"

      check_constraint [:last_status], "source_health_status_invariant",
        check:
          "last_status IS NULL OR last_status IN ('succeeded','retryable_failure','failed','cancelled')"

      check_constraint [:last_failure_category], "source_health_failure_category_invariant",
        check:
          "last_failure_category IS NULL OR last_failure_category IN ('budget','rate_limit','timeout','transport','provider_response','persistence','configuration','local_input','unknown')"
    end
  end

  actions do
    read :read

    read :by_providers do
      argument :provider_keys, {:array, :string},
        allow_nil?: false,
        constraints: [max_length: 100, items: [max_length: 160, min_length: 1], nil_items?: false]

      filter expr(provider_key in ^arg(:provider_keys))
      prepare build(sort: [provider_key: :asc, id: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 160]

    attribute :last_started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_succeeded_at, :utc_datetime_usec, public?: true
    attribute :last_failed_at, :utc_datetime_usec, public?: true
    attribute :last_status, :string, public?: true
    attribute :last_failure_category, :string, public?: true
    attribute :consecutive_failures, :integer, allow_nil?: false, default: 0, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  identities do
    identity :unique_provider_key, [:provider_key]
  end
end
