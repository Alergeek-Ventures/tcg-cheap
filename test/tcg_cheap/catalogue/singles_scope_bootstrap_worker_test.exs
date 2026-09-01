defmodule TcgCheap.Catalogue.SinglesScopeBootstrapWorkerTestProvider do
  def fetch_set(_id, _opts), do: {:error, :not_used}

  def list_sets(opts) do
    with :ok <- Keyword.fetch!(opts, :request_admitter).() do
      agent = Keyword.fetch!(opts, :agent)

      Agent.get_and_update(agent, fn state ->
        {{:ok, state.sets}, %{state | calls: state.calls + 1}}
      end)
    end
  end
end

defmodule TcgCheap.Catalogue.SinglesScopeBootstrapWorkerAdmission do
  def admit(_key) do
    Agent.get_and_update(Application.fetch_env!(:tcg_cheap, :singles_admissions), fn
      [result | rest] -> {result, rest}
    end)
  end
end

defmodule TcgCheap.Catalogue.SinglesScopeBootstrapWorkerTest do
  use TcgCheap.DataCase, async: false
  import Ecto.Query
  import Oban.Testing
  alias TcgCheap.Catalogue.SinglesScopeBootstrapWorker

  setup do
    {:ok, provider} = Agent.start_link(fn -> %{sets: [], calls: 0} end)
    {:ok, admissions} = Agent.start_link(fn -> List.duplicate({:ok, %{}}, 10) end)

    previous =
      for key <- [
            :catalogue_sync,
            :singles_collection,
            :acquisition_budget,
            :acquisition_budget_admitter,
            :singles_admissions
          ],
          into: %{},
          do: {key, Application.get_env(:tcg_cheap, key)}

    Application.put_env(:tcg_cheap, :catalogue_sync,
      provider: TcgCheap.Catalogue.SinglesScopeBootstrapWorkerTestProvider,
      provider_options: [agent: provider],
      batch_size: 20,
      batch_delay_seconds: 900,
      budget_backoff_seconds: 3600
    )

    Application.put_env(:tcg_cheap, :singles_collection,
      pitch_black_set_id: "me05",
      paper_series_ids: ["sv", "me"],
      rolling_rarities: ["illustration rare", "special illustration rare"],
      chunk_size: 20
    )

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

    Application.put_env(
      :tcg_cheap,
      :acquisition_budget_admitter,
      TcgCheap.Catalogue.SinglesScopeBootstrapWorkerAdmission
    )

    Application.put_env(:tcg_cheap, :singles_admissions, admissions)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:tcg_cheap, key)
        {key, value} -> Application.put_env(:tcg_cheap, key, value)
      end)
    end)

    %{provider: provider, admissions: admissions}
  end

  test "admits once and enqueues the exact valid two-set child jobs", %{provider: provider} do
    ids = Enum.map(1..2, fn _ -> "sv#{System.unique_integer([:positive])}" end)

    Agent.update(provider, fn state ->
      Map.put(state, :sets, Enum.map(ids, fn id -> %{"id" => id, "name" => "Set"} end))
    end)

    assert :ok = SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))
    assert Agent.get(provider, & &1.calls) == 1

    assert Enum.sort(
             Enum.map(
               all_enqueued(
                 repo: TcgCheap.Repo,
                 worker: TcgCheap.Catalogue.SinglesSetCollectionWorker
               ),
               & &1.args
             )
           ) ==
             Enum.sort(
               Enum.map(
                 ids,
                 &%{"set_id" => &1, "offset" => 0, "as_of" => "2026-08-19", "policy_version" => 2}
               )
             )
  end

  test "filters historic and Pocket set IDs and prioritizes me05", %{provider: provider} do
    Agent.update(provider, fn state ->
      %{
        state
        | sets: [
            %{"id" => "base1", "name" => "Historic"},
            %{"id" => "tcgp01", "name" => "Pocket"},
            %{"id" => "sv01", "name" => "SV"},
            %{"id" => "me01", "name" => "ME"},
            %{"id" => "me05", "name" => "Pitch Black"}
          ]
      }
    end)

    assert :ok = SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    jobs =
      all_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)

    assert Enum.map(jobs, & &1.args["set_id"]) |> Enum.sort() == ["me01", "me05", "sv01"]

    assert Enum.find(jobs, &(&1.args["set_id"] == "me05")).priority <
             Enum.find(jobs, &(&1.args["set_id"] == "me01")).priority

    assert Enum.find(jobs, &(&1.args["set_id"] == "me01")).priority == 2
    assert Enum.find(jobs, &(&1.args["set_id"] == "sv01")).priority == 2
  end

  test "cron payload uses today's date and enqueues versioned children", %{provider: provider} do
    id = "sv#{System.unique_integer([:positive])}"
    Agent.update(provider, &Map.put(&1, :sets, [%{"id" => id, "name" => "Set"}]))

    assert :ok = SinglesScopeBootstrapWorker.perform(job(%{"policy_version" => 2}))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: TcgCheap.Catalogue.SinglesSetCollectionWorker,
      args: %{
        "policy_version" => 2,
        "set_id" => id,
        "offset" => 0,
        "as_of" => Date.to_iso8601(Date.utc_today())
      }
    )
  end

  test "uniqueness compares the complete bootstrap args" do
    cron = Oban.insert!(SinglesScopeBootstrapWorker.new(%{"policy_version" => 2}))
    same_cron = Oban.insert!(SinglesScopeBootstrapWorker.new(%{"policy_version" => 2}))
    assert cron.id == same_cron.id

    {1, _} =
      TcgCheap.Repo.update_all(from(j in Oban.Job, where: j.id == ^cron.id),
        set: [state: "completed", inserted_at: DateTime.add(DateTime.utc_now(), -1, :day)]
      )

    completed_cron = Oban.insert!(SinglesScopeBootstrapWorker.new(%{"policy_version" => 2}))
    assert completed_cron.id == cron.id

    {1, _} =
      TcgCheap.Repo.update_all(from(j in Oban.Job, where: j.id == ^cron.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)]
      )

    rerun_cron = Oban.insert!(SinglesScopeBootstrapWorker.new(%{"policy_version" => 2}))
    manual_args = %{"policy_version" => 2, "as_of" => "2026-08-19"}
    manual = Oban.insert!(SinglesScopeBootstrapWorker.new(manual_args))
    same_manual = Oban.insert!(SinglesScopeBootstrapWorker.new(manual_args))

    other_manual =
      Oban.insert!(
        SinglesScopeBootstrapWorker.new(%{"policy_version" => 2, "as_of" => "2026-08-20"})
      )

    assert rerun_cron.id != cron.id
    assert rerun_cron.id != manual.id
    assert manual.id == same_manual.id
    assert cron.id != manual.id
    assert manual.id != other_manual.id
  end

  test "unsupported and extra bootstrap payloads are malformed" do
    assert {:cancel, :malformed_job_args} =
             SinglesScopeBootstrapWorker.perform(
               job(%{"policy_version" => 2})
               |> Map.update!(:args, &Map.put(&1, "policy_version", 3))
             )

    assert {:cancel, :malformed_job_args} =
             SinglesScopeBootstrapWorker.perform(job(%{"policy_version" => 2, "extra" => true}))
  end

  test "duplicate and malformed set lists enqueue no children", %{provider: provider} do
    id = "sv#{System.unique_integer([:positive])}"

    Agent.update(
      provider,
      &Map.put(&1, :sets, [%{"id" => id, "name" => "Set"}, %{"id" => id, "name" => "Again"}])
    )

    assert {:cancel, :invalid_provider_response} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)
    Agent.update(provider, &Map.put(&1, :sets, [%{"name" => "missing id"}]))

    assert {:cancel, :invalid_provider_response} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)
  end

  test "wrong but valid pitch black set ID is rejected" do
    Application.put_env(:tcg_cheap, :singles_collection,
      pitch_black_set_id: "sv-base",
      paper_series_ids: ["sv", "me"],
      rolling_rarities: ["illustration rare", "special illustration rare"],
      chunk_size: 20
    )

    assert {:error, :invalid_singles_collection_configuration} =
             SinglesScopeBootstrapWorker.singles_config()
  end

  test "duplicate paper series config entries are rejected" do
    Application.put_env(:tcg_cheap, :singles_collection,
      pitch_black_set_id: "me05",
      paper_series_ids: ["sv", "me", "sv"],
      rolling_rarities: ["illustration rare", "special illustration rare"],
      chunk_size: 20
    )

    assert {:error, :invalid_singles_collection_configuration} =
             SinglesScopeBootstrapWorker.singles_config()
  end

  test "non-map set list elements cancel without enqueuing children", %{provider: provider} do
    Agent.update(provider, &Map.put(&1, :sets, ["not a set"]))

    assert {:cancel, :invalid_provider_response} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)
  end

  test "budget rejection is retryable and creates no children", %{
    provider: provider,
    admissions: admissions
  } do
    id = "sv#{System.unique_integer([:positive])}"
    Agent.update(provider, &Map.put(&1, :sets, [%{"id" => id, "name" => "Set"}]))
    Agent.update(admissions, fn _ -> [{:error, :hourly_limit_reached}] end)

    assert {:snooze, seconds} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    assert seconds > 0
    assert Agent.get(provider, & &1.calls) == 0
    run = latest_run("tcgdex_catalogue")
    assert run.status == "retryable_failure"
    assert run.failure_category == "budget"
    assert run.request_count == 0
    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)
  end

  test "disabled provider budget rejection is terminal", %{
    provider: provider,
    admissions: admissions
  } do
    Agent.update(provider, &Map.put(&1, :sets, [%{"id" => "sv01", "name" => "Set"}]))
    Agent.update(admissions, fn _ -> [{:error, :provider_disabled}] end)

    assert {:cancel, {:acquisition_budget_rejected, :provider_disabled}} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    assert %{status: "cancelled", failure_category: "budget", request_count: 0} =
             latest_run("tcgdex_catalogue")

    assert Agent.get(provider, & &1.calls) == 0
    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)
  end

  test "preserves an attached budget reset through snooze translation", %{
    provider: provider,
    admissions: admissions
  } do
    reset_at = ~U[2099-01-01 00:00:00Z]

    Agent.update(admissions, fn _ ->
      [{:error, {:acquisition_budget_rejected, :hourly_limit_reached, reset_at}}]
    end)

    assert {:snooze, seconds} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    assert seconds > 2_000_000_000
    assert Agent.get(provider, & &1.calls) == 0
  end

  test "legacy bootstrap payload is superseded without provider or budget calls", %{
    provider: provider
  } do
    legacy =
      job(%{"as_of" => "2026-08-19"}) |> Map.update!(:args, &Map.delete(&1, "policy_version"))

    assert {:cancel, :superseded_policy} = SinglesScopeBootstrapWorker.perform(legacy)
    assert Agent.get(provider, & &1.calls) == 0

    assert Agent.get(Application.fetch_env!(:tcg_cheap, :singles_admissions), & &1) ==
             List.duplicate({:ok, %{}}, 10)
  end

  test "completed legacy bootstrap does not conflict with a versioned bootstrap" do
    {:ok, legacy} =
      SinglesScopeBootstrapWorker.new(%{"as_of" => "2026-08-19"})
      |> Oban.insert()

    TcgCheap.Repo.update_all(from(j in Oban.Job, where: j.id == ^legacy.id),
      set: [state: "completed"]
    )

    assert {:ok, versioned} = SinglesScopeBootstrapWorker.enqueue(~D[2026-08-19])
    assert versioned.id != legacy.id
  end

  defp job(args),
    do: %Oban.Job{
      args: Map.put(args, "policy_version", 2),
      attempt: 1,
      max_attempts: 5,
      worker: Atom.to_string(SinglesScopeBootstrapWorker),
      queue: "catalogue_sync"
    }

  defp budget_config,
    do: [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: "tcgdex_catalogue",
          display_name: "TCGdex",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ],
        [
          provider_key: "tcgdex_cardmarket",
          display_name: "Cardmarket",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]

  defp latest_run(provider_key),
    do:
      TcgCheap.Operations.list_recent_acquisition_runs!([provider_key], 1, authorize?: false)
      |> hd()
end
