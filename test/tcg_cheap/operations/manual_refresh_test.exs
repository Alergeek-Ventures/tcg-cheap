defmodule TcgCheap.Operations.ManualRefreshTestAdapter do
  def source_key, do: "manual-refresh-stub"
  def fetch_listings(_retailer, _options), do: {:ok, []}
end

defmodule TcgCheap.Operations.ManualRefreshTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.{CatalogueSyncWorker, SealedRetailerWorker}
  alias TcgCheap.Core
  alias TcgCheap.Operations
  alias TcgCheap.Operations.{AcquisitionBudget, ImportIssues, ManualRefresh, Overview}
  alias TcgCheap.Pricing.ExchangeRateWorker
  alias TcgCheap.Pricing.Singles.ValuationWorker

  setup do
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_adapters = Application.get_env(:tcg_cheap, :sealed_retailer_adapters)
    previous_exchange = Application.get_env(:tcg_cheap, :exchange_rate_provider)
    previous_valuation = Application.get_env(:tcg_cheap, :valuation_provider)
    previous_catalogue = Application.get_env(:tcg_cheap, :catalogue_sync)

    Application.put_env(:tcg_cheap, :acquisition_budget, budget())
    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{})

    on_exit(fn ->
      restore(:acquisition_budget, previous_budget)
      restore(:sealed_retailer_adapters, previous_adapters)
      restore(:exchange_rate_provider, previous_exchange)
      restore(:valuation_provider, previous_valuation)
      restore(:catalogue_sync, previous_catalogue)
    end)

    admin = admin()
    %{admin: admin}
  end

  test "returns bounded secret-free target projections", %{admin: admin} do
    retailer = configure_retailer()

    assert {:ok, targets} = ManualRefresh.targets(admin)

    assert Enum.map(targets, & &1.kind) == [
             :catalogue_sync,
             :catalogue_repair,
             :exchange_rate,
             :single_valuation,
             :sealed_retailer
           ]

    assert Enum.find(targets, &(&1.kind == :catalogue_repair)).status == :empty

    retailer_target = Enum.find(targets, &(&1.kind == :sealed_retailer))
    assert retailer_target.retailer_id == retailer.id
    assert retailer_target.source_key == "manual-refresh-stub"

    projection = inspect(targets)
    refute projection =~ "source_payload"
    refute projection =~ "ManualRefreshTestAdapter"
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

  test "queues a valuation only for one exact local printing", %{admin: admin} do
    card = card()

    assert {:ok, %{status: :queued}} =
             ManualRefresh.enqueue(admin, {:single_valuation, card.tcgdex_id})

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{
        "local_card_id" => card.id,
        "tcgdex_id" => card.tcgdex_id,
        "policy_version" => "tcgdex_cardmarket_v1",
        "currency" => "EUR"
      }
    )

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:single_valuation, "missing-card"})

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:single_valuation, String.duplicate("x", 241)})

    assert length(all_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)) == 1
  end

  test "derives sealed source identity from the active local retailer", %{admin: admin} do
    retailer = configure_retailer()

    assert {:ok, %{status: :queued}} =
             ManualRefresh.enqueue(admin, {:sealed_retailer, retailer.id})

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SealedRetailerWorker,
      args: %{"retailer_id" => retailer.id, "source_key" => "manual-refresh-stub"}
    )

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:sealed_retailer, Ecto.UUID.generate()})
  end

  test "rejects disabled and malformed sealed targets", %{admin: admin} do
    retailer = configure_retailer()
    Core.disable_retailer!(retailer)

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:sealed_retailer, retailer.id})

    assert {:error, :invalid_target} =
             ManualRefresh.enqueue(admin, {:sealed_retailer, "not-a-uuid"})

    refute_enqueued(repo: TcgCheap.Repo, worker: SealedRetailerWorker)
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

    Application.put_env(:tcg_cheap, :acquisition_budget, budget([provider("tcgdex_cardmarket")]))

    assert {:ok, targets} = ManualRefresh.targets(admin)
    assert Enum.find(targets, &(&1.kind == :exchange_rate)).status == :unconfigured
    assert {:error, :unconfigured} = ManualRefresh.enqueue(admin, :exchange_rate)
  end

  test "malformed fixed or retailer configuration fails safely", %{admin: admin} do
    Application.put_env(:tcg_cheap, :exchange_rate_provider, [])
    assert {:ok, targets} = ManualRefresh.targets(admin)
    assert Enum.find(targets, &(&1.kind == :exchange_rate)).status == :unconfigured
    assert {:error, :unconfigured} = ManualRefresh.enqueue(admin, :exchange_rate)

    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{"bad" => %{}})
    assert {:error, :manual_refresh_unavailable} = ManualRefresh.targets(admin)
  end

  test "adapter target loading is capped and validates source-key bounds", %{admin: admin} do
    too_many =
      Map.new(1..101, fn index ->
        {"source-#{index}", %{adapter: TcgCheap.Operations.ManualRefreshTestAdapter, options: []}}
      end)

    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, too_many)
    assert {:error, :manual_refresh_unavailable} = ManualRefresh.targets(admin)

    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{
      String.duplicate("x", 145) => %{
        adapter: TcgCheap.Operations.ManualRefreshTestAdapter,
        options: []
      }
    })

    assert {:error, :manual_refresh_unavailable} = ManualRefresh.targets(admin)
  end

  defp configure_retailer do
    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{
      "manual-refresh-stub" => %{
        adapter: TcgCheap.Operations.ManualRefreshTestAdapter,
        options: []
      }
    })

    Application.put_env(
      :tcg_cheap,
      :acquisition_budget,
      budget([
        provider("nbp"),
        provider("tcgdex_catalogue"),
        provider("tcgdex_cardmarket"),
        provider("sealed_retailer:manual-refresh-stub")
      ])
    )

    Core.register_retailer!(%{
      slug: "manual-refresh-#{System.unique_integer([:positive])}",
      source_key: "manual-refresh-stub",
      name: "Manual Refresh Shop",
      category: "regular_retailer",
      homepage_url: "https://example.test/manual-refresh",
      source_payload: %{"secret" => "retailer-source-secret"}
    })
  end

  defp card do
    unique = System.unique_integer([:positive])

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: "manual-card-#{unique}",
      name: "Manual card #{unique}",
      set_name: "Manual set",
      collector_number: Integer.to_string(unique),
      mapping_status: "matched",
      cardmarket_product_id: unique
    })
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
           provider("nbp"),
           provider("tcgdex_cardmarket")
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
