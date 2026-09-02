defmodule TcgCheap.Catalogue.CardDetailEnrichmentWorker do
  @moduledoc "Enriches one canonical card detail at a time, with a resumable chain."

  use Oban.Worker,
    queue: :catalogue_sync,
    priority: 5,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:local_card_id, :tcgdex_id, :policy_version, :continue],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, Importer}
  alias TcgCheap.Core
  alias TcgCheap.Operations.{AcquisitionBudget, AcquisitionTracker, ImportIssues}
  alias TcgCheap.Pricing.Singles.EmbeddedValuation

  @policy_version 1
  @provider_key "tcgdex_catalogue"

  def timeout(_), do: :timer.seconds(70)

  def backoff(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}})
      when reason in [:acquisition_budget_rejected, :budget_persistence_failed], do: 3_600

  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 3_600)

  def enqueue(card, continuation? \\ false, opts \\ [])

  def enqueue(%{id: local_id, tcgdex_id: tcgdex_id}, continuation?, opts)
      when is_binary(local_id) and is_binary(tcgdex_id) and is_boolean(continuation?) do
    args = %{
      "local_card_id" => local_id,
      "tcgdex_id" => tcgdex_id,
      "policy_version" => @policy_version,
      "continue" => continuation?
    }

    args |> new(opts) |> Oban.insert()
  end

  def enqueue(_, _, _), do: {:error, :invalid_local_card}

  def perform(%Oban.Job{args: args} = job)
      when is_map(args) and map_size(args) == 4 do
    with %{
           "local_card_id" => local_id,
           "tcgdex_id" => tcgdex_id,
           "policy_version" => @policy_version,
           "continue" => continuation?
         } <- args,
         true <- is_binary(local_id) and is_binary(tcgdex_id) and is_boolean(continuation?) do
      run(job, local_id, tcgdex_id, continuation?)
    else
      _ -> {:cancel, :malformed_job_args}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  @doc false
  def topic(id) when is_binary(id), do: "card-detail-enrichment:#{id}"
  def topic(%{id: id}), do: topic(id)
  def subscribe(card), do: Phoenix.PubSub.subscribe(TcgCheap.PubSub, topic(card))

  defp run(job, local_id, tcgdex_id, continuation?) do
    result =
      AcquisitionTracker.run(
        job,
        [
          provider_key: @provider_key,
          operation: "card_catalogue_enrichment",
          target_key: tcgdex_id
        ],
        fn admitter ->
          enrich(local_id, tcgdex_id, continuation?, admitter, job)
        end
      )

    result = translate_result(result)
    broadcast(local_id, tcgdex_id, result)
    result
  end

  defp enrich(local_id, tcgdex_id, continuation?, admitter, job) do
    synced_at = imported_at()

    case canonical_card(local_id, tcgdex_id) do
      {:ok, card} ->
        case enrich_checked(card, tcgdex_id, continuation?, admitter, synced_at) do
          :ok ->
            :ok

          {:error, reason} ->
            failure_or_continue(continuation?, tcgdex_id, reason, synced_at, job)

          _other ->
            failure_or_continue(continuation?, tcgdex_id, :provider_response, synced_at, job)
        end

      {:error, reason} ->
        failure_or_continue(continuation?, tcgdex_id, reason, synced_at, job)
    end
  end

  defp enrich_checked(
         %{details_enrichment_failed_at: failed_at, pricing_checked_at: nil} = card,
         _tcgdex_id,
         continuation?,
         _admitter,
         synced_at
       )
       when not is_nil(failed_at) do
    pricing_only(card, continuation?, synced_at)
  end

  # A successful import persists the provider payload before pricing. Resume that
  # staged completion from the payload instead of fetching details again.
  defp enrich_checked(
         %{details_synced_at: details_synced_at, pricing_checked_at: nil} = card,
         _tcgdex_id,
         continuation?,
         _admitter,
         synced_at
       )
       when not is_nil(details_synced_at) do
    pricing_only(card, continuation?, synced_at, Map.get(card, :source_payload) || %{})
  end

  defp enrich_checked(
         %{pricing_checked_at: checked} = card,
         _tcgdex_id,
         continuation?,
         _admitter,
         _synced_at
       )
       when not is_nil(checked) do
    if continuation?, do: maybe_continue(true, card), else: :ok
  end

  defp enrich_checked(card, tcgdex_id, continuation?, admitter, synced_at) do
    with {:ok, provider} <- CatalogueSyncWorker.provider_config(),
         {:ok, payload} <-
           fetch(
             provider.provider,
             tcgdex_id,
             Keyword.put(provider.provider_options, :request_admitter, admitter)
           ),
         {:ok, _imported} <- import_card(card, payload, synced_at),
         {:ok, fresh} <- Core.get_card_printing_by_tcgdex_id(tcgdex_id),
         :ok <- embedded_valuation().record_or_enqueue(fresh, payload, synced_at),
         :ok <- mark_pricing_checked(fresh, synced_at) do
      maybe_continue(continuation?, fresh)
    end
  end

  # Once detail enrichment has failed, the provider must not be called again.
  # The retryable part is only the pricing fallback and its persistence.
  defp pricing_only(card, continuation?, synced_at) do
    pricing_only(card, continuation?, synced_at, %{})
  end

  defp pricing_only(card, continuation?, synced_at, provider_card) do
    with :ok <- embedded_valuation().record_or_enqueue(card, provider_card, synced_at),
         :ok <- mark_pricing_checked(card, synced_at) do
      maybe_continue(continuation?, card)
    else
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp canonical_card(local_id, tcgdex_id) do
    case Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, %{id: ^local_id, tcgdex_id: ^tcgdex_id} = card} ->
        case Ash.load(card, [:card_set, :source_payload], authorize?: false) do
          {:ok, %{card_set: %{tcgdex_id: _, name: _, series_id: series_id} = _set} = loaded}
          when is_binary(series_id) and series_id != "tcgp" ->
            {:ok, loaded}

          {:ok, _loaded} ->
            {:error, :invalid_card_set}

          _ ->
            {:error, :persistence_failed}
        end

      _ ->
        {:error, :invalid_local_card}
    end
  end

  defp fetch(provider, id, options) do
    task = Task.async(fn -> safe_fetch(provider, id, options) end)

    case Task.yield(task, :timer.seconds(60)) do
      {:ok, result} ->
        result

      _ ->
        Task.shutdown(task, :brutal_kill)
        {:error, :provider_timeout}
    end
  end

  defp safe_fetch(provider, id, options) do
    case provider.fetch_card(id, options) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :provider_response}
    end
  rescue
    _ -> {:error, :provider_transport_error}
  catch
    _, _ -> {:error, :provider_transport_error}
  end

  defp import_card(card, payload, synced_at) do
    set = card.card_set
    minimal = %{"id" => set.tcgdex_id, "name" => set.name}

    Importer.import_fetched_card(payload, minimal, card.tcgdex_id,
      synced_at: synced_at,
      expected_set_id: set.tcgdex_id,
      pricing_checked?: false
    )
  end

  defp imported_at, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp maybe_continue(false, _card), do: :ok

  defp maybe_continue(true, card) do
    case Core.list_detail_enrichment_candidates(card.tcgdex_id, 1, authorize?: false) do
      {:ok, [next | _]} -> enqueue(next, true, priority: 5) |> insert_result()
      {:ok, []} -> :ok
      _ -> {:error, :persistence_failed}
    end
  end

  defp failure_or_continue(true, tcgdex_id, :invalid_card_set, _synced_at, job) do
    case continue_after(tcgdex_id) do
      :ok -> {:cancel, :invalid_card_set}
      {:error, _} -> persistence_failure(job)
    end
  end

  defp failure_or_continue(true, tcgdex_id, reason, synced_at, job) do
    handle_failure(permanent_failure?(reason), true, tcgdex_id, reason, synced_at, job)
  end

  defp failure_or_continue(false, tcgdex_id, reason, synced_at, job) do
    handle_failure(permanent_failure?(reason), false, tcgdex_id, reason, synced_at, job)
  end

  defp handle_failure(true, continuation?, tcgdex_id, reason, synced_at, job),
    do: permanent_failure(continuation?, tcgdex_id, reason, synced_at, job)

  defp handle_failure(false, continuation?, tcgdex_id, reason, synced_at, job) do
    cond do
      persistence_at_limit?(job, reason) ->
        persistence_failure(job)

      last_retryable_attempt?(job, reason) ->
        terminal_retryable_failure(continuation?, tcgdex_id, reason, synced_at)

      true ->
        {:error, reason}
    end
  end

  defp permanent_failure(continuation?, tcgdex_id, reason, synced_at, job) do
    with :ok <- record_issue(tcgdex_id, reason),
         {:ok, card} <- Core.get_card_printing_by_tcgdex_id(tcgdex_id),
         {:ok, failed_card} <- mark_details_enrichment_failed(card, synced_at),
         :ok <- embedded_valuation().record_or_enqueue(failed_card, %{}, synced_at),
         :ok <- mark_pricing_checked(failed_card, synced_at),
         :ok <- maybe_continue_after(continuation?, tcgdex_id) do
      {:cancel, :provider_response}
    else
      _ -> persistence_failure(job)
    end
  end

  defp mark_details_enrichment_failed(card, failed_at) do
    case Core.mark_card_printing_details_enrichment_failed(card, failed_at, authorize?: false) do
      {:ok, updated} -> {:ok, updated}
      _ -> {:error, :persistence_failed}
    end
  end

  defp maybe_continue_after(true, tcgdex_id), do: continue_after(tcgdex_id)
  defp maybe_continue_after(false, _tcgdex_id), do: :ok

  defp persistence_failure(%{attempt: attempt, max_attempts: max_attempts})
       when attempt >= max_attempts,
       do: {:snooze, 60}

  defp persistence_failure(_job), do: {:error, :persistence_failed}

  defp persistence_at_limit?(%{attempt: attempt, max_attempts: max_attempts}, reason),
    do: attempt >= max_attempts and AcquisitionTracker.classify(reason) == :persistence

  defp persistence_at_limit?(_, _), do: false

  defp record_issue(tcgdex_id, reason),
    do:
      ImportIssues.record(
        @provider_key,
        "card_catalogue_enrichment",
        "card_fetch",
        "card",
        tcgdex_id,
        failure_category(reason)
      )

  defp mark_pricing_checked(card, checked_at) when is_map(card) do
    case Core.mark_card_printing_pricing_checked(card, checked_at, authorize?: false) do
      {:ok, _} -> :ok
      _ -> {:error, :persistence_failed}
    end
  end

  defp terminal_retryable_failure(continuation?, tcgdex_id, reason, checked_at) do
    with :ok <- record_issue(tcgdex_id, reason),
         {:ok, card} <- Core.get_card_printing_by_tcgdex_id(tcgdex_id),
         {:ok, failed_card} <- mark_details_enrichment_failed(card, checked_at),
         :ok <- embedded_valuation().record_or_enqueue(failed_card, %{}, checked_at),
         :ok <- mark_pricing_checked(failed_card, checked_at),
         :ok <- if(continuation?, do: continue_after(tcgdex_id), else: :ok) do
      {:cancel, :provider_response}
    else
      _ -> {:snooze, 60}
    end
  end

  defp last_retryable_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}, reason),
    do:
      attempt >= max_attempts and
        AcquisitionTracker.classify(reason) not in [:budget, :persistence]

  defp continue_after(tcgdex_id) do
    case Core.list_detail_enrichment_candidates(tcgdex_id, 1, authorize?: false) do
      {:ok, [next | _]} -> enqueue(next, true, priority: 5) |> insert_result()
      {:ok, []} -> :ok
      _ -> {:error, :persistence_failed}
    end
  end

  defp permanent_failure?({:http_error, status}) when status in [404, 410], do: true
  defp permanent_failure?({:http_error, %{status: status}}) when status in [404, 410], do: true
  defp permanent_failure?({:malformed_response, _}), do: true
  defp permanent_failure?(:invalid_provider_response), do: true
  defp permanent_failure?(:provider_not_found), do: true
  defp permanent_failure?(_), do: false

  defp classify_result(reason) do
    classify_result(AcquisitionTracker.classify(reason), reason)
  end

  defp classify_result(:budget, reason), do: budget_result(reason)
  defp classify_result(:rate_limit, _), do: {:error, :provider_rate_limited}
  defp classify_result(:timeout, _), do: {:error, :provider_timeout}
  defp classify_result(:transport, _), do: {:error, :provider_transport_error}
  defp classify_result(:provider_response, _), do: {:error, :provider_response}
  defp classify_result(:persistence, _), do: {:error, :persistence_failed}
  defp classify_result(:configuration, _), do: {:cancel, :invalid_provider_configuration}
  defp classify_result(:local_input, _), do: {:cancel, :malformed_job_args}
  defp classify_result(_, _), do: {:error, :unknown}

  defp failure_category(reason) do
    categorize_failure(AcquisitionTracker.classify(reason))
  end

  defp categorize_failure(category)
       when category in [
              :budget,
              :rate_limit,
              :timeout,
              :transport,
              :provider_response,
              :persistence,
              :configuration,
              :local_input
            ],
       do: category

  defp categorize_failure(_), do: :unknown

  defp translate_result(:ok), do: :ok
  defp translate_result({:cancel, _} = result), do: result
  defp translate_result({:snooze, _} = result), do: result
  defp translate_result({:error, reason}), do: classify_result(reason)
  defp translate_result(_), do: {:error, :unknown}

  defp budget_result({:acquisition_budget_rejected, _reason, reset}) do
    {:ok, delay} = AcquisitionBudget.remaining_budget_window_delay(reset, DateTime.utc_now())
    {:snooze, delay}
  end

  defp budget_result(_), do: {:error, :acquisition_budget_rejected}

  defp insert_result({:ok, _}), do: :ok
  defp insert_result({:error, _}), do: {:error, :persistence_failed}

  defp embedded_valuation do
    Application.get_env(:tcg_cheap, :card_detail_enrichment_embedded_valuation, EmbeddedValuation)
  end

  defp broadcast(local_id, tcgdex_id, result) do
    event =
      case result do
        :ok ->
          {:card_detail_enrichment_completed,
           %{tcgdex_id: tcgdex_id, local_card_id: local_id, card_printing_id: local_id}}

        {:snooze, _} ->
          {:card_detail_enrichment_deferred,
           %{tcgdex_id: tcgdex_id, local_card_id: local_id, card_printing_id: local_id}}

        {:error, _reason} ->
          {:card_detail_enrichment_deferred,
           %{tcgdex_id: tcgdex_id, local_card_id: local_id, card_printing_id: local_id}}

        _ ->
          {:card_detail_enrichment_failed,
           %{tcgdex_id: tcgdex_id, local_card_id: local_id, card_printing_id: local_id}}
      end

    Phoenix.PubSub.broadcast(TcgCheap.PubSub, topic(local_id), event)
  end
end
