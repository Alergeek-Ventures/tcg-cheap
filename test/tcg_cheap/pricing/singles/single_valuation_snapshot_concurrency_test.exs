defmodule TcgCheap.Pricing.Singles.SingleValuationSnapshotConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot
  alias TcgCheap.Repo

  setup do
    card =
      Sandbox.unboxed_run(Repo, fn ->
        suffix = System.unique_integer([:positive])

        Core.create_card_printing!(%{
          tcgdex_id: "base1-concurrent-#{suffix}",
          name: "Charizard",
          set_name: "Base Set",
          collector_number: "4"
        })
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(
          from snapshot in SingleValuationSnapshot,
            where: snapshot.card_printing_id == ^card.id
        )

        Repo.delete_all(
          from card_printing in TcgCheap.Catalogue.CardPrinting,
            where: card_printing.id == ^card.id
        )
      end)
    end)

    {:ok, card: card}
  end

  test "concurrent recordings use independent transactions", %{card: card} do
    policy = "tcgdex_cardmarket_concurrent-#{System.unique_integer([:positive])}"
    parent = self()

    tasks =
      for value <- ["101.00", "202.00"] do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              Sandbox.unboxed_run(Repo, fn ->
                Core.record_single_valuation(
                  snapshot_attributes(card, %{
                    policy_version: policy,
                    value_eur: Decimal.new(value)
                  })
                )
              end)
          end
        end)
      end

    assert_receive {:ready, first_task}, 5_000
    assert_receive {:ready, second_task}, 5_000
    send(first_task, :go)
    send(second_task, :go)

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.all?(results, &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      history = Core.list_single_valuation_history!(card.id, policy)

      assert length(history) == 2
      assert Enum.count(history, & &1.current?) == 1
    end)
  end

  defp snapshot_attributes(card, overrides) do
    Map.merge(
      %{
        card_printing_id: card.id,
        value_eur: Decimal.new("411.69"),
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex_cardmarket",
        source_metric: "avg7",
        fetched_at: ~U[2026-08-07 12:00:00.000000Z]
      },
      overrides
    )
  end
end
