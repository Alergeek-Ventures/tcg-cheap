defmodule TcgCheap.Pricing.CardmarketBulk.SyncWorkerTestAdapter do
  alias TcgCheap.Pricing.CardmarketBulk.Adapter

  def fetch_products(opts), do: fetch(:products, opts)
  def fetch_prices(opts), do: fetch(:prices, opts)

  defp fetch(kind, opts) do
    admit = Keyword.fetch!(opts, :request_admitter)
    state = Application.fetch_env!(:tcg_cheap, :cardmarket_bulk_sync_test_state)

    case admit.() do
      :ok ->
        admitted_result(state, kind)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp admitted_result(state, kind) do
    Agent.get_and_update(state, fn %{outcomes: [outcome | rest]} = value ->
      {reply(outcome, kind), %{value | outcomes: [outcome | rest], calls: value.calls + 1}}
    end)
  end

  defp reply(outcome, kind) do
    outcome
    |> Map.fetch!(kind)
    |> wrap_result()
  end

  defp wrap_result({:error, _} = error), do: error
  defp wrap_result(result), do: {:ok, result}
end

defmodule TcgCheap.Pricing.CardmarketBulk.SyncWorkerTestBudget do
  def admit(_provider),
    do: Application.fetch_env!(:tcg_cheap, :cardmarket_bulk_sync_test_admissions) |> pop()

  defp pop(agent) do
    Agent.get_and_update(agent, fn [result | rest] -> {result, rest} end)
  end
end

