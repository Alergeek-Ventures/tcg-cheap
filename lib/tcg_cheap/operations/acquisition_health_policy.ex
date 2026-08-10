defmodule TcgCheap.Operations.AcquisitionHealthPolicy do
  @moduledoc "Strict, pure policy for acquisition freshness, repair, and circuit breaking."

  @config_keys [
    :circuit_breaker_failure_threshold,
    :reconcile_limit,
    :stale_after_seconds,
    :stranded_after_seconds
  ]
  @max_stranded_seconds 86_400
  @max_stale_seconds 31_536_000

  def load do
    config = Application.get_env(:tcg_cheap, :acquisition_health)

    with {:ok, config} <- strict_map(config),
         {:ok, stranded} <-
           bounded(Map.get(config, :stranded_after_seconds), 1, @max_stranded_seconds),
         {:ok, limit} <- bounded(Map.get(config, :reconcile_limit), 1, 100),
         {:ok, circuit_threshold} <-
           bounded(Map.get(config, :circuit_breaker_failure_threshold), 1, 100),
         {:ok, stale} <- normalize_stale(Map.get(config, :stale_after_seconds)) do
      {:ok,
       %{
         circuit_breaker_failure_threshold: circuit_threshold,
         stranded_after_seconds: stranded,
         reconcile_limit: limit,
         stale_after_seconds: stale
       }}
    else
      _ -> {:error, :invalid_acquisition_health_configuration}
    end
  end

  def validate_provider_keys(%{stale_after_seconds: stale} = policy, provider_keys)
      when is_map(stale) and is_list(provider_keys) do
    configured = MapSet.new(provider_keys)

    if MapSet.size(configured) == length(provider_keys) and
         Enum.all?(provider_keys, &canonical_provider?/1) and
         Enum.all?(Map.keys(stale), &MapSet.member?(configured, &1)) do
      {:ok, policy}
    else
      {:error, :invalid_acquisition_health_configuration}
    end
  end

  def validate_provider_keys(_, _), do: {:error, :invalid_acquisition_health_configuration}

  def overdue?(%DateTime{} = started_at, %DateTime{} = now, threshold)
      when is_integer(threshold) and threshold > 0 do
    utc?(started_at) and utc?(now) and DateTime.compare(started_at, now) != :gt and
      DateTime.diff(now, started_at) >= threshold
  end

  def overdue?(_, _, _), do: false

  @doc "Returns whether a persisted failure category contributes to the provider circuit."
  def circuit_eligible_category?(category)
      when category in ["rate_limit", "timeout", "transport", "provider_response"],
      do: true

  def circuit_eligible_category?(_), do: false

  def provider_state(
        %{stale_after_seconds: stale},
        provider,
        last_succeeded_at,
        %DateTime{} = now
      )
      when is_map(stale) and is_binary(provider) do
    if utc?(now) do
      case Map.fetch(stale, provider) do
        :error -> :on_demand
        {:ok, seconds} -> freshness_state(last_succeeded_at, now, seconds)
      end
    else
      :invalid
    end
  end

  def provider_state(_, _, _, _), do: :invalid

  defp freshness_state(nil, %DateTime{} = now, _seconds) do
    if utc?(now), do: :not_observed, else: :invalid
  end

  defp freshness_state(%DateTime{} = succeeded_at, %DateTime{} = now, seconds)
       when is_integer(seconds) and seconds > 0 do
    cond do
      not utc?(succeeded_at) or not utc?(now) -> :invalid
      DateTime.compare(succeeded_at, now) == :gt -> :invalid
      DateTime.diff(now, succeeded_at) >= seconds -> :stale
      true -> :current
    end
  end

  defp freshness_state(_, _, _), do: :invalid

  defp strict_map(config) when is_map(config) do
    if Map.keys(config) |> Enum.sort() == @config_keys, do: {:ok, config}, else: :error
  end

  defp strict_map(config) when is_list(config) do
    if Keyword.keyword?(config) do
      keys = Keyword.keys(config)

      if Enum.sort(keys) == @config_keys and length(keys) == length(Enum.uniq(keys)),
        do: {:ok, Map.new(config)},
        else: :error
    else
      :error
    end
  end

  defp strict_map(_), do: :error

  defp bounded(value, min, max) when is_integer(value) and value >= min and value <= max,
    do: {:ok, value}

  defp bounded(_, _, _), do: :error

  defp normalize_stale(stale) when is_map(stale) and map_size(stale) <= 100 do
    normalized =
      Enum.reduce_while(stale, %{}, fn {key, seconds}, acc ->
        normalize_entry(key, seconds, acc)
      end)

    if is_map(normalized) and map_size(normalized) == map_size(stale),
      do: {:ok, normalized},
      else: :error
  end

  defp normalize_stale(_), do: :error

  defp normalize_provider(key) when is_binary(key) do
    if canonical_provider?(key), do: {:ok, key}, else: :error
  end

  defp normalize_provider(_), do: :error

  defp normalize_entry(key, seconds, acc) do
    with {:ok, provider} <- normalize_provider(key),
         {:ok, seconds} <- bounded(seconds, 1, @max_stale_seconds) do
      {:cont, Map.put(acc, provider, seconds)}
    else
      _ -> {:halt, :error}
    end
  end

  defp canonical_provider?(provider),
    do:
      is_binary(provider) and byte_size(provider) in 1..160 and
        provider == String.trim(provider)

  defp utc?(%DateTime{time_zone: "Etc/UTC"}), do: true
  defp utc?(_), do: false
end
