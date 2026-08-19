defmodule TcgCheap.Catalogue.SinglesScopeBootstrapWorker do
  @moduledoc "Bootstraps bounded Singles set collection jobs from the catalogue provider."
  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: 7 * 24 * 60 * 60,
      keys: [],
      states: [:available, :scheduled, :executing, :retryable, :suspended, :completed],
      fields: [:worker]
    ]

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, SinglesSetCollectionWorker, Tcgdex}
  alias TcgCheap.Operations.AcquisitionTracker

  def timeout(_), do: :timer.seconds(120)

  @doc "Returns the shared provider and strict Singles configuration."
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
      %{"as_of" => Date.to_iso8601(date)} |> new() |> Oban.insert()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args} = job) when map_size(args) == 0,
    do: run(job, Date.utc_today())

  def perform(%Oban.Job{args: %{"as_of" => value} = args} = job) when map_size(args) == 1 do
    case valid_date(value) do
      {:ok, date} -> run(job, date)
      {:error, _} -> {:cancel, :malformed_job_args}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp run(job, as_of) do
    case provider_config() do
      {:ok, %{provider: config}} ->
        AcquisitionTracker.run(
          job,
          [
            provider_key: "tcgdex_catalogue",
            operation: "card_catalogue_sync",
            target_key: "singles_bootstrap"
          ],
          fn admitter ->
            list_and_enqueue(config, admitter, as_of)
          end
        )

      {:error, reason} ->
        {:cancel, reason}
    end
  end

  defp list_and_enqueue(config, admitter, as_of) do
    options = Keyword.put(config.provider_options, :request_admitter, admitter)

    case safe_call(config.provider, :list_sets, [options]) do
      {:ok, sets} when is_list(sets) -> enqueue_sets(sets, as_of)
      {:ok, _} -> {:cancel, :invalid_provider_response}
      {:error, reason} -> classify(reason)
      _ -> {:cancel, :invalid_provider_response}
    end
  end

  defp enqueue_sets(sets, as_of) when length(sets) <= 1_000 do
    with {:ok, ids} <- set_ids(sets),
         :ok <- enqueue_set_jobs(ids, as_of) do
      :ok
    else
      {:error, :persistence_failed} -> {:error, :persistence_failed}
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp enqueue_sets(_, _), do: {:cancel, :invalid_provider_response}

  defp enqueue_set_jobs(ids, as_of),
    do: Enum.reduce_while(ids, :ok, &enqueue_set_job(&1, &2, as_of))

  defp enqueue_set_job(id, :ok, as_of) do
    job =
      SinglesSetCollectionWorker.new(%{
        "set_id" => id,
        "offset" => 0,
        "as_of" => Date.to_iso8601(as_of)
      })

    case Oban.insert(job) do
      {:ok, _} -> {:cont, :ok}
      {:error, _} -> {:halt, {:error, :persistence_failed}}
    end
  end

  defp set_ids(sets) do
    if Enum.all?(sets, &is_map/1) do
      ids = Enum.map(sets, &Map.get(&1, "id"))

      if Enum.all?(ids, &(is_binary(&1) and Tcgdex.valid_set_id?(&1))) and
           length(ids) == length(Enum.uniq(ids)),
         do: {:ok, ids},
         else: {:error, :invalid_provider_response}
    else
      {:error, :invalid_provider_response}
    end
  end

  @doc false
  def singles_config do
    value = Application.get_env(:tcg_cheap, :singles_collection, [])

    with true <- is_list(value) and Keyword.keyword?(value),
         [:chunk_size, :pitch_black_set_id, :rolling_rarities] <- Enum.sort(Keyword.keys(value)),
         id when is_binary(id) <- Keyword.get(value, :pitch_black_set_id),
         "me05" <- id,
         rarities when is_list(rarities) <- Keyword.get(value, :rolling_rarities),
         true <- Enum.all?(rarities, &(is_binary(&1) and String.trim(&1) != "")),
         normalized = Enum.map(rarities, &String.downcase(String.trim(&1))),
         ["illustration rare", "special illustration rare"] <- Enum.sort(normalized),
         size when is_integer(size) and size in 1..20 <- Keyword.get(value, :chunk_size) do
      {:ok, %{pitch_black_set_id: id, rolling_rarities: normalized, chunk_size: size}}
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
      category
      when category in [
             :budget,
             :rate_limit,
             :timeout,
             :transport,
             :provider_response,
             :persistence
           ] ->
        {:error, category_error(category)}

      category when category in [:configuration, :local_input] ->
        {:cancel, category_error(category)}

      _ ->
        {:cancel, :provider_response}
    end
  end

  defp category_error(:budget), do: :acquisition_budget_rejected
  defp category_error(:rate_limit), do: :provider_rate_limited
  defp category_error(:timeout), do: :provider_timeout
  defp category_error(:transport), do: :provider_transport_error
  defp category_error(:provider_response), do: :provider_response
  defp category_error(:persistence), do: :persistence_failed
  defp category_error(:configuration), do: :invalid_provider_configuration
  defp category_error(:local_input), do: :malformed_job_args
end