defmodule TcgCheap.Pricing.CardmarketBulk.SyncWorkerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Operations
  alias TcgCheap.Pricing.CardmarketBulk.{Adapter, SyncWorker}
  alias TcgCheap.Pricing.Singles.ValuationAcquisition

  @provider "cardmarket_bulk"
  @now ~U[2026-09-03 10:00:00Z]

  test "timeout is fifteen minutes in milliseconds" do
    assert SyncWorker.timeout() == :timer.minutes(15)
    assert SyncWorker.timeout(%Oban.Job{}) == :timer.minutes(15)
  end

  setup do
    previous =
      for key <- [
            :cardmarket_bulk,
            :acquisition_budget,
            :acquisition_budget_admitter,
            :cardmarket_bulk_sync_test_state,
            :cardmarket_bulk_sync_test_admissions
          ],
          into: %{},
          do: {key, Application.get_env(:tcg_cheap, key)}

    {:ok, state} = Agent.start(fn -> %{outcomes: [outcome()], calls: 0} end)
    {:ok, admissions} = Agent.start(fn -> List.duplicate({:ok, %{}}, 10) end)
    Application.put_env(:tcg_cheap, :cardmarket_bulk_sync_test_state, state)
    Application.put_env(:tcg_cheap, :cardmarket_bulk_sync_test_admissions, admissions)

    Application.put_env(:tcg_cheap, :cardmarket_bulk,
      adapter: TcgCheap.Pricing.CardmarketBulk.SyncWorkerTestAdapter,
      adapter_options: []
    )

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

    Application.put_env(
      :tcg_cheap,
      :acquisition_budget_admitter,
      TcgCheap.Pricing.CardmarketBulk.SyncWorkerTestBudget
    )

    on_exit(fn ->
      Agent.stop(state)
      Agent.stop(admissions)
      Enum.each(previous, fn {key, value} -> restore(key, value) end)
    end)

    %{state: state, admissions: admissions}
  end

  test "valid empty args succeeds and records exactly two admitted requests", %{state: state} do
    assert :ok = SyncWorker.perform(job(%{}))
    assert %{calls: 2} = Agent.get(state, & &1)
    run = latest_run()
    assert run.provider_key == @provider
    assert run.operation == "cardmarket_bulk_sync"
    assert run.request_count == 2
    assert run.status == "succeeded"
  end

  test "malformed args cancel without provider work", %{state: state} do
    assert {:cancel, :malformed_job_args} = SyncWorker.perform(job(%{"scope" => "all"}))
    assert Agent.get(state, & &1.calls) == 0
    assert Operations.list_recent_acquisition_runs!([@provider], 1, authorize?: false) == []
  end

  test "missing and malformed config cancel before provider work", %{state: state} do
    Application.delete_env(:tcg_cheap, :cardmarket_bulk)
    assert {:cancel, :invalid_configuration} = SyncWorker.perform(job(%{}))
    Application.put_env(:tcg_cheap, :cardmarket_bulk, adapter: String, adapter_options: [])
    assert {:cancel, :invalid_configuration} = SyncWorker.perform(job(%{}))
    assert Agent.get(state, & &1.calls) == 0
  end

  test "transport, timeout, rate-limit, and server failures retry" do
    for reason <- [
          {:transport_error, :closed},
          {:timeout, :request},
          {:http_error, :rate_limited},
          {:http_error, {:unexpected_status, 503}}
        ] do
      set_outcome({:error, reason})
      assert {:error, ^reason} = SyncWorker.perform(job(%{}))
    end
  end

  test "malformed and identity-mismatched responses cancel" do
    set_outcome({:error, {:malformed, :invalid_json}})
    assert {:cancel, {:malformed, :invalid_json}} = SyncWorker.perform(job(%{}))

    set_outcome(%{products: valid_result([product(1)]), prices: valid_result([price(2)])})
    assert {:cancel, {:identity_mismatch, 1, 1, _}} = SyncWorker.perform(job(%{}))
  end

  test "stale source and persistence/configuration errors cancel" do
    assert :ok = SyncWorker.perform(job(%{}))

    set_outcome(%{
      products: valid_result([product(1)], ~U[2026-09-02 00:00:00Z]),
      prices: valid_result([price(1)], ~U[2026-09-02 00:00:00Z])
    })

    assert {:cancel, {:stale_source_batch, _}} = SyncWorker.perform(job(%{}))
  end

  test "hourly, daily, and monthly budget rejection snoozes without invoking adapter", %{
    state: state
  } do
    reset_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    for reason <- [:hourly_limit_reached, :daily_limit_reached, :monthly_request_limit_reached] do
      set_admissions({:error, {:acquisition_budget_rejected, reason, reset_at}})
      assert {:snooze, seconds} = SyncWorker.perform(job(%{}))
      assert is_integer(seconds) and seconds in 1..3601
      assert Agent.get(state, & &1.calls) == 0
    end
  end

  test "disabled and invalid budget configuration cancel without invoking adapter", %{
    state: state
  } do
    for reason <- [:provider_disabled, :invalid_provider_configuration] do
      set_admissions({:error, {:acquisition_budget_rejected, reason}})
      assert {:cancel, :acquisition_budget_rejected} = SyncWorker.perform(job(%{}))
      assert Agent.get(state, & &1.calls) == 0
    end
  end

  test "successful sync and materialization are recorded as success, not unknown failure" do
    assert :ok = SyncWorker.perform(job(%{}))
    run = latest_run()
    assert run.status == "succeeded"
    assert run.failure_category == nil
  end

  test "crosswalk runs before materialization for pending cards", %{state: state} do
    product_id = 10_000 + System.unique_integer([:positive])
    pending_product_id = product_id + 1
    set_id = "worker-set-#{System.unique_integer([:positive])}"

    set =
      Core.import_card_set!(
        %{tcgdex_id: set_id, name: set_id, series_id: set_id, series_name: set_id},
        authorize?: false
      )

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: "worker-anchor-#{System.unique_integer([:positive])}",
      name: "Anchor",
      set_name: set.name,
      collector_number: "1",
      card_set_id: set.id,
      mapping_status: "matched",
      cardmarket_product_id: product_id
    })

    pending =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "worker-pending-#{System.unique_integer([:positive])}",
        name: "Pending",
        set_name: set.name,
        collector_number: "2",
        card_set_id: set.id,
        mapping_status: "pending",
        details_synced_at: DateTime.utc_now()
      })

    set_outcome(%{
      products:
        valid_result([
          bulk_product(product_id, "Anchor"),
          bulk_product(pending_product_id, "Pending")
        ]),
      prices: valid_result([bulk_price(product_id), bulk_price(pending_product_id)])
    })

    card_id = pending.id
    assert :ok = ValuationAcquisition.subscribe(pending)

    assert :ok = SyncWorker.perform(job(%{}))
    assert %{calls: 2} = Agent.get(state, & &1)
    assert latest_run().request_count == 2
    assert_receive {:card_mapping_changed, %{card_printing_id: ^card_id}}

    assert {:ok, refreshed} =
             Core.get_card_printing_by_tcgdex_id(pending.tcgdex_id, authorize?: false)

    assert {refreshed.mapping_status, refreshed.cardmarket_product_id} ==
             {"matched", pending_product_id}

    assert {:ok, valuation} = Core.get_current_single_valuation(pending.id, "cardmarket_bulk_v1")
    assert valuation.cardmarket_product_id == pending_product_id

    assert :ok = SyncWorker.perform(job(%{}))
    refute_receive {:card_mapping_changed, %{card_printing_id: ^card_id}}

    assert :ok = SyncWorker.perform(job(%{}, 2))
    assert_receive {:card_mapping_changed, %{card_printing_id: ^card_id}}
  end

  defp job(args, attempt \\ 1),
    do: %Oban.Job{
      id: nil,
      attempt: attempt,
      max_attempts: 5,
      worker: Atom.to_string(SyncWorker),
      queue: "cardmarket_bulk",
      args: args
    }

  defp set_outcome({:error, reason}) do
    set_outcome(%{products: {:error, reason}, prices: {:error, reason}})
  end

  defp set_outcome(%{products: products, prices: prices}) do
    Application.put_env(:tcg_cheap, :cardmarket_bulk,
      adapter: TcgCheap.Pricing.CardmarketBulk.SyncWorkerTestAdapter,
      adapter_options: []
    )

    Agent.update(Application.fetch_env!(:tcg_cheap, :cardmarket_bulk_sync_test_state), fn s ->
      %{s | outcomes: [%{products: products, prices: prices}], calls: 0}
    end)
  end

  defp set_admissions(result) do
    Agent.update(
      Application.fetch_env!(:tcg_cheap, :cardmarket_bulk_sync_test_admissions),
      fn _ -> [result] end
    )
  end

  defp outcome, do: %{products: valid_result([product(1)]), prices: valid_result([price(1)])}

  defp valid_result(rows, created_at \\ @now) do
    %Adapter{
      raw_body: "{}",
      sha256: String.duplicate("a", 64),
      byte_size: 2,
      fetched_at: @now,
      created_at: created_at,
      total_rows: length(rows),
      source_rows: length(rows),
      priceable_count: length(rows),
      rows: rows
    }
  end

  defp product(id),
    do: %Adapter.Product{
      id_product: id,
      name: "Pikachu",
      category: "Pokémon Single",
      category_id: 51,
      id_expansion: 2,
      id_metacard: 3,
      date_added: "0000-00-00"
    }

  defp price(id),
    do: %Adapter.Price{
      id_product: id,
      category_id: 51,
      selected_metric: :avg7,
      selected_value: Decimal.new("1.00"),
      avg7: Decimal.new("1.00")
    }

  defp bulk_product(id, name),
    do: %Adapter.Product{
      id_product: id,
      name: name,
      category: "Pokémon Single",
      category_id: 51,
      id_expansion: 2,
      id_metacard: id,
      date_added: "2026-09-03"
    }

  defp bulk_price(id),
    do: %Adapter.Price{
      id_product: id,
      category_id: 51,
      selected_metric: :avg7,
      selected_value: Decimal.new("1.00"),
      avg7: Decimal.new("1.00")
    }

  defp latest_run,
    do: Operations.list_recent_acquisition_runs!([@provider], 1, authorize?: false) |> hd()

  defp budget_config do
    [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: @provider,
          display_name: "Cardmarket Bulk",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1000,
          monthly_request_limit: 1000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]
  end

  defp restore(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
