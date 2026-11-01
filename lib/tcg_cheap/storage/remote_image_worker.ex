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

  def perform(%Oban.Job{args: args}) do
    {cursor, count} =
      RemoteImageMirror.register_batch(Map.get(args, "cursor", ["", ""]), @register_batch)

    mirrored = RemoteImageMirror.run(@mirror_batch)

    next =
      cond do
        count == @register_batch -> %{"cursor" => cursor}
        mirrored == @mirror_batch -> %{"registered" => true}
        true -> nil
      end

    if next do
      case next |> new() |> Oban.insert() do
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
