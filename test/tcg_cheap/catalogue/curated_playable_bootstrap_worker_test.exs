defmodule TcgCheap.Catalogue.CuratedPlayableBootstrapWorkerTest do
  use TcgCheap.DataCase, async: false
  import Oban.Testing
  import Ecto.Query

  alias TcgCheap.Catalogue.{
    CuratedPlayableBootstrapWorker,
    CuratedPlayableCollectionWorker,
    CuratedPlayablePolicy
  }

  test "plans no work outside the inclusive evidence window" do
    assert CuratedPlayableBootstrapWorker.plan(~D[2026-08-18]) == []
    assert length(CuratedPlayableBootstrapWorker.plan(~D[2026-08-19])) == 7
    assert length(CuratedPlayableBootstrapWorker.plan(~D[2026-11-17])) == 7
    assert CuratedPlayableBootstrapWorker.plan(~D[2026-11-18]) == []
  end

  test "enqueues exactly seven priority-one children" do
    assert :ok = CuratedPlayableBootstrapWorker.perform_on(job(), ~D[2026-08-19])
    jobs = all_enqueued(repo: TcgCheap.Repo, worker: CuratedPlayableCollectionWorker)
    assert length(jobs) == 7
    assert Enum.all?(jobs, &(&1.priority == 1))

    assert Enum.map(jobs, & &1.args) |> MapSet.new() ==
             CuratedPlayableBootstrapWorker.plan(~D[2026-08-19]) |> MapSet.new()
  end

  test "perform_on is closed before evidence and after expiry" do
    assert :ok = CuratedPlayableBootstrapWorker.perform_on(job(), ~D[2026-08-18])
    assert [] == all_enqueued(repo: TcgCheap.Repo, worker: CuratedPlayableCollectionWorker)
    assert :ok = CuratedPlayableBootstrapWorker.perform_on(job(), ~D[2026-11-18])
    assert [] == all_enqueued(repo: TcgCheap.Repo, worker: CuratedPlayableCollectionWorker)
  end

  test "malformed bootstrap args cancel and cron uses only the evidence version" do
    assert {:cancel, :malformed_job_args} =
             CuratedPlayableBootstrapWorker.perform(%Oban.Job{args: %{}})

    assert {:cancel, :malformed_job_args} =
             CuratedPlayableBootstrapWorker.perform(%Oban.Job{
               args: %{"evidence_version" => "wrong"}
             })

    assert {:cancel, :malformed_job_args} =
             CuratedPlayableBootstrapWorker.perform(%Oban.Job{
               args: %{"evidence_version" => "2026-08-19-naic", "extra" => true}
             })

    crontab =
      Application.fetch_env!(:tcg_cheap, Oban)
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
        _ -> nil
      end)

    assert {"*/15 * * * *", CuratedPlayableBootstrapWorker,
            [args: %{"evidence_version" => "2026-08-19-naic"}]} = Enum.at(crontab, 1)

    assert CuratedPlayablePolicy.evidence_version() == "2026-08-19-naic"
  end

  test "bootstrap uniqueness includes completed jobs" do
    first =
      Oban.insert!(CuratedPlayableBootstrapWorker.new(%{"evidence_version" => "2026-08-19-naic"}))

    {1, _} =
      TcgCheap.Repo.update_all(from(j in Oban.Job, where: j.id == ^first.id),
        set: [state: "completed", inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)]
      )

    assert %{state: "completed"} = TcgCheap.Repo.get!(Oban.Job, first.id)

    second =
      Oban.insert!(CuratedPlayableBootstrapWorker.new(%{"evidence_version" => "2026-08-19-naic"}))

    assert first.id == second.id
  end

  defp job(args \\ %{"evidence_version" => "2026-08-19-naic"}),
    do: %Oban.Job{
      args: args,
      attempt: 1,
      max_attempts: 5,
      worker: Atom.to_string(CuratedPlayableBootstrapWorker),
      queue: "catalogue_sync"
    }
end
