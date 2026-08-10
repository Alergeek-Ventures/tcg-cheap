defmodule TcgCheap.Operations.AcquisitionTrackerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Operations
  alias TcgCheap.Operations.{AcquisitionBudget, AcquisitionTracker}

  defmodule AdmissionStub do
    def admit(_provider_key) do
      Agent.get_and_update(
        Application.fetch_env!(:tcg_cheap, :acquisition_tracker_admission_stub),
        fn [result | remaining] -> {result, remaining} end
      )
    end
  end

  setup do
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_health = Application.get_env(:tcg_cheap, :acquisition_health)
    previous_admitter = Application.get_env(:tcg_cheap, :acquisition_budget_admitter)
    previous_stub = Application.get_env(:tcg_cheap, :acquisition_tracker_admission_stub)
    provider_key = "tracker-#{System.unique_integer([:positive])}"

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config(provider_key))
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(5))

    {:ok, %{rows: [[admin_id]]}} =
      TcgCheap.Repo.query(
        "INSERT INTO admins (id, email, hashed_password) VALUES (gen_random_uuid(), $1, 'test') RETURNING id",
        ["admin-#{provider_key}@example.test"]
      )

    Operations.register_provider!(
      provider_key,
      "Tracker provider",
      Decimal.new(0),
      100,
      1_000,
      20_000,
      Decimal.new(0),
      authorize?: false
    )

    on_exit(fn ->
      restore_env(:acquisition_budget, previous_budget)
      restore_env(:acquisition_health, previous_health)
      restore_env(:acquisition_budget_admitter, previous_admitter)
      restore_env(:acquisition_tracker_admission_stub, previous_stub)
    end)

    %{provider_key: provider_key, actor: %Admin{id: admin_id}}
  end

  test "successful attempts count admitted requests and reset source failures", %{
    provider_key: provider_key,
    actor: actor
  } do
    failed = start_tracker(provider_key)
    assert {:ok, failed_run} = AcquisitionTracker.finish(failed, {:error, :provider_timeout})
    assert failed_run.status == "retryable_failure"
    assert failed_run.failure_category == "timeout"

    tracker = start_tracker(provider_key)
    assert :ok = AcquisitionTracker.admit_request(tracker)
    assert {:ok, run} = AcquisitionTracker.finish(tracker, :ok)
    assert run.status == "succeeded"
    assert run.request_count == 1
    assert run.failure_category == nil

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.last_status == "succeeded"
    assert health.consecutive_failures == 0
    assert health.last_failure_category == nil
    assert health.last_failed_at
    assert health.last_succeeded_at

    assert {:ok, runs} = Operations.list_recent_acquisition_runs([provider_key], 50, actor: actor)
    assert Enum.map(runs, & &1.status) == ["succeeded", "retryable_failure"]
  end

  test "only successful admissions count and raw failures become fixed categories", %{
    provider_key: provider_key,
    actor: actor
  } do
    {:ok, stub} =
      Agent.start_link(fn ->
        [
          {:error, {:secret_reason, "bearer-secret"}},
          {:ok, %{estimated_cost_per_request: Decimal.new(0)}}
        ]
      end)

    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, AdmissionStub)
    Application.put_env(:tcg_cheap, :acquisition_tracker_admission_stub, stub)

    tracker = start_tracker(provider_key)

    assert {:error, {:acquisition_budget_rejected, {:secret_reason, "bearer-secret"}}} =
             AcquisitionTracker.admit_request(tracker)

    assert :ok = AcquisitionTracker.admit_request(tracker)

    assert {:ok, run} =
             AcquisitionTracker.finish(
               tracker,
               {:cancel, {:acquisition_budget_rejected, {:secret_reason, "bearer-secret"}}}
             )

    assert run.status == "cancelled"
    assert run.failure_category == "budget"
    assert run.request_count == 1

    assert {:ok, [projected]} =
             Operations.list_recent_acquisition_runs([provider_key], 1, actor: actor)

    refute inspect(projected) =~ "bearer-secret"
    assert projected.failure_category == "budget"
  end

  test "attempt identity and finish are single-use", %{provider_key: provider_key} do
    job = job(System.unique_integer([:positive]))
    opts = tracker_options(provider_key)

    assert {:ok, tracker} = AcquisitionTracker.start(job, opts)
    assert {:error, :acquisition_tracking_failed} = AcquisitionTracker.start(job, opts)
    assert {:ok, _run} = AcquisitionTracker.finish(tracker, {:cancel, :provider_not_found})
    assert {:error, :acquisition_tracking_failed} = AcquisitionTracker.finish(tracker, :ok)

    assert {:error, :acquisition_tracking_failed} =
             AcquisitionTracker.start(job, Keyword.put(opts, :operation, "arbitrary"))

    assert {:error, :acquisition_tracking_failed} =
             AcquisitionTracker.start(
               job,
               Keyword.put(opts, :provider_key, String.duplicate("x", 161))
             )

    assert {:error, :acquisition_tracking_failed} =
             AcquisitionTracker.start(job, opts ++ [provider_key: "duplicate"])
  end

  test "duplicate persisted job attempts do not execute the callback", %{
    provider_key: provider_key
  } do
    job = job(System.unique_integer([:positive]))

    assert :ok =
             AcquisitionTracker.run(job, tracker_options(provider_key), fn _ -> :ok end)

    executed = self()

    assert {:error, :acquisition_tracking_failed} =
             AcquisitionTracker.run(job, tracker_options(provider_key), fn _ ->
               send(executed, :executed)
             end)

    refute_receive :executed
  end

  test "a terminal error is recorded as failed", %{provider_key: provider_key, actor: actor} do
    assert {:error, :provider_timeout} =
             AcquisitionTracker.run(
               job(System.unique_integer([:positive]), 1, 1),
               tracker_options(provider_key),
               fn _ ->
                 {:error, :provider_timeout}
               end
             )

    assert {:ok, [run]} = Operations.list_recent_acquisition_runs([provider_key], 1, actor: actor)
    assert run.status == "failed"
    assert run.failure_category == "timeout"

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.last_status == "failed"
    assert health.consecutive_failures == 1
  end

  test "eligible retryable failures build a streak without opening the circuit", %{
    provider_key: provider_key,
    actor: actor
  } do
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(3))

    for _ <- 1..2 do
      tracker = start_tracker(provider_key)

      assert {:ok, %{status: "retryable_failure"}} =
               AcquisitionTracker.finish(tracker, {:error, :provider_timeout})
    end

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.circuit_failure_streak == 2
    assert is_nil(health.circuit_opened_at)
    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "active"
  end

  test "terminal eligible failure opens at threshold and rejects later admission", %{
    provider_key: provider_key,
    actor: actor
  } do
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(3))

    for _ <- 1..3 do
      tracker = start_tracker(provider_key, 1, 1)

      assert {:ok, %{status: "failed"}} =
               AcquisitionTracker.finish(tracker, {:error, :provider_timeout})
    end

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.circuit_failure_streak == 3
    assert %DateTime{} = health.circuit_opened_at
    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "disabled"

    assert {:error, :provider_disabled} =
             AcquisitionBudget.admit(provider_key)
  end

  test "opening materializes a configured provider that has not been persisted", %{
    provider_key: provider_key,
    actor: actor
  } do
    TcgCheap.Repo.query!(
      "DELETE FROM acquisition_data_providers WHERE provider_key = $1",
      [provider_key]
    )

    Application.put_env(:tcg_cheap, :acquisition_health, health_config(1))

    assert {:ok, %{status: "failed"}} =
             AcquisitionTracker.finish(
               start_tracker(provider_key, 1, 1),
               {:error, :provider_timeout}
             )

    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "disabled"
    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert %DateTime{} = health.circuit_opened_at
  end

  test "terminal cancelled eligible outcomes open at threshold", %{
    provider_key: provider_key,
    actor: actor
  } do
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(2))

    for _ <- 1..2 do
      tracker = start_tracker(provider_key, 1, 1)

      assert {:ok, %{status: "cancelled"}} =
               AcquisitionTracker.finish(tracker, {:cancel, :provider_timeout})
    end

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.circuit_failure_streak == 2
    assert %DateTime{} = health.circuit_opened_at
    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "disabled"
  end

  test "excluded categories do not increment or open the circuit", %{
    provider_key: provider_key,
    actor: actor
  } do
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(1))

    for {reason, category} <- [
          {:acquisition_budget_rejected, "budget"},
          {:persistence_failed, "persistence"},
          {:invalid_provider_configuration, "configuration"},
          {:invalid_input, "local_input"},
          {:unclassified, "unknown"}
        ] do
      tracker = start_tracker(provider_key, 1, 1)

      assert {:ok, %{status: "failed", failure_category: ^category}} =
               AcquisitionTracker.finish(tracker, {:error, reason})
    end

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.circuit_failure_streak == 0
    assert is_nil(health.circuit_opened_at)
    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "active"
  end

  test "database rejects a closed pristine health row with a circuit streak", %{
    provider_key: provider_key
  } do
    error =
      assert_raise Postgrex.Error, fn ->
        TcgCheap.Repo.query!(
          "INSERT INTO acquisition_source_health (provider_key, last_started_at, consecutive_failures, circuit_failure_streak) VALUES ($1, now(), 0, 1)",
          ["invalid-#{provider_key}"]
        )
      end

    assert error.postgres.constraint == "source_health_circuit_open_invariant"
  end

  test "success resets a closed circuit streak", %{provider_key: provider_key, actor: actor} do
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(3))

    for _ <- 1..2 do
      assert {:ok, _} =
               AcquisitionTracker.finish(start_tracker(provider_key), {:error, :provider_timeout})
    end

    assert {:ok, _} = AcquisitionTracker.finish(start_tracker(provider_key), :ok)
    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.circuit_failure_streak == 0
    assert is_nil(health.circuit_opened_at)
  end

  test "an in-flight success cannot close a circuit opened by another attempt", %{
    provider_key: provider_key,
    actor: actor
  } do
    Application.put_env(:tcg_cheap, :acquisition_health, health_config(1))
    success = start_tracker(provider_key)

    assert {:ok, %{status: "failed"}} =
             AcquisitionTracker.finish(
               start_tracker(provider_key, 1, 1),
               {:error, :provider_timeout}
             )

    assert {:ok, %{status: "succeeded"}} = AcquisitionTracker.finish(success, :ok)
    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.circuit_failure_streak == 1
    assert %DateTime{} = health.circuit_opened_at
    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "disabled"
  end

  test "invalid circuit configuration rolls back terminal finalization", %{
    provider_key: provider_key,
    actor: actor
  } do
    tracker = start_tracker(provider_key, 1, 1)

    Application.put_env(
      :tcg_cheap,
      :acquisition_health,
      Keyword.delete(health_config(1), :circuit_breaker_failure_threshold)
    )

    assert {:error, :acquisition_tracking_failed} =
             AcquisitionTracker.finish(tracker, {:error, :provider_timeout})

    assert {:ok, [run]} = Operations.list_recent_acquisition_runs([provider_key], 1, actor: actor)
    assert run.status == "running"
    assert run.finished_at == nil

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.last_status == nil
    assert health.circuit_failure_streak == 0
    assert health.circuit_opened_at == nil
    assert Operations.get_provider_by_key!(provider_key, authorize?: false).status == "active"
  end

  test "finalization failure is returned and leaves the run running", %{
    provider_key: provider_key,
    actor: actor
  } do
    assert {:error, :acquisition_tracking_failed} =
             AcquisitionTracker.run(job(nil), tracker_options(provider_key), fn _ ->
               TcgCheap.Repo.query!(
                 "DELETE FROM acquisition_source_health WHERE provider_key = $1",
                 [provider_key]
               )

               :ok
             end)

    assert {:ok, [run]} = Operations.list_recent_acquisition_runs([provider_key], 1, actor: actor)
    assert run.status == "running"
    assert run.finished_at == nil
    assert {:ok, []} = Operations.list_source_health([provider_key], actor: actor)
  end

  test "a later persisted attempt reconciles stranded lower attempts", %{
    provider_key: provider_key,
    actor: actor
  } do
    persisted_job_id = System.unique_integer([:positive])

    assert {:ok, first} =
             AcquisitionTracker.start(job(persisted_job_id, 1, 2), tracker_options(provider_key))

    assert {:ok, second} =
             AcquisitionTracker.start(job(persisted_job_id, 2, 2), tracker_options(provider_key))

    assert first.run.id != second.run.id
    assert {:ok, runs} = Operations.list_recent_acquisition_runs([provider_key], 10, actor: actor)
    assert Enum.sort_by(runs, & &1.attempt) |> Enum.map(& &1.status) == ["failed", "running"]

    first_run = Enum.find(runs, &(&1.attempt == 1))
    assert first_run.failure_category == "unknown"
    assert DateTime.compare(first_run.finished_at, second.run.started_at) == :eq
    assert DateTime.compare(second.run.started_at, first.run.started_at) in [:eq, :gt]

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.last_status == "failed"
    assert health.last_failure_category == "unknown"
    assert health.consecutive_failures == 1
  end

  test "reconciliation restores missing source health before recording the new attempt", %{
    provider_key: provider_key,
    actor: actor
  } do
    persisted_job_id = System.unique_integer([:positive])

    assert {:ok, _first} =
             AcquisitionTracker.start(job(persisted_job_id, 1, 2), tracker_options(provider_key))

    TcgCheap.Repo.query!("DELETE FROM acquisition_source_health WHERE provider_key = $1", [
      provider_key
    ])

    assert {:ok, _second} =
             AcquisitionTracker.start(job(persisted_job_id, 2, 2), tracker_options(provider_key))

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.last_status == "failed"
    assert health.last_failure_category == "unknown"
    assert health.consecutive_failures == 1
  end

  test "callback exceptions finalize safely and preserve their original kind", %{
    provider_key: provider_key,
    actor: actor
  } do
    assert_raise RuntimeError, "bearer-secret", fn ->
      AcquisitionTracker.run(job(nil), tracker_options(provider_key), fn _admitter ->
        raise "bearer-secret"
      end)
    end

    assert catch_throw(
             AcquisitionTracker.run(job(nil), tracker_options(provider_key), fn _admitter ->
               throw(:bearer_secret)
             end)
           ) == :bearer_secret

    assert catch_exit(
             AcquisitionTracker.run(job(nil), tracker_options(provider_key), fn _admitter ->
               exit(:bearer_secret)
             end)
           ) == :bearer_secret

    assert {:ok, runs} = Operations.list_recent_acquisition_runs([provider_key], 10, actor: actor)
    assert length(runs) == 3
    assert Enum.all?(runs, &(&1.status == "retryable_failure"))
    assert Enum.all?(runs, &(&1.failure_category == "unknown"))
    refute inspect(runs) =~ "bearer-secret"
    refute inspect(runs) =~ "bearer_secret"

    assert {:ok, [health]} = Operations.list_source_health([provider_key], actor: actor)
    assert health.consecutive_failures == 3
    assert health.last_failure_category == "unknown"
  end

  test "admin reads are bounded and protected", %{provider_key: provider_key, actor: actor} do
    tracker = start_tracker(provider_key)
    assert {:ok, _run} = AcquisitionTracker.finish(tracker, {:error, :persistence_failed})

    assert {:ok, [_run]} =
             Operations.list_recent_acquisition_runs([provider_key], 1, actor: actor)

    assert {:ok, [_health]} = Operations.list_source_health([provider_key], actor: actor)

    assert {:ok, []} =
             Operations.list_recent_acquisition_runs([provider_key], 1,
               actor: %{},
               authorize?: true
             )

    assert {:error, _reason} =
             Operations.list_recent_acquisition_runs([provider_key], 51, actor: actor)

    assert {:error, _reason} =
             Operations.list_source_health(List.duplicate(provider_key, 101), actor: actor)

    assert {:error, _reason} =
             Operations.start_acquisition_run(
               "forbidden-#{System.unique_integer([:positive])}",
               provider_key,
               "single_valuation",
               "base1-4",
               "TcgCheap.TestWorker",
               "valuations",
               nil,
               1,
               5,
               DateTime.utc_now()
             )
  end

  defp start_tracker(provider_key, attempt \\ 1, max_attempts \\ 5) do
    assert {:ok, tracker} =
             AcquisitionTracker.start(
               job(System.unique_integer([:positive]), attempt, max_attempts),
               tracker_options(provider_key)
             )

    tracker
  end

  defp job(id, attempt \\ 1, max_attempts \\ 5),
    do: %Oban.Job{
      id: id,
      attempt: attempt,
      max_attempts: max_attempts,
      worker: "Worker",
      queue: "valuations"
    }

  defp tracker_options(provider_key),
    do: [
      provider_key: provider_key,
      operation: "single_valuation",
      target_key: "base1-4"
    ]

  defp budget_config(provider_key),
    do: [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: provider_key,
          display_name: "Tracker provider",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1_000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]

  defp health_config(threshold),
    do: [
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      circuit_breaker_failure_threshold: threshold,
      stale_after_seconds: %{}
    ]

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
