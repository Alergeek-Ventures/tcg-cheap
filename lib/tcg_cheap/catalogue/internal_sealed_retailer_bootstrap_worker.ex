defmodule TcgCheap.Catalogue.InternalSealedRetailerBootstrapWorker do
  @moduledoc "Bootstraps one canonical internal sealed retailer and queues its refresh."

  use Oban.Worker,
    queue: :operations,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:policy_version, :source_key],
      states: [:available, :scheduled, :executing, :retryable, :suspended]
    ]

  alias TcgCheap.Catalogue.{Retailer, SealedRetailerAcquisition}
  alias TcgCheap.Operations

  @policy_version 1
  @sources %{
    "lootquest" => %{
      slug: "lootquest",
      name: "LootQuest",
      category: "regular_retailer",
      homepage_url: "https://lootquest.pl"
    },
    "cardzhouse" => %{
      slug: "cardzhouse",
      name: "CardzHouse",
      category: "lgs",
      homepage_url: "https://cardzhouse.pl"
    },
    "boosterpoint" => %{
      slug: "boosterpoint",
      name: "BoosterPoint",
      category: "lgs",
      homepage_url: "https://boosterpoint.pl"
    },
    "pokebooster" => %{
      slug: "pokebooster",
      name: "PokeBooster",
      category: "lgs",
      homepage_url: "https://pokebooster.pl"
    }
  }

  @spec sources() :: map()
  def sources, do: @sources

  @impl true
  def perform(%Oban.Job{args: args}) do
    with {:ok, source_key} <- validate_args(args),
         {:ok, _adapter, _options} <- selected_provider_config(source_key),
         :ok <- provider_available?(source_key),
         {:ok, retailer} <- canonical_retailer(source_key),
         {:ok, _job} <- enqueue_child(retailer.id, source_key) do
      :ok
    else
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> classify_persistence(reason)
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  @impl true
  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * attempt * attempt, 900)

  @impl true
  def timeout(_job), do: :timer.seconds(60)

  defp validate_args(%{"policy_version" => @policy_version, "source_key" => source_key} = args)
       when map_size(args) == 2 and is_binary(source_key),
       do: validate_source_key(source_key)

  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp validate_source_key(source_key) when is_map_key(@sources, source_key),
    do: {:ok, source_key}

  defp validate_source_key(_), do: {:cancel, :malformed_job_args}

  defp selected_provider_config(source_key) do
    case SealedRetailerAcquisition.config(source_key) do
      {:ok, adapter, options} -> {:ok, adapter, options}
      {:error, :invalid_provider_configuration} -> {:cancel, :invalid_provider_configuration}
    end
  end

  defp canonical_retailer(source_key) do
    case TcgCheap.Core.find_retailer_by_source_key(source_key, authorize?: false) do
      {:ok, nil} ->
        attrs = Map.put(@sources[source_key], :source_key, source_key)
        register_retailer(attrs)

      {:ok, %Retailer{source_key: ^source_key, status: "active", category: category} = retailer} ->
        if category == @sources[source_key].category,
          do: {:ok, retailer},
          else: {:error, :retailer_identity_mismatch}

      {:ok, %Retailer{status: "disabled"}} ->
        {:error, :retailer_disabled}

      {:ok, %Retailer{}} ->
        {:error, :retailer_identity_mismatch}

      {:error, _} ->
        {:error, :retailer_lookup_failed}
    end
  rescue
    _ -> {:error, :retailer_persistence_failed}
  end

  defp register_retailer(attrs) do
    case TcgCheap.Core.register_retailer(attrs, authorize?: false) do
      {:ok, retailer} -> {:ok, retailer}
      {:error, _reason} -> {:error, :retailer_persistence_failed}
    end
  rescue
    _ -> {:error, :retailer_persistence_failed}
  end

  defp enqueue_child(retailer_id, source_key) do
    case SealedRetailerAcquisition.enqueue(retailer_id, source_key) do
      {:ok, job} -> {:ok, job}
      {:error, reason} -> normalize_enqueue_error(reason)
    end
  rescue
    _ -> {:error, :child_persistence_failed}
  end

  defp normalize_enqueue_error(reason)
       when reason in [
              :retailer_not_active_or_mismatched,
              :retailer_not_found,
              :invalid_provider_configuration
            ],
       do: {:cancel, :retailer_disabled_or_changed}

  defp normalize_enqueue_error(_reason), do: {:error, :child_persistence_failed}

  defp provider_available?(source_key) do
    case Operations.get_provider_by_key("sealed_retailer:" <> source_key, authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, %{status: "active"}} -> :ok
      {:ok, %{status: "disabled"}} -> {:cancel, :provider_disabled}
      {:error, _} -> {:error, :provider_lookup_failed}
    end
  rescue
    _ -> {:error, :provider_lookup_failed}
  end

  defp classify_persistence(reason)
       when reason in [:retailer_disabled, :retailer_identity_mismatch],
       do: {:cancel, reason}

  defp classify_persistence(reason)
       when reason in [
              :retailer_lookup_failed,
              :retailer_persistence_failed,
              :provider_lookup_failed,
              :child_persistence_failed
            ],
       do: {:error, :internal_bootstrap_failed}
end
