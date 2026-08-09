defmodule TcgCheap.Pricing.SealedDailyAggregateWorker do
  @moduledoc "Daily local-only sealed-market aggregate worker."
  use Oban.Worker,
    queue: :sealed_aggregates,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Core
  alias TcgCheap.Pricing.{SealedBuyingGuideWorker, SealedDailyAggregateCalculator}
  alias TcgCheap.Repo

  @impl true
  def perform(%Oban.Job{args: args}) do
    with :ok <- validate_args(args),
         {:ok, as_of} <- clock(),
         {:ok, products} <- Core.list_public_sealed_products(),
         :ok <- process(products, as_of) do
      :ok
    else
      {:cancel, reason} -> {:cancel, reason}
      {:retry, reason} -> {:error, reason}
      {:error, %Ash.Error.Invalid{}} -> {:cancel, :persistence_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp validate_args(%{} = args) when map_size(args) == 0, do: :ok
  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp clock do
    case Application.get_env(:tcg_cheap, :sealed_daily_aggregate_clock, &DateTime.utc_now/0) do
      clock when is_function(clock, 0) -> safely_clock(clock)
      _ -> {:cancel, :invalid_clock_configuration}
    end
  end

  defp safely_clock(clock) do
    case clock.() do
      %DateTime{} = value -> {:ok, value}
      _ -> {:cancel, :invalid_clock}
    end
  rescue
    _ -> {:cancel, :invalid_clock}
  catch
    _, _ -> {:cancel, :invalid_clock}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity,Credo.Check.Refactor.Nesting
  defp process(products, as_of) when is_list(products) do
    Enum.reduce_while(products, :ok, fn product, :ok ->
      case product_id(product) do
        {:ok, _id} -> process_product(product, as_of)
        {:error, reason} -> {:cancel, reason}
      end
      |> case do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
        {:cancel, reason} -> {:halt, {:cancel, reason}}
      end
    end)
  end

  defp process(_products, _as_of), do: {:cancel, :malformed_products}

  defp process_product(%{id: product_id} = product, as_of) do
    case Core.list_public_listing_mappings_for_product(product_id) do
      {:ok, []} ->
        :ok

      {:ok, mappings} ->
        with {:ok, offers, evidence, mapping_confident} <- mapping_offers(mappings, as_of),
             {:ok, attrs} <- SealedDailyAggregateCalculator.calculate(offers, as_of) do
          attrs =
            attrs
            |> Map.put(:source_evidence, evidence)
            |> Map.put(:source_mapping_confident, mapping_confident)
            |> Map.put(:source_msrp_pln, Map.get(product, :msrp_pln))

          persist_and_enqueue(product_id, attrs)
        else
          {:skip, _reason} -> :ok
          {:error, reason} -> {:cancel, reason}
        end

      {:error, _} ->
        {:error, :mapping_read_failed}
    end
  end

  defp product_id(%{id: id}) when is_binary(id), do: {:ok, id}
  defp product_id(_), do: {:error, :malformed_product}

  defp mapping_offers(mappings, as_of) when is_list(mappings) and is_struct(as_of, DateTime) do
    with :ok <- validate_approval_times(mappings),
         eligible <- Enum.filter(mappings, &approved_as_of?(&1, as_of)) do
      mapping_offers_eligible(eligible, as_of)
    end
  end

  defp mapping_offers(_, _), do: {:error, :malformed_mappings}

  defp mapping_offers_eligible(eligible, _as_of) when eligible == [],
    do: {:skip, :no_eligible_mapping}

  defp mapping_offers_eligible(eligible, as_of) do
    with {:ok, mapping_confident} <- mapping_confidence(eligible),
         {:ok, %{current: current, sold_out: sold_out, evidence: evidence}} <-
           collect_mapping_offers(eligible) do
      {:ok, %{current: Enum.reverse(current), sold_out: Enum.reverse(sold_out)},
       evidence
       |> Enum.filter(&retained_evidence?(&1, as_of))
       |> Enum.sort_by(&evidence_sort_key/1), mapping_confident}
    end
  end

  defp collect_mapping_offers(mappings) do
    Enum.reduce_while(
      mappings,
      {:ok, %{current: [], sold_out: [], evidence: []}},
      &collect_mapping_offer/2
    )
  end

  defp collect_mapping_offer(mapping, {:ok, acc}) do
    case mapping_offer(mapping) do
      {:ok, status, offer, evidence} ->
        {:cont,
         {:ok,
          acc
          |> Map.update!(status, &[offer | &1])
          |> Map.update!(:evidence, &[evidence | &1])}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp mapping_offer(
         %{
           id: _mapping_id,
           status: "matched",
           retailer_listing:
             %{stock_status: status, retailer: %{id: id, category: category} = retailer} = listing
         } = mapping
       )
       when status in ["in_stock", "sold_out"] and is_binary(id) and
              category in ["regular_retailer", "lgs"] do
    offer = %{listing: listing, retailer: retailer}

    {:ok, status_key(status), offer, evidence(mapping, listing, retailer)}
  end

  defp mapping_offer(_), do: {:error, :malformed_mapping}

  defp approved_as_of?(%{approved_at: %DateTime{} = approved_at}, as_of),
    do: DateTime.compare(approved_at, as_of) != :gt

  defp approved_as_of?(_, _), do: false

  defp validate_approval_times(mappings) do
    if Enum.all?(mappings, &match?(%{approved_at: %DateTime{}}, &1)),
      do: :ok,
      else: {:error, :malformed_mapping}
  end

  defp mapping_confidence(mappings) do
    Enum.reduce_while(mappings, {:ok, true}, fn
      %{confidence: %Decimal{} = confidence}, {:ok, confident?} ->
        if finite_unit_confidence?(confidence) do
          {:cont, {:ok, confident? and Decimal.equal?(confidence, Decimal.new("1"))}}
        else
          {:halt, {:error, :malformed_mapping}}
        end

      _, _ ->
        {:halt, {:error, :malformed_mapping}}
    end)
  end

  defp finite_unit_confidence?(value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt and
        Decimal.compare(value, Decimal.new(1)) != :gt

  defp evidence(mapping, listing, retailer) do
    %{
      mapping_id: mapping.id,
      confidence: mapping.confidence,
      approved_at: mapping.approved_at,
      listing_id: listing.id,
      retailer_id: retailer.id,
      retailer_category: retailer.category,
      stock_status: listing.stock_status,
      price_pln: Map.get(listing, :current_price_pln),
      checked_at: listing.last_checked_at
    }
  end

  defp retained_evidence?(%{stock_status: "in_stock"}, _as_of), do: true

  defp retained_evidence?(
         %{stock_status: "sold_out", checked_at: %DateTime{} = checked_at},
         as_of
       ) do
    DateTime.diff(as_of, checked_at, :second) in 0..(30 * 86_400)
  end

  defp retained_evidence?(_, _), do: false

  defp evidence_sort_key(evidence),
    do: {
      evidence.stock_status,
      evidence.retailer_id,
      evidence.checked_at,
      evidence.listing_id,
      evidence.mapping_id
    }

  defp status_key("in_stock"), do: :current
  defp status_key("sold_out"), do: :sold_out

  defp persist_and_enqueue(product_id, attrs) do
    product_id
    |> persist_transaction(attrs)
    |> finish_persistence()
  end

  defp persist_transaction(product_id, attrs) do
    Repo.transaction(fn ->
      Core.record_sealed_daily_aggregate(
        Map.put(attrs, :sealed_product_id, product_id),
        return_notifications?: true
      )
      |> persist_aggregate_result()
    end)
  end

  defp persist_aggregate_result({:ok, aggregate, notifications}) do
    case enqueue_dependent_guides(aggregate) do
      :ok -> {aggregate, notifications}
      result -> Repo.rollback(result)
    end
  end

  defp persist_aggregate_result({:error, %Ash.Error.Invalid{}}),
    do: Repo.rollback({:cancel, :persistence_invalid})

  defp persist_aggregate_result({:error, _}),
    do: Repo.rollback({:error, :persistence_failed})

  defp finish_persistence(result) do
    case result do
      {:ok, {_aggregate, notifications}} ->
        Ash.Notifier.notify(notifications)
        :ok

      {:error, {:cancel, reason}} ->
        {:cancel, reason}

      {:error, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp enqueue_dependent_guides(aggregate) do
    through_date = Date.add(aggregate.aggregate_date, 30)

    case Core.list_sealed_daily_aggregate_guide_dependents(
           aggregate.sealed_product_id,
           aggregate.calculation_version,
           aggregate.aggregate_date,
           through_date
         ) do
      {:ok, dependents} when is_list(dependents) ->
        enqueue_dependent_guide_jobs(dependents, aggregate.id)

      _ ->
        {:error, :guide_dependency_read_failed}
    end
  end

  defp enqueue_dependent_guide_jobs(dependents, source_aggregate_id) do
    if Enum.any?(dependents, &(&1.id == source_aggregate_id)) do
      Enum.reduce_while(dependents, :ok, &enqueue_dependent_guide/2)
    else
      {:cancel, :missing_persisted_aggregate}
    end
  end

  defp enqueue_dependent_guide(aggregate, :ok) do
    case enqueue_guide(aggregate) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp enqueue_guide(aggregate) do
    with {:ok, job_changeset} <- SealedBuyingGuideWorker.new_for_aggregate(aggregate),
         {:ok, _job} <- enqueue_job(job_changeset) do
      :ok
    else
      {:error, :malformed_aggregate_revision} -> {:cancel, :malformed_aggregate_revision}
      {:error, _} -> {:error, :guide_enqueue_failed}
    end
  end

  defp enqueue_job(changeset) do
    enqueuer =
      case Application.fetch_env(:tcg_cheap, :sealed_daily_aggregate_enqueue) do
        {:ok, configured} -> configured
        :error -> &Oban.insert/1
      end

    case enqueuer do
      fun when is_function(fun, 1) -> fun.(changeset)
      _ -> {:error, :invalid_enqueue_configuration}
    end
  end
end
