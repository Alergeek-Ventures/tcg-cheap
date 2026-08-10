defmodule TcgCheap.Operations.AcquisitionReconcilerWorker do
  @moduledoc "Oban worker for periodic acquisition-run reconciliation."
  use Oban.Worker,
    queue: :operations,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable, :suspended]
    ]

  alias TcgCheap.Operations.AcquisitionReconciler

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) when is_map(args) and map_size(args) == 0 do
    case AcquisitionReconciler.run() do
      {:ok, _result} ->
        :ok

      {:error, :invalid_acquisition_health_configuration} ->
        {:cancel, :invalid_acquisition_health_configuration}

      {:error, :invalid_provider_configuration} ->
        {:cancel, :invalid_provider_configuration}

      {:error, :invalid_acquisition_reconciler_clock} ->
        {:cancel, :invalid_acquisition_reconciler_clock}

      {:error, reason} ->
        retry_or_fail(job, reason)
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp retry_or_fail(%Oban.Job{attempt: attempt, max_attempts: max}, reason) when attempt >= max,
    do: {:error, reason}

  defp retry_or_fail(_job, reason), do: {:error, reason}
end
