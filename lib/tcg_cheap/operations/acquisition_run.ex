defmodule TcgCheap.Operations.AcquisitionRun do
  @moduledoc "Durable, secret-free record of one external acquisition attempt."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "acquisition_runs"
    repo TcgCheap.Repo

    custom_indexes do
      index [:provider_key, :started_at, :id]
      index [:started_at, :id], where: "status = 'running'"
    end

    check_constraints do
      check_constraint [:attempt_key], "acquisition_runs_attempt_key_invariant",
        check: "btrim(attempt_key) <> ''"

      check_constraint [:attempt, :max_attempts], "acquisition_runs_attempt_bounds",
        check: "attempt > 0 AND max_attempts > 0 AND attempt <= max_attempts"

      check_constraint [:request_count], "acquisition_runs_request_count_nonnegative",
        check: "request_count >= 0"

      check_constraint [:status, :finished_at, :failure_category],
                       "acquisition_runs_lifecycle_invariant",
                       check:
                         "(status = 'running' AND finished_at IS NULL AND failure_category IS NULL) OR (status = 'succeeded' AND finished_at IS NOT NULL AND failure_category IS NULL) OR (status IN ('retryable_failure','failed','cancelled') AND finished_at IS NOT NULL AND failure_category IS NOT NULL)"

      check_constraint [:started_at, :finished_at], "acquisition_runs_timestamp_invariant",
        check: "finished_at IS NULL OR finished_at >= started_at"

      check_constraint [:status], "acquisition_runs_status_invariant",
        check: "status IN ('running','succeeded','retryable_failure','failed','cancelled')"

      check_constraint [:failure_category], "acquisition_runs_failure_category_invariant",
        check:
          "failure_category IS NULL OR failure_category IN ('budget','rate_limit','timeout','transport','provider_response','persistence','configuration','local_input','unknown')"

      check_constraint [:operation], "acquisition_runs_operation_invariant",
        check:
          "operation IN ('single_valuation','exchange_rate','sealed_retailer_refresh','card_catalogue_sync')"
    end
  end

  actions do
    read :read

    read :recent do
      argument :provider_keys, {:array, :string},
        allow_nil?: false,
        constraints: [max_length: 100, items: [max_length: 160, min_length: 1], nil_items?: false]

      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 50]
      filter expr(provider_key in ^arg(:provider_keys))

      prepare fn query, _context ->
        Ash.Query.limit(query, Ash.Query.get_argument(query, :limit))
      end

      prepare build(sort: [started_at: :desc, id: :desc])
    end

    create :start do
      argument :attempt_key, :string,
        allow_nil?: false,
        constraints: [max_length: 240, min_length: 1]

      argument :provider_key, :string,
        allow_nil?: false,
        constraints: [max_length: 160, min_length: 1]

      argument :operation, :string,
        allow_nil?: false,
        constraints: [max_length: 160, min_length: 1]

      argument :target_key, :string,
        allow_nil?: false,
        constraints: [max_length: 240, min_length: 1]

      argument :worker, :string, allow_nil?: false, constraints: [max_length: 240, min_length: 1]
      argument :queue, :string, allow_nil?: false, constraints: [max_length: 160, min_length: 1]
      argument :job_id, :integer, constraints: [min: 1]
      argument :attempt, :integer, allow_nil?: false, constraints: [min: 1]
      argument :max_attempts, :integer, allow_nil?: false, constraints: [min: 1]
      argument :started_at, :utc_datetime_usec, allow_nil?: false
      accept []
      change set_attribute(:attempt_key, arg(:attempt_key))
      change set_attribute(:provider_key, arg(:provider_key))
      change set_attribute(:operation, arg(:operation))
      change set_attribute(:target_key, arg(:target_key))
      change set_attribute(:worker, arg(:worker))
      change set_attribute(:queue, arg(:queue))
      change set_attribute(:job_id, arg(:job_id))
      change set_attribute(:attempt, arg(:attempt))
      change set_attribute(:max_attempts, arg(:max_attempts))
      change set_attribute(:started_at, arg(:started_at))

      validate one_of(:operation, [
                 "single_valuation",
                 "exchange_rate",
                 "sealed_retailer_refresh",
                 "card_catalogue_sync"
               ])

      change {TcgCheap.Operations.Changes.SourceHealthLifecycle, event: :start}
    end

    update :finish do
      argument :status, :string, allow_nil?: false

      argument :failure_category, :string

      argument :request_count, :integer, allow_nil?: false, constraints: [min: 0]
      accept []
      require_atomic? false
      change set_attribute(:status, arg(:status))
      change set_attribute(:failure_category, arg(:failure_category))
      change set_attribute(:request_count, arg(:request_count))
      validate one_of(:status, ["succeeded", "retryable_failure", "failed", "cancelled"])

      validate one_of(:failure_category, [
                 "budget",
                 "rate_limit",
                 "timeout",
                 "transport",
                 "provider_response",
                 "persistence",
                 "configuration",
                 "local_input",
                 "unknown"
               ])

      change {TcgCheap.Operations.Changes.SourceHealthLifecycle, event: :finish}
    end

    update :reconcile_stranded do
      argument :expected_cutoff, :utc_datetime_usec, allow_nil?: false
      argument :finished_at, :utc_datetime_usec, allow_nil?: false
      accept []
      require_atomic? false
      change {TcgCheap.Operations.Changes.SourceHealthLifecycle, event: :reconcile}
      change {TcgCheap.Operations.Changes.ReconcileStranded, []}
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate compare(:attempt, less_than_or_equal_to: :max_attempts)
  end

  attributes do
    uuid_primary_key :id

    attribute :attempt_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :provider_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 160]

    attribute :operation, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 160]

    attribute :target_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :worker, :string, allow_nil?: false, public?: true, constraints: [max_length: 240]
    attribute :queue, :string, allow_nil?: false, public?: true, constraints: [max_length: 160]
    attribute :job_id, :integer, public?: true
    attribute :attempt, :integer, allow_nil?: false, public?: true
    attribute :max_attempts, :integer, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, default: "running", public?: true
    attribute :failure_category, :string, public?: true
    attribute :request_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :finished_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  identities do
    identity :unique_attempt_key, [:attempt_key]
  end
end
