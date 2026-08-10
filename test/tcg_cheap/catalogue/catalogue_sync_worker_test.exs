defmodule TcgCheap.Catalogue.CatalogueSyncWorkerTestProvider do
  def list_sets(opts) do
    with :ok <- admit(opts) do
      Agent.get_and_update(agent(opts), &list_result/1)
    end
  end

  def fetch_set(id, opts) do
    with :ok <- admit(opts) do
      Agent.get_and_update(agent(opts), fn state ->
        result = Map.fetch!(state.sets, id)
        response = provider_response(result)
        {response, %{state | fetched: state.fetched ++ [id]}}
      end)
    end
  end

  defp admit(opts), do: Keyword.fetch!(opts, :request_admitter).()
  defp agent(opts), do: Keyword.fetch!(opts, :agent)
  defp list_result(%{list_error: nil} = state), do: reply({:ok, state.briefs}, state)
  defp list_result(state), do: reply({:error, state.list_error}, state)
  defp reply(result, state), do: {result, %{state | list_calls: state.list_calls + 1}}
  defp provider_response({:error, _reason} = error), do: error
  defp provider_response(result), do: {:ok, result}
end

defmodule TcgCheap.Catalogue.CatalogueSyncWorkerAdmissionStub do
  def admit(_provider_key) do
    Agent.get_and_update(
      Application.fetch_env!(:tcg_cheap, :catalogue_sync_worker_admissions),
      fn [result | remaining] -> {result, remaining} end
    )
  end
end

