defmodule TcgCheap.Storage.Config do
  @moduledoc """
  Pure materialization helpers for application storage configuration.

  The static application config owns storage policy: which service is active,
  which resources use storage, and non-sensitive service options. Runtime config
  passes only runtime facts, such as a randomized local S3 port, into this module.
  """

  @type storage_config :: keyword()
  @type runtime_values :: %{optional(String.t()) => String.t() | nil}

  @doc """
  Builds per-resource AshStorage configuration from the central storage config.
  """
  @spec resource_configs(storage_config(), runtime_values()) :: [{module(), keyword()}]
  def resource_configs(config, runtime_values \\ %{}) do
    service = service(config, runtime_values)

    config
    |> Keyword.fetch!(:resources)
    |> Enum.map(&{&1, [storage: [service: service]]})
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

    if blank?(port), do: nil, else: "http://localhost:#{port}#{Keyword.get(opts, :path)}"
  end

  defp resolve_runtime_opt({:env, env_name}, runtime_values) when is_binary(env_name) do
    runtime_value(runtime_values, env_name)
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
