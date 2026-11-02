defmodule TcgCheap.Sealed.PhotoMirrorWorker do
  @moduledoc "Oban job that copies new or changed product photos into our storage (`TcgCheap.Sealed.PhotoMirror`)."

  use Oban.Worker,
    queue: :media,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  require Logger

  alias TcgCheap.Sealed.PhotoMirror

  # Small batches: every photo is downloaded, resized and uploaded.
  @batch 40

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    %{stored: stored, failed: failed} = PhotoMirror.run(@batch)
    if stored + failed > 0, do: Logger.info("Product photos: #{stored} stored, #{failed} failed")

    # Photos stored before the small variant existed, while no new ones wait.
    %{added: added, failed: small_failed} =
      if stored + failed < @batch,
        do: PhotoMirror.add_small_variants(@batch),
        else: %{added: 0, failed: 0}

    if added + small_failed > 0,
      do: Logger.info("Small product photos: #{added} added, #{small_failed} failed")

    if stored + failed == @batch or (added > 0 and added + small_failed == @batch),
      do: {:snooze, 1},
      else: :ok
  end

  @doc "Queues a run."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> new() |> Oban.insert()
end
