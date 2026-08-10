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
  alias TcgCheap.Operations.AcquisitionTracker
  alias TcgCheap.Operations.ImportIssues

  @malformed_issue_reasons [
    :malformed_provider_result,
    :malformed_batch,
    :malformed_listing,
    :duplicate_source_listing_id,
    :malformed_json,
    :malformed_shape,
    :malformed_pagination,
    :malformed_price,
    :invalid_pagination,
    :invalid_url,
    :response_too_large
  ]
  @listing_validation_reasons [:malformed_batch, :malformed_listing, :duplicate_source_listing_id]

  @impl true
  def perform(%Oban.Job{args: args} = job) when is_map(args) do
    with {:ok, retailer_id, source_key} <- validate_args(args),
         result <-
           AcquisitionTracker.run(
             job,
             tracker_options(retailer_id, source_key),
             &execute(retailer_id, source_key, &1)
           ) do
      result
    else
      {:cancel, reason} -> {:cancel, reason}
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
    with {:ok, canonical_id} <- Ecto.UUID.cast(id),
         true <- byte_size(key) in 1..144 and key == String.trim(key) do
      {:ok, canonical_id, key}
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

  defp classify({:error, {:http_error, %{status: status}}}) when status in 400..499,
    do: {:cancel, {:http_error, status}}

  defp classify({:error, :persistence_failed}), do: {:retry, :persistence_failed}
  defp classify({:error, :budget_persistence_failed}), do: {:retry, :budget_persistence_failed}
  defp classify({:error, :retailer_lookup_failed}), do: {:retry, :retailer_lookup_failed}
  defp classify({:error, :pagination_changed}), do: {:retry, :pagination_changed}

  defp classify({:error, {:acquisition_budget_rejected, reason}}) when is_atom(reason),
    do: {:cancel, {:acquisition_budget_rejected, reason}}

  defp classify({:error, {:acquisition_budget_rejected, _reason}}),
    do: {:cancel, :acquisition_budget_rejected}

  defp classify({:error, {reason, _detail}}) when reason in @malformed_issue_reasons,
    do: {:cancel, reason}

  defp classify({:error, reason}) when is_atom(reason), do: {:cancel, reason}
  defp classify({:error, _reason}), do: {:cancel, :provider_failure}

  defp classify_error(reason) do
    case classify({:error, reason}) do
      {:retry, value} -> {:error, value}
      {:cancel, value} -> {:cancel, value}
    end
  end

  defp execute(retailer_id, source_key, request_admitter) do
    with {:ok, _retailer} <- SealedRetailerRefresh.canonical_retailer(retailer_id, source_key),
         {:ok, adapter, options} <- SealedRetailerAcquisition.config(source_key),
         {:ok, _result} <-
           SealedRetailerRefresh.refresh(
             retailer_id,
             source_key,
             adapter,
             Keyword.put(options, :request_admitter, request_admitter)
           ) do
      :ok
    else
      {:error, reason} ->
        _ =
          ImportIssues.record(
            diagnostic_provider_key(source_key),
            "sealed_retailer_refresh",
            failure_stage(reason),
            "retailer",
            retailer_id,
            reason
          )

        classify_error(reason)
    end
  end

  defp failure_stage(reason) when reason in @listing_validation_reasons,
    do: "listing_validation"

  defp failure_stage(:persistence_invalid), do: "listing_import"
  defp failure_stage(:persistence_failed), do: "listing_import"

  defp failure_stage({reason, _}) when reason in @listing_validation_reasons,
    do: "listing_validation"

  defp failure_stage(_), do: "retailer_fetch"

  defp diagnostic_provider_key(source_key) do
    suffix =
      if Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,143}\z/, source_key),
        do: source_key,
        else: "other"

    "sealed_retailer:" <> suffix
  end

  defp tracker_options(retailer_id, source_key),
    do: [
      provider_key: "sealed_retailer:" <> source_key,
      operation: "sealed_retailer_refresh",
      target_key: retailer_id
    ]
end
