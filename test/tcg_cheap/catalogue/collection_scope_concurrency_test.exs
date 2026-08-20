defmodule TcgCheap.Catalogue.CollectionScopeConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Core
  alias TcgCheap.Repo

  test "independent transactions retain both concurrent scope additions" do
    {card, id} =
      Sandbox.unboxed_run(Repo, fn ->
        suffix = System.unique_integer([:positive])
        id = "scope-race-#{suffix}"

        card =
          TcgCheap.TestSupport.import_card_printing!(
            %{tcgdex_id: id, name: "Race", set_name: "Race", collector_number: "1"},
            scoped?: false
          )

        {card, id}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        dumped = Ecto.UUID.dump!(card.id)

        Repo.query!("DELETE FROM card_printing_mapping_decisions WHERE card_printing_id = $1", [
          dumped
        ])

        Repo.query!("DELETE FROM single_valuation_snapshots WHERE card_printing_id = $1", [dumped])

        Repo.query!("DELETE FROM card_printings WHERE tcgdex_id = $1", [id])
      end)
    end)

    parent = self()

    external_lock =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.query!(
              "SELECT id FROM card_printings WHERE id = $1 FOR UPDATE",
              [Ecto.UUID.dump!(card.id)]
            )

            send(parent, {:external_lock_ready, self()})

            receive do
              :release_external_lock -> :released
            end
          end)
        end)
      end)

    on_exit(fn ->
      if Process.alive?(external_lock.pid), do: send(external_lock.pid, :release_external_lock)
    end)

    assert_receive {:external_lock_ready, _}, 5_000

    tasks =
      [{["curated_playable"], ~D[2026-11-17]}, {["rolling_ir_sir"], ~D[2027-01-01]}]
      |> Enum.map(fn {scopes, expiry} ->
        task =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :go ->
                  card = Core.get_card_printing_by_tcgdex_id!(id)

                  result =
                    Core.add_card_printing_collection_scopes(
                      card,
                      scopes,
                      expiry,
                      ~U[2025-01-01 00:00:00Z],
                      authorize?: false
                    )

                  send(parent, {:added, self(), result})
                  result
              end
            end)
          end)

        task
      end)

    assert_receive {:ready, _}, 5_000
    assert_receive {:ready, _}, 5_000
    Enum.each(tasks, &send(&1.pid, :go))

    refute_receive {:added, _, _}, 250

    send(external_lock.pid, :release_external_lock)
    assert {:ok, :released} = Task.await(external_lock, 5_000)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.all?(results, &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      updated = Core.get_card_printing_by_tcgdex_id!(id)
      assert updated.collection_scopes == ["curated_playable", "rolling_ir_sir"]
      assert updated.collection_expires_on == ~D[2027-01-01]
    end)
  end
end
