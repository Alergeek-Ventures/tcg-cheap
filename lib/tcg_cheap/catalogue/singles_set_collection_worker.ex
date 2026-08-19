defmodule TcgCheap.Catalogue.SinglesSetCollectionWorker do
  @moduledoc "Collects selected Singles cards from one validated provider set."
  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:set_id, :offset],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, Importer, SinglesScopeBootstrapWorker, Tcgdex}
  alias TcgCheap.Core
  alias TcgCheap.Operations.AcquisitionTracker
  alias TcgCheap.Pricing.Singles.ValuationAcquisition

  def timeout(_), do: :timer.seconds(360)

  def backoff(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}})
      when reason in [:acquisition_budget_rejected, :budget_persistence_failed], do: 3_600

  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  def perform(
        %Oban.Job{args: %{"set_id" => set_id, "offset" => offset, "as_of" => as_of} = args} = job
      )
      when map_size(args) == 3 and is_binary(set_id) and is_integer(offset) and offset >= 0 do
    with {:ok, date} <- valid_date(as_of), true <- Tcgdex.valid_set_id?(set_id) do
      run_collection(job, set_id, offset, date)
    else
      _ ->
        {:cancel, :malformed_job_args}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp run_collection(job, set_id, offset, date) do
    with {:ok, config} <- SinglesScopeBootstrapWorker.singles_config(),
         {:ok, provider} <- CatalogueSyncWorker.provider_config() do
      AcquisitionTracker.run(
        job,
        [provider_key: "tcgdex_catalogue", operation: "card_catalogue_sync", target_key: set_id],
        fn admitter ->
          options = Keyword.put(provider.provider_options, :request_admitter, admitter)
          fetch_and_process(provider.provider, set_id, offset, date, config, options)
        end
      )
    else
      _ -> {:cancel, :invalid_provider_configuration}
    end
  end

  defp fetch_and_process(provider, set_id, offset, date, config, options) do
    case safe_fetch(provider, :fetch_set, [set_id, options]) do
      {:ok, set} -> process_set(set, set_id, offset, date, config, provider, options)
      {:error, reason} -> classify(reason)
      _ -> {:cancel, :invalid_provider_response}
    end
  end

  defp process_set(set, set_id, offset, as_of, config, provider, options) do
    with :ok <- validate_set(set, set_id, as_of),
         {:ok, release_date} <- Date.from_iso8601(set["releaseDate"]),
         true <- selected_set?(set_id, release_date, as_of, config),
         {:ok, briefs} <- validate_coverage(set) do
      chunk = briefs |> Enum.drop(offset) |> Enum.take(config.chunk_size)
      scoped_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      with {:ok, cards} <- fetch_cards(chunk, provider, options, set_id),
           :ok <- persist_selected(cards, set, set_id, release_date, as_of, config, scoped_at),
           :ok <- enqueue_next(set_id, offset + length(chunk), length(briefs), as_of) do
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
    case target_scope(set_id, card, release_date, as_of, config) do
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
         {:ok, updated} <- merge_scopes(local, target, release_date, scoped_at),
         :ok <- maybe_enqueue_valuation(updated) do
      {:cont, :ok}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp imported_card(%{card: %{tcgdex_id: tcgdex_id}}),
    do: Core.get_card_printing_by_tcgdex_id(tcgdex_id)

  defp imported_card(_), do: {:error, :persistence_failed}

  defp merge_scopes(card, incoming_scopes, release_date, scoped_at) do
    scopes =
      ((card.collection_scopes || []) ++ incoming_scopes)
      |> Enum.uniq()
      |> Enum.sort()

    source =
      case card.collection_scope_source do
        "administrator" -> "administrator"
        "legacy" -> "legacy"
        _ -> "system"
      end

    scoped_at = card.collection_scoped_at || scoped_at

    expiry =
      if Enum.any?(scopes, &(&1 in ["pitch_black_full", "curated_playable", "legacy_local"])),
        do: nil,
        else: Date.shift(release_date, year: 2)

    case Core.set_card_printing_collection_scope(
           card,
           %{
             collection_scopes: scopes,
             collection_scope_source: source,
             collection_scoped_at: scoped_at,
             collection_expires_on: expiry
           },
           authorize?: false
         ) do
      {:ok, updated} -> {:ok, updated}
      {:error, _reason} -> {:error, :persistence_failed}
    end
  end

  defp maybe_enqueue_valuation(%{mapping_status: "matched"} = card) do
    case ValuationAcquisition.enqueue_if_stale_background(card) do
      {:fresh, _} -> :ok
      {:enqueued, _} -> :ok
      {:error, :unpriced_mapping} -> :ok
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp maybe_enqueue_valuation(_), do: :ok

  defp enqueue_next(_set_id, offset, total, _as_of) when offset >= total, do: :ok

  defp enqueue_next(set_id, offset, _total, as_of) do
    case new(%{"set_id" => set_id, "offset" => offset, "as_of" => Date.to_iso8601(as_of)})
         |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp target_scope(set_id, card, release, as_of, config) do
    full = if set_id == config.pitch_black_set_id, do: ["pitch_black_full"], else: []

    rolling =
      if release >= Date.shift(as_of, year: -2) and release <= as_of and
           is_binary(card["rarity"]) and
           String.downcase(String.trim(card["rarity"])) in config.rolling_rarities,
         do: ["rolling_ir_sir"],
         else: []

    full ++ rolling
  end

  defp selected_set?(set_id, release, as_of, config),
    do:
      set_id == config.pitch_black_set_id or
        (release >= Date.shift(as_of, year: -2) and release <= as_of)

  defp validate_set(%{"id" => actual_id, "name" => name, "releaseDate" => release}, set_id, as_of)
       when is_binary(name) and name != "" and is_binary(release) do
    case {actual_id, Date.from_iso8601(release)} do
      {^set_id, {:ok, date}} when date <= as_of -> :ok
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp validate_set(_, _, _), do: {:error, :invalid_provider_response}

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
