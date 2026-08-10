defmodule TcgCheap.Operations.Changes.SourceHealthLifecycle do
  @moduledoc "Serializes run lifecycle updates and keeps source health derived from durable events."
  use Ash.Resource.Change

  @categories ~w(budget rate_limit timeout transport provider_response persistence configuration local_input unknown)
  alias TcgCheap.Operations.AcquisitionBudget
  alias TcgCheap.Operations.AcquisitionHealthPolicy
  alias TcgCheap.Operations.ProviderSourceHealthLock

  @impl true
  def init(opts) do
    if Keyword.get(opts, :event) in [:start, :finish, :reconcile],
      do: {:ok, opts},
      else: {:error, "event must be start, finish, or reconcile"}
  end

  @impl true
  def change(changeset, opts, _context) do
    event = Keyword.fetch!(opts, :event)

    changeset
    |> lock_running_attempt(event)
    |> Ash.Changeset.after_action(fn changeset, result ->
      provider = Ash.Changeset.get_attribute(changeset, :provider_key)

      completed_at =
        Ash.Changeset.get_attribute(
          changeset,
          if(event == :start, do: :started_at, else: :finished_at)
        )

      update_health(provider, event, changeset, completed_at)
      {:ok, result}
    end)
  end

  defp lock_running_attempt(changeset, :start) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      provider = Ash.Changeset.get_attribute(changeset, :provider_key)
      job_id = Ash.Changeset.get_attribute(changeset, :job_id)
      attempt = Ash.Changeset.get_attribute(changeset, :attempt)

      lock_source_health(provider)
      started_at = DateTime.utc_now()

      if is_integer(job_id) do
        reconcile_stranded_attempts(provider, job_id, attempt, started_at)
      end

      Ash.Changeset.force_change_attribute(changeset, :started_at, started_at)
    end)
  end

  defp lock_running_attempt(changeset, :reconcile) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      provider = Ash.Changeset.get_data(changeset, :provider_key)
      lock_source_health(provider)
      changeset
    end)
  end

  defp lock_running_attempt(changeset, :finish) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      provider = Ash.Changeset.get_data(changeset, :provider_key)
      id = Ash.Changeset.get_data(changeset, :id)

      lock_source_health(provider)

      case TcgCheap.Repo.query(
             "SELECT status FROM acquisition_runs WHERE id = $1 FOR UPDATE",
             [Ecto.UUID.dump!(id)]
           ) do
        {:ok, %{rows: [["running"]]}} ->
          Ash.Changeset.force_change_attribute(changeset, :finished_at, DateTime.utc_now())

        _ ->
          Ash.Changeset.add_error(changeset, message: "acquisition run is already finished")
      end
    end)
  end

  defp update_health(provider, :start, _changeset, now) do
    lock_source_health(provider)

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_source_health (id, provider_key, last_started_at, consecutive_failures, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 0, now(), now()) ON CONFLICT (provider_key) DO UPDATE SET last_started_at = GREATEST(acquisition_source_health.last_started_at, EXCLUDED.last_started_at), updated_at = now()",
      [provider, now]
    )
  end

  defp update_health(provider, event, changeset, now) when event in [:finish, :reconcile] do
    status = Ash.Changeset.get_attribute(changeset, :status)
    category = Ash.Changeset.get_attribute(changeset, :failure_category)
    if category not in [nil | @categories], do: raise(ArgumentError, "invalid failure category")

    case status do
      "succeeded" ->
        record_success!(provider, now)

      status
      when status in ["retryable_failure", "failed", "cancelled"] and event == :reconcile ->
        record_reconciliation_failure!(provider, now, status, category, changeset)

      status when status in ["retryable_failure", "failed", "cancelled"] ->
        record_failure!(provider, now, status, category)

      _ ->
        raise ArgumentError, "invalid acquisition run status"
    end
  end

  defp record_success!(provider, now) do
    result =
      TcgCheap.Repo.query!(
        "UPDATE acquisition_source_health SET last_status = 'succeeded', last_succeeded_at = $2, last_failure_category = NULL, consecutive_failures = 0, circuit_failure_streak = CASE WHEN circuit_opened_at IS NULL THEN 0 ELSE circuit_failure_streak END, updated_at = now() WHERE provider_key = $1",
        [provider, now]
      )

    verify_health_updated!(result)
  end

  defp record_failure!(provider, now, status, category) do
    circuit_increment =
      if AcquisitionHealthPolicy.circuit_eligible_category?(category), do: 1, else: 0

    result =
      TcgCheap.Repo.query!(
        "UPDATE acquisition_source_health SET last_failed_at = $2, last_status = $3, last_failure_category = $4, consecutive_failures = consecutive_failures + 1, circuit_failure_streak = circuit_failure_streak + $5, updated_at = now() WHERE provider_key = $1 RETURNING circuit_failure_streak, circuit_opened_at",
        [provider, now, status, category, circuit_increment]
      )

    verify_health_updated!(result)

    if status in ["failed", "cancelled"] and
         AcquisitionHealthPolicy.circuit_eligible_category?(category),
       do: maybe_open_circuit!(provider, now, result.rows)
  end

  defp record_reconciliation_failure!(provider, now, status, category, changeset) do
    started_at = Ash.Changeset.get_attribute(changeset, :started_at)

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_source_health (id, provider_key, last_started_at, last_failed_at, last_status, last_failure_category, consecutive_failures, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, 1, now(), now()) ON CONFLICT (provider_key) DO UPDATE SET last_started_at = GREATEST(acquisition_source_health.last_started_at, EXCLUDED.last_started_at), last_failed_at = EXCLUDED.last_failed_at, last_status = EXCLUDED.last_status, last_failure_category = EXCLUDED.last_failure_category, consecutive_failures = acquisition_source_health.consecutive_failures + 1, updated_at = now()",
      [provider, started_at, now, status, category]
    )
  end

  defp verify_health_updated!(result) do
    case result do
      %{num_rows: 1} -> :ok
      _ -> raise "acquisition source health row is missing"
    end
  end

  defp lock_source_health(provider) do
    ProviderSourceHealthLock.lock_source!(provider)
  end

  defp maybe_open_circuit!(provider, now, [[streak, nil]]) do
    {:ok, policy} = AcquisitionHealthPolicy.load()

    if streak >= policy.circuit_breaker_failure_threshold,
      do: disable_active_provider!(provider, now),
      else: :ok
  end

  defp maybe_open_circuit!(_provider, _now, _rows), do: :ok

  defp disable_active_provider!(provider, now) do
    case lock_or_register_provider!(provider) do
      %{rows: [[id, "active"]]} ->
        provider_update =
          TcgCheap.Repo.query!(
            "UPDATE acquisition_data_providers SET status = 'disabled', updated_at = now() WHERE id = $1 AND status = 'active'",
            [id]
          )

        if provider_update.num_rows != 1, do: raise("provider circuit transition failed")

        health_update =
          TcgCheap.Repo.query!(
            "UPDATE acquisition_source_health SET circuit_opened_at = $2, updated_at = now() WHERE provider_key = $1 AND circuit_opened_at IS NULL",
            [provider, now]
          )

        if health_update.num_rows != 1, do: raise("source circuit transition failed")

      _ ->
        :ok
    end
  end

  defp lock_or_register_provider!(provider) do
    case ProviderSourceHealthLock.lock_provider!(provider) do
      %{rows: []} ->
        case AcquisitionBudget.register_configured_provider(provider) do
          {:ok, _provider} -> ProviderSourceHealthLock.lock_provider!(provider)
          {:error, reason} -> raise "provider circuit registration failed: #{inspect(reason)}"
        end

      result ->
        result
    end
  end

  defp reconcile_stranded_attempts(provider, job_id, attempt, started_at) do
    result =
      TcgCheap.Repo.query!(
        "WITH stranded AS (SELECT id FROM acquisition_runs WHERE provider_key = $1 AND job_id = $2 AND attempt < $3 AND status = 'running' FOR UPDATE) UPDATE acquisition_runs SET status = 'failed', failure_category = 'unknown', finished_at = $4, updated_at = now() WHERE id IN (SELECT id FROM stranded)",
        [provider, job_id, attempt, started_at]
      )

    if result.num_rows > 0 do
      TcgCheap.Repo.query!(
        "INSERT INTO acquisition_source_health (id, provider_key, last_started_at, last_failed_at, last_status, last_failure_category, consecutive_failures, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $2, 'failed', 'unknown', $3, now(), now()) ON CONFLICT (provider_key) DO UPDATE SET last_started_at = GREATEST(acquisition_source_health.last_started_at, EXCLUDED.last_started_at), last_failed_at = EXCLUDED.last_failed_at, last_status = 'failed', last_failure_category = 'unknown', consecutive_failures = acquisition_source_health.consecutive_failures + EXCLUDED.consecutive_failures, updated_at = now()",
        [provider, started_at, result.num_rows]
      )
    end
  end
end
