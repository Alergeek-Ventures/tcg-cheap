defmodule TcgCheap.Health do
  @moduledoc "Secret-safe application readiness checks."

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

  @spec check() :: %{
          status: String.t(),
          timestamp: String.t(),
          revision: String.t(),
          checks: map()
        }
  def check do
    checks = %{database: database_check(), oban: oban_check()}

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

  defp database_check do
    guarded(fn ->
      case TcgCheap.Repo.query("SELECT 1", [], log: false, timeout: @timeout) do
        {:ok, %{num_rows: 1}} -> %{status: "ok", message: "database ready"}
        _ -> failed()
      end
    end)
  end

  # Oban is up when its supervisor runs and every configured queue is running
  # and not paused.
  defp oban_check do
    guarded(fn ->
      with pid when is_pid(pid) <- Oban.whereis(Oban),
           true <- Process.alive?(pid),
           queues = configured_queues(Oban.config()),
           true <- queues != [] and queues_running?(queues) do
        %{status: "ok", message: "oban ready", queue_count: length(queues)}
      else
        _ -> failed()
      end
    end)
  end

  defp configured_queues(%{queues: queues}),
    do: queues |> Keyword.keys() |> Enum.map(&to_string/1)

  defp queues_running?(queues) do
    running = Oban.check_all_queues()

    Enum.all?(queues, fn queue ->
      Enum.any?(running, &(&1.queue == queue and &1.paused == false))
    end)
  end

  # A check reports only that it failed, never why: the response is public.
  defp guarded(check) do
    check.()
  rescue
    _ -> failed()
  catch
    _, _ -> failed()
  end

  defp failed, do: %{status: "error", message: "check failed"}
end