defmodule TcgCheap.Catalogue.CatalogueSyncWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.CatalogueSyncWorker
  alias TcgCheap.Operations
  alias TcgCheap.Operations.CatalogueSyncRun

  setup do
    previous_sync = Application.get_env(:tcg_cheap, :catalogue_sync)
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_admitter = Application.get_env(:tcg_cheap, :acquisition_budget_admitter)
    previous_admissions = Application.get_env(:tcg_cheap, :catalogue_sync_worker_admissions)

    {:ok, provider} =
      Agent.start_link(fn ->
        %{briefs: [], sets: %{}, list_calls: 0, fetched: [], list_error: nil}
      end)

    Application.put_env(:tcg_cheap, :catalogue_sync, sync_config(provider))
    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

    on_exit(fn ->
      restore(:catalogue_sync, previous_sync)
      restore(:acquisition_budget, previous_budget)
      restore(:acquisition_budget_admitter, previous_admitter)
      restore(:catalogue_sync_worker_admissions, previous_admissions)
    end)

    %{provider: provider}
  end

  test "discovers once and resumes from durable progress across snoozed batches", %{
    provider: provider
  } do
    ids = Enum.map(1..3, &"worker-set-#{&1}")
    configure_provider(provider, ids)

    assert {:snooze, 900} = CatalogueSyncWorker.perform(job(1, 5))
    assert {:ok, first_run} = Operations.get_active_catalogue_sync_run(authorize?: false)
    assert first_run.next_index == 2
    assert first_run.synced_sets == 2
    assert provider_state(provider).list_calls == 1
    assert provider_state(provider).fetched == Enum.take(ids, 2)

    assert :ok = CatalogueSyncWorker.perform(job(2, 6))
    assert {:ok, nil} = Operations.get_active_catalogue_sync_run(authorize?: false)

    [completed] = Ash.read!(CatalogueSyncRun, authorize?: false)
    assert completed.status == "completed"
    assert completed.next_index == 3
    assert completed.synced_sets == 3
    assert provider_state(provider).list_calls == 1
    assert provider_state(provider).fetched == ids
  end

  test "budget rejection pauses on the current set without refetching completed sets", %{
    provider: provider
  } do
    ids = ["budget-set-1", "budget-set-2"]
    configure_provider(provider, ids)

    {:ok, admissions} =
      Agent.start_link(fn ->
        [
          {:ok, %{}},
          {:ok, %{}},
          {:error, :hourly_limit_reached}
        ]
      end)

    Application.put_env(
      :tcg_cheap,
      :acquisition_budget_admitter,
      TcgCheap.Catalogue.CatalogueSyncWorkerAdmissionStub
    )

    Application.put_env(:tcg_cheap, :catalogue_sync_worker_admissions, admissions)

    assert {:error, :acquisition_budget_rejected} = CatalogueSyncWorker.perform(job(1, 5))
    assert {:ok, run} = Operations.get_active_catalogue_sync_run(authorize?: false)
    assert run.next_index == 1
    assert provider_state(provider).list_calls == 1
    assert provider_state(provider).fetched == [hd(ids)]
  end

  test "permanent set failures advance safely and complete with an incomplete outcome", %{
    provider: provider
  } do
    ids = ["broken-set", "healthy-set"]

    configure_provider(provider, ids, %{
      "broken-set" => {:error, {:malformed_response, :missing_identity}}
    })

    assert {:cancel, :catalogue_sync_incomplete} = CatalogueSyncWorker.perform(job(1, 5))

    [completed] = Ash.read!(CatalogueSyncRun, authorize?: false)
    assert completed.status == "completed"
    assert completed.failed_sets == 1
    assert completed.synced_sets == 1

    assert {:ok, [issue]} = Operations.list_admin_import_issues(authorize?: false)
    assert issue.provider_key == "tcgdex_catalogue"
    assert issue.target_key == "broken-set"
  end

  test "transient set failures preserve the checkpoint for a later retry", %{provider: provider} do
    ids = ["retry-set"]

    configure_provider(provider, ids, %{
      "retry-set" => {:error, {:transport_error, "do-not-retain"}}
    })

    assert {:error, :provider_transport_error} = CatalogueSyncWorker.perform(job(1, 5))
    assert {:ok, run} = Operations.get_active_catalogue_sync_run(authorize?: false)
    assert run.next_index == 0
    assert run.failed_sets == 0

    configure_provider(provider, ids)
    assert :ok = CatalogueSyncWorker.perform(job(2, 5))

    [completed] = Ash.read!(CatalogueSyncRun, authorize?: false)
    assert completed.status == "completed"
    assert completed.synced_sets == 1
    assert completed.failed_sets == 0
  end

  test "decode and provider-wide HTTP failures retry while missing sets advance", %{
    provider: provider
  } do
    ids = ["classified-set"]

    configure_provider(provider, ids, %{
      "classified-set" => {:error, {:decode_error, :truncated}}
    })

    assert {:error, :provider_response} = CatalogueSyncWorker.perform(job(1, 5))
    assert {:ok, %{next_index: 0}} = Operations.get_active_catalogue_sync_run(authorize?: false)

    configure_provider(provider, ids, %{
      "classified-set" => {:error, {:http_error, %{status: 401}}}
    })

    assert {:error, :provider_response} = CatalogueSyncWorker.perform(job(2, 5))
    assert {:ok, %{next_index: 0}} = Operations.get_active_catalogue_sync_run(authorize?: false)

    configure_provider(provider, ids, %{
      "classified-set" => {:error, {:http_error, %{status: 404}}}
    })

    assert {:cancel, :catalogue_sync_incomplete} = CatalogueSyncWorker.perform(job(3, 5))

    [completed] = Ash.read!(CatalogueSyncRun, authorize?: false)
    assert completed.status == "completed"
    assert completed.failed_sets == 1
  end

  test "budget persistence uses the configured long backoff" do
    job = %Oban.Job{
      attempt: 1,
      unsaved_error: %{
        reason: %Oban.PerformError{reason: :budget_persistence_failed}
      }
    }

    assert CatalogueSyncWorker.backoff(job) == 3_600
  end

  test "reserved provider admission options fail configuration closed", %{provider: provider} do
    Application.put_env(
      :tcg_cheap,
      :catalogue_sync,
      Keyword.put(sync_config(provider), :provider_options, request_admitter: fn -> :ok end)
    )

    assert {:error, :invalid_provider_configuration} = CatalogueSyncWorker.provider_config()
    assert {:error, :invalid_provider_configuration} = CatalogueSyncWorker.enqueue()
  end

  test "the canonical enqueue is unique and accepts no dynamic target" do
    assert {:ok, first} = CatalogueSyncWorker.enqueue()
    assert {:ok, duplicate} = CatalogueSyncWorker.enqueue()
    assert duplicate.conflict?
    assert duplicate.id == first.id

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CatalogueSyncWorker,
      args: %{"scope" => "all_sets"}
    )

    assert {:cancel, :malformed_job_args} =
             CatalogueSyncWorker.perform(%{job(1, 5) | args: %{"scope" => "one-set"}})
  end

  test "snoozed tracked batches are successful health evidence", %{provider: provider} do
    ids = ["health-set-1", "health-set-2", "health-set-3"]
    configure_provider(provider, ids)

    assert {:snooze, 900} = CatalogueSyncWorker.perform(job(1, 5))
    admin = admin()

    assert {:ok, [health]} =
             Operations.list_source_health(["tcgdex_catalogue"], actor: admin)

    assert health.last_status == "succeeded"
    assert health.consecutive_failures == 0
  end

  test "discovery timeout leaves no run, records health, and retries from discovery", %{
    provider: provider
  } do
    ids = ["timeout-set"]
    configure_provider(provider, ids)
    Agent.update(provider, &Map.put(&1, :list_error, {:provider_timeout, :request}))

    assert {:error, :provider_timeout} = CatalogueSyncWorker.perform(job(1, 5))
    assert {:ok, nil} = Operations.get_active_catalogue_sync_run(authorize?: false)
    assert provider_state(provider).list_calls == 1
    assert provider_state(provider).fetched == []

    admin = admin()
    assert {:ok, [health]} = Operations.list_source_health(["tcgdex_catalogue"], actor: admin)
    assert health.last_failure_category == "timeout"

    configure_provider(provider, ids)
    assert :ok = CatalogueSyncWorker.perform(job(2, 5))
    assert provider_state(provider).list_calls == 1
    assert provider_state(provider).fetched == ids

    [completed] = Ash.read!(CatalogueSyncRun, authorize?: false)
    assert completed.status == "completed"
    assert completed.synced_sets == 1
  end

  defp configure_provider(agent, ids, overrides \\ %{}) do
    sets =
      Map.new(ids, fn id ->
        {id,
         Map.get(overrides, id, %{
           "id" => id,
           "name" => "Set #{id}",
           "cards" => [],
           "releaseDate" => "2026-01-02",
           "logo" => "https://assets.example/logo",
           "symbol" => "https://assets.example/symbol",
           "cardCount" => %{"official" => 0, "total" => 0},
           "legal" => %{"standard" => true, "expanded" => false}
         })}
      end)

    briefs = Enum.map(Enum.reverse(ids), &%{"id" => &1, "name" => "Set #{&1}"})

    Agent.update(agent, fn state ->
      %{state | briefs: briefs, sets: sets, list_calls: 0, fetched: [], list_error: nil}
    end)
  end

  defp provider_state(agent), do: Agent.get(agent, & &1)

  defp job(attempt, max_attempts),
    do: %Oban.Job{
      id: nil,
      attempt: attempt,
      max_attempts: max_attempts,
      worker: Oban.Worker.to_string(CatalogueSyncWorker),
      queue: "catalogue_sync",
      args: %{"scope" => "all_sets"}
    }

  defp sync_config(agent),
    do: [
      provider: TcgCheap.Catalogue.CatalogueSyncWorkerTestProvider,
      provider_options: [agent: agent],
      batch_size: 2,
      batch_delay_seconds: 900,
      budget_backoff_seconds: 3_600
    ]

  defp budget_config,
    do: [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: "tcgdex_catalogue",
          display_name: "TCGdex Catalogue",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1_000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]

  defp admin do
    Accounts.register_admin!(
      %{
        email: "catalogue-worker-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp restore(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
