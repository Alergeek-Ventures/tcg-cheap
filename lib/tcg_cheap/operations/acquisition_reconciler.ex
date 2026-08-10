defmodule TcgCheap.Operations.AcquisitionReconciler do
  @moduledoc "Reconciles durable acquisition attempts that outlived their workers."

  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionBudget
  alias TcgCheap.Operations.AcquisitionHealthPolicy
  alias TcgCheap.Operations.AcquisitionRun

  def run(opts \\ [])

  def run(opts) when is_list(opts) do
    with {:ok, clock} <- validate_options(opts),
         {:ok, config} <- AcquisitionBudget.configured_limits(),
         {:ok, policy} <- AcquisitionHealthPolicy.load(),
         {:ok, policy} <-
           AcquisitionHealthPolicy.validate_provider_keys(
             policy,
             Enum.map(config.providers, & &1.provider_key)
           ),
         {:ok, now} <- read_clock(clock),
         cutoff <- DateTime.add(now, -policy.stranded_after_seconds, :second),
         {:ok, count} <- reconcile_rows(cutoff, now, clock, policy.reconcile_limit) do
      {:ok, %{reconciled_count: count, cutoff: cutoff}}
    else
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :acquisition_reconciliation_persistence_failed}
  end

  def run(_), do: {:error, :invalid_acquisition_reconciler_options}

  defp validate_options([]), do: {:ok, &DateTime.utc_now/0}

  defp validate_options(clock: clock) when is_function(clock, 0), do: {:ok, clock}
  defp validate_options(_), do: {:error, :invalid_acquisition_reconciler_options}

  defp read_clock(clock) do
    case clock.() do
      %DateTime{time_zone: "Etc/UTC"} = now -> {:ok, now}
      _ -> {:error, :invalid_acquisition_reconciler_clock}
    end
  rescue
    _ -> {:error, :invalid_acquisition_reconciler_clock}
  catch
    _, _ -> {:error, :invalid_acquisition_reconciler_clock}
  end

  defp reconcile_rows(cutoff, observed_at, clock, limit) do
    TcgCheap.Repo.transaction(fn ->
      candidates = select_candidates(cutoff, limit)
      lock_sources(candidates)
      ids = lock_candidate_ids(candidates, cutoff)
      finished_at = finish_time(clock, observed_at)

      Enum.reduce(ids, 0, fn id, count ->
        reconcile_one(id, cutoff, finished_at, count)
      end)
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_time(clock, observed_at) do
    case read_clock(clock) do
      {:ok, finished_at} ->
        if DateTime.compare(finished_at, observed_at) == :lt,
          do: TcgCheap.Repo.rollback(:invalid_acquisition_reconciler_clock),
          else: finished_at

      {:error, reason} ->
        TcgCheap.Repo.rollback(reason)
    end
  end

  defp select_candidates(cutoff, limit) do
    case TcgCheap.Repo.query(
           "SELECT id::text, provider_key FROM acquisition_runs WHERE status = 'running' AND started_at <= $1 ORDER BY started_at ASC, id ASC LIMIT $2",
           [cutoff, limit]
         ) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [id, provider] -> {id, provider} end)
      {:error, _} -> TcgCheap.Repo.rollback(:acquisition_reconciliation_persistence_failed)
    end
  end

  defp lock_sources(candidates) do
    candidates
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(fn provider ->
      TcgCheap.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "tcg_cheap:source_health:" <> provider
      ])
    end)
  end

  defp lock_candidate_ids([], _cutoff), do: []

  defp lock_candidate_ids(candidates, cutoff) do
    ids = Enum.map(candidates, &Ecto.UUID.dump!(elem(&1, 0)))

    case TcgCheap.Repo.query(
           "SELECT id::text FROM acquisition_runs WHERE id = ANY($1::uuid[]) AND status = 'running' AND started_at <= $2 ORDER BY started_at ASC, id ASC FOR UPDATE SKIP LOCKED",
           [ids, cutoff]
         ) do
      {:ok, %{rows: rows}} -> Enum.map(rows, &List.first/1)
      {:error, _} -> TcgCheap.Repo.rollback(:acquisition_reconciliation_persistence_failed)
    end
  end

  defp reconcile_one(id, cutoff, finished_at, count) do
    run = Ash.get!(AcquisitionRun, id, action: :read, authorize?: false)

    case Operations.reconcile_stranded_acquisition_run(
           run,
           cutoff,
           finished_at,
           authorize?: false,
           return_notifications?: true
         ) do
      {:ok, _run} ->
        count + 1

      {:ok, _run, _notifications} ->
        count + 1

      {:error, _error} ->
        TcgCheap.Repo.rollback({:acquisition_reconciliation_persistence_failed, :action})
    end
  end
end
