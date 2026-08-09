defmodule TcgCheap.Pricing.ExchangeRateAcquisitionTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Pricing.{ExchangeRateAcquisition, ExchangeRateWorker}

  test "fresh rates never call the public admitter" do
    Core.record_exchange_rate!(rate(DateTime.utc_now()))
    agent = Agent.start_link(fn -> 0 end) |> elem(1)

    assert {:fresh, _} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> DateTime.utc_now() end,
               request_admitter: fn ->
                 Agent.update(agent, &(&1 + 1))
                 :ok
               end
             )

    assert Agent.get(agent, & &1) == 0
  end

  test "missing and stale rates reject before enqueue and preserve invalid clock semantics" do
    reject = fn -> {:error, {:public_acquisition_rate_limited, 12}} end
    now = DateTime.utc_now()

    assert {:error, :request_admitter_required} =
             ExchangeRateAcquisition.subscribe_and_request_latest(clock: fn -> now end)

    assert {:error, {:public_acquisition_rate_limited, 12}} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> now end,
               request_admitter: reject
             )

    Core.record_exchange_rate!(rate(DateTime.add(now, -1, :day)))

    assert {:error, {:public_acquisition_rate_limited, 12}} =
             ExchangeRateAcquisition.subscribe_and_request_latest(
               clock: fn -> now end,
               request_admitter: reject
             )

    assert {:error, :invalid_clock} =
             ExchangeRateAcquisition.subscribe_and_request_latest(clock: :bad)

    refute_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)
  end

  defp rate(fetched_at),
    do: %{
      source: "nbp",
      table: "A",
      base_currency: "EUR",
      quote_currency: "PLN",
      rate: Decimal.new("4.30"),
      effective_date: Date.utc_today(),
      publication_number: "acq-#{System.unique_integer([:positive])}",
      fetched_at: fetched_at
    }
end
