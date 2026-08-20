defmodule TcgCheap.Catalogue.CuratedPlayableBootstrapWorker do
  @moduledoc """
  Queues the fixed curated playable manifest while its evidence is valid.

  Outside the validity window this intentionally produces no children. Replace or
  remove this worker and its Cron entry when a new approved manifest supersedes it.
  """

  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:evidence_version],
      states: [:available, :scheduled, :executing, :retryable, :suspended, :completed],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{CuratedPlayableCollectionWorker, CuratedPlayablePolicy}

  def timeout(_), do: :timer.seconds(120)
  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  def enqueue do
    new(%{"evidence_version" => CuratedPlayablePolicy.evidence_version()}) |> Oban.insert()
  end

  def plan(as_of) do
    if CuratedPlayablePolicy.valid_on?(as_of),
      do:
        Enum.map(
          CuratedPlayablePolicy.entries(),
          &%{
            "evidence_version" => CuratedPlayablePolicy.evidence_version(),
            "tcgdex_id" => &1.tcgdex_id
          }
        ),
      else: []
  end

  def perform(%Oban.Job{} = job), do: perform_on(job, Date.utc_today())

  def perform_on(%Oban.Job{args: %{"evidence_version" => version}} = job, as_of)
      when map_size(job.args) == 1 and version == "2026-08-19-naic" do
    Enum.reduce_while(plan(as_of), :ok, fn args, :ok ->
      case CuratedPlayableCollectionWorker.new(args, priority: 1) |> Oban.insert() do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :persistence_failed}}
      end
    end)
  end

  def perform_on(%Oban.Job{}, _as_of), do: {:cancel, :malformed_job_args}
end
