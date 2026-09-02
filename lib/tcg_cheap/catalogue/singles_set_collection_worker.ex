defmodule TcgCheap.Catalogue.SinglesSetCollectionWorker do
  @moduledoc "Collects selected Singles cards from one validated provider set."
  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:policy_version, :set_id, :offset],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{
    CatalogueSyncWorker,
    Importer,
    SinglesScopeBootstrapWorker,
    Tcgdex
  }

  alias TcgCheap.Core
  alias TcgCheap.Operations.{AcquisitionBudget, AcquisitionTracker}
  alias TcgCheap.Pricing.Singles.EmbeddedValuation

  @policy_version 2

  def timeout(_), do: :timer.seconds(360)

  def backoff(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}})
      when reason in [:acquisition_budget_rejected, :budget_persistence_failed], do: 3_600

  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  def perform(%Oban.Job{} = job), do: perform_on(job, DateTime.utc_now())

  def perform_on(%Oban.Job{} = job, scoped_at) do
    case valid_scoped_at(scoped_at) do
      {:ok, scoped_at} -> perform_with_scope(job, scoped_at)
      {:error, _} -> {:cancel, :malformed_job_args}
    end
  end

  def perform_on(_, _), do: {:cancel, :malformed_job_args}

  defp perform_with_scope(
         %Oban.Job{
           args:
             %{
               "policy_version" => @policy_version,
               "set_id" => set_id,
               "offset" => offset,
               "as_of" => as_of
             } = args
         } = job,
         scoped_at
       )
       when map_size(args) == 4 and is_binary(set_id) and is_integer(offset) and offset >= 0 do
    with {:ok, date} <- valid_date(as_of), true <- Tcgdex.valid_set_id?(set_id) do
      run_collection(job, set_id, offset, date, scoped_at)
    else
      _ ->
        {:cancel, :malformed_job_args}
    end
  end

  defp perform_with_scope(
         %Oban.Job{args: %{"set_id" => _, "offset" => _, "as_of" => _} = args},
         _scoped_at
       )
       when map_size(args) == 3,
       do: {:cancel, :superseded_policy}

  defp perform_with_scope(_, _scoped_at), do: {:cancel, :malformed_job_args}

  defp run_collection(job, set_id, offset, date, scoped_at) do
    with {:ok, config} <- SinglesScopeBootstrapWorker.singles_config(),
         {:ok, provider} <- CatalogueSyncWorker.provider_config() do
      AcquisitionTracker.run(
        job,
        [provider_key: "tcgdex_catalogue", operation: "card_catalogue_sync", target_key: set_id],
        fn admitter ->
          options = Keyword.put(provider.provider_options, :request_admitter, admitter)
          fetch_and_process(provider.provider, set_id, offset, date, config, options, scoped_at)
        end
      )
      |> translate_budget_result()
    else
      _ -> {:cancel, :invalid_provider_configuration}
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

  defp fetch_and_process(provider, set_id, offset, date, config, options, scoped_at) do
    case safe_fetch(provider, :fetch_set, [set_id, options]) do
      {:ok, set} -> process_set(set, set_id, offset, date, config, provider, options, scoped_at)
      {:error, reason} -> classify(reason)
      _ -> {:cancel, :invalid_provider_response}
    end
  end

  defp process_set(set, set_id, offset, as_of, config, provider, options, scoped_at) do
    with :ok <- validate_set(set, set_id, as_of, config),
         {:ok, release_date} <- Date.from_iso8601(set["releaseDate"]),
         true <- selected_set?(set_id, release_date, as_of, config),
         true <- set_active_at_scope?(set_id, release_date, config, scoped_at),
         {:ok, briefs} <- validate_coverage(set) do
      chunk = briefs |> Enum.drop(offset) |> Enum.take(config.chunk_size)

      with {:ok, cards} <- fetch_cards(chunk, provider, options, set_id),
           :ok <- persist_selected(cards, set, set_id, release_date, as_of, config, scoped_at),
           :ok <- enqueue_next(set_id, offset + length(chunk), length(briefs), as_of, config) do
        :ok
      else
        {:error, reason} -> classify(reason)
      end
    else
      false -> :ok
      {:error, reason} -> classify(reason)
    end
  end

  defp fetch_cards(briefs, provider, options, set_id) do
    Enum.reduce_while(briefs, {:ok, []}, &fetch_card(&1, &2, provider, options, set_id))
  end

  defp fetch_card(%{"id" => id}, {:ok, cards}, provider, options, set_id) do
    case safe_fetch(provider, :fetch_card, [id, options]) do
      {:ok, card} -> valid_fetched_card(card, id, set_id, cards)
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp valid_fetched_card(card, id, set_id, cards) do
    if valid_card_payload?(card, id, set_id),
      do: {:cont, {:ok, [card | cards]}},
      else: {:halt, {:error, :invalid_provider_response}}
  end

  defp persist_selected(cards, set, set_id, release_date, as_of, config, scoped_at) do
    Enum.reduce_while(cards, :ok, fn card, :ok ->
      persist_card(card, set, set_id, release_date, as_of, config, scoped_at)
    end)
  end

  defp persist_card(card, set, set_id, release_date, as_of, config, scoped_at) do
    case target_scope(set_id, card, release_date, as_of, config, scoped_at) do
      [] -> {:cont, :ok}
      target -> persist_targeted_card(card, target, set, set_id, release_date, scoped_at)
    end
  end

  defp persist_targeted_card(card, target, set, set_id, release_date, scoped_at) do
    with {:ok, imported} <-
           Importer.import_fetched_card(card, set, card["id"],
             synced_at: scoped_at,
             expected_set_id: set_id
           ),
         {:ok, local} <- imported_card(imported),
         {:ok, updated} <- add_scopes(local, target, release_date, scoped_at),
         :ok <- EmbeddedValuation.record_or_enqueue(updated, card, scoped_at) do
      {:cont, :ok}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp imported_card(%{card: %{tcgdex_id: tcgdex_id}}),
    do: Core.get_card_printing_by_tcgdex_id(tcgdex_id)

  defp imported_card(_), do: {:error, :persistence_failed}

  defp add_scopes(card, incoming_scopes, release_date, scoped_at) do
    case Core.add_card_printing_collection_scopes(
           card,
           incoming_scopes,
           Date.shift(release_date, year: 2),
           scoped_at,
           authorize?: false
         ) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp enqueue_next(_set_id, offset, total, _as_of, _config) when offset >= total, do: :ok

  defp enqueue_next(set_id, offset, _total, as_of, config) do
    priority = if set_id == config.pitch_black_set_id, do: 0, else: 1

    case new(
           %{
             "policy_version" => @policy_version,
             "set_id" => set_id,
             "offset" => offset,
             "as_of" => Date.to_iso8601(as_of)
           },
           priority: priority
         )
         |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp target_scope(set_id, card, release, as_of, config, scoped_at) do
    full = if set_id == config.pitch_black_set_id, do: ["pitch_black_full"], else: []

    rolling =
      if date_between?(release, Date.shift(as_of, year: -2), as_of) and
           Date.compare(Date.shift(release, year: 2), DateTime.to_date(scoped_at)) in [:eq, :gt] and
           is_binary(card["rarity"]) and
           String.downcase(String.trim(card["rarity"])) in config.rolling_rarities,
         do: ["rolling_ir_sir"],
         else: []

    full ++ rolling
  end

  defp selected_set?(set_id, release, as_of, config),
    do:
      set_id == config.pitch_black_set_id or
        date_between?(release, Date.shift(as_of, year: -2), as_of)

  defp set_active_at_scope?(set_id, _release, config, _scoped_at)
       when set_id == config.pitch_black_set_id,
       do: true

  defp set_active_at_scope?(_set_id, release, _config, scoped_at),
    do: Date.compare(Date.shift(release, year: 2), DateTime.to_date(scoped_at)) != :lt

  defp validate_set(
         %{"id" => actual_id, "name" => name, "releaseDate" => release, "serie" => serie},
         set_id,
         as_of,
         config
       )
       when is_binary(name) and name != "" and is_binary(release) do
    case {actual_id, Date.from_iso8601(release)} do
      {^set_id, {:ok, date}} when is_map(serie) ->
        cond do
          date_on_or_before?(date, as_of) and Map.get(serie, "id") in config.paper_series_ids ->
            :ok

          date_on_or_before?(date, as_of) ->
            {:error, :out_of_scope}

          true ->
            {:error, :invalid_provider_response}
        end

      _ ->
        {:error, :invalid_provider_response}
    end
  end

  defp validate_set(_, _, _, _), do: {:error, :invalid_provider_response}

  defp date_on_or_before?(date, boundary),
    do: Date.compare(date, boundary) in [:lt, :eq]

  defp date_between?(date, earliest, latest),
    do: date_on_or_before?(earliest, date) and date_on_or_before?(date, latest)

  defp validate_coverage(%{"cardCount" => count, "cards" => cards})
       when is_map(count) and is_list(cards) do
    with {:ok, total} <- valid_counts(count),
         {:ok, briefs} <- validate_cards(cards),
         true <- length(briefs) == total do
      {:ok, briefs}
    else
      false -> {:error, :incomplete_provider_response}
      {:error, :invalid_provider_response} -> {:error, :invalid_provider_response}
    end
  end

  defp validate_coverage(_), do: {:error, :invalid_provider_response}

  defp valid_counts(%{"official" => official, "total" => total})
       when is_integer(official) and is_integer(total) and official >= 0 and
              total >= official and total <= 1_000,
       do: {:ok, total}

  defp valid_counts(_), do: {:error, :invalid_provider_response}

  defp validate_cards(cards) when length(cards) <= 1_000 do
    if Enum.all?(cards, &is_map/1) do
      ids = Enum.map(cards, &Map.get(&1, "id"))

      if Enum.all?(ids, &(is_binary(&1) and Tcgdex.valid_card_id?(&1))) and
           length(ids) == length(Enum.uniq(ids)),
         do: {:ok, Enum.map(ids, &%{"id" => &1})},
         else: {:error, :invalid_provider_response}
    else
      {:error, :invalid_provider_response}
    end
  end

  defp validate_cards(_), do: {:error, :invalid_provider_response}

  defp valid_card_payload?(
         %{"id" => id, "name" => name, "localId" => local, "set" => set},
         id,
         set_id
       )
       when is_binary(name) and name != "" and is_binary(local),
       do: set == set_id or (is_map(set) and Map.get(set, "id") == set_id)

  defp valid_card_payload?(_, _, _), do: false

  defp valid_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :malformed_job_args}
    end
  end

  defp valid_date(_), do: {:error, :malformed_job_args}

  defp valid_scoped_at(%DateTime{} = scoped_at) do
    {:ok, DateTime.truncate(scoped_at, :microsecond)}
  rescue
    ArgumentError -> {:error, :malformed_job_args}
  end

  defp valid_scoped_at(_), do: {:error, :malformed_job_args}

  defp safe_fetch(module, function, args) do
    apply(module, function, args)
  rescue
    error in [MatchError] -> match_error_result(error)
    _ -> {:error, :provider_response}
  catch
    _, _ -> {:error, :provider_response}
  end

  defp match_error_result(%MatchError{term: {:error, reason}}), do: {:error, reason}
  defp match_error_result(_), do: {:error, :provider_response}

  defp classify(:incomplete_provider_response), do: {:error, :provider_response}

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
