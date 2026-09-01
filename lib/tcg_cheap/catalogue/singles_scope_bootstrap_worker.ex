defmodule TcgCheap.Catalogue.SinglesScopeBootstrapWorker do
  @moduledoc "Bootstraps Singles jobs using configured sv/me ID candidates and fetched-series revalidation."
  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: 7 * 24 * 60 * 60,
      states: [:available, :scheduled, :executing, :retryable, :suspended, :completed],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, SinglesSetCollectionWorker, Tcgdex}
  alias TcgCheap.Operations.{AcquisitionBudget, AcquisitionTracker}

  @policy_version 2

  def timeout(_), do: :timer.seconds(120)

  @doc "Returns provider config plus sv/me policy used for candidate filtering and revalidation."
  def provider_config do
    with {:ok, provider} <- CatalogueSyncWorker.provider_config(),
         {:ok, singles} <- singles_config() do
      {:ok, %{provider: provider, singles: singles}}
    end
  end

  def backoff(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}})
      when reason in [:acquisition_budget_rejected, :budget_persistence_failed], do: 3_600

  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  def enqueue(as_of \\ Date.utc_today()) do
    with {:ok, date} <- valid_date(as_of),
         {:ok, _config} <- provider_config() do
      %{"as_of" => Date.to_iso8601(date), "policy_version" => @policy_version}
      |> new()
      |> Oban.insert()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"policy_version" => @policy_version} = args} = job)
      when map_size(args) == 1,
      do: run(job, Date.utc_today())

  def perform(
        %Oban.Job{args: %{"as_of" => value, "policy_version" => @policy_version} = args} = job
      )
      when map_size(args) == 2 do
    case valid_date(value) do
      {:ok, date} -> run(job, date)
      {:error, _} -> {:cancel, :malformed_job_args}
    end
  end

  def perform(%Oban.Job{args: args}) when is_map(args) and map_size(args) == 0,
    do: {:cancel, :superseded_policy}

  def perform(%Oban.Job{args: %{"as_of" => _} = args}) when map_size(args) == 1,
    do: {:cancel, :superseded_policy}

  def perform(_), do: {:cancel, :malformed_job_args}

  defp run(job, as_of) do
    case provider_config() do
      {:ok, %{provider: provider, singles: singles}} ->
        AcquisitionTracker.run(
          job,
          [
            provider_key: "tcgdex_catalogue",
            operation: "card_catalogue_sync",
            target_key: "singles_bootstrap"
          ],
          fn admitter ->
            list_and_enqueue(provider, singles, admitter, as_of)
          end
        )
        |> translate_budget_result()

      {:error, reason} ->
        {:cancel, reason}
    end
  end

  defp translate_budget_result(
         {kind,
          {:acquisition_budget_rejected, _reason, %DateTime{time_zone: "Etc/UTC"} = reset_at}}
       )
       when kind in [:error, :cancel] do
    {:ok, seconds} = AcquisitionBudget.remaining_budget_window_delay(reset_at, DateTime.utc_now())
    {:snooze, seconds}
  end

  defp translate_budget_result(result), do: result

  defp list_and_enqueue(%{provider_options: _} = provider, singles, admitter, as_of) do
    options = Keyword.put(provider.provider_options, :request_admitter, admitter)

    case safe_call(provider.provider, :list_sets, [options]) do
      {:ok, sets} when is_list(sets) -> enqueue_sets(sets, as_of, singles)
      {:ok, _} -> {:cancel, :invalid_provider_response}
      {:error, reason} -> classify(reason)
      _ -> {:cancel, :invalid_provider_response}
    end
  end

  defp enqueue_sets(sets, as_of, config) when length(sets) <= 1_000 do
    with {:ok, ids} <- set_ids(sets, config),
         :ok <- enqueue_set_jobs(ids, as_of, config) do
      :ok
    else
      {:error, :persistence_failed} -> {:error, :persistence_failed}
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp enqueue_sets(_, _, _), do: {:cancel, :invalid_provider_response}

  defp enqueue_set_jobs(ids, as_of, config),
    do: Enum.reduce_while(ids, :ok, &enqueue_set_job(&1, &2, as_of, config))

  defp enqueue_set_job(id, :ok, as_of, config) do
    job =
      SinglesSetCollectionWorker.new(
        %{
          "policy_version" => 2,
          "set_id" => id,
          "offset" => 0,
          "as_of" => Date.to_iso8601(as_of)
        },
        priority: if(id == config.pitch_black_set_id, do: 0, else: 2)
      )

    case Oban.insert(job) do
      {:ok, _} -> {:cont, :ok}
      {:error, _} -> {:halt, {:error, :persistence_failed}}
    end
  end

  defp set_ids(sets, config) do
    if Enum.all?(sets, &is_map/1) do
      ids =
        sets
        |> Enum.map(&Map.get(&1, "id"))
        |> Enum.filter(&candidate_set_id?(&1, config))

      all_ids = Enum.map(sets, &Map.get(&1, "id"))

      valid_briefs? =
        Enum.all?(sets, fn set ->
          is_binary(Map.get(set, "name")) and String.trim(Map.get(set, "name")) != ""
        end)

      if valid_briefs? and Enum.all?(all_ids, &(is_binary(&1) and Tcgdex.valid_set_id?(&1))) and
           length(all_ids) == length(Enum.uniq(all_ids)),
         do: {:ok, ids},
         else: {:error, :invalid_provider_response}
    else
      {:error, :invalid_provider_response}
    end
  end

  defp candidate_set_id?(id, config) when is_binary(id) do
    id == config.pitch_black_set_id or
      Enum.any?(config.paper_series_ids, &String.starts_with?(id, &1))
  end

  defp candidate_set_id?(_, _), do: false

  @doc false
  def singles_config do
    value = Application.get_env(:tcg_cheap, :singles_collection, [])

    with true <- is_list(value) and Keyword.keyword?(value),
         [:chunk_size, :paper_series_ids, :pitch_black_set_id, :rolling_rarities] <-
           Enum.sort(Keyword.keys(value)),
         id when is_binary(id) <- Keyword.get(value, :pitch_black_set_id),
         "me05" <- id,
         rarities when is_list(rarities) <- Keyword.get(value, :rolling_rarities),
         true <- Enum.all?(rarities, &(is_binary(&1) and String.trim(&1) != "")),
         normalized = Enum.map(rarities, &String.downcase(String.trim(&1))),
         ["illustration rare", "special illustration rare"] <- Enum.sort(normalized),
         series_ids when is_list(series_ids) <- Keyword.get(value, :paper_series_ids),
         true <- Enum.all?(series_ids, &(is_binary(&1) and &1 in ["sv", "me"])),
         true <- length(series_ids) == length(Enum.uniq(series_ids)),
         ["me", "sv"] <- Enum.sort(Enum.uniq(series_ids)),
         size when is_integer(size) and size in 1..20 <- Keyword.get(value, :chunk_size) do
      {:ok,
       %{
         pitch_black_set_id: id,
         rolling_rarities: normalized,
         chunk_size: size,
         paper_series_ids: Enum.uniq(series_ids)
       }}
    else
      _ -> {:error, :invalid_singles_collection_configuration}
    end
  end

  defp valid_date(%Date{} = date), do: {:ok, date}

  defp valid_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :malformed_job_args}
    end
  end

  defp valid_date(_), do: {:error, :malformed_job_args}

  defp safe_call(module, function, args) do
    apply(module, function, args)
  rescue
    _ -> {:error, :provider_response}
  catch
    _, _ -> {:error, :provider_response}
  end

  defp classify(reason) do
    if reason in [:invalid_provider_response, :malformed_provider_response] or
         match?({:malformed_response, _}, reason) do
      {:cancel, :provider_response}
    else
      classify_retriable(reason)
    end
  end

  defp classify_retriable(reason) do
    case AcquisitionTracker.classify(reason) do
      :budget ->
        budget_result(reason)

      category
      when category in [:rate_limit, :timeout, :transport, :provider_response, :persistence] ->
        {:error, category_error(category)}

      category when category in [:configuration, :local_input] ->
        {:cancel, category_error(category)}

      _ ->
        {:cancel, :provider_response}
    end
  end

  defp budget_result(reason) do
    rejection = category_error(:budget, reason)

    case AcquisitionBudget.budget_reason_disposition(rejection) do
      :terminal ->
        {:cancel, rejection}

      disposition when disposition in [:hourly, :daily, :monthly] ->
        case rejection do
          {:acquisition_budget_rejected, _, %DateTime{time_zone: "Etc/UTC"}} ->
            {:error, rejection}

          {:acquisition_budget_rejected, reason} ->
            {:ok, reset_at} =
              AcquisitionBudget.next_budget_window_reset(rejection, DateTime.utc_now())

            {:error, {:acquisition_budget_rejected, reason, reset_at}}
        end

      _ ->
        {:error, rejection}
    end
  end

  defp category_error(:budget, {:acquisition_budget_rejected, reason}),
    do: {:acquisition_budget_rejected, reason}

  defp category_error(:budget, {:acquisition_budget_rejected, reason, reset_at}),
    do: {:acquisition_budget_rejected, reason, reset_at}

  defp category_error(:budget, reason), do: {:acquisition_budget_rejected, reason}
  defp category_error(:rate_limit), do: :provider_rate_limited
  defp category_error(:timeout), do: :provider_timeout
  defp category_error(:transport), do: :provider_transport_error
  defp category_error(:provider_response), do: :provider_response
  defp category_error(:persistence), do: :persistence_failed
  defp category_error(:configuration), do: :invalid_provider_configuration
  defp category_error(:local_input), do: :malformed_job_args
end
