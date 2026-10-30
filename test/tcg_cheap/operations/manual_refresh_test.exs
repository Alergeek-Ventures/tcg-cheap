defmodule TcgCheap.Operations.ManualRefreshTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Accounts

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, SinglesScopeBootstrapWorker}
  alias TcgCheap.Operations
  alias TcgCheap.Operations.{AcquisitionBudget, ImportIssues, ManualRefresh, Overview}
  alias TcgCheap.Pricing.ExchangeRateWorker

  setup do
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_exchange = Application.get_env(:tcg_cheap, :exchange_rate_provider)
    previous_catalogue = Application.get_env(:tcg_cheap, :catalogue_sync)

    Application.put_env(:tcg_cheap, :acquisition_budget, budget())

    on_exit(fn ->
      restore(:acquisition_budget, previous_budget)
      restore(:exchange_rate_provider, previous_exchange)
      restore(:catalogue_sync, previous_catalogue)
    end)

    admin = admin()
    %{admin: admin}
  end

  test "returns bounded secret-free target projections", %{admin: admin} do
    configure_providers()

    assert {:ok, targets} = ManualRefresh.targets(admin)

    assert Enum.map(targets, & &1.kind) == [
             :singles_collection,
             :catalogue_sync,
             :catalogue_repair,
             :exchange_rate
           ]

    assert Enum.find(targets, &(&1.kind == :catalogue_repair)).status == :empty

    projection = inspect(targets)
    refute projection =~ "options"
  end

  test "rejects missing and forged administrators without enqueueing", %{admin: admin} do
    forged = %{admin | id: Ecto.UUID.generate()}

    assert {:error, :invalid_actor} = ManualRefresh.targets(forged)
    assert {:error, :invalid_actor} = ManualRefresh.enqueue(forged, :exchange_rate)
    assert {:error, :invalid_actor} = ManualRefresh.enqueue(%{}, :exchange_rate)
    refute_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)
  end

  test "queues one fixed exchange job and projects an active duplicate", %{admin: admin} do
    assert {:ok, %{status: :queued, job_id: job_id}} =
             ManualRefresh.enqueue(admin, :exchange_rate)

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: ExchangeRateWorker,
      args: %{
        "source" => "nbp",
        "table" => "A",
        "base_currency" => "EUR",
        "quote_currency" => "PLN"
      }
    )

    assert {:ok, %{status: :already_queued, job_id: ^job_id}} =
             ManualRefresh.enqueue(admin, :exchange_rate)
  end

  test "queues or resumes only the fixed catalogue synchronization", %{admin: admin} do
    assert {:ok, %{status: :queued, job_id: job_id}} =
             ManualRefresh.enqueue(admin, :catalogue_sync)

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CatalogueSyncWorker,
      args: %{"scope" => "all_sets"}
    )

    assert {:ok, %{status: :already_queued, job_id: ^job_id}} =
             ManualRefresh.enqueue(admin, :catalogue_sync)

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:catalogue_sync, "caller-controlled"})
  end

  test "queues only the server-dated scoped Singles bootstrap", %{admin: admin} do
    assert {:ok, %{status: :queued, job_id: job_id}} =
             ManualRefresh.enqueue(admin, :singles_collection)

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SinglesScopeBootstrapWorker,
      args: %{"as_of" => Date.to_iso8601(Date.utc_today()), "policy_version" => 2}
    )

    assert {:ok, %{status: :already_queued, job_id: ^job_id}} =
             ManualRefresh.enqueue(admin, :singles_collection)

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:singles_collection, "caller-controlled"})
  end

  test "queues the failed-set scope without exposing set identifiers", %{admin: admin} do
    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_import",
               "set",
               "base1",
               :malformed_response
             )

    assert {:ok, targets} = ManualRefresh.targets(admin)
    repair = Enum.find(targets, &(&1.kind == :catalogue_repair))
    assert repair.failure_count == 1
    assert repair.status == :available
    refute Map.has_key?(repair, :set_ids)

    assert {:ok, %{status: :queued}} = ManualRefresh.enqueue(admin, :catalogue_repair)

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CatalogueSyncWorker,
      args: %{"scope" => "failed_sets"}
    )
  end

  test "failed-set repair closes safely when issues disappear", %{admin: admin} do
    assert {:error, :invalid_target} = ManualRefresh.enqueue(admin, :catalogue_repair)
    refute_enqueued(repo: TcgCheap.Repo, worker: CatalogueSyncWorker)
  end

  test "does not expose or enqueue retired TCGdex valuations", %{admin: admin} do
    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:single_valuation, "base1-4"})

    assert all_enqueued(repo: TcgCheap.Repo) == []
  end

  test "repair discovery overflow leaves unrelated targets available", %{admin: admin} do
    timestamp = ~U[2026-01-01 00:00:00.000000Z]

    rows =
      Enum.map(1..1001, fn index ->
        %{
          provider_key: "tcgdex_catalogue",
          operation: "card_catalogue_sync",
          stage: "set_fetch",
          target_type: "set",
          target_key: "manual-overflow-#{index}",
          issue_kind: "failed",
          issue_code: "timeout",
          first_seen_at: timestamp,
          last_seen_at: timestamp
        }
      end)

    assert {1001, nil} =
             TcgCheap.Repo.insert_all(TcgCheap.Operations.ImportIssue, rows, returning: false)

    assert {:ok, targets} = ManualRefresh.targets(admin)
    repair = Enum.find(targets, &(&1.kind == :catalogue_repair))
    exchange = Enum.find(targets, &(&1.kind == :exchange_rate))

    assert repair.status == :unavailable
    assert repair.failure_count == nil
    assert exchange.status == :available
  end

  test "disabled or absent budget providers cannot queue work", %{admin: admin} do
    assert {:ok, _admission} = AcquisitionBudget.admit("nbp")
    provider = Operations.get_provider_by_key!("nbp")

    assert {:ok, _disabled} =
             Overview.set_provider_status(admin, "nbp", "disabled", provider.updated_at)

    assert {:ok, targets} = ManualRefresh.targets(admin)
    assert Enum.find(targets, &(&1.kind == :exchange_rate)).status == :disabled
    assert {:error, :disabled} = ManualRefresh.enqueue(admin, :exchange_rate)
    refute_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)

    Application.put_env(:tcg_cheap, :acquisition_budget, budget([provider("tcgdex_catalogue")]))

    assert {:ok, targets} = ManualRefresh.targets(admin)
    assert Enum.find(targets, &(&1.kind == :exchange_rate)).status == :unconfigured
    assert {:error, :unconfigured} = ManualRefresh.enqueue(admin, :exchange_rate)
  end

  test "malformed fixed configuration fails safely", %{admin: admin} do
    Application.put_env(:tcg_cheap, :exchange_rate_provider, [])
    assert {:ok, targets} = ManualRefresh.targets(admin)
    assert Enum.find(targets, &(&1.kind == :exchange_rate)).status == :unconfigured
    assert {:error, :unconfigured} = ManualRefresh.enqueue(admin, :exchange_rate)
  end

  defp configure_providers do
    Application.put_env(
      :tcg_cheap,
      :acquisition_budget,
      budget([provider("nbp"), provider("tcgdex_catalogue")])
    )
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "manual-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp budget(
         providers \\ [
           provider("tcgdex_catalogue"),
           provider("nbp")
         ]
       ) do
    [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: providers
    ]
  end

  defp provider(key),
    do: [
      provider_key: key,
      display_name: key,
      estimated_cost_per_request: "0.00",
      hourly_request_limit: 10,
      daily_request_limit: 20,
      monthly_request_limit: 30,
      monthly_spend_limit: "0.00"
    ]

  defp restore(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
