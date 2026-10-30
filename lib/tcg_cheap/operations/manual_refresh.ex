defmodule TcgCheap.Operations.ManualRefresh do
  @moduledoc "Safe, bounded boundary for manually requesting canonical acquisition jobs."

  alias TcgCheap.Accounts.{Admin, AdminActor}

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, SinglesScopeBootstrapWorker}

  alias TcgCheap.Operations.{AcquisitionBudget, DataProvider, ImportIssues}
  alias TcgCheap.Pricing.{ExchangeRateAcquisition, ExchangeRateWorker}

  @type target_status :: :available | :disabled | :unconfigured | :empty | :unavailable
  @type result :: %{status: :queued | :already_queued, job_id: pos_integer()}

  @spec targets(Admin.t()) :: {:ok, [map()]} | {:error, atom()}
  def targets(%Admin{} = admin) do
    with :ok <- AdminActor.validate(admin),
         {:ok, budget} <- AcquisitionBudget.configured_limits(),
         {:ok, persisted_statuses} <- persisted_statuses(admin, budget) do
      {:ok, fixed_targets(budget, persisted_statuses)}
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

  @spec enqueue(Admin.t(), atom()) :: {:ok, result()} | {:error, atom()}
  def enqueue(%Admin{} = admin, target) do
    with :ok <- AdminActor.validate(admin),
         {:ok, budget} <- AcquisitionBudget.configured_limits(),
         {:ok, job} <- checked_enqueue(target, budget),
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
    singles_target = %{
      kind: :singles_collection,
      label: "Scoped Singles collection",
      provider_key: "tcgdex_catalogue",
      status:
        target_status(
          budget,
          persisted_statuses,
          "tcgdex_catalogue",
          worker_configured?(SinglesScopeBootstrapWorker)
        )
    }

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
      singles_target,
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

  defp checked_enqueue(:exchange_rate, budget) do
    with :ok <- provider_available?(budget, "nbp", worker_configured?(ExchangeRateWorker)) do
      enqueue_job(&ExchangeRateAcquisition.enqueue/0)
    end
  end

  defp checked_enqueue(:catalogue_sync, budget) do
    with :ok <-
           provider_available?(
             budget,
             "tcgdex_catalogue",
             worker_configured?(CatalogueSyncWorker)
           ) do
      enqueue_job(&CatalogueSyncWorker.enqueue/0)
    end
  end

  defp checked_enqueue(:singles_collection, budget) do
    with :ok <-
           provider_available?(
             budget,
             "tcgdex_catalogue",
             worker_configured?(SinglesScopeBootstrapWorker)
           ) do
      enqueue_job(fn -> SinglesScopeBootstrapWorker.enqueue(Date.utc_today()) end)
    end
  end

  defp checked_enqueue(:catalogue_repair, budget) do
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

  defp checked_enqueue(_, _), do: {:error, :invalid_target}

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

  defp job_projection(%Oban.Job{conflict?: true, id: id}) when is_integer(id) and id > 0,
    do: {:ok, %{status: :already_queued, job_id: id}}

  defp job_projection(%Oban.Job{id: id}) when is_integer(id) and id > 0,
    do: {:ok, %{status: :queued, job_id: id}}

  defp job_projection(_), do: {:error, :manual_refresh_unavailable}
end
