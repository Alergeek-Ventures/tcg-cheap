defmodule TcgCheap.Catalogue.CatalogueSyncWorker do
  @moduledoc "Resumable, budget-aware Oban worker for the TCGdex set and card-brief catalogue."

  use Oban.Worker,
    queue: :catalogue_sync,
    priority: 9,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:scope],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.Sync
  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionTracker

  @args %{"scope" => "all_sets"}
  @max_batch_size 20
  @min_batch_delay_seconds 900
  @max_delay_seconds 86_400

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(360)

  @impl Oban.Worker
  def backoff(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}})
      when reason in [:acquisition_budget_rejected, :budget_persistence_failed] do
    case provider_config() do
      {:ok, config} -> config.budget_backoff_seconds
      {:error, _reason} -> 3_600
    end
  end

  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  @impl Oban.Worker
  def perform(%Oban.Job{args: @args} = job) do
    case provider_config() do
      {:ok, config} ->
        AcquisitionTracker.run(
          job,
          tracker_options(),
          &execute(config, &1)
        )

      {:error, :invalid_provider_configuration} ->
        {:cancel, :invalid_provider_configuration}
    end
  end

  def perform(_job), do: {:cancel, :malformed_job_args}

  @doc "Queues or reuses the one canonical full-catalogue synchronization job."
  def enqueue do
    case provider_config() do
      {:ok, _config} ->
        @args
        |> new()
        |> Oban.insert()

      {:error, :invalid_provider_configuration} = error ->
        error
    end
  end

  @doc false
  def provider_config do
    config = Application.get_env(:tcg_cheap, :catalogue_sync, [])

    with true <- is_list(config) and Keyword.keyword?(config),
         true <- unique_keys?(config),
         [
           :batch_delay_seconds,
           :batch_size,
           :budget_backoff_seconds,
           :provider,
           :provider_options
         ] <- Enum.sort(Keyword.keys(config)),
         provider when is_atom(provider) <- Keyword.fetch!(config, :provider),
         true <- valid_provider?(provider),
         options when is_list(options) <- Keyword.fetch!(config, :provider_options),
         true <-
           Keyword.keyword?(options) and unique_keys?(options) and
             not Keyword.has_key?(options, :request_admitter),
         batch_size when batch_size in 1..@max_batch_size <- Keyword.fetch!(config, :batch_size),
         batch_delay when batch_delay in @min_batch_delay_seconds..@max_delay_seconds <-
           Keyword.fetch!(config, :batch_delay_seconds),
         budget_backoff when budget_backoff in 60..@max_delay_seconds <-
           Keyword.fetch!(config, :budget_backoff_seconds) do
      {:ok,
       %{
         provider: provider,
         provider_options: options,
         batch_size: batch_size,
         batch_delay_seconds: batch_delay,
         budget_backoff_seconds: budget_backoff
       }}
    else
      _ -> {:error, :invalid_provider_configuration}
    end
  rescue
    _ -> {:error, :invalid_provider_configuration}
  end

  defp execute(config, request_admitter) do
    case active_or_start(config, request_admitter) do
      {:ok, run} -> process_batch(run, config, request_admitter)
      {:error, reason} -> safe_failure(reason)
    end
  end

  defp active_or_start(config, request_admitter) do
    case Operations.get_active_catalogue_sync_run(authorize?: false) do
      {:ok, nil} -> discover_and_start(config, request_admitter)
      {:ok, run} -> {:ok, run}
      {:error, _reason} -> {:error, :persistence_failed}
    end
  end

  defp discover_and_start(config, request_admitter) do
    case Sync.discover_set_ids(sync_options(config, request_admitter)) do
      {:ok, []} -> {:error, :invalid_provider_response}
      {:ok, set_ids} -> start_discovered_run(set_ids)
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_discovered_run(set_ids) do
    case Operations.start_catalogue_sync_run(set_ids, DateTime.utc_now(), authorize?: false) do
      {:ok, run} ->
        {:ok, run}

      {:error, _reason} ->
        case Operations.get_active_catalogue_sync_run(authorize?: false) do
          {:ok, run} when not is_nil(run) -> {:ok, run}
          _ -> {:error, :persistence_failed}
        end
    end
  end

  defp process_batch(run, config, request_admitter) do
    1..config.batch_size
    |> Enum.reduce_while({:ok, run}, fn _step, {:ok, current} ->
      if current.status == "completed" do
        {:halt, {:ok, current}}
      else
        process_current_set(current, config, request_admitter)
      end
    end)
    |> batch_result(config)
  end

  defp process_current_set(run, config, request_admitter) do
    set_id = Enum.at(run.set_ids, run.next_index)

    case Sync.sync_set(set_id, sync_options(config, request_admitter)) do
      {:ok, %{status: :excluded}} -> advance(run, set_id, "excluded")
      {:ok, _result} -> advance(run, set_id, "synced")
      {:error, reason} -> handle_set_failure(run, set_id, reason)
    end
  end

  defp handle_set_failure(run, set_id, reason) do
    if permanent_set_failure?(reason),
      do: advance(run, set_id, "failed"),
      else: {:halt, {:error, reason}}
  end

  defp advance(run, set_id, outcome) do
    completed_at =
      if run.next_index + 1 == length(run.set_ids), do: DateTime.utc_now(), else: nil

    case Operations.advance_catalogue_sync_run(
           run,
           run.next_index,
           set_id,
           outcome,
           completed_at,
           authorize?: false
         ) do
      {:ok, advanced} -> {:cont, {:ok, advanced}}
      {:error, _reason} -> {:halt, {:error, :persistence_failed}}
    end
  end

  defp batch_result({:error, reason}, _config), do: safe_failure(reason)

  defp batch_result({:ok, %{status: "running"}}, config),
    do: {:snooze, config.batch_delay_seconds}

  defp batch_result({:ok, %{status: "completed", failed_sets: 0}}, _config), do: :ok

  defp batch_result({:ok, %{status: "completed"}}, _config),
    do: {:cancel, :catalogue_sync_incomplete}

  defp safe_failure(:budget_persistence_failed), do: {:error, :budget_persistence_failed}
  defp safe_failure(reason), do: reason |> AcquisitionTracker.classify() |> safe_category()

  defp safe_category(:budget), do: {:error, :acquisition_budget_rejected}
  defp safe_category(:rate_limit), do: {:error, :provider_rate_limited}
  defp safe_category(:timeout), do: {:error, :provider_timeout}
  defp safe_category(:transport), do: {:error, :provider_transport_error}
  defp safe_category(:provider_response), do: {:error, :provider_response}
  defp safe_category(:persistence), do: {:error, :persistence_failed}
  defp safe_category(:configuration), do: {:cancel, :invalid_provider_configuration}
  defp safe_category(:local_input), do: {:cancel, :invalid_local_input}
  defp safe_category(:unknown), do: {:error, :unknown}

  defp permanent_set_failure?({:malformed_response, _reason}), do: true
  defp permanent_set_failure?({:card_set_conflict, _detail}), do: true

  defp permanent_set_failure?({:http_error, %{status: status}}),
    do: status in [404, 410]

  defp permanent_set_failure?({:http_error, status}),
    do: status in [404, 410]

  defp permanent_set_failure?(_reason), do: false

  defp sync_options(config, request_admitter),
    do: [
      provider: config.provider,
      provider_options: config.provider_options,
      request_admitter: request_admitter
    ]

  defp tracker_options,
    do: [
      provider_key: "tcgdex_catalogue",
      operation: "card_catalogue_sync",
      target_key: "all_sets"
    ]

  defp valid_provider?(provider),
    do:
      Code.ensure_loaded?(provider) and function_exported?(provider, :list_sets, 1) and
        function_exported?(provider, :fetch_set, 2)

  defp unique_keys?(keyword), do: length(keyword) == length(Enum.uniq(Keyword.keys(keyword)))
end
