defmodule TcgCheap.Operations.AcquisitionBudget do
  @moduledoc """
  Admission boundary for configured external acquisition worker attempts.

  The raw SQL transaction is intentionally narrow: one global admission transaction
  must span provider upsert/status locking, provider and global aggregate checks,
  and atomic window increments under one advisory lock. Normal provider and
  resource management remains behind the Operations code interfaces.
  """

  alias TcgCheap.Operations.DataProvider

  @global_lock_key "tcg_cheap:acquisition_budget:global"
  @top_level_keys [
    :global_daily_request_limit,
    :global_hourly_request_limit,
    :global_monthly_spend_limit,
    :providers
  ]
  @max_bigint 9_223_372_036_854_775_807
  @max_provider_count 100
  @provider_keys [
    :provider_key,
    :display_name,
    :estimated_cost_per_request,
    :hourly_request_limit,
    :daily_request_limit,
    :monthly_request_limit,
    :monthly_spend_limit
  ]

  @spec admit(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def admit(provider_key, opts \\ []) do
    with {:ok, config} <- provider_config(provider_key),
         {:ok, clock} <- parse_options(opts),
         {:ok, now} <- valid_clock(clock) do
      reserve(config, now)
    else
      {:error, reason} when reason in [:invalid_provider_configuration, :invalid_clock] ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :budget_persistence_failed}
  end

  @doc "Normalizes the admission result used by external-acquisition workers."
  @spec admit_attempt(String.t()) ::
          {:ok, map()}
          | {:error, :budget_persistence_failed | {:acquisition_budget_rejected, term()}}
  def admit_attempt(provider_key) do
    with {:ok, module} <- admission_module() do
      case module.admit(provider_key) do
        {:ok, admission} -> {:ok, admission}
        {:error, :budget_persistence_failed} -> {:error, :budget_persistence_failed}
        {:error, reason} -> {:error, {:acquisition_budget_rejected, reason}}
        _ -> {:error, {:acquisition_budget_rejected, :invalid_admission_result}}
      end
    end
  rescue
    _ -> {:error, :budget_persistence_failed}
  catch
    _, _ -> {:error, :budget_persistence_failed}
  end

  @doc "Admits one outbound provider request without exposing accounting details."
  @spec admit_request(String.t()) ::
          :ok | {:error, :budget_persistence_failed | {:acquisition_budget_rejected, term()}}
  def admit_request(provider_key) do
    case admit_attempt(provider_key) do
      {:ok, _admission} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Returns the complete, validated server-side acquisition configuration."
  @spec configured_limits() :: {:ok, map()} | {:error, :invalid_provider_configuration}
  def configured_limits do
    with config when is_list(config) <- Application.get_env(:tcg_cheap, :acquisition_budget),
         providers when is_list(providers) and length(providers) in 1..@max_provider_count <-
           Keyword.get(config, :providers),
         true <- valid_complete_config?(config, providers) do
      {:ok, configured_limits(config, providers)}
    else
      _ -> {:error, :invalid_provider_configuration}
    end
  rescue
    _ -> {:error, :invalid_provider_configuration}
  end

  defp configured_limits(config, providers) do
    %{
      global_hourly_request_limit: Keyword.get(config, :global_hourly_request_limit),
      global_daily_request_limit: Keyword.get(config, :global_daily_request_limit),
      global_monthly_spend_limit: decimal_value(Keyword.get(config, :global_monthly_spend_limit)),
      providers: Enum.map(providers, &normalize_provider(config, &1))
    }
  end

  defp normalize_provider(config, entry) do
    config
    |> normalize_config(entry)
    |> Map.drop([:global_monthly_spend_limit])
  end

  defp valid_complete_config?(config, providers) do
    provider_keys = Enum.map(providers, &Keyword.get(&1, :provider_key))

    valid_top_level_config?(config) and valid_global_limits?(config) and
      Enum.all?(providers, &valid_raw_provider_entry?(config, &1)) and
      Enum.uniq(provider_keys) == provider_keys
  end

  defp provider_config(provider_key)
       when is_binary(provider_key) and byte_size(provider_key) > 0 do
    with {:ok, config} <- configured_limits(),
         true <- provider_key == String.trim(provider_key),
         provider when is_map(provider) <-
           Enum.find(config.providers, &(&1.provider_key == provider_key)) do
      {:ok,
       provider
       |> Map.put(:global_hourly_request_limit, config.global_hourly_request_limit)
       |> Map.put(:global_daily_request_limit, config.global_daily_request_limit)
       |> Map.put(:global_monthly_spend_limit, config.global_monthly_spend_limit)}
    else
      _ -> {:error, :invalid_provider_configuration}
    end
  rescue
    _ -> {:error, :invalid_provider_configuration}
  end

  defp provider_config(_), do: {:error, :invalid_provider_configuration}

  defp valid_raw_provider_entry?(config, entry) when is_list(entry) do
    normalized = normalize_config(config, entry)

    valid_keys?(normalized) and valid_identity?(normalized) and valid_provider_limits?(normalized) and
      Decimal.compare(normalized.monthly_spend_limit, normalized.global_monthly_spend_limit) !=
        :gt
  rescue
    _ -> false
  end

  defp valid_raw_provider_entry?(_, _), do: false

  defp valid_top_level_config?(config) do
    keys = Keyword.keys(config)
    length(keys) == length(Enum.uniq(keys)) and Enum.sort(keys) == Enum.sort(@top_level_keys)
  end

  defp valid_keys?(entry),
    do: Enum.sort(Map.keys(entry) -- [:global_monthly_spend_limit]) == Enum.sort(@provider_keys)

  defp valid_global_limit?(global),
    do: finite_nonnegative?(global) and Decimal.compare(global, Decimal.new("50")) != :gt

  defp valid_global_limits?(config) do
    valid_global_limit?(decimal_value(Keyword.get(config, :global_monthly_spend_limit))) and
      positive_integer?(Keyword.get(config, :global_hourly_request_limit)) and
      positive_integer?(Keyword.get(config, :global_daily_request_limit)) and
      Keyword.get(config, :global_hourly_request_limit) <=
        Keyword.get(config, :global_daily_request_limit)
  end

  defp valid_identity?(entry),
    do:
      is_binary(entry.provider_key) and entry.provider_key == String.trim(entry.provider_key) and
        byte_size(entry.provider_key) in 1..160 and is_binary(entry.display_name) and
        entry.display_name == String.trim(entry.display_name) and
        byte_size(entry.display_name) in 1..240

  defp valid_provider_limits?(entry) do
    positive_integer?(entry.hourly_request_limit) and positive_integer?(entry.daily_request_limit) and
      positive_integer?(entry.monthly_request_limit) and
      entry.hourly_request_limit <= entry.daily_request_limit and
      entry.daily_request_limit <= entry.monthly_request_limit and
      valid_estimated_cost?(entry.estimated_cost_per_request) and
      finite_nonnegative?(entry.monthly_spend_limit) and
      Decimal.compare(entry.monthly_spend_limit, Decimal.new("50")) != :gt
  end

  defp normalize_config(config, entry) when is_list(entry) do
    if Keyword.keys(entry) |> Enum.sort() != Enum.sort(@provider_keys) do
      %{}
    else
      Map.new(entry)
      |> Map.put(
        :global_monthly_spend_limit,
        decimal_value(Keyword.get(config, :global_monthly_spend_limit))
      )
      |> Map.put(
        :estimated_cost_per_request,
        decimal_value(Keyword.get(entry, :estimated_cost_per_request))
      )
      |> Map.put(:monthly_spend_limit, decimal_value(Keyword.get(entry, :monthly_spend_limit)))
    end
  end

  defp normalize_config(_, _), do: []

  defp decimal_value(%Decimal{} = value), do: value
  defp decimal_value(value) when is_binary(value), do: Decimal.new(value)
  defp decimal_value(_), do: nil

  defp finite_nonnegative?(%Decimal{} = value) do
    value_string = Decimal.to_string(value)

    not Enum.any?(["NaN", "Inf"], &String.contains?(value_string, &1)) and
      Decimal.compare(value, Decimal.new(0)) != :lt
  rescue
    _ -> false
  end

  defp finite_nonnegative?(_), do: false
  defp positive_integer?(value), do: is_integer(value) and value in 1..@max_bigint

  defp valid_estimated_cost?(value) do
    finite_nonnegative?(value) and Decimal.compare(value, Decimal.new("1000000000")) == :lt
  end

  defp parse_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and (Keyword.keys(opts) == [:clock] or opts == []) and
         (opts == [] or is_function(Keyword.get(opts, :clock), 0)) do
      {:ok, Keyword.get(opts, :clock, &DateTime.utc_now/0)}
    else
      {:error, :invalid_clock}
    end
  end

  defp parse_options(_), do: {:error, :invalid_clock}

  defp valid_clock(clock) when is_function(clock, 0) do
    value = clock.()

    case value do
      %DateTime{time_zone: "Etc/UTC"} = value -> {:ok, value}
      _ -> {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp valid_clock(_), do: {:error, :invalid_clock}

  defp admission_module do
    module = Application.get_env(:tcg_cheap, :acquisition_budget_admitter, __MODULE__)

    if is_atom(module) and Code.ensure_loaded?(module) and function_exported?(module, :admit, 1),
      do: {:ok, module},
      else: {:error, {:acquisition_budget_rejected, :invalid_admission_configuration}}
  end

  defp reserve(config, %DateTime{} = now) do
    hour = DateTime.truncate(%DateTime{now | minute: 0, second: 0}, :second)
    day = DateTime.truncate(%DateTime{now | hour: 0, minute: 0, second: 0}, :second)
    month = DateTime.new!(Date.new!(now.year, now.month, 1), Time.new!(0, 0, 0), "Etc/UTC")
    cost = config.estimated_cost_per_request

    TcgCheap.Repo.transaction(fn ->
      TcgCheap.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [@global_lock_key])

      case Ash.create(DataProvider, Map.take(config, @provider_keys),
             action: :register,
             authorize?: false,
             return_notifications?: true
           ) do
        {:ok, _provider} -> :ok
        {:ok, _provider, _notifications} -> :ok
        {:error, _error} -> TcgCheap.Repo.rollback(:budget_persistence_failed)
      end

      provider = locked_provider(config.provider_key)
      if provider.status != "active", do: TcgCheap.Repo.rollback(:provider_disabled)

      usages = usage_totals(provider.id, hour, day, month)
      reject_if_over_limit(usages, provider, config, cost, month, hour, day)

      Enum.each(
        [{:hour, hour}, {:day, day}, {:month, month}],
        &increment_usage(provider.id, elem(&1, 0), elem(&1, 1), cost)
      )

      %{
        provider_key: provider.provider_key,
        admitted_at: now,
        estimated_cost_per_request: cost,
        windows: %{hour: hour, day: day, month: month}
      }
    end)
    |> case do
      {:ok, summary} ->
        {:ok, summary}

      {:error, reason}
      when reason in [
             :provider_disabled,
             :hourly_limit_reached,
             :daily_limit_reached,
             :monthly_request_limit_reached,
             :provider_monthly_spend_limit_reached,
             :global_monthly_spend_limit_reached,
             :global_hourly_limit_reached,
             :global_daily_limit_reached
           ] ->
        {:error, reason}

      _ ->
        {:error, :budget_persistence_failed}
    end
  rescue
    _ -> {:error, :budget_persistence_failed}
  end

  defp usage_totals(provider_id, hour, day, month) do
    result =
      TcgCheap.Repo.query!(
        "SELECT window_kind, request_count, estimated_spend_usd FROM acquisition_budget_usages WHERE provider_id = $1 AND ((window_kind = 'hour' AND window_started_at = $2) OR (window_kind = 'day' AND window_started_at = $3) OR (window_kind = 'month' AND window_started_at = $4))",
        [provider_id, hour, day, month]
      )

    Map.new(result.rows, fn [kind, count, spend] -> {kind, {count, spend}} end)
  end

  defp reject_if_over_limit(usages, provider, config, cost, month, hour, day) do
    {hour_count, _} = Map.get(usages, "hour", {0, Decimal.new(0)})
    {day_count, _} = Map.get(usages, "day", {0, Decimal.new(0)})
    {month_count, month_spend} = Map.get(usages, "month", {0, Decimal.new(0)})

    global_spend =
      TcgCheap.Repo.query!(
        "SELECT COALESCE(SUM(estimated_spend_usd), 0) FROM acquisition_budget_usages WHERE window_kind = 'month' AND window_started_at = $1",
        [month]
      ).rows
      |> List.first()
      |> List.first()

    global_counts =
      TcgCheap.Repo.query!(
        "SELECT window_kind, COALESCE(SUM(request_count), 0) FROM acquisition_budget_usages WHERE (window_kind = 'hour' AND window_started_at = $1) OR (window_kind = 'day' AND window_started_at = $2) GROUP BY window_kind",
        [hour, day]
      ).rows
      |> Map.new(fn [kind, count] -> {kind, Decimal.to_integer(count)} end)

    global_hour_count = Map.get(global_counts, "hour", 0)

    global_day_count = Map.get(global_counts, "day", 0)

    cond do
      hour_count >= provider.hourly_request_limit ->
        TcgCheap.Repo.rollback(:hourly_limit_reached)

      global_hour_count >= config.global_hourly_request_limit ->
        TcgCheap.Repo.rollback(:global_hourly_limit_reached)

      day_count >= provider.daily_request_limit ->
        TcgCheap.Repo.rollback(:daily_limit_reached)

      global_day_count >= config.global_daily_request_limit ->
        TcgCheap.Repo.rollback(:global_daily_limit_reached)

      month_count >= provider.monthly_request_limit ->
        TcgCheap.Repo.rollback(:monthly_request_limit_reached)

      Decimal.compare(Decimal.add(month_spend, cost), provider.monthly_spend_limit) == :gt ->
        TcgCheap.Repo.rollback(:provider_monthly_spend_limit_reached)

      Decimal.compare(Decimal.add(global_spend, cost), config.global_monthly_spend_limit) == :gt ->
        TcgCheap.Repo.rollback(:global_monthly_spend_limit_reached)

      true ->
        :ok
    end
  end

  defp locked_provider(provider_key) do
    case TcgCheap.Repo.query!(
           "SELECT id, provider_key, status, hourly_request_limit, daily_request_limit, monthly_request_limit, monthly_spend_limit FROM acquisition_data_providers WHERE provider_key = $1 FOR UPDATE",
           [provider_key]
         ).rows do
      [[id, key, status, hourly, daily, monthly, spend]] ->
        %{
          id: id,
          provider_key: key,
          status: status,
          hourly_request_limit: hourly,
          daily_request_limit: daily,
          monthly_request_limit: monthly,
          monthly_spend_limit: spend
        }

      _ ->
        TcgCheap.Repo.rollback(:budget_persistence_failed)
    end
  end

  defp increment_usage(provider_id, kind, started_at, cost) do
    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_budget_usages (id, provider_id, window_kind, window_started_at, request_count, estimated_spend_usd, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $3, 1, $4, now(), now()) ON CONFLICT (provider_id, window_kind, window_started_at) DO UPDATE SET request_count = acquisition_budget_usages.request_count + 1, estimated_spend_usd = acquisition_budget_usages.estimated_spend_usd + EXCLUDED.estimated_spend_usd, updated_at = now()",
      [provider_id, Atom.to_string(kind), started_at, cost]
    )
  end
end
