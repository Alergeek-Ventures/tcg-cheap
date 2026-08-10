defmodule TcgCheap.Pricing.ExchangeRateWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Pricing.{ExchangeRateAcquisition, ExchangeRateProvider, ExchangeRateWorker}

  defmodule AdapterStub do
    def fetch(args, options) do
      with :ok <- Keyword.fetch!(options, :request_admitter).(),
           do: fetch_admitted(args, options)
    end

    defp fetch_admitted(args, options) do
      pid = Application.fetch_env!(:tcg_cheap, :exchange_rate_test_stub)
      Agent.update(pid, fn state -> Map.update!(state, :calls, fn calls -> calls + 1 end) end)

      case Agent.get(pid, & &1.mode) do
        :raise -> raise "boom"
        :throw -> throw(:boom)
        :exit -> exit(:boom)
        :malformed -> :bad
        {:error, reason} -> {:error, reason}
        mode -> {:ok, result(args, options, mode)}
      end
    end

    defp result(_args, options, mode) do
      now = Keyword.get(options, :clock, fn -> ~U[2026-08-08 12:00:00Z] end).()

      result = %ExchangeRateProvider.Result{
        rate: Decimal.new("4.3010"),
        effective_date: ~D[2026-08-07],
        publication_number: "pub-#{System.unique_integer([:positive])}",
        fetched_at: now,
        source: "nbp",
        table: "A",
        base_currency: "EUR",
        quote_currency: "PLN"
      }

      case mode do
        :wrong_pair -> %{result | quote_currency: "USD"}
        :wrong_source -> %{result | source: "other"}
        :zero -> %{result | rate: Decimal.new(0)}
        :nan -> %{result | rate: Decimal.new("NaN")}
        :future -> %{result | effective_date: ~D[2026-08-09]}
        :invalid_persist -> %{result | publication_number: ""}
        _ -> result
      end
    end
  end

  defmodule BudgetStub do
    def admit(_provider_key), do: Application.fetch_env!(:tcg_cheap, :exchange_budget_stub_result)
  end

  setup do
    previous = Application.get_env(:tcg_cheap, :exchange_rate_provider)
    previous_stub = Application.get_env(:tcg_cheap, :exchange_rate_test_stub)
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_admitter = Application.get_env(:tcg_cheap, :acquisition_budget_admitter)
    previous_budget_result = Application.get_env(:tcg_cheap, :exchange_budget_stub_result)
    {:ok, stub} = Agent.start(fn -> %{mode: :success, calls: 0} end)
    Application.put_env(:tcg_cheap, :exchange_rate_test_stub, stub)

    Application.put_env(:tcg_cheap, :exchange_rate_provider,
      adapter: AdapterStub,
      options: [clock: fn -> ~U[2026-08-08 12:00:00Z] end]
    )

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

    on_exit(fn ->
      Application.put_env(:tcg_cheap, :exchange_rate_provider, previous)
      Application.put_env(:tcg_cheap, :exchange_rate_test_stub, previous_stub)
      restore_env(:acquisition_budget, previous_budget)
      restore_env(:acquisition_budget_admitter, previous_admitter)
      restore_env(:exchange_budget_stub_result, previous_budget_result)
      if Process.alive?(stub), do: Agent.stop(stub)
    end)

    %{stub: stub}
  end

  defp args,
    do: %{"source" => "nbp", "table" => "A", "base_currency" => "EUR", "quote_currency" => "PLN"}

  defp job(args \\ args(), attempt \\ 1, max_attempts \\ 5),
    do: %Oban.Job{
      args: args,
      worker: Atom.to_string(ExchangeRateWorker),
      queue: "exchange_rates",
      attempt: attempt,
      max_attempts: max_attempts,
      scheduled_at: ~U[2026-08-08 12:00:00Z],
      attempted_at: ~U[2026-08-08 12:00:00Z],
      inserted_at: ~U[2026-08-08 12:00:00Z]
    }

  test "enqueues one canonical unique job with exact args" do
    assert {:ok, first} = ExchangeRateAcquisition.enqueue()
    assert {:ok, second} = ExchangeRateAcquisition.enqueue()
    assert first.id == second.id
    assert first.queue == "exchange_rates"
    assert first.args == args()
  end

  test "performs once, persists a typed rate, and broadcasts completion", %{stub: stub} do
    assert :ok = Phoenix.PubSub.subscribe(TcgCheap.PubSub, ExchangeRateAcquisition.topic())

    assert :ok = perform_job(job(), [])
    assert %{calls: 1} = Agent.get(stub, & &1)
    assert usage_counts("nbp") == %{"day" => 1, "hour" => 1, "month" => 1}
    assert {:ok, rate} = Core.get_latest_exchange_rate(~D[2026-08-08])
    assert %Decimal{} = rate.rate
    run = latest_run("nbp")
    assert run.operation == "exchange_rate"
    assert run.target_key == "EUR/PLN"
    assert run.status == "succeeded"
    assert run.request_count == 1
    assert source_health("nbp").last_status == "succeeded"
    assert_receive {:exchange_rate_completed, %{exchange_rate: event_rate}}, 500
    assert event_rate.id == rate.id
    assert Decimal.equal?(event_rate.rate, rate.rate)
  end

  test "malformed callbacks/results and invalid configuration cancel without persistence", %{
    stub: stub
  } do
    assert {:cancel, :malformed_job_args} = perform_job(job(%{}), [])
    assert usage_counts("nbp") == %{}

    for mode <- [:malformed, :wrong_pair, :wrong_source, :zero, :nan, :future] do
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:cancel, _} = perform_job(job(), [])
      assert {:ok, nil} = Core.get_latest_exchange_rate(~D[2026-08-08])
    end

    for mode <- [:raise, :throw, :exit] do
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:error, :transport_error} = perform_job(job(), [])
    end

    before_invalid_config = usage_counts("nbp")
    Application.put_env(:tcg_cheap, :exchange_rate_provider, bad: true)
    assert {:cancel, :invalid_provider_configuration} = perform_job(job(), [])
    assert %{calls: 9} = Agent.get(stub, & &1)
    assert usage_counts("nbp") == before_invalid_config
  end

  test "transient failures retry and only final retry broadcasts failure", %{stub: stub} do
    assert :ok = Phoenix.PubSub.subscribe(TcgCheap.PubSub, ExchangeRateAcquisition.topic())

    for reason <- [
          {:http_error, %{status: 408}},
          {:http_error, %{status: 429}},
          {:http_error, %{status: 500}},
          :transport_error
        ] do
      Agent.update(stub, &Map.put(&1, :mode, {:error, reason}))
      assert {:error, _} = perform_job(job(args(), 1, 5), [])
      refute_receive {:exchange_rate_failed, _}, 20
    end

    assert {:error, _} = perform_job(job(args(), 5, 5), [])
    assert_receive {:exchange_rate_failed, _}, 500
    assert %{calls: 5} = Agent.get(stub, & &1)
    assert usage_counts("nbp") == %{"day" => 5, "hour" => 5, "month" => 5}
  end

  test "permanent provider errors and invalid persistence are cancelled", %{stub: stub} do
    for reason <- [:no_published_rate, {:http_error, %{status: 404}}, :malformed_provider_result] do
      Agent.update(stub, &Map.put(&1, :mode, {:error, reason}))
      assert {:cancel, _} = perform_job(job(), [])
    end

    Agent.update(stub, &Map.put(&1, :mode, :invalid_persist))
    assert {:cancel, :malformed_provider_result} = perform_job(job(), [])
  end

  test "a capped provider is rejected before the callback and broadcasts failure", %{stub: stub} do
    assert :ok = Phoenix.PubSub.subscribe(TcgCheap.PubSub, ExchangeRateAcquisition.topic())
    assert :ok = perform_job(job(), [])
    provider = TcgCheap.Operations.get_provider_by_key!("nbp")
    TcgCheap.Operations.disable_provider!(provider, provider.updated_at, authorize?: false)

    assert {:cancel, {:acquisition_budget_rejected, :provider_disabled}} =
             perform_job(job(), [])

    assert %{calls: 1} = Agent.get(stub, & &1)

    assert_receive {:exchange_rate_failed,
                    %{reason: {:acquisition_budget_rejected, :provider_disabled}}},
                   500
  end

  test "budget persistence failure retries without callback and broadcasts on final attempt", %{
    stub: stub
  } do
    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, BudgetStub)

    Application.put_env(
      :tcg_cheap,
      :exchange_budget_stub_result,
      {:error, :budget_persistence_failed}
    )

    assert :ok = Phoenix.PubSub.subscribe(TcgCheap.PubSub, ExchangeRateAcquisition.topic())

    assert {:error, :budget_persistence_failed} = perform_job(job(args(), 1, 5), [])
    assert %{calls: 0} = Agent.get(stub, & &1)
    refute_receive {:exchange_rate_failed, _}, 20
    assert {:error, :budget_persistence_failed} = perform_job(job(args(), 5, 5), [])
    assert_receive {:exchange_rate_failed, %{reason: :budget_persistence_failed}}, 500
    assert usage_counts("nbp") == %{}
  end

  test "malformed admission configuration fails closed without usage", %{stub: stub} do
    assert :ok = Phoenix.PubSub.subscribe(TcgCheap.PubSub, ExchangeRateAcquisition.topic())
    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, String)

    assert {:cancel, {:acquisition_budget_rejected, :invalid_admission_configuration}} =
             perform_job(job(), [])

    assert %{calls: 0} = Agent.get(stub, & &1)
    assert usage_counts("nbp") == %{}

    assert_receive {:exchange_rate_failed,
                    %{reason: {:acquisition_budget_rejected, :invalid_admission_configuration}}},
                   500
  end

  test "latest validates dates/options and acquisition enqueues only when stale" do
    assert {:error, :invalid_date} = ExchangeRateAcquisition.latest("2026-08-08")

    assert {:error, :invalid_clock} =
             ExchangeRateAcquisition.subscribe_and_request_latest(clock: :bad)

    assert {:error, :invalid_options} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-08 12:00:00Z] end,
               clock: fn -> ~U[2026-08-08 12:00:00Z] end
             )
  end

  test "fresh observations do not enqueue and stale observations do" do
    fresh = %{
      source: "nbp",
      table: "A",
      base_currency: "EUR",
      quote_currency: "PLN",
      rate: Decimal.new("4.3"),
      effective_date: ~D[2026-08-07],
      publication_number: "pub-#{System.unique_integer([:positive])}",
      fetched_at: ~U[2026-08-08 11:00:00Z]
    }

    assert {:ok, _} = Core.record_exchange_rate(fresh)

    assert {:fresh, _} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-08 12:00:00Z] end
             )

    old = %{fresh | fetched_at: ~U[2026-08-07 11:00:00Z]}
    assert {:ok, _} = Core.record_exchange_rate(old)

    assert {:enqueued, %Oban.Job{args: enqueued_args} = enqueued_job} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-08 12:00:00Z] end,
               request_admitter: fn -> :ok end
             )

    assert enqueued_job.worker == "TcgCheap.Pricing.ExchangeRateWorker"
    assert enqueued_args == args()
  end

  test "missing observations enqueue a request" do
    assert {:enqueued, %Oban.Job{args: enqueued_args} = enqueued_job} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-01 12:00:00Z] end,
               request_admitter: fn -> :ok end
             )

    assert enqueued_job.worker == "TcgCheap.Pricing.ExchangeRateWorker"
    assert enqueued_args == args()
  end

  test "subscribes before requesting and receives persisted completion", %{stub: stub} do
    assert {:enqueued, job} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-08 12:00:00Z] end,
               request_admitter: fn -> :ok end
             )

    job = %{
      job
      | attempted_at: ~U[2026-08-08 12:00:00Z],
        scheduled_at: ~U[2026-08-08 12:00:00Z],
        attempt: 1
    }

    assert :ok = perform_job(job, [])
    assert_receive {:exchange_rate_completed, %{exchange_rate: rate}}, 500
    assert rate.id
    assert {:ok, persisted} = Core.get_latest_exchange_rate(~D[2026-08-08])
    assert persisted.id == rate.id
    assert %{calls: 1} = Agent.get(stub, & &1)
  end

  test "cron configuration uses the canonical queue and arguments" do
    [{Oban.Plugins.Pruner, _}, {Oban.Plugins.Cron, opts}] =
      Application.fetch_env!(:tcg_cheap, Oban)[:plugins]

    assert {"0 15 * * *", ExchangeRateWorker, [args: args]} =
             Enum.find(opts[:crontab], fn {_schedule, worker, _options} ->
               worker == ExchangeRateWorker
             end)

    assert args == %{source: "nbp", table: "A", base_currency: "EUR", quote_currency: "PLN"}
  end

  defp budget_config(opts \\ []) do
    [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: "nbp",
          display_name: "Narodowy Bank Polski",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: Keyword.get(opts, :hourly, 100),
          daily_request_limit: 1_000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]
  end

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)

  defp usage_counts(provider_key) do
    TcgCheap.Repo.query!(
      "SELECT u.window_kind, u.request_count FROM acquisition_budget_usages u JOIN acquisition_data_providers p ON p.id = u.provider_id WHERE p.provider_key = $1",
      [provider_key]
    ).rows
    |> Enum.reduce(%{}, fn [kind, count], acc -> Map.update(acc, kind, count, &(&1 + count)) end)
  end

  defp latest_run(provider_key),
    do:
      TcgCheap.Operations.list_recent_acquisition_runs!([provider_key], 1, authorize?: false)
      |> hd()

  defp source_health(provider_key),
    do: TcgCheap.Operations.list_source_health!([provider_key], authorize?: false) |> hd()
end
