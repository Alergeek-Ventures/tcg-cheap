defmodule TcgCheap.Catalogue.SealedRetailerAcquisition do
  @moduledoc "Enqueues explicitly configured, deduplicated sealed retailer refreshes."

  alias TcgCheap.Catalogue.{SealedRetailerRefresh, SealedRetailerWorker}

  @spec enqueue(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(retailer_id, source_key) do
    with {:ok, _retailer} <- SealedRetailerRefresh.canonical_retailer(retailer_id, source_key),
         {:ok, _adapter, _options} <- config(source_key) do
      %{"retailer_id" => retailer_id, "source_key" => source_key}
      |> SealedRetailerWorker.new()
      |> Oban.insert()
    end
  end

  def config(source_key) when is_binary(source_key) do
    providers = Application.get_env(:tcg_cheap, :sealed_retailer_adapters, %{})

    with true <- is_map(providers),
         %{adapter: adapter, options: options} = entry <- Map.get(providers, source_key),
         true <- map_size(entry) == 2,
         true <- is_atom(adapter) and is_list(options) and Keyword.keyword?(options),
         true <- unique_keys?(options),
         true <-
           Code.ensure_loaded?(adapter) and
             function_exported?(adapter, :source_key, 0) and
             function_exported?(adapter, :fetch_listings, 2),
         {:ok, callback_key} <- safe_source_key(adapter),
         true <- callback_key == source_key do
      {:ok, adapter, options}
    else
      _ -> {:error, :invalid_provider_configuration}
    end
  end

  def config(_), do: {:error, :invalid_provider_configuration}

  defp unique_keys?(options),
    do: length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options)))

  defp safe_source_key(adapter) do
    case adapter.source_key() do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_provider_configuration}
    end
  rescue
    _ -> {:error, :invalid_provider_configuration}
  catch
    _, _ -> {:error, :invalid_provider_configuration}
  end
end
