defmodule TcgCheap.Operations.ManualRefresh do
  @moduledoc "Safe, bounded boundary for manually requesting canonical acquisition jobs."

  alias TcgCheap.Accounts.{Admin, AdminActor}
  alias TcgCheap.Catalogue.{CatalogueSyncWorker, Retailer, SealedRetailerAcquisition}
  alias TcgCheap.Operations.{AcquisitionBudget, DataProvider, ImportIssues}
  alias TcgCheap.Pricing.{ExchangeRateAcquisition, ExchangeRateWorker}
  alias TcgCheap.Pricing.Singles.{ValuationAcquisition, ValuationWorker}

  @max_card_id 240
  @max_adapters 100
  @max_source_key 144

  @type target_status :: :available | :disabled | :unconfigured | :empty | :unavailable
  @type result :: %{status: :queued | :already_queued, job_id: pos_integer()}

  @spec targets(Admin.t()) :: {:ok, [map()]} | {:error, atom()}
  def targets(%Admin{} = admin) do
    with :ok <- AdminActor.validate(admin),
         {:ok, budget} <- AcquisitionBudget.configured_limits(),
         {:ok, persisted_statuses} <- persisted_statuses(admin, budget),
         {:ok, retailer_targets} <- retailer_targets(budget, persisted_statuses) do
      {:ok, fixed_targets(budget, persisted_statuses) ++ retailer_targets}
    else
      {:error, :invalid_actor} -> {:error, :invalid_actor}
      _ -> {:error, :manual_refresh_unavailable}
    end
  rescue
    _ -> {:error, :manual_refresh_unavailable}
  catch
    _, _ -> {:error, :manual_refresh_unavailable}
  end

  def targets(_), do: {:error, :invalid_actor}

  @spec enqueue(Admin.t(), atom() | {atom(), String.t()}) :: {:ok, result()} | {:error, atom()}
  def enqueue(%Admin{} = admin, target) do
    with :ok <- AdminActor.validate(admin),
         {:ok, budget} <- AcquisitionBudget.configured_limits(),
         {:ok, job} <- checked_enqueue(target, budget, admin),
         {:ok, projection} <- job_projection(job) do
      {:ok, projection}
    else
      {:error, :invalid_actor} ->
        {:error, :invalid_actor}

      {:error, reason} when reason in [:invalid_target, :unconfigured, :disabled] ->
        {:error, reason}

      _ ->
        {:error, :manual_refresh_unavailable}
    end
  rescue
    _ -> {:error, :manual_refresh_unavailable}
  catch
    _, _ -> {:error, :manual_refresh_unavailable}
  end

  def enqueue(_, _), do: {:error, :invalid_actor}

  defp fixed_targets(budget, persisted_statuses) do
    catalogue_target = %{
      kind: :catalogue_sync,
      label: "TCGdex catalogue",
      provider_key: "tcgdex_catalogue",
      status:
        target_status(
          budget,
          persisted_statuses,
          "tcgdex_catalogue",
          worker_configured?(CatalogueSyncWorker)
        )
    }

    catalogue_repair_target = catalogue_repair_target(budget, persisted_statuses)

    [
      catalogue_target,
      catalogue_repair_target,
      %{
        kind: :exchange_rate,
        label: "NBP EUR/PLN",
        provider_key: "nbp",
        status:
          target_status(
            budget,
            persisted_statuses,
            "nbp",
            worker_configured?(ExchangeRateWorker)
          )
      },
      %{
        kind: :single_valuation,
        label: "TCGdex Cardmarket",
        provider_key: "tcgdex_cardmarket",
        status:
          target_status(
            budget,
            persisted_statuses,
            "tcgdex_cardmarket",
            worker_configured?(ValuationWorker)
          )
      }
    ]
  end

  defp catalogue_repair_target(budget, persisted_statuses) do
    provider_status =
      target_status(
        budget,
        persisted_statuses,
        "tcgdex_catalogue",
        worker_configured?(CatalogueSyncWorker)
      )

    case ImportIssues.unresolved_catalogue_set_ids() do
      {:ok, set_ids} ->
        failure_count = length(set_ids)

        %{
          kind: :catalogue_repair,
          label: "TCGdex failed-set repair",
          provider_key: "tcgdex_catalogue",
          failure_count: failure_count,
          status: if(failure_count == 0, do: :empty, else: provider_status)
        }

      {:error, _reason} ->
        %{
          kind: :catalogue_repair,
          label: "TCGdex failed-set repair",
          provider_key: "tcgdex_catalogue",
          failure_count: nil,
          status: :unavailable
        }
    end
  end

  defp retailer_targets(budget, persisted_statuses) do
    with {:ok, source_keys} <- configured_retailer_source_keys() do
      load_retailer_targets(source_keys, budget, persisted_statuses)
    end
  end

  defp configured_retailer_source_keys do
    case Application.get_env(:tcg_cheap, :sealed_retailer_adapters, %{}) do
      adapters when is_map(adapters) and map_size(adapters) <= @max_adapters ->
        adapters
        |> Map.keys()
        |> Enum.sort()
        |> validate_retailer_source_keys()

      _ ->
        {:error, :invalid_provider_configuration}
    end
  end

  defp validate_retailer_source_keys(source_keys) do
    if Enum.all?(source_keys, &valid_source_key?/1) do
      validate_retailer_adapters(source_keys)
    else
      {:error, :invalid_provider_configuration}
    end
  end

  defp validate_retailer_adapters(source_keys) do
    Enum.reduce_while(source_keys, {:ok, []}, fn source_key, {:ok, valid} ->
      case SealedRetailerAcquisition.config(source_key) do
        {:ok, _adapter, _options} -> {:cont, {:ok, [source_key | valid]}}
        {:error, _reason} -> {:halt, {:error, :invalid_provider_configuration}}
      end
    end)
    |> case do
      {:ok, valid} -> {:ok, Enum.reverse(valid)}
      error -> error
    end
  end

  defp load_retailer_targets(source_keys, budget, persisted_statuses) do
    Enum.reduce_while(source_keys, {:ok, []}, fn source_key, {:ok, targets} ->
      case active_retailer_by_source_key(source_key) do
        {:ok, nil} ->
          {:cont, {:ok, targets}}

        {:ok, retailer} ->
          provider_key = "sealed_retailer:" <> source_key

          target = %{
            kind: :sealed_retailer,
            retailer_id: retailer.id,
            source_key: source_key,
            label: retailer.name,
            provider_key: provider_key,
            status: target_status(budget, persisted_statuses, provider_key, true)
          }

          {:cont, {:ok, [target | targets]}}

        {:error, _reason} ->
          {:halt, {:error, :retailer_query_failed}}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.sort_by(targets, &{&1.label, &1.retailer_id})}
      error -> error
    end
  end

  defp active_retailer_by_source_key(source_key) do
    case TcgCheap.Core.get_retailer_by_source_key(source_key) do
      {:ok, %Retailer{status: "active", source_key: ^source_key} = retailer} -> {:ok, retailer}
      {:ok, %Retailer{}} -> {:ok, nil}
      {:error, error} -> if(not_found?(error), do: {:ok, nil}, else: {:error, error})
    end
  end

  defp checked_enqueue(:exchange_rate, budget, _admin) do
    with :ok <- provider_available?(budget, "nbp", worker_configured?(ExchangeRateWorker)) do
      enqueue_job(&ExchangeRateAcquisition.enqueue/0)
    end
  end

  defp checked_enqueue(:catalogue_sync, budget, _admin) do
    with :ok <-
           provider_available?(
             budget,
             "tcgdex_catalogue",
             worker_configured?(CatalogueSyncWorker)
           ) do
      enqueue_job(&CatalogueSyncWorker.enqueue/0)
    end
  end

  defp checked_enqueue(:catalogue_repair, budget, _admin) do
    with :ok <-
           provider_available?(
             budget,
             "tcgdex_catalogue",
             worker_configured?(CatalogueSyncWorker)
           ) do
      case CatalogueSyncWorker.enqueue_failed() do
        {:ok, %Oban.Job{} = job} -> {:ok, job}
        {:error, :no_failures} -> {:error, :invalid_target}
        {:error, :invalid_provider_configuration} -> {:error, :unconfigured}
        {:error, :import_issue_read_failed} -> {:error, :manual_refresh_unavailable}
        _ -> {:error, :manual_refresh_unavailable}
      end
    end
  end

  defp checked_enqueue({:single_valuation, id}, budget, _admin) do
    with :ok <- valid_card_id(id),
         :ok <-
           provider_available?(
             budget,
             "tcgdex_cardmarket",
             worker_configured?(ValuationWorker)
           ),
         {:ok, card} <- canonical_card(id) do
      enqueue_job(fn -> ValuationAcquisition.enqueue(card) end)
    end
  end

  defp checked_enqueue({:sealed_retailer, id}, budget, admin) do
    with {:ok, uuid} <- cast_uuid(id),
         {:ok, retailer} <- active_retailer(uuid, admin),
         {:ok, _adapter, _options} <- SealedRetailerAcquisition.config(retailer.source_key),
         :ok <- provider_available?(budget, "sealed_retailer:" <> retailer.source_key, true) do
      enqueue_job(fn -> SealedRetailerAcquisition.enqueue(retailer.id, retailer.source_key) end)
    else
      {:error, :invalid_provider_configuration} -> {:error, :unconfigured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp checked_enqueue(_, _, _), do: {:error, :invalid_target}

  defp valid_card_id(id) when is_binary(id) and byte_size(id) in 1..@max_card_id do
    if id == String.trim(id), do: :ok, else: {:error, :invalid_target}
  end

  defp valid_card_id(_), do: {:error, :invalid_target}

  defp canonical_card(id) do
    case TcgCheap.Core.get_card_printing_by_tcgdex_id(id) do
      {:ok, card} ->
        {:ok, card}

      {:error, error} ->
        if(not_found?(error), do: {:error, :invalid_target}, else: {:error, error})
    end
  end

  defp cast_uuid(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_target}
    end
  end

  defp cast_uuid(_), do: {:error, :invalid_target}

  defp active_retailer(id, admin) do
    case Ash.get(Retailer, id, action: :read, actor: admin) do
      {:ok, %Retailer{status: "active"} = retailer} ->
        {:ok, retailer}

      {:ok, %Retailer{}} ->
        {:error, :invalid_target}

      {:error, error} ->
        if(not_found?(error), do: {:error, :invalid_target}, else: {:error, error})
    end
  end

  defp persisted_statuses(admin, budget) do
    provider_keys = Enum.map(budget.providers, & &1.provider_key)

    case TcgCheap.Operations.list_providers(provider_keys, actor: admin) do
      {:ok, providers} when is_list(providers) ->
        if Enum.all?(providers, &valid_persisted_provider?(&1, provider_keys)) do
          {:ok, Map.new(providers, &{&1.provider_key, &1.status})}
        else
          {:error, :invalid_provider_state}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_persisted_provider?(
         %DataProvider{provider_key: key, status: status},
         provider_keys
       ),
       do: key in provider_keys and status in ["active", "disabled"]

  defp valid_persisted_provider?(_, _), do: false

  @spec target_status(map(), map(), String.t(), boolean()) :: target_status()
  defp target_status(budget, persisted_statuses, key, configured?) do
    cond do
      not configured? -> :unconfigured
      not Enum.any?(budget.providers, &(&1.provider_key == key)) -> :unconfigured
      Map.get(persisted_statuses, key, "active") == "disabled" -> :disabled
      true -> :available
    end
  end

  defp provider_available?(budget, key, configured?) do
    cond do
      not configured? ->
        {:error, :unconfigured}

      not Enum.any?(budget.providers, &(&1.provider_key == key)) ->
        {:error, :unconfigured}

      true ->
        persisted_provider_available?(key)
    end
  end

  defp persisted_provider_available?(key) do
    case TcgCheap.Operations.get_provider_by_key(key, authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, %DataProvider{status: "active"}} -> :ok
      {:ok, %DataProvider{status: "disabled"}} -> {:error, :disabled}
      _ -> {:error, :manual_refresh_unavailable}
    end
  end

  defp worker_configured?(worker) do
    case worker.provider_config() do
      {:ok, _config} -> true
      {:ok, _adapter, _options} -> true
      _other -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp enqueue_job(callback) do
    case callback.() do
      {:ok, %Oban.Job{} = job} -> {:ok, job}
      _ -> {:error, :manual_refresh_unavailable}
    end
  end

  defp valid_source_key?(key),
    do: is_binary(key) and byte_size(key) in 1..@max_source_key and key == String.trim(key)

  defp not_found?(%Ash.Error.Invalid{errors: errors}) when errors != [],
    do: Enum.all?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))

  defp not_found?(_), do: false

  defp job_projection(%Oban.Job{conflict?: true, id: id}) when is_integer(id) and id > 0,
    do: {:ok, %{status: :already_queued, job_id: id}}

  defp job_projection(%Oban.Job{id: id}) when is_integer(id) and id > 0,
    do: {:ok, %{status: :queued, job_id: id}}

  defp job_projection(_), do: {:error, :manual_refresh_unavailable}
end
