defmodule TcgCheap.Operations.AcquisitionReconcilerWorkerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Operations.AcquisitionReconcilerWorker
  alias TcgCheap.Pricing.ExchangeRateWorker
  alias TcgCheap.Pricing.Singles.ValuationWorker

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_health)

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      stale_after_seconds: %{}
    )

    on_exit(fn -> Application.put_env(:tcg_cheap, :acquisition_health, previous) end)
    :ok
  end

  test "malformed arguments cancel and empty arguments reconcile" do
    assert {:cancel, :malformed_job_args} =
             AcquisitionReconcilerWorker.perform(%Oban.Job{args: %{unexpected: true}})

    provider = "worker-#{System.unique_integer([:positive])}"
    now = DateTime.utc_now()
    started_at = DateTime.add(now, -1_000, :second)

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_source_health (id, provider_key, last_started_at, consecutive_failures, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 0, $2, $2)",
      [provider, started_at]
    )

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_runs (id, attempt_key, provider_key, operation, target_key, worker, queue, attempt, max_attempts, status, request_count, started_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 'exchange_rate', 'EUR/PLN', 'worker', 'operations', 1, 3, 'running', 0, $3, $3, $3)",
      ["worker-#{System.unique_integer([:positive])}", provider, started_at]
    )

    assert :ok = AcquisitionReconcilerWorker.perform(%Oban.Job{args: %{}})

    assert {:ok, %{rows: [["failed"]]}} =
             TcgCheap.Repo.query("SELECT status FROM acquisition_runs WHERE provider_key = $1", [
               provider
             ])
  end

  test "invalid configuration cancels" do
    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 0,
      reconcile_limit: 100,
      stale_after_seconds: %{}
    )

    assert {:cancel, :invalid_acquisition_health_configuration} =
             AcquisitionReconcilerWorker.perform(%Oban.Job{args: %{}})
  end

  test "malformed provider configuration cancels explicitly" do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    Application.put_env(:tcg_cheap, :acquisition_budget, [])

    on_exit(fn -> Application.put_env(:tcg_cheap, :acquisition_budget, previous) end)

    assert {:cancel, :invalid_provider_configuration} =
             AcquisitionReconcilerWorker.perform(%Oban.Job{args: %{}})
  end

  test "external acquisition timeouts remain bounded" do
    assert ValuationWorker.timeout(%Oban.Job{}) == 60_000
    assert ExchangeRateWorker.timeout(%Oban.Job{}) == 60_000
    assert AcquisitionReconcilerWorker.timeout(%Oban.Job{}) == 60_000
  end
end
