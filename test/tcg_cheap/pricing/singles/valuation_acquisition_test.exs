defmodule TcgCheap.Pricing.Singles.ValuationAcquisitionTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{ValuationAcquisition, ValuationWorker}

  test "fresh results never call the public admitter" do
    card = card("fresh")
    Core.record_single_valuation!(snapshot(card, DateTime.utc_now()))
    agent = Agent.start_link(fn -> 0 end) |> elem(1)

    assert {:fresh, _} =
             ValuationAcquisition.enqueue_if_stale(card,
               request_admitter: fn ->
                 Agent.update(agent, &(&1 + 1))
                 :ok
               end
             )

    assert Agent.get(agent, & &1) == 0
  end

  test "bulk requests admit each stale card independently and retain partial results" do
    first = card("bulk-a")
    second = card("bulk-b")
    {:ok, admissions} = Agent.start_link(fn -> 0 end)

    callback = fn ->
      Agent.get_and_update(admissions, fn count ->
        result =
          if count == 0,
            do: :ok,
            else: {:error, {:public_acquisition_rate_limited, 60}}

        {result, count + 1}
      end)
    end

    assert {:ok, results} =
             ValuationAcquisition.subscribe_and_request_many([first, second],
               request_admitter: callback
             )

    assert {:enqueued, _} = results[first.tcgdex_id]
    assert {:error, {:public_acquisition_rate_limited, 60}} = results[second.tcgdex_id]
    assert Agent.get(admissions, & &1) == 2
    assert length(all_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)) == 1
  end

  test "malformed and raising admitters fail closed" do
    card = card("admitter")

    assert {:error, :request_admitter_required} =
             ValuationAcquisition.enqueue_if_stale(card)

    assert {:error, :invalid_options} =
             ValuationAcquisition.enqueue_if_stale(card, request_admitter: :bad)

    assert {:error, :request_admission_failed} =
             ValuationAcquisition.enqueue_if_stale(card, request_admitter: fn -> raise "boom" end)

    assert {:error, :invalid_clock} = ValuationAcquisition.enqueue_if_stale(card, clock: :bad)
    refute_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)
  end

  defp card(label),
    do:
      Core.import_card_printing!(%{
        tcgdex_id: "acq-#{label}-#{System.unique_integer([:positive])}",
        name: label,
        set_name: "set",
        collector_number: "1"
      })

  defp snapshot(card, fetched_at),
    do: %{
      card_printing_id: card.id,
      value_eur: Decimal.new("1.00"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "test",
      source_metric: "avg7",
      fetched_at: fetched_at
    }
end
