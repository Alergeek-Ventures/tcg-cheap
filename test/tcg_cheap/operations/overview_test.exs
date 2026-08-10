defmodule TcgCheap.Operations.OverviewTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Operations.{AcquisitionBudget, AcquisitionTracker, Overview}

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_health = Application.get_env(:tcg_cheap, :acquisition_health)
    key = "overview-provider-#{System.unique_integer([:positive])}"

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key), provider("unpersisted-#{key}")]
    )

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      stale_after_seconds: %{}
    )

    {:ok, %{rows: [[id]]}} =
      TcgCheap.Repo.query(
        "INSERT INTO admins (id, email, hashed_password) VALUES (gen_random_uuid(), $1, 'test') RETURNING id",
        ["admin-#{key}@example.com"]
      )

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:tcg_cheap, :acquisition_budget),
        else: Application.put_env(:tcg_cheap, :acquisition_budget, previous)

      if is_nil(previous_health),
        do: Application.delete_env(:tcg_cheap, :acquisition_health),
        else: Application.put_env(:tcg_cheap, :acquisition_health, previous_health)
    end)

    {:ok, key: key, actor: %Admin{id: id}, now: ~U[2026-08-09 12:34:56Z]}
  end

  test "overview merges unpersisted providers and reports persisted versions", %{
    key: key,
    actor: actor,
    now: now
  } do
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> now end)
    assert {:ok, overview} = Overview.load(actor, clock: fn -> now end)

    persisted = Enum.find(overview.providers, &(&1.provider_key == key))

    unpersisted =
      Enum.find(overview.providers, &String.starts_with?(&1.provider_key, "unpersisted-"))

    assert persisted.persisted?
    assert is_struct(persisted.updated_at, DateTime)
    assert unpersisted.persisted? == false
    assert unpersisted.updated_at == nil
    assert unpersisted.status == "active"
    assert persisted.current_usage.hour.request_count == 1
    assert overview.global.hour.request_count == 1
  end

  test "current windows exclude old rows and sum provider usage", %{
    key: key,
    actor: actor,
    now: now
  } do
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> now end)
    assert {:ok, _} = AcquisitionBudget.admit("unpersisted-#{key}", clock: fn -> now end)
    provider = TcgCheap.Operations.get_provider_by_key!(key)
    old = DateTime.add(now, -7_200, :second)

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_budget_usages (id, provider_id, window_kind, window_started_at, request_count, estimated_spend_usd, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, 'hour', $2, 99, 99, now(), now())",
      [Ecto.UUID.dump!(provider.id), old]
    )

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key)]
    )

    assert {:ok, overview} = Overview.load(actor, clock: fn -> now end)
    assert overview.global.hour.request_count == 2
    assert Enum.map(overview.providers, & &1.provider_key) == [key]

    assert Enum.find(overview.providers, &(&1.provider_key == key)).current_usage.hour.request_count ==
             1
  end

  test "authorization allows exact internal lookup but protects admin reads", %{key: key} do
    assert {:ok, _} =
             TcgCheap.Operations.register_provider(
               key,
               "Provider",
               Decimal.new("1"),
               1,
               1,
               1,
               Decimal.new("1"),
               authorize?: false
             )

    assert {:ok, _} = TcgCheap.Operations.get_provider_by_key(key)

    assert {:ok, []} = TcgCheap.Operations.list_providers([key], actor: %{}, authorize?: true)

    assert {:error, :invalid_actor} = Overview.load(%{id: "fake"})
    assert {:error, :invalid_actor} = Overview.load(%Admin{id: Ecto.UUID.generate()})
  end

  test "control is configured, stale-safe, and rejects invalid input", %{key: key, actor: actor} do
    assert {:error, :already_effectively_active} =
             Overview.set_provider_status(actor, key, "active")

    assert {:error, :stale_expected_updated_at} =
             Overview.set_provider_status(actor, key, "disabled", "bogus")

    assert {:ok, provider} = Overview.set_provider_status(actor, key, "disabled")
    assert provider.status == "disabled"

    assert {:error, :missing_expected_updated_at} =
             Overview.set_provider_status(actor, key, "active")

    assert {:ok, provider} =
             Overview.set_provider_status(actor, key, "active", provider.updated_at)

    assert provider.status == "active"

    assert {:error, _} =
             Overview.set_provider_status(
               actor,
               key,
               "disabled",
               DateTime.add(provider.updated_at, -1, :second)
             )

    assert {:error, :invalid_provider_key} =
             Overview.set_provider_status(actor, "nope", "disabled")

    assert {:error, :invalid_provider_status} = Overview.set_provider_status(actor, key, "paused")
  end

  test "overview validates clock, options, and malformed configuration", %{actor: actor, now: now} do
    assert {:error, :invalid_clock} =
             Overview.load(actor, clock: fn -> DateTime.now!("Europe/Warsaw") end)

    assert {:error, :invalid_limit} = Overview.load(actor, max_recent_jobs: 51)
    assert {:error, :invalid_limit} = Overview.load(actor, max_recent_runs: 51)
    assert {:error, :invalid_overview_input} = Overview.load(actor, [:bad])
    Application.put_env(:tcg_cheap, :acquisition_budget, [])
    assert {:error, :invalid_provider_configuration} = Overview.load(actor, clock: fn -> now end)
  end

  test "overview validates and reuses one clock instant", %{actor: actor, now: now} do
    {:ok, clock} = Agent.start_link(fn -> 0 end)

    assert {:ok, _overview} =
             Overview.load(actor,
               clock: fn ->
                 Agent.get_and_update(clock, fn calls -> {now, calls + 1} end)
               end
             )

    assert Agent.get(clock, & &1) == 1
  end

  test "overview projects bounded source health and acquisition runs without raw failures", %{
    key: key,
    actor: actor
  } do
    job = %Oban.Job{
      id: System.unique_integer([:positive]),
      attempt: 2,
      max_attempts: 5,
      worker: "TcgCheap.TestWorker",
      queue: "valuations"
    }

    assert {:cancel, {:provider_rate_limited, "bearer-secret"}} =
             AcquisitionTracker.run(
               job,
               [
                 provider_key: key,
                 operation: "single_valuation",
                 target_key: "base1-4"
               ],
               fn _request_admitter ->
                 {:cancel, {:provider_rate_limited, "bearer-secret"}}
               end
             )

    assert {:ok, overview} = Overview.load(actor)
    provider = Enum.find(overview.providers, &(&1.provider_key == key))
    run = Enum.find(overview.recent_runs, &(&1.provider_key == key))

    assert provider.health.last_status == "cancelled"
    assert provider.health.last_failure_category == "rate_limit"
    assert provider.health.consecutive_failures == 1
    assert run.failure_category == "rate_limit"
    assert run.status == "cancelled"
    assert run.request_count == 0
    refute inspect(run) =~ "bearer-secret"
    refute Map.has_key?(run, :attempt_key)
  end

  test "failed job projection is safe and bounded", %{actor: actor, now: now} do
    for index <- 1..60 do
      state = if rem(index, 2) == 0, do: "retryable", else: "discarded"

      TcgCheap.Repo.query!(
        ~S<INSERT INTO oban_jobs (state, queue, worker, args, errors, attempt, max_attempts, inserted_at, scheduled_at, meta) VALUES ($1, 'ops', 'Worker', '{"secret":"hidden"}', ARRAY[$2::jsonb], $3, 5, $4, $4, '{"secret":"hidden"}')>,
        [
          state,
          Jason.encode!(%{
            "error" =>
              if(index == 60,
                do: "timeout bearer top-secret-#{String.duplicate("x", 2_000)}",
                else: "safe-error-#{index}"
              ),
            "args" => "do-not-leak"
          }),
          rem(index, 5),
          DateTime.add(now, index, :second)
        ]
      )
    end

    assert {:ok, overview} = Overview.load(actor, clock: fn -> now end)
    assert length(overview.recent_jobs) == 25
    assert {:ok, bounded} = Overview.load(actor, clock: fn -> now end, max_recent_jobs: 50)
    assert length(bounded.recent_jobs) == 50
    job = hd(overview.recent_jobs)
    assert job.failure_category == "Timeout"
    refute Map.has_key?(job, :args)
    refute Map.has_key?(job, :meta)
    refute Map.has_key?(job, :latest_error)
  end

  test "projects source freshness and stranded attempts from the strict policy", %{
    key: key,
    actor: actor,
    now: now
  } do
    not_observed = "not-observed-#{key}"

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        provider(key),
        provider("unpersisted-#{key}"),
        provider(not_observed)
      ]
    )

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 10,
      reconcile_limit: 100,
      stale_after_seconds: %{key => 10, not_observed => 10}
    )

    insert_health(key, now, DateTime.add(now, -10, :second))
    insert_health(not_observed, now, nil)
    insert_run(key, "running", DateTime.add(now, -10, :second), nil, "running-at-boundary")
    insert_run(key, "succeeded", DateTime.add(now, -20, :second), now, "terminal-old")

    assert {:ok, overview} = Overview.load(actor, clock: fn -> now end)
    states = Map.new(overview.providers, &{&1.provider_key, &1.source_state})
    assert states[key] == :stale
    assert states["unpersisted-#{key}"] == :on_demand
    assert states[not_observed] == :not_observed

    running = Enum.find(overview.recent_runs, &(&1.target_key == "running-at-boundary"))
    terminal = Enum.find(overview.recent_runs, &(&1.target_key == "terminal-old"))
    assert running.overdue?
    refute terminal.overdue?
  end

  test "future source health evidence fails the overview closed", %{
    key: key,
    actor: actor,
    now: now
  } do
    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 10,
      reconcile_limit: 100,
      stale_after_seconds: %{key => 10}
    )

    insert_health(key, now, DateTime.add(now, 1, :second))

    assert {:error, :invalid_source_health_evidence} =
             Overview.load(actor, clock: fn -> now end)
  end

  test "invalid health policy fails the overview closed", %{actor: actor, now: now} do
    Application.put_env(:tcg_cheap, :acquisition_health, [])

    assert {:error, :invalid_acquisition_health_configuration} =
             Overview.load(actor, clock: fn -> now end)
  end

  defp insert_health(provider_key, now, succeeded_at) do
    values =
      if succeeded_at do
        [provider_key, now, succeeded_at]
      else
        [provider_key, now]
      end

    query =
      if succeeded_at do
        "INSERT INTO acquisition_source_health (provider_key, last_started_at, last_succeeded_at, last_status, consecutive_failures) VALUES ($1, $2, $3, 'succeeded', 0)"
      else
        "INSERT INTO acquisition_source_health (provider_key, last_started_at, consecutive_failures) VALUES ($1, $2, 0)"
      end

    TcgCheap.Repo.query!(query, values)
  end

  defp insert_run(provider_key, status, started_at, finished_at, target_key) do
    failure = if status == "running" or status == "succeeded", do: nil, else: "timeout"

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_runs (attempt_key, provider_key, operation, target_key, worker, queue, attempt, max_attempts, status, failure_category, started_at, finished_at) VALUES ($1, $2, 'single_valuation', $3, 'TestWorker', 'ops', 1, 5, $4, $5, $6, $7)",
      [
        "#{provider_key}-#{target_key}",
        provider_key,
        target_key,
        status,
        failure,
        started_at,
        finished_at
      ]
    )
  end

  defp provider(key),
    do: [
      provider_key: key,
      display_name: "Provider",
      estimated_cost_per_request: "1.00",
      hourly_request_limit: 10,
      daily_request_limit: 20,
      monthly_request_limit: 30,
      monthly_spend_limit: "50.00"
    ]
end
