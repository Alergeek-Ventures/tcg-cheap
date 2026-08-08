defmodule TcgCheap.Catalogue.SealedRetailerWorker do
  @moduledoc "Oban worker for one explicitly configured sealed retailer refresh."

  use Oban.Worker,
    queue: :sealed_retailers,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:retailer_id, :source_key],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{SealedRetailerAcquisition, SealedRetailerRefresh}

  @impl true
  def perform(%Oban.Job{args: args}) when is_map(args) do
    with {:ok, retailer_id, source_key} <- validate_args(args),
         {:ok, _retailer} <- SealedRetailerRefresh.canonical_retailer(retailer_id, source_key),
         {:ok, adapter, options} <- SealedRetailerAcquisition.config(source_key),
         {:ok, _result} <-
           SealedRetailerRefresh.refresh(retailer_id, source_key, adapter, options) do
      :ok
    else
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> classify_error(reason)
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  @impl true
  def backoff(%Oban.Job{
        unsaved_error: %{reason: %Oban.PerformError{reason: {:rate_limited, seconds}}}
      })
      when seconds in 1..3_600,
      do: seconds

  def backoff(%Oban.Job{attempt: attempt}), do: min(30 * attempt * attempt, 3_600)

  @impl true
  def timeout(_job), do: :timer.seconds(360)

  defp validate_args(%{"retailer_id" => id, "source_key" => key} = args)
       when map_size(args) == 2 and is_binary(id) and is_binary(key) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         true <- key != "" and key == String.trim(key) do
      {:ok, id, key}
    else
      _ -> {:cancel, :malformed_job_args}
    end
  end

  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp classify({:error, :transport_error}), do: {:retry, :transport_error}
  defp classify({:error, {:transport_error, _}}), do: {:retry, :transport_error}
  defp classify({:error, :timeout}), do: {:retry, :timeout}
  defp classify({:error, {:timeout, _}}), do: {:retry, :timeout}
  defp classify({:error, :rate_limited}), do: {:retry, :rate_limited}

  defp classify({:error, {:rate_limited, %{retry_after_seconds: seconds}}})
       when seconds in 1..3_600,
       do: {:retry, {:rate_limited, seconds}}

  defp classify({:error, {:rate_limited, _}}), do: {:retry, :rate_limited}

  defp classify({:error, {:http_error, %{status: status}}})
       when status == 408 or status == 429 or (status >= 500 and status <= 599),
       do: {:retry, {:http_error, status}}

  defp classify({:error, :persistence_failed}), do: {:retry, :persistence_failed}
  defp classify({:error, :retailer_lookup_failed}), do: {:retry, :retailer_lookup_failed}
  defp classify({:error, :pagination_changed}), do: {:retry, :pagination_changed}

  defp classify({:error, reason}), do: {:cancel, reason}

  defp classify_error(reason) do
    case classify({:error, reason}) do
      {:retry, value} -> {:error, value}
      {:cancel, value} -> {:cancel, value}
    end
  end
end
