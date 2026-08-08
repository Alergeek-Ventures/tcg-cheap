defmodule TcgCheap.Pricing.ExchangeRateWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Pricing.{ExchangeRateAcquisition, ExchangeRateProvider, ExchangeRateWorker}

  defmodule AdapterStub do
    def fetch(args, options) do
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

  setup do
    previous = Application.get_env(:tcg_cheap, :exchange_rate_provider)
    previous_stub = Application.get_env(:tcg_cheap, :exchange_rate_test_stub)
    {:ok, stub} = Agent.start(fn -> %{mode: :success, calls: 0} end)
    Application.put_env(:tcg_cheap, :exchange_rate_test_stub, stub)

    Application.put_env(:tcg_cheap, :exchange_rate_provider,
      adapter: AdapterStub,
      options: [clock: fn -> ~U[2026-08-08 12:00:00Z] end]
    )

    on_exit(fn ->
      Application.put_env(:tcg_cheap, :exchange_rate_provider, previous)
      Application.put_env(:tcg_cheap, :exchange_rate_test_stub, previous_stub)
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
    assert {:ok, rate} = Core.get_latest_exchange_rate(~D[2026-08-08])
    assert %Decimal{} = rate.rate
    assert_receive {:exchange_rate_completed, %{exchange_rate: event_rate}}, 500
    assert event_rate.id == rate.id
    assert Decimal.equal?(event_rate.rate, rate.rate)
  end

  test "malformed callbacks/results and invalid configuration cancel without persistence", %{
    stub: stub
  } do
    for mode <- [:malformed, :wrong_pair, :wrong_source, :zero, :nan, :future] do
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:cancel, _} = perform_job(job(), [])
      assert {:ok, nil} = Core.get_latest_exchange_rate(~D[2026-08-08])
    end

    for mode <- [:raise, :throw, :exit] do
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:error, :transport_error} = perform_job(job(), [])
    end

    Application.put_env(:tcg_cheap, :exchange_rate_provider, bad: true)
    assert {:cancel, :invalid_provider_configuration} = perform_job(job(), [])
    assert %{calls: 9} = Agent.get(stub, & &1)
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
  end

  test "permanent provider errors and invalid persistence are cancelled", %{stub: stub} do
    for reason <- [:no_published_rate, {:http_error, %{status: 404}}, :malformed_provider_result] do
      Agent.update(stub, &Map.put(&1, :mode, {:error, reason}))
      assert {:cancel, _} = perform_job(job(), [])
    end

    Agent.update(stub, &Map.put(&1, :mode, :invalid_persist))
    assert {:cancel, :malformed_provider_result} = perform_job(job(), [])
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
               clock: fn -> ~U[2026-08-08 12:00:00Z] end
             )

    assert enqueued_job.worker == "TcgCheap.Pricing.ExchangeRateWorker"
    assert enqueued_args == args()
  end

  test "missing observations enqueue a request" do
    assert {:enqueued, %Oban.Job{args: enqueued_args} = enqueued_job} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-01 12:00:00Z] end
             )

    assert enqueued_job.worker == "TcgCheap.Pricing.ExchangeRateWorker"
    assert enqueued_args == args()
  end

  test "subscribes before requesting and receives persisted completion", %{stub: stub} do
    assert {:enqueued, job} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> ~U[2026-08-08 12:00:00Z] end
             )

    job = %{
      job
      | attempted_at: ~U[2026-08-08 12:00:00Z],
        scheduled_at: ~U[2026-08-08 12:00:00Z]
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

    assert [{"0 15 * * *", ExchangeRateWorker, [args: args]}] = opts[:crontab]
    assert args == %{source: "nbp", table: "A", base_currency: "EUR", quote_currency: "PLN"}
  end
end
