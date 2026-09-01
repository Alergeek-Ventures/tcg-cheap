defmodule TcgCheap.Catalogue.InternalSealedRetailerBootstrapWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing, only: [all_enqueued: 1]

  alias TcgCheap.Catalogue.InternalSealedRetailerBootstrapWorker, as: Worker
  alias TcgCheap.Catalogue.SealedRetailerWorker
  alias TcgCheap.Core

  test "publishes the fixed policy, registry, and Monday schedule" do
    assert Map.keys(Worker.sources()) |> Enum.sort() == [
             "boosterpoint",
             "cardzhouse",
             "lootquest",
             "pokebooster"
           ]

    assert Worker.sources() == %{
             "lootquest" => %{
               slug: "lootquest",
               name: "LootQuest",
               category: "regular_retailer",
               homepage_url: "https://lootquest.pl"
             },
             "cardzhouse" => %{
               slug: "cardzhouse",
               name: "CardzHouse",
               category: "lgs",
               homepage_url: "https://cardzhouse.pl"
             },
             "boosterpoint" => %{
               slug: "boosterpoint",
               name: "BoosterPoint",
               category: "lgs",
               homepage_url: "https://boosterpoint.pl"
             },
             "pokebooster" => %{
               slug: "pokebooster",
               name: "PokeBooster",
               category: "lgs",
               homepage_url: "https://pokebooster.pl"
             }
           }

    assert Application.fetch_env!(:tcg_cheap, Oban)[:plugins]
           |> Enum.find_value(fn
             {Oban.Plugins.Cron, opts} ->
               Enum.map(opts[:crontab], fn {cron, worker, child_opts} ->
                 {cron, worker, child_opts[:args]}
               end)

             _ ->
               nil
           end)
           |> Enum.filter(fn {_, worker, _} -> worker == Worker end) ==
             [
               {"0 1 * * 1", Worker, %{"policy_version" => 1, "source_key" => "lootquest"}},
               {"0 2 * * 1", Worker, %{"policy_version" => 1, "source_key" => "cardzhouse"}},
               {"0 3 * * 1", Worker, %{"policy_version" => 1, "source_key" => "boosterpoint"}},
               {"0 4 * * 1", Worker, %{"policy_version" => 1, "source_key" => "pokebooster"}}
             ]

    assert Application.fetch_env!(:tcg_cheap, :sealed_retailer_adapters) == %{
             "lootquest" => %{
               adapter: TcgCheap.Catalogue.SealedRetailers.LootQuest,
               options: [per_page: 100, max_pages: 10]
             },
             "cardzhouse" => %{
               adapter: TcgCheap.Catalogue.SealedRetailers.CardzHouse,
               options: [per_page: 100, max_pages: 10]
             },
             "boosterpoint" => %{
               adapter: TcgCheap.Catalogue.SealedRetailers.BoosterPoint,
               options: [per_page: 100, max_pages: 10]
             },
             "pokebooster" => %{
               adapter: TcgCheap.Catalogue.SealedRetailers.PokeBooster,
               options: [per_page: 100, max_pages: 10]
             }
           }
  end

  test "malformed and unknown arguments cancel" do
    assert {:cancel, :malformed_job_args} = Worker.perform(%Oban.Job{args: %{}})

    assert {:cancel, :malformed_job_args} =
             Worker.perform(%Oban.Job{args: %{"policy_version" => 1, "source_key" => "unknown"}})
  end

  test "the exact registry creates each canonical retailer and one child" do
    for source_key <- Map.keys(Application.fetch_env!(:tcg_cheap, :sealed_retailer_adapters)) do
      assert :ok = Worker.perform(job(source_key))
      assert {:ok, retailer} = Core.find_retailer_by_source_key(source_key, authorize?: false)
      assert retailer.slug == source_key
      assert retailer.category == Worker.sources()[source_key].category
      assert [%{worker: worker, args: args}] = child_jobs(source_key)
      assert worker == inspect(SealedRetailerWorker, structs: false)
      assert args == %{"retailer_id" => retailer.id, "source_key" => source_key}
    end
  end

  test "a malformed selected provider configuration cancels without details" do
    previous = Application.fetch_env!(:tcg_cheap, :sealed_retailer_adapters)

    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{
      "lootquest" => %{adapter: String}
    })

    assert {:cancel, :invalid_provider_configuration} = Worker.perform(job("lootquest"))
    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, previous)
  end

  test "disabled and mismatched persisted retailers fail closed without a child" do
    disabled =
      Core.register_retailer!(%{
        slug: "disabled-#{System.unique_integer([:positive])}",
        source_key: "lootquest",
        name: "LootQuest",
        category: "regular_retailer",
        homepage_url: "https://lootquest.pl"
      })

    Core.disable_retailer!(disabled)
    assert {:cancel, :retailer_disabled} = Worker.perform(job("lootquest"))
    assert child_jobs("lootquest") == []

    mismatch =
      Core.register_retailer!(%{
        slug: "mismatch-#{System.unique_integer([:positive])}",
        source_key: "cardzhouse",
        name: "CardzHouse",
        category: "regular_retailer",
        homepage_url: "https://cardzhouse.pl"
      })

    assert {:cancel, :retailer_identity_mismatch} = Worker.perform(job("cardzhouse"))
    assert mismatch.status == "active"
    assert child_jobs("cardzhouse") == []
  end

  test "active-only uniqueness permits a completed weekly bootstrap" do
    assert %{changes: %{unique: %{states: states}}} = Worker.new(job("lootquest").args)
    assert states == [:available, :scheduled, :executing, :retryable, :suspended]
  end

  test "keeps all seven provider budgets and global limits" do
    budget = Application.fetch_env!(:tcg_cheap, :acquisition_budget)
    providers = Keyword.fetch!(budget, :providers)

    assert Keyword.get(budget, :global_hourly_request_limit) == 100
    assert Keyword.get(budget, :global_daily_request_limit) == 1_000
    assert Keyword.get(budget, :global_monthly_spend_limit) == "50.00"

    assert Enum.map(providers, &Keyword.fetch!(&1, :provider_key)) == [
             "tcgdex_catalogue",
             "tcgdex_cardmarket",
             "nbp",
             "sealed_retailer:lootquest",
             "sealed_retailer:cardzhouse",
             "sealed_retailer:boosterpoint",
             "sealed_retailer:pokebooster"
           ]
  end

  defp job(source_key), do: %Oban.Job{args: %{"policy_version" => 1, "source_key" => source_key}}

  defp child_jobs(source_key) do
    all_enqueued(repo: TcgCheap.Repo, worker: SealedRetailerWorker)
    |> Enum.filter(fn %{args: args} -> args["source_key"] == source_key end)
  end
end
