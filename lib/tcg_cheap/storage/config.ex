defmodule TcgCheap.Storage.Config do
  @moduledoc """
  Pure materialization helpers for application storage configuration.

  The static application config owns storage policy: which service is active,
  which resources use storage, and non-sensitive service options. Runtime config
  passes only runtime facts, such as a randomized local S3 port, into this module.
  """

  alias AshStorage.Service.Context

  @type storage_config :: keyword()
  @type runtime_values :: %{optional(String.t()) => String.t() | nil}

  @doc """
  Builds per-resource AshStorage configuration from the central storage config.
  """
  @spec resource_configs(storage_config(), runtime_values()) :: [{module(), keyword()}]
  def resource_configs(config, runtime_values \\ %{}) do
    default_service = service(config, runtime_values)
    active_service = Keyword.get(config, :active_service)
    overrides = Keyword.get(config, :resource_overrides, [])

    config
    |> Keyword.fetch!(:resources)
    |> Enum.map(fn resource ->
      service =
        case {active_service, Keyword.get(overrides, resource)} do
          {:test, _} -> default_service
          {_, nil} -> default_service
          {_, service_name} -> service(config, service_name, runtime_values)
        end

      {resource, [storage: [service: service]]}
    end)
  end

  @doc """
  Resolves a specific service tuple expected by AshStorage.
  """
  @spec service(storage_config(), atom(), runtime_values()) :: {module(), keyword()}
  def service(config, service_name, runtime_values) do
    service_config = config |> Keyword.fetch!(:services) |> Keyword.fetch!(service_name)
    module = Keyword.fetch!(service_config, :module)

    opts =
      service_config
      |> Keyword.get(:opts, [])
      |> merge_runtime_opts(Keyword.get(service_config, :runtime_opts, []), runtime_values)

    {module, opts}
  end

  @doc """
  Resolves the default active service tuple expected by AshStorage.
  """
  @spec service(storage_config(), runtime_values()) :: {module(), keyword()}
  def service(config, runtime_values \\ %{}) do
    active_service = Keyword.fetch!(config, :active_service)
    service(config, active_service, runtime_values)
  end

  @doc """
  Builds an AshStorage service context from a persisted or loaded storage blob.

  Parsed options take precedence when they contain a usable bucket; otherwise
  persisted options are used. String and atom option keys are accepted.
  """
  @spec service_context(map(), keyword()) :: Context.t()
  def service_context(blob, overrides \\ []) when is_map(blob) and is_list(overrides) do
    parsed = normalize_service_options(Map.get(blob, :parsed_service_opts))
    persisted = normalize_service_options(Map.get(blob, :service_opts))
    opts = if usable_service_options?(parsed), do: parsed, else: persisted

    Context.new(Keyword.merge(opts, overrides))
  end

  defp merge_runtime_opts(opts, runtime_opts, runtime_values) do
    Enum.reduce(runtime_opts, opts, fn {key, spec}, opts ->
      case resolve_runtime_opt(spec, runtime_values) do
        nil -> opts
        value -> Keyword.put(opts, key, value)
      end
    end)
  end

  defp resolve_runtime_opt({:localhost_url_from_port, opts}, runtime_values) when is_list(opts) do
    env_name = Keyword.fetch!(opts, :env)
    port = runtime_value(runtime_values, env_name) || Keyword.get(opts, :default)

    if blank?(port), do: nil, else: "http://localhost:#{port}"
  end

  defp resolve_runtime_opt({:env, env_name}, runtime_values) when is_binary(env_name) do
    runtime_value(runtime_values, env_name)
  end

  defp normalize_service_options(%Ash.NotLoaded{}), do: []

  defp normalize_service_options(opts) when is_map(opts) do
    for key <- [:bucket, :region, :endpoint_url, :prefix, :public_base_url],
        value = Map.get(opts, key) || Map.get(opts, Atom.to_string(key)),
        not is_nil(value),
        into: [] do
      {key, value}
    end
  end

  defp normalize_service_options(opts) when is_list(opts) do
    opts |> Map.new() |> normalize_service_options()
  rescue
    _error in [ArgumentError] -> []
  end

  defp normalize_service_options(_opts), do: []

  defp usable_service_options?(opts) do
    is_binary(Keyword.get(opts, :bucket)) and Keyword.get(opts, :bucket) != ""
  end

  defp runtime_value(runtime_values, env_name) do
    runtime_values
    |> Map.get(env_name)
    |> blank_to_nil()
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank_to_nil(value), do: value

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
