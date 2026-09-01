defmodule TcgCheap.Operations.Health do
  @moduledoc "Secret-safe application readiness checks."

  alias TcgCheap.Operations.AcquisitionBudget

  @timeout 2_000
  @git_object_id ~r/\A[0-9a-fA-F]{7,64}\z/

  @spec revision() :: String.t()
  def revision do
    case System.get_env("SOURCE_COMMIT") do
      source_commit when is_binary(source_commit) ->
        source_commit = String.trim(source_commit)

        if Regex.match?(@git_object_id, source_commit), do: source_commit, else: "unknown"

      _ ->
        "unknown"
    end
  end

  @spec check(keyword()) :: %{
          status: String.t(),
          timestamp: String.t(),
          revision: String.t(),
          checks: map()
        }
  def check(opts \\ []) when is_list(opts) do
    checks = %{
      database: run_check(Keyword.get(opts, :database, &database_check/0), "database ready", nil),
      oban: run_check(Keyword.get(opts, :oban, &oban_check/0), "oban ready", :queue_count),
      acquisition_budget:
        run_check(
          Keyword.get(opts, :acquisition_budget, &budget_check/0),
          "acquisition budget configured",
          :provider_count
        )
    }

    status =
      if Enum.all?(checks, fn {_name, check} -> check.status == "ok" end),
        do: "healthy",
        else: "unhealthy"

    %{
      status: status,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      revision: revision(),
      checks: checks
    }
  end

  defp run_check(callback, message, detail_key) when is_function(callback, 0) do
    case safe_call(callback) do
      :ok when is_nil(detail_key) ->
        %{status: "ok", message: message}

      {:ok, details} when is_atom(detail_key) ->
        project_details(details, detail_key, message)

      _ ->
        %{status: "error", message: "check failed"}
    end
  end

  defp run_check(_callback, _message, _detail_key),
    do: %{status: "error", message: "check failed"}

  defp safe_call(callback) do
    callback.()
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp project_details(details, detail_key, message)
       when is_map(details) and map_size(details) == 1 do
    case Map.fetch(details, detail_key) do
      {:ok, value} when is_integer(value) and value >= 0 ->
        Map.put(%{status: "ok", message: message}, detail_key, value)

      _ ->
        %{status: "error", message: "check failed"}
    end
  end

  defp project_details(_details, _detail_key, _message),
    do: %{status: "error", message: "check failed"}

  defp database_check do
    case TcgCheap.Repo.query("SELECT 1", [], log: false, timeout: @timeout) do
      {:ok, %{num_rows: 1}} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp oban_check do
    with pid when is_pid(pid) <- Oban.whereis(Oban),
         true <- Process.alive?(pid),
         {:ok, config} <- oban_config(),
         queues <- configured_queues(config),
         :ok <- configured_queues_ready(config.testing, queues) do
      {:ok, %{queue_count: length(queues)}}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp oban_config do
    {:ok, Oban.config()}
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp configured_queues(%{queues: queues}),
    do: Keyword.keys(queues) |> Enum.map(&to_string/1)

  defp configured_queues_ready(testing, _queues) when testing in [:manual, :inline], do: :ok

  defp configured_queues_ready(:disabled, []), do: :error

  defp configured_queues_ready(:disabled, queues) do
    running = Oban.check_all_queues()

    if Enum.all?(queues, &queue_ready?(&1, running)), do: :ok, else: :error
  end

  defp queue_ready?(queue, running) do
    Enum.any?(running, fn state -> state.queue == queue and state.paused == false end)
  end

  defp budget_check do
    case AcquisitionBudget.configured_limits() do
      {:ok, config} when is_map(config) ->
        {:ok, %{provider_count: config |> Map.get(:providers, []) |> length()}}

      _ ->
        :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end
end
