defmodule TcgCheap.Pricing.SealedBuyingGuideWorker do
  @moduledoc "Computes one local buying guide from an exact daily-aggregate revision."
  use Oban.Worker,
    queue: :sealed_buying_guides,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Core

  alias TcgCheap.Pricing.{
    SealedBuyingGuideInput,
    SealedBuyingModel,
    SealedDailyAggregateRevision
  }

  @impl true
  def perform(%Oban.Job{args: args}) do
    with {:ok, target} <- validate_args(args),
         :ok <- process(target) do
      :ok
    else
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  @impl true
  def timeout(_job), do: :timer.minutes(10)

  def new_for_aggregate(aggregate) do
    with {:ok, fingerprint} <- SealedDailyAggregateRevision.fingerprint(aggregate),
         id when is_binary(id) <- Map.get(aggregate, :id),
         product_id when is_binary(product_id) <- Map.get(aggregate, :sealed_product_id),
         calculation_version when is_binary(calculation_version) <-
           Map.get(aggregate, :calculation_version),
         %Date{} <- Map.get(aggregate, :aggregate_date),
         %DateTime{} = calculated_at <- Map.get(aggregate, :calculated_at),
         {:ok, history} <- read_persisted_history(product_id, calculation_version, aggregate),
         {:ok, history_fingerprint} <- SealedDailyAggregateRevision.history_fingerprint(history) do
      {:ok,
       new(%{
         source_aggregate_id: id,
         source_aggregate_calculated_at: DateTime.to_iso8601(calculated_at),
         source_aggregate_fingerprint: fingerprint,
         source_history_fingerprint: history_fingerprint
       })}
    else
      {:error, :history_read_failed} = error -> error
      _ -> {:error, :malformed_aggregate_revision}
    end
  end

  defp validate_args(
         %{
           "source_aggregate_id" => aggregate_id,
           "source_aggregate_calculated_at" => calculated_at,
           "source_aggregate_fingerprint" => fingerprint,
           "source_history_fingerprint" => history_fingerprint
         } = args
       )
       when map_size(args) == 4 and is_binary(aggregate_id) and is_binary(calculated_at) and
              is_binary(fingerprint) and is_binary(history_fingerprint) do
    with {:ok, aggregate_id} <- Ecto.UUID.cast(aggregate_id),
         {:ok, calculated_at, 0} <- DateTime.from_iso8601(calculated_at),
         true <- Regex.match?(~r/^[0-9a-f]{64}$/, fingerprint),
         true <- Regex.match?(~r/^[0-9a-f]{64}$/, history_fingerprint) do
      {:ok,
       %{
         aggregate_id: aggregate_id,
         calculated_at: calculated_at,
         fingerprint: fingerprint,
         history_fingerprint: history_fingerprint
       }}
    else
      _ -> {:cancel, :malformed_job_args}
    end
  end

  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp process(target) do
    case Core.get_sealed_daily_aggregate(target.aggregate_id) do
      {:ok, nil} -> {:cancel, :source_aggregate_not_found}
      {:ok, aggregate} -> process_if_current_revision(aggregate, target)
      {:error, _} -> {:error, :aggregate_read_failed}
    end
  end

  defp process_if_current_revision(aggregate, target) do
    with :eq <- DateTime.compare(aggregate.calculated_at, target.calculated_at),
         {:ok, fingerprint} <- SealedDailyAggregateRevision.fingerprint(aggregate),
         true <- fingerprint == target.fingerprint,
         {:ok, history} <-
           read_history(aggregate.sealed_product_id, aggregate.calculation_version, aggregate),
         {:ok, history_fingerprint} <- SealedDailyAggregateRevision.history_fingerprint(history),
         true <- history_fingerprint == target.history_fingerprint do
      process_current_revision(aggregate, fingerprint, history, history_fingerprint)
    else
      :lt -> enqueue_latest_successor(aggregate)
      :gt -> enqueue_latest_successor(aggregate)
      false -> enqueue_latest_successor(aggregate)
      {:error, :history_read_failed} -> {:error, :history_read_failed}
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp process_current_revision(aggregate, source_fingerprint, history, history_fingerprint) do
    case Core.get_public_sealed_product_by_id(aggregate.sealed_product_id) do
      {:ok, nil} ->
        :ok

      {:ok, product} ->
        calculate_and_persist(
          product,
          aggregate,
          source_fingerprint,
          history,
          history_fingerprint
        )

      {:error, _} ->
        {:error, :product_read_failed}
    end
  end

  defp calculate_and_persist(product, aggregate, source_fingerprint, history, history_fingerprint) do
    with {:ok, input} <- SealedBuyingGuideInput.build(product, aggregate, history),
         {:ok, result} <- SealedBuyingModel.calculate(input, aggregate.calculated_at) do
      persist(aggregate, source_fingerprint, history_fingerprint, result)
    else
      {:error, :history_read_failed} -> {:error, :history_read_failed}
      {:error, reason} when is_atom(reason) -> {:cancel, reason}
    end
  end

  defp read_history(product_id, calculation_version, aggregate) do
    reader =
      case Application.fetch_env(:tcg_cheap, :sealed_buying_guide_history_reader) do
        {:ok, configured} -> configured
        :error -> &Core.list_sealed_daily_aggregate_history/5
      end

    result =
      if is_function(reader, 5) do
        reader.(
          product_id,
          calculation_version,
          Date.add(aggregate.aggregate_date, -30),
          Date.add(aggregate.aggregate_date, -1),
          []
        )
      else
        {:error, :history_read_failed}
      end

    case result do
      {:ok, history} -> {:ok, history}
      {:error, _} -> {:error, :history_read_failed}
      _ -> {:error, :history_read_failed}
    end
  end

  defp read_persisted_history(product_id, calculation_version, aggregate) do
    case Core.list_sealed_daily_aggregate_history(
           product_id,
           calculation_version,
           Date.add(aggregate.aggregate_date, -30),
           Date.add(aggregate.aggregate_date, -1)
         ) do
      {:ok, history} -> {:ok, history}
      {:error, _} -> {:error, :history_read_failed}
    end
  end

  defp persist(aggregate, source_fingerprint, history_fingerprint, result) do
    centers = Map.get(result, :component_centers, %{})

    attrs = %{
      source_aggregate_id: aggregate.id,
      expected_source_aggregate_date: aggregate.aggregate_date,
      expected_source_aggregate_calculated_at: aggregate.calculated_at,
      expected_source_aggregate_fingerprint: source_fingerprint,
      expected_source_history_fingerprint: history_fingerprint,
      model_version: result.model_version,
      currency: result.currency,
      status: result.status,
      limited_reason: result.limited_reason,
      reference_price_pln: result.reference_price_pln,
      great_price_max_pln: result.great_price_max_pln,
      fair_price_max_pln: result.fair_price_max_pln,
      expensive_price_max_pln: result.expensive_price_max_pln,
      confidence: result.confidence,
      trend: result.trend,
      trend_change: result.trend_change,
      availability: result.availability,
      availability_trend: result.availability_trend,
      regular_benchmark_pln: centers[:regular_benchmark],
      msrp_pln: centers[:msrp],
      lgs_median_pln: centers[:lgs_median],
      sold_out_center_pln: centers[:sold_out_center],
      explanation_factors: result.explanation_factors,
      calculated_at: aggregate.calculated_at
    }

    case Core.record_sealed_buying_guide_snapshot(attrs) do
      {:ok, _} -> :ok
      {:error, %Ash.Error.Invalid{} = error} -> classify_invalid_persistence(error, aggregate)
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp classify_invalid_persistence(error, aggregate) do
    if stale_source_revision?(error),
      do: enqueue_latest_successor(aggregate),
      else: {:cancel, :persistence_invalid}
  end

  defp enqueue_latest_successor(aggregate) do
    case Core.get_latest_sealed_daily_aggregate(
           aggregate.sealed_product_id,
           aggregate.calculation_version,
           aggregate.aggregate_date
         ) do
      {:ok, nil} ->
        {:cancel, :source_aggregate_not_found}

      {:ok, latest} ->
        with {:ok, changeset} <- new_for_aggregate(latest),
             {:ok, _job} <- Oban.insert(changeset) do
          :ok
        else
          _ -> {:error, :successor_enqueue_failed}
        end

      _ ->
        {:error, :successor_enqueue_failed}
    end
  end

  defp stale_source_revision?(%Ash.Error.Changes.StaleRecord{}), do: true

  defp stale_source_revision?(%{errors: errors}) when is_list(errors),
    do: Enum.any?(errors, &stale_source_revision?/1)

  defp stale_source_revision?(_), do: false
end
