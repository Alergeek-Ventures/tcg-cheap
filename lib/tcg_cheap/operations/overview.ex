defmodule TcgCheap.Operations.Overview do
  @moduledoc "The authenticated, bounded query and control boundary for operations UI."

  alias TcgCheap.Accounts.{Admin, AdminActor}
  alias TcgCheap.Operations.{AcquisitionBudget, AcquisitionHealthPolicy, DataProvider}

  @default_job_limit 25
  @max_job_limit 50
  @default_run_limit 25
  @max_run_limit 50
  @job_states ~w(retryable discarded cancelled)
  @failure_categories [
    {"Timeout", ["timeout"]},
    {"Rate limited", ["rate limit", "429"]},
    {"Acquisition budget rejected", ["budget"]},
    {"Provider authorization rejected", ["unauthorized", "forbidden"]},
    {"Provider transport failure", ["connection", "transport", "socket"]},
    {"Persistence failure", ["postgres", "database"]}
  ]

  @spec load(Admin.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(actor, opts \\ [])

  def load(%Admin{} = actor, opts) do
    with :ok <- validate_actor(actor),
         {:ok, clock, job_limit, run_limit} <- parse_options(opts),
         {:ok, health_policy} <- AcquisitionHealthPolicy.load(),
         {:ok, config} <- AcquisitionBudget.configured_limits(),
         {:ok, health_policy} <-
           AcquisitionHealthPolicy.validate_provider_keys(
             health_policy,
             Enum.map(config.providers, & &1.provider_key)
           ),
         {:ok, providers} <- list_providers(actor, config.providers),
         {:ok, health} <- source_health(actor, config.providers),
         {:ok, runs} <- recent_runs(actor, config.providers, run_limit),
         {:ok, jobs} <- recent_jobs(job_limit),
         {:ok, now} <- valid_clock(clock),
         {:ok, windows} <- current_windows(actor, providers, now),
         {:ok, global_usage} <- global_current_usage(now),
         {:ok, health} <- validate_source_health(health, now) do
      projected_runs = Enum.map(runs, &run_projection(&1, health_policy, now))

      {:ok,
       build_overview(config, %{
         providers: providers,
         windows: windows,
         global_usage: global_usage,
         health: health,
         runs: projected_runs,
         jobs: jobs,
         health_policy: health_policy,
         now: now
       })}
    else
      {:error, _} = error -> error
    end
  rescue
    error -> {:error, {:overview_query_failed, error}}
  end

  def load(_, _), do: {:error, :invalid_actor}

  @doc "Changes a configured provider status using only server-side configuration."
  def set_provider_status(actor, provider_key, status, expected_updated_at \\ nil)

  def set_provider_status(%Admin{} = actor, provider_key, status, expected_updated_at) do
    with :ok <- validate_actor(actor),
         {:ok, config} <- AcquisitionBudget.configured_limits(),
         {:ok, provider_config} <- configured_provider(config, provider_key),
         true <- status in ["active", "disabled"] do
      case TcgCheap.Operations.get_provider_by_key(provider_key, authorize?: false) do
        {:ok, nil} ->
          register_then_disable(actor, provider_config, status, expected_updated_at)

        {:ok, provider} ->
          transition(actor, provider, provider_config, status, expected_updated_at)

        {:error, reason} ->
          {:error, reason}
      end
    else
      false -> {:error, :invalid_provider_status}
      {:error, _} = error -> error
    end
  rescue
    error -> {:error, {:provider_control_failed, error}}
  end

  def set_provider_status(_, _, _, _), do: {:error, :invalid_actor}

  defp transition(_actor, _provider, _config, "active", nil),
    do: {:error, :missing_expected_updated_at}

  defp transition(_actor, _provider, _config, "disabled", nil),
    do: {:error, :missing_expected_updated_at}

  defp transition(_actor, %{status: status}, _config, status, _expected),
    do: {:error, :stale_expected_updated_at}

  defp transition(actor, provider, _config, status, expected) do
    action = if status == "active", do: :enable, else: :disable

    provider
    |> Ash.Changeset.for_update(action, %{expected_updated_at: expected})
    |> Ash.update(actor: actor)
  end

  defp register_then_disable(_actor, _config, "active", _expected),
    do: {:error, :already_effectively_active}

  defp register_then_disable(actor, config, "disabled", expected) when expected in [nil, ""] do
    with {:ok, provider} <-
           Ash.create(DataProvider, Map.take(config, provider_keys()),
             action: :register,
             authorize?: false
           ) do
      provider
      |> Ash.Changeset.for_update(:disable, %{
        expected_updated_at: persisted_updated_at(provider.id)
      })
      |> Ash.update(actor: actor)
    end
  end

  defp register_then_disable(_actor, _config, "disabled", _expected),
    do: {:error, :stale_expected_updated_at}

  defp configured_provider(config, key) when is_binary(key) do
    case Enum.find(config.providers, &(&1.provider_key == key)) do
      nil ->
        {:error, :invalid_provider_key}

      provider ->
        {:ok, Map.put(provider, :global_monthly_spend_limit, config.global_monthly_spend_limit)}
    end
  end

  defp configured_provider(_, _), do: {:error, :invalid_provider_key}

  defp list_providers(actor, configured_providers) do
    provider_keys = Enum.map(configured_providers, & &1.provider_key)

    case TcgCheap.Operations.list_providers(provider_keys, actor: actor) do
      {:ok, providers} -> {:ok, providers}
      {:error, reason} -> {:error, {:provider_query_failed, reason}}
    end
  end

  defp validate_actor(%Admin{} = actor), do: AdminActor.validate(actor)

  defp parse_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:clock, :max_recent_jobs, :max_recent_runs])) and
         (not Keyword.has_key?(opts, :clock) or is_function(opts[:clock], 0)) do
      job_limit = Keyword.get(opts, :max_recent_jobs, @default_job_limit)
      run_limit = Keyword.get(opts, :max_recent_runs, @default_run_limit)

      if is_integer(job_limit) and job_limit in 1..@max_job_limit and is_integer(run_limit) and
           run_limit in 1..@max_run_limit,
         do: {:ok, Keyword.get(opts, :clock, &DateTime.utc_now/0), job_limit, run_limit},
         else: {:error, :invalid_limit}
    else
      {:error, :invalid_overview_input}
    end
  end

  defp parse_options(_), do: {:error, :invalid_overview_input}

  defp valid_clock(clock) when is_function(clock, 0) do
    case clock.() do
      %DateTime{time_zone: "Etc/UTC"} = now -> {:ok, now}
      _ -> {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp valid_clock(_), do: {:error, :invalid_clock}

  defp current_windows(actor, providers, %DateTime{} = now) do
    {hour, day, month} = window_starts(now)
    provider_ids = Enum.map(providers, & &1.id)

    case TcgCheap.Operations.list_current_budget_windows(provider_ids, hour, day, month,
           actor: actor
         ) do
      {:ok, windows} -> {:ok, windows}
      {:error, reason} -> {:error, {:usage_query_failed, reason}}
    end
  end

  defp source_health(actor, configured_providers) do
    provider_keys = Enum.map(configured_providers, & &1.provider_key)

    case TcgCheap.Operations.list_source_health(provider_keys, actor: actor) do
      {:ok, health} -> {:ok, health}
      {:error, reason} -> {:error, {:source_health_query_failed, reason}}
    end
  end

  defp validate_source_health(health, now) do
    if Enum.all?(health, &valid_source_health?(&1, now)),
      do: {:ok, health},
      else: {:error, :invalid_source_health_evidence}
  end

  defp valid_source_health?(health, now) do
    valid_health_times?(health, now) and valid_health_state?(health)
  end

  defp valid_health_times?(health, now) do
    valid_past_time?(health.last_started_at, now) and
      valid_optional_past_time?(health.last_succeeded_at, now) and
      valid_optional_past_time?(health.last_failed_at, now)
  end

  defp valid_health_state?(%{last_status: nil} = health) do
    is_nil(health.last_succeeded_at) and is_nil(health.last_failed_at) and
      is_nil(health.last_failure_category) and health.consecutive_failures == 0
  end

  defp valid_health_state?(%{last_status: "succeeded"} = health) do
    not is_nil(health.last_succeeded_at) and is_nil(health.last_failure_category) and
      health.consecutive_failures == 0 and
      nondecreasing_evidence?(health.last_succeeded_at, health.last_failed_at)
  end

  defp valid_health_state?(%{last_status: status} = health)
       when status in ["retryable_failure", "failed", "cancelled"] do
    not is_nil(health.last_failed_at) and
      health.last_failure_category in ~w(budget rate_limit timeout transport provider_response persistence configuration local_input unknown) and
      is_integer(health.consecutive_failures) and health.consecutive_failures > 0 and
      nondecreasing_evidence?(health.last_failed_at, health.last_succeeded_at)
  end

  defp valid_health_state?(_), do: false

  defp valid_optional_past_time?(nil, _now), do: true
  defp valid_optional_past_time?(value, now), do: valid_past_time?(value, now)

  defp nondecreasing_evidence?(_latest, nil), do: true

  defp nondecreasing_evidence?(latest, previous) do
    DateTime.compare(latest, previous) in [:eq, :gt]
  end

  defp valid_past_time?(%DateTime{time_zone: "Etc/UTC"} = value, now),
    do: DateTime.compare(value, now) != :gt

  defp valid_past_time?(_, _now), do: false

  defp recent_runs(actor, configured_providers, limit) do
    provider_keys = Enum.map(configured_providers, & &1.provider_key)

    case TcgCheap.Operations.list_recent_acquisition_runs(provider_keys, limit, actor: actor) do
      {:ok, runs} -> {:ok, runs}
      {:error, reason} -> {:error, {:acquisition_run_query_failed, reason}}
    end
  end

  defp global_current_usage(%DateTime{} = now) do
    {hour, day, month} = window_starts(now)

    result =
      TcgCheap.Repo.query(
        "SELECT window_kind, SUM(request_count)::bigint, SUM(estimated_spend_usd) FROM acquisition_budget_usages WHERE (window_kind = 'hour' AND window_started_at = $1) OR (window_kind = 'day' AND window_started_at = $2) OR (window_kind = 'month' AND window_started_at = $3) GROUP BY window_kind ORDER BY window_kind",
        [hour, day, month]
      )

    case result do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &global_usage_projection/1)}
      {:error, reason} -> {:error, {:usage_query_failed, reason}}
    end
  end

  defp window_starts(%DateTime{} = now) do
    hour = %DateTime{now | minute: 0, second: 0, microsecond: {0, 0}}
    day = %DateTime{hour | hour: 0}
    month = DateTime.new!(Date.new!(now.year, now.month, 1), ~T[00:00:00], "Etc/UTC")
    {hour, day, month}
  end

  defp build_overview(config, %{
         providers: persisted,
         windows: windows,
         global_usage: global_usage,
         health: health,
         runs: runs,
         jobs: jobs,
         health_policy: health_policy,
         now: now
       }) do
    by_provider = Map.new(persisted, &{&1.provider_key, &1})
    usage = Enum.group_by(windows, & &1.provider_id)
    health_by_provider = Map.new(health, &{&1.provider_key, &1})

    providers =
      Enum.map(config.providers, fn configured ->
        persisted_provider = by_provider[configured.provider_key]
        rows = if persisted_provider, do: Map.get(usage, persisted_provider.id, []), else: []

        %{
          provider_key: configured.provider_key,
          display_name: configured.display_name,
          estimated_cost_per_request: configured.estimated_cost_per_request,
          hourly_request_limit: configured.hourly_request_limit,
          daily_request_limit: configured.daily_request_limit,
          monthly_request_limit: configured.monthly_request_limit,
          monthly_spend_limit: configured.monthly_spend_limit,
          persisted?: not is_nil(persisted_provider),
          updated_at: persisted_provider && persisted_provider.updated_at,
          status: (persisted_provider && persisted_provider.status) || "active",
          current_usage: usage_summary(rows),
          health: health_projection(health_by_provider[configured.provider_key]),
          source_state:
            AcquisitionHealthPolicy.provider_state(
              health_policy,
              configured.provider_key,
              last_succeeded_at(health_by_provider[configured.provider_key]),
              now
            )
        }
      end)

    global =
      global_summary(global_usage)
      |> Map.put(:limits, %{
        hourly_request_limit: config.global_hourly_request_limit,
        daily_request_limit: config.global_daily_request_limit,
        monthly_spend_limit: config.global_monthly_spend_limit
      })

    %{global: global, providers: providers, recent_runs: runs, recent_jobs: jobs}
  end

  defp health_projection(nil), do: nil

  defp health_projection(health) do
    %{
      last_started_at: health.last_started_at,
      last_succeeded_at: health.last_succeeded_at,
      last_failed_at: health.last_failed_at,
      last_status: health.last_status,
      last_failure_category: health.last_failure_category,
      consecutive_failures: health.consecutive_failures
    }
  end

  defp run_projection(run, health_policy, now) do
    %{
      id: run.id,
      provider_key: run.provider_key,
      operation: run.operation,
      target_key: run.target_key,
      worker: run.worker,
      queue: run.queue,
      job_id: run.job_id,
      attempt: run.attempt,
      max_attempts: run.max_attempts,
      status: run.status,
      failure_category: run.failure_category,
      request_count: run.request_count,
      started_at: run.started_at,
      finished_at: run.finished_at,
      overdue?:
        run.status == "running" and
          AcquisitionHealthPolicy.overdue?(
            run.started_at,
            now,
            health_policy.stranded_after_seconds
          )
    }
  end

  defp last_succeeded_at(nil), do: nil
  defp last_succeeded_at(health), do: health.last_succeeded_at

  defp usage_summary(rows) do
    Enum.reduce(rows, %{hour: zero(), day: zero(), month: zero()}, fn row, acc ->
      case row.window_kind do
        "hour" -> Map.put(acc, :hour, usage_value(row))
        "day" -> Map.put(acc, :day, usage_value(row))
        "month" -> Map.put(acc, :month, usage_value(row))
        _ -> acc
      end
    end)
  end

  defp global_summary(rows) do
    Enum.reduce(rows, %{hour: zero(), day: zero(), month: zero()}, fn row, acc ->
      case row.window_kind do
        "hour" -> Map.put(acc, :hour, usage_value(row))
        "day" -> Map.put(acc, :day, usage_value(row))
        "month" -> Map.put(acc, :month, usage_value(row))
        _ -> acc
      end
    end)
  end

  defp zero, do: %{request_count: 0, estimated_spend_usd: Decimal.new(0)}

  defp usage_value(row),
    do: %{request_count: row.request_count, estimated_spend_usd: row.estimated_spend_usd}

  defp global_usage_projection([window_kind, request_count, estimated_spend_usd]),
    do: %{
      window_kind: window_kind,
      request_count: request_count,
      estimated_spend_usd: estimated_spend_usd
    }

  defp persisted_updated_at(id) do
    TcgCheap.Repo.query!("SELECT updated_at FROM acquisition_data_providers WHERE id = $1", [
      Ecto.UUID.dump!(id)
    ]).rows
    |> List.first()
    |> List.first()
  end

  defp recent_jobs(limit) do
    result =
      TcgCheap.Repo.query(
        """
        SELECT
          id,
          state,
          queue,
          worker,
          attempt,
          max_attempts,
          LEFT(
            CASE jsonb_typeof(errors[array_length(errors, 1)])
              WHEN 'object' THEN COALESCE(
                errors[array_length(errors, 1)]->>'error',
                errors[array_length(errors, 1)]->>'message',
                errors[array_length(errors, 1)]->>'reason'
              )
              WHEN 'string' THEN errors[array_length(errors, 1)] #>> '{}'
              ELSE NULL
            END,
            500
          ) AS latest_error,
          COALESCE(cancelled_at, completed_at, discarded_at, attempted_at, inserted_at) AS observed_at
        FROM oban_jobs
        WHERE state = ANY($1)
        ORDER BY observed_at DESC NULLS LAST, id DESC
        LIMIT $2
        """,
        [@job_states, limit]
      )

    case result do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &job_projection/1)}
      {:error, reason} -> {:error, {:overview_query_failed, reason}}
    end
  end

  defp job_projection([
         id,
         state,
         queue,
         worker,
         attempt,
         max_attempts,
         latest_error,
         observed_at
       ]) do
    %{
      id: id,
      state: state,
      queue: queue,
      worker: worker,
      attempt: attempt,
      max_attempts: max_attempts,
      failure_category: failure_category(latest_error),
      observed_at: observed_at
    }
  end

  defp failure_category(nil), do: "No error detail retained"

  defp failure_category(error) when is_binary(error) do
    normalized = String.downcase(error)

    Enum.find_value(@failure_categories, "Worker failure", fn {category, fragments} ->
      Enum.any?(fragments, &String.contains?(normalized, &1)) && category
    end)
  end

  defp provider_keys,
    do: [
      :provider_key,
      :display_name,
      :estimated_cost_per_request,
      :hourly_request_limit,
      :daily_request_limit,
      :monthly_request_limit,
      :monthly_spend_limit
    ]
end
