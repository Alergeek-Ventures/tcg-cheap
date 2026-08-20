defmodule TcgCheap.Catalogue.CuratedPlayableCollectionWorker do
  @moduledoc "Fetches and imports one identity-pinned curated playable printing."

  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:evidence_version, :tcgdex_id],
      states: [:available, :scheduled, :executing, :retryable, :suspended, :completed],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, CuratedPlayablePolicy, Importer}
  alias TcgCheap.Core
  alias TcgCheap.Operations.AcquisitionTracker
  alias TcgCheap.Pricing.Singles.ValuationAcquisition

  def timeout(_), do: :timer.seconds(360)

  def backoff(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}})
      when reason in [:acquisition_budget_rejected, :budget_persistence_failed],
      do: 3_600

  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  def perform(%Oban.Job{} = job), do: perform_on(job, Date.utc_today(), DateTime.utc_now())

  def perform_on(job, as_of, scoped_at \\ DateTime.utc_now())

  def perform_on(
        %Oban.Job{args: %{"evidence_version" => version, "tcgdex_id" => id}} = job,
        as_of,
        scoped_at
      )
      when map_size(job.args) == 2 and version == "2026-08-19-naic" and is_binary(id) do
    entry = CuratedPlayablePolicy.entry(id)
    status = CuratedPlayablePolicy.status(as_of)

    cond do
      is_nil(entry) ->
        {:cancel, :malformed_job_args}

      status == :before_evidence ->
        {:cancel, :evidence_not_yet_valid}

      status == :after_expiry ->
        {:cancel, :evidence_expired}

      status == :active ->
        run(job, entry, as_of, scoped_at)

      true ->
        {:cancel, :malformed_job_args}
    end
  end

  def perform_on(%Oban.Job{}, _, _), do: {:cancel, :malformed_job_args}

  defp run(job, entry, as_of, scoped_at) do
    case CatalogueSyncWorker.provider_config() do
      {:ok, provider} ->
        AcquisitionTracker.run(
          job,
          [
            provider_key: "tcgdex_catalogue",
            operation: "card_catalogue_sync",
            target_key: entry.tcgdex_id
          ],
          &collect(&1, provider, entry, as_of, scoped_at)
        )

      _ ->
        {:cancel, :invalid_provider_configuration}
    end
  end

  defp collect(admitter, provider, entry, as_of, scoped_at) do
    options = Keyword.put(provider.provider_options, :request_admitter, admitter)

    with {:ok, card} <- safe_fetch(provider.provider, :fetch_card, [entry.tcgdex_id, options]),
         {:ok, set} <- safe_fetch(provider.provider, :fetch_set, [entry.set_id, options]),
         :ok <- validate(entry, card, set, as_of),
         :ok <- persist_import(card, set, entry, scoped_at) do
      :ok
    else
      {:error, reason} -> classify(reason)
    end
  end

  defp persist_import(card, set, entry, scoped_at) do
    expected_id = entry.tcgdex_id

    with {:ok, %{card: %{tcgdex_id: ^expected_id}}} <-
           Importer.import_fetched_card(card, set, entry.tcgdex_id,
             synced_at: scoped_at,
             expected_set_id: entry.set_id
           ),
         {:ok, local} <- Core.get_card_printing_by_tcgdex_id(entry.tcgdex_id),
         {:ok, updated} <-
           Core.add_card_printing_collection_scopes(
             local,
             ["curated_playable"],
             CuratedPlayablePolicy.expires_on(),
             scoped_at,
             authorize?: false
           ),
         :ok <- maybe_valuation(updated) do
      :ok
    else
      _ -> {:error, :persistence_failed}
    end
  end

  defp validate(
         entry,
         %{
           "id" => id,
           "name" => name,
           "category" => category,
           "trainerType" => trainer_type,
           "regulationMark" => mark,
           "localId" => local_id,
           "set" => card_set,
           "legal" => %{"standard" => true}
         },
         %{
           "id" => set_id,
           "name" => set_name,
           "releaseDate" => release,
           "serie" => %{"id" => series}
         },
         as_of
       )
       when is_binary(set_name) and byte_size(set_name) > 0 and is_binary(release) do
    with true <-
           id == entry.tcgdex_id and name == entry.name and category == entry.category and
             trainer_type == entry.trainer_type and mark == entry.regulation_mark and
             local_id == entry.collector_number,
         true <- String.trim(set_name) != "",
         true <- set_link?(card_set, entry.set_id) and set_id == entry.set_id,
         true <- series == String.slice(entry.set_id, 0, 2),
         {:ok, release_date} <- Date.from_iso8601(release),
         true <- Date.compare(release_date, as_of) != :gt do
      :ok
    else
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp validate(_, _, _, _), do: {:error, :invalid_provider_response}
  defp set_link?(%{"id" => id}, id), do: true
  defp set_link?(id, id) when is_binary(id), do: true
  defp set_link?(_, _), do: false

  defp maybe_valuation(%{mapping_status: "matched"} = card) do
    case ValuationAcquisition.enqueue_if_stale_background(card) do
      {:fresh, _} -> :ok
      {:enqueued, _} -> :ok
      {:error, :unpriced_mapping} -> :ok
      _ -> {:error, :persistence_failed}
    end
  end

  defp maybe_valuation(_), do: :ok

  defp safe_fetch(module, function, args) do
    case apply(module, function, args) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_provider_response}
    end
  rescue
    _ -> {:error, :provider_response}
  catch
    _, _ -> {:error, :provider_response}
  end

  defp classify(:invalid_provider_response), do: {:cancel, :provider_response}

  defp classify(reason) do
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
