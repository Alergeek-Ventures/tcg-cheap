defmodule TcgCheap.Operations.CatalogueSyncRunTest do
  use TcgCheap.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Operations
  alias TcgCheap.Repo

  test "starts only with a canonical set list" do
    started_at = ~U[2026-08-10 12:00:00Z]

    assert {:ok, run} =
             Operations.start_catalogue_sync_run(["base1", "sv1"], started_at, authorize?: false)

    assert run.provider_key == "tcgdex_catalogue"
    assert run.set_ids == ["base1", "sv1"]
    assert run.next_index == 0
    assert run.status == "running"
    assert run.completed_at == nil

    assert {:error, _} =
             Operations.start_catalogue_sync_run(["sv1", "base1"], started_at, authorize?: false)
  end

  test "advances sequential outcomes and completes the final set" do
    {:ok, run} = start_run(["a", "b", "c"])
    completed_at = ~U[2026-08-10 12:03:00Z]

    {:ok, run} = advance(run, 0, "a", "synced", nil)
    assert {run.next_index, run.synced_sets, run.failed_sets, run.excluded_sets} == {1, 1, 0, 0}
    assert run.completed_at == nil

    {:ok, run} = advance(run, 1, "b", "failed", nil)
    {:ok, run} = advance(run, 2, "c", "excluded", completed_at)
    assert {run.next_index, run.synced_sets, run.failed_sets, run.excluded_sets} == {3, 1, 1, 1}
    assert run.status == "completed"
    assert DateTime.compare(run.completed_at, completed_at) == :eq
  end

  test "rejects stale indexes and wrong current IDs" do
    {:ok, run} = start_run(["a", "b"])
    assert {:error, _} = advance(run, 1, "a", "synced", nil)
    assert {:error, _} = advance(run, 0, "b", "synced", nil)
    assert {:error, _} = advance(run, 0, "a", "synced", ~U[2026-08-10 12:01:00Z])
  end

  test "rejects final completion before the run started" do
    {:ok, run} = start_run(["c"])

    assert {:error, _} =
             advance(run, 0, "c", "synced", ~U[2026-08-10 11:59:59Z])
  end

  test "rejects malformed set lists" do
    now = ~U[2026-08-10 12:00:00Z]

    for set_ids <- [["a", "a"], ["b", "a"], ["bad id"], ["-bad"]] do
      assert {:error, _} = Operations.start_catalogue_sync_run(set_ids, now, authorize?: false)
    end
  end

  test "database rejects null, unsorted, and duplicate set arrays" do
    query =
      "INSERT INTO catalogue_sync_runs (provider_key, set_ids, started_at) VALUES ('tcgdex_catalogue', $1, now())"

    for set_ids <- [["b", "a"], ["a", "a"], ["a", nil]] do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               Sandbox.unboxed_run(Repo, fn -> Repo.query(query, [set_ids]) end)
    end
  end

  test "concurrent advances at one index allow exactly one success" do
    {:ok, run} = Sandbox.unboxed_run(Repo, fn -> start_run(["a", "b"]) end)

    try do
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> Sandbox.unboxed_run(Repo, fn -> advance(run, 0, "a", "synced", nil) end)
            end
          end)
        end

      for _ <- tasks, do: assert_receive({:ready, _}, 5_000)
      Enum.each(tasks, &send(&1.pid, :go))
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1, inspect(results)
      assert Enum.count(results, &match?({:error, _}, &1)) == 1
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM catalogue_sync_runs WHERE id = $1", [Ecto.UUID.dump!(run.id)])
      end)
    end
  end

  test "operational mutations require an explicit authorization bypass" do
    assert {:error, _} =
             Operations.start_catalogue_sync_run(
               ["base1"],
               ~U[2026-08-10 12:00:00Z]
             )
  end

  defp start_run(set_ids) do
    Operations.start_catalogue_sync_run(set_ids, ~U[2026-08-10 12:00:00Z], authorize?: false)
  end

  defp advance(run, expected_index, set_id, outcome, completed_at) do
    Operations.advance_catalogue_sync_run(run, expected_index, set_id, outcome, completed_at,
      authorize?: false
    )
  end
end
