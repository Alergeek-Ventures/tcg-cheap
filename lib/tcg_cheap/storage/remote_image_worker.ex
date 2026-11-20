defmodule TcgCheap.Storage.RemoteImageWorker do
  @moduledoc "Backfills and refreshes known TCGdex images without fetching during requests."
  use Oban.Worker,
    queue: :media,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  alias TcgCheap.Storage.RemoteImageMirror

  @register_batch 500
  @mirror_batch 40

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"registered" => true}}) do
    if RemoteImageMirror.run(@mirror_batch) == @mirror_batch, do: {:snooze, 1}, else: :ok
  end

  def perform(%Oban.Job{}) do
    RemoteImageMirror.register_all(@register_batch)

    if RemoteImageMirror.run(@mirror_batch) == @mirror_batch do
      case %{"registered" => true} |> new() |> Oban.insert() do
        {:ok, _job} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @doc "Starts a complete bounded scan and mirror run (also scheduled by cron)."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> new() |> Oban.insert()
end
