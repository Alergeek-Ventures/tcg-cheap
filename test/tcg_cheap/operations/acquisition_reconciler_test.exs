defmodule TcgCheap.Operations.AcquisitionReconcilerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Operations.AcquisitionReconciler

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_health)
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      stale_after_seconds: %{"nbp" => 129_600}
    )

    on_exit(fn ->
      Application.put_env(:tcg_cheap, :acquisition_health, previous)
      Application.put_env(:tcg_cheap, :acquisition_budget, previous_budget)
    end)

    :ok
  end

  test "reconciles oldest running rows and is idempotent" do
    now = ~U[2026-08-10 12:00:00Z]
    provider = "reconcile-#{System.unique_integer([:positive])}"

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_source_health (id, provider_key, last_started_at, consecutive_failures, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 0, $2, $2)",
      [provider, now]
    )

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_runs (id, attempt_key, provider_key, operation, target_key, worker, queue, attempt, max_attempts, status, request_count, started_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 'exchange_rate', 'EUR/PLN', 'worker', 'operations', 1, 3, 'running', 7, $3, $3, $3)",
      [
        "reconcile-#{System.unique_integer([:positive])}",
        provider,
        DateTime.add(now, -1_000, :second)
      ]
    )

    assert {:ok, %{reconciled_count: 1}} = AcquisitionReconciler.run(clock: fn -> now end)
    assert {:ok, %{reconciled_count: 0}} = AcquisitionReconciler.run(clock: fn -> now end)

    assert {:ok, %{rows: [["failed", "unknown", 7]]}} =
             TcgCheap.Repo.query(
               "SELECT status, failure_category, request_count FROM acquisition_runs WHERE provider_key = $1",
               [provider]
             )

    assert {:ok, %{rows: [[1, "failed", "unknown"]]}} =
             TcgCheap.Repo.query(
               "SELECT consecutive_failures, last_status, last_failure_category FROM acquisition_source_health WHERE provider_key = $1",
               [provider]
             )
  end

  test "leaves fresh and 899-second rows running, but reconciles exact boundary" do
    now = ~U[2026-08-10 12:00:00Z]
    provider = "boundary-#{System.unique_integer([:positive])}"
    insert_health(provider, now)
    insert_run(provider, "fresh", DateTime.add(now, -899, :second), 1)
    insert_run(provider, "exact", DateTime.add(now, -900, :second), 2)

    assert {:ok, %{reconciled_count: 1}} = AcquisitionReconciler.run(clock: fn -> now end)

    assert {:ok, %{rows: [["running", nil], ["failed", "unknown"]]}} =
             TcgCheap.Repo.query(
               "SELECT status, failure_category FROM acquisition_runs WHERE provider_key = $1 ORDER BY attempt",
               [provider]
             )
  end

  test "restores missing source health during reconciliation" do
    now = ~U[2026-08-10 12:00:00Z]
    provider = "missing-health-#{System.unique_integer([:positive])}"
    insert_run(provider, "missing", DateTime.add(now, -900, :second), 3)

    assert {:ok, %{reconciled_count: 1}} = AcquisitionReconciler.run(clock: fn -> now end)

    assert {:ok, %{rows: [[1, "failed", "unknown", ^provider]]}} =
             TcgCheap.Repo.query(
               "SELECT consecutive_failures, last_status, last_failure_category, provider_key FROM acquisition_source_health WHERE provider_key = $1",
               [provider]
             )
  end

  test "uses a post-lock completion clock and rejects time regression" do
    now = ~U[2026-08-10 12:00:00Z]
    finished_at = DateTime.add(now, 1, :second)
    provider = "completion-clock-#{System.unique_integer([:positive])}"
    insert_health(provider, now)
    insert_run(provider, "post-lock", DateTime.add(now, -900, :second), 1)

    {:ok, clock} = Agent.start_link(fn -> [now, finished_at] end)

    assert {:ok, %{reconciled_count: 1}} =
             AcquisitionReconciler.run(
               clock: fn ->
                 Agent.get_and_update(clock, fn [value | rest] -> {value, rest} end)
               end
             )

    assert {:ok, %{rows: [[persisted_finished_at]]}} =
             TcgCheap.Repo.query(
               "SELECT finished_at FROM acquisition_runs WHERE provider_key = $1",
               [provider]
             )

    assert NaiveDateTime.compare(persisted_finished_at, DateTime.to_naive(finished_at)) == :eq

    regressed_provider = "regressed-clock-#{System.unique_integer([:positive])}"
    insert_health(regressed_provider, now)
    insert_run(regressed_provider, "regressed", DateTime.add(now, -900, :second), 1)
    {:ok, regressed_clock} = Agent.start_link(fn -> [now, DateTime.add(now, -1, :second)] end)

    assert {:error, :invalid_acquisition_reconciler_clock} =
             AcquisitionReconciler.run(
               clock: fn ->
                 Agent.get_and_update(regressed_clock, fn [value | rest] -> {value, rest} end)
               end
             )

    assert {:ok, %{rows: [["running"]]}} =
             TcgCheap.Repo.query(
               "SELECT status FROM acquisition_runs WHERE provider_key = $1",
               [regressed_provider]
             )
  end

  test "honors the configured oldest-first limit" do
    now = ~U[2026-08-10 12:00:00Z]
    provider = "limited-#{System.unique_integer([:positive])}"
    insert_health(provider, now)

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 900,
      reconcile_limit: 2,
      stale_after_seconds: %{}
    )

    insert_run(provider, "oldest", DateTime.add(now, -1_000, :second), 1)
    insert_run(provider, "middle", DateTime.add(now, -950, :second), 2)
    insert_run(provider, "newest", DateTime.add(now, -901, :second), 3)

    assert {:ok, %{reconciled_count: 2}} = AcquisitionReconciler.run(clock: fn -> now end)

    assert {:ok, %{rows: [["failed"], ["failed"], ["running"]]}} =
             TcgCheap.Repo.query(
               "SELECT status FROM acquisition_runs WHERE provider_key = $1 ORDER BY attempt",
               [provider]
             )
  end

  test "rejects malformed provider configuration before mutating rows" do
    now = ~U[2026-08-10 12:00:00Z]
    provider = "malformed-config-#{System.unique_integer([:positive])}"
    insert_health(provider, now)
    insert_run(provider, "malformed", DateTime.add(now, -900, :second), 1)
    Application.put_env(:tcg_cheap, :acquisition_budget, [])

    assert {:error, :invalid_provider_configuration} =
             AcquisitionReconciler.run(clock: fn -> now end)

    assert {:ok, %{rows: [["running"]]}} =
             TcgCheap.Repo.query("SELECT status FROM acquisition_runs WHERE provider_key = $1", [
               provider
             ])
  end

  test "rejects stale-source policy for an unconfigured provider before mutating rows" do
    now = ~U[2026-08-10 12:00:00Z]
    provider = "unknown-policy-#{System.unique_integer([:positive])}"
    insert_health(provider, now)
    insert_run(provider, "unknown-policy", DateTime.add(now, -900, :second), 1)

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      stale_after_seconds: %{"unconfigured-provider" => 60}
    )

    assert {:error, :invalid_acquisition_health_configuration} =
             AcquisitionReconciler.run(clock: fn -> now end)

    assert {:ok, %{rows: [["running"]]}} =
             TcgCheap.Repo.query("SELECT status FROM acquisition_runs WHERE provider_key = $1", [
               provider
             ])
  end

  test "database rejects source success evidence without a terminal status" do
    now = ~U[2026-08-10 12:00:00Z]

    assert {:error,
            %Postgrex.Error{
              postgres: %{code: :check_violation, constraint: "source_health_state_invariant"}
            }} =
             TcgCheap.Repo.query(
               "INSERT INTO acquisition_source_health (provider_key, last_started_at, last_succeeded_at, consecutive_failures) VALUES ($1, $2, $2, 0)",
               ["missing-status-#{System.unique_integer([:positive])}", now]
             )
  end

  test "database rejects source status that contradicts terminal evidence order" do
    now = ~U[2026-08-10 12:00:00Z]

    assert {:error,
            %Postgrex.Error{
              postgres: %{code: :check_violation, constraint: "source_health_state_invariant"}
            }} =
             TcgCheap.Repo.query(
               "INSERT INTO acquisition_source_health (provider_key, last_started_at, last_succeeded_at, last_failed_at, last_status, consecutive_failures) VALUES ($1, $2, $3, $2, 'succeeded', 0)",
               [
                 "regressed-status-#{System.unique_integer([:positive])}",
                 now,
                 DateTime.add(now, -1, :second)
               ]
             )
  end

  defp insert_health(provider, now) do
    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_source_health (id, provider_key, last_started_at, consecutive_failures, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 0, $2, $2)",
      [provider, now]
    )
  end

  defp insert_run(provider, key, started_at, attempt) do
    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_runs (id, attempt_key, provider_key, operation, target_key, worker, queue, attempt, max_attempts, status, request_count, started_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 'exchange_rate', 'EUR/PLN', 'worker', 'operations', $3, 3, 'running', $4, $5, $5, $5)",
      ["#{key}-#{System.unique_integer([:positive])}", provider, attempt, attempt + 4, started_at]
    )
  end
end
