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
             Enum.sort(Enum.map(ids, &%{"set_id" => &1, "offset" => 0, "as_of" => "2026-08-19"}))
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

    assert {:error, :acquisition_budget_rejected} =
             SinglesScopeBootstrapWorker.perform(job(%{"as_of" => "2026-08-19"}))

    assert Agent.get(provider, & &1.calls) == 0
    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Catalogue.SinglesSetCollectionWorker)
  end

  defp job(args),
    do: %Oban.Job{
      args: args,
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
end
