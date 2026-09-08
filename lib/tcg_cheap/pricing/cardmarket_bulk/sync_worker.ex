defmodule TcgCheap.Pricing.CardmarketBulk.SyncWorker do
  @moduledoc "Oban worker for acquiring and materializing Cardmarket bulk data."

  use Oban.Worker,
    queue: :cardmarket_bulk,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.CardmarketCrosswalk
  alias TcgCheap.Operations.AcquisitionBudget
  alias TcgCheap.Operations.AcquisitionTracker
  alias TcgCheap.Pricing.CardmarketBulk.{MappingNotifications, Materializer, Sync}

  @doc "The intended maximum runtime for a bulk attempt, in milliseconds."
  def timeout, do: :timer.minutes(15)
  def timeout(_job), do: timeout()

  @impl true
  def perform(%Oban.Job{args: args} = job) when is_map(args) and map_size(args) == 0 do
    case config() do
      {:ok, config} ->
        job
        |> run_acquisition(config)
        |> classify_result()

      {:error, reason} ->
        classify(reason)
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp config do
    case Application.fetch_env(:tcg_cheap, :cardmarket_bulk) do
      {:ok, value} when is_list(value) ->
        case valid_config?(value) do
          true -> {:ok, value}
          false -> {:error, :invalid_configuration}
        end

      _ ->
        {:error, :invalid_configuration}
    end
  end

  defp run_acquisition(job, config) do
    AcquisitionTracker.run(job, acquisition_metadata(), fn admit ->
      run_sync(config, admit, job.attempt)
    end)
  after
  end

  defp acquisition_metadata do
    [
      provider_key: "cardmarket_bulk",
      operation: "cardmarket_bulk_sync",
      target_key: "pokemon_singles_daily"
    ]
  end

  defp run_sync(config, admit, attempt) do
    config
    |> sync_options(admit)
    |> Keyword.put(:after_stage, fn batch ->
      with {:ok, _} <- CardmarketCrosswalk.run(batch),
           {:ok, _} <- Materializer.run(batch),
           do: :ok
    end)
    |> Sync.run()
    |> notify_persisted_batch(attempt)
  end

  defp notify_persisted_batch({:ok, %{batch: %{id: batch_id}, persisted?: true}}, _attempt) do
    case MappingNotifications.notify_batch(batch_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp notify_persisted_batch({:ok, %{batch: %{id: batch_id}, persisted?: false}}, attempt)
       when attempt > 1 do
    case MappingNotifications.notify_batch(batch_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp notify_persisted_batch({:ok, %{persisted?: false}}, _attempt), do: :ok
  defp notify_persisted_batch(other, _attempt), do: other

  defp sync_options(config, admit) do
    [
      adapter: config[:adapter],
      adapter_options: Keyword.get(config, :adapter_options, []),
      request_admitter: admit,
      deadline: System.monotonic_time(:millisecond) + timeout()
    ]
  end

  defp classify_result(:ok), do: :ok

  defp classify_result({:snooze, seconds}) when is_integer(seconds) and seconds > 0,
    do: {:snooze, seconds}

  defp classify_result({:error, reason}), do: classify(reason)
  defp classify_result(result), do: classify(result)

  defp valid_config?(value) do
    Keyword.keyword?(value) and valid_config_keys?(value) and valid_adapter_config?(value)
  end

  defp valid_config_keys?(value),
    do: Enum.sort(Keyword.keys(value)) == [:adapter, :adapter_options]

  defp valid_adapter_config?(value) do
    adapter = Keyword.get(value, :adapter)
    adapter_options = Keyword.get(value, :adapter_options, [])

    valid_adapter?(adapter) and valid_adapter_options?(adapter_options)
  end

  defp valid_adapter?(adapter) when is_atom(adapter) do
    Code.ensure_loaded?(adapter) and
      function_exported?(adapter, :fetch_products, 1) and
      function_exported?(adapter, :fetch_prices, 1)
  end

  defp valid_adapter?(_), do: false

  defp valid_adapter_options?(options) do
    Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in [:request_options]))
  end

  defp classify({:timeout, _} = r), do: {:error, r}
  defp classify({:acquisition_budget_rejected, _reason} = r), do: budget_classification(r)
  defp classify({:acquisition_budget_rejected, _reason, _reset} = r), do: budget_classification(r)
  defp classify(:timeout), do: {:error, :timeout}
  defp classify({:transport_error, _} = r), do: {:error, r}
  defp classify(:transport_error), do: {:error, :transport_error}
  defp classify({:http_error, :rate_limited} = r), do: {:error, r}
  defp classify({:http_error, status} = r) when status in [408, 429], do: {:error, r}

  defp classify({:http_error, {:unexpected_status, status}} = r) when status in [408, 429],
    do: {:error, r}

  defp classify({:http_error, {:unexpected_status, status}} = r) when status >= 500,
    do: {:error, r}

  defp classify({:identity_mismatch, _, _} = r), do: {:cancel, r}
  defp classify({:malformed, _} = r), do: {:cancel, r}
  defp classify(:invalid_configuration), do: {:cancel, :invalid_configuration}
  defp classify({:persistence, _} = r), do: {:error, r}
  defp classify({:mapping_notification_failed, _} = r), do: {:error, r}
  defp classify(r), do: {:cancel, r}

  defp budget_classification(reason) do
    with disposition when disposition in [:hourly, :daily, :monthly] <-
           AcquisitionBudget.budget_reason_disposition(reason),
         {:acquisition_budget_rejected, _reason, reset_at} <- reason,
         {:ok, seconds} <-
           AcquisitionBudget.remaining_budget_window_delay(reset_at, DateTime.utc_now()) do
      {:snooze, seconds}
    else
      _ -> {:cancel, :acquisition_budget_rejected}
    end
  rescue
    _ -> {:cancel, :acquisition_budget_rejected}
  end
end
