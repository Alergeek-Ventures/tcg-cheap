defmodule Mix.Tasks.Dev.Down do
  use Mix.Task
  @moduledoc "Stop this worktree's local services."
  alias Mix.Tasks.Dev.Shared

  @shortdoc "Stop this worktree's local services"
  def run(_args) do
    env = Shared.load_env()
    branch = env["BRANCH"]
    session = Shared.session(branch)

    if System.find_executable("tmux"),
      do: System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true)

    stop_fallback_server()

    Shared.compose(["-p", Shared.project(branch), "down"], Map.to_list(env))
  end

  defp stop_fallback_server do
    with {:ok, pid} <- File.read(".phoenix.pid"),
         {pid, ""} <- Integer.parse(String.trim(pid)) do
      case System.cmd("ps", ["-p", to_string(pid), "-o", "command="], stderr_to_stdout: true) do
        {command, 0} when is_binary(command) ->
          signal_if_verifiable(pid, command)

        _ ->
          Mix.shell().error("warning: refusing to kill stale or unrelated Phoenix PID #{pid}")
      end
    end

    File.rm(".phoenix.pid")
  end

  defp signal_if_verifiable(pid, command) do
    case process_cwd(pid) do
      {:ok, cwd} ->
        signal_if_phoenix(pid, command, cwd, File.cwd!())

      :unavailable ->
        Mix.shell().error(
          "warning: refusing to kill Phoenix PID #{pid}; process working directory could not be verified"
        )
    end
  end

  @doc false
  def safe_to_signal?(command, process_cwd, current_worktree)
      when is_binary(command) and is_binary(process_cwd) and is_binary(current_worktree) do
    Regex.match?(~r/\bmix phx\.server\b/, command) and process_cwd == current_worktree
  end

  def safe_to_signal?(_, _, _), do: false

  defp signal_if_phoenix(pid, command, process_cwd, current_worktree) do
    if safe_to_signal?(command, process_cwd, current_worktree) do
      System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true)
    else
      Mix.shell().error(
        "warning: refusing to kill stale or unrelated Phoenix PID #{pid}; command and worktree did not both match"
      )
    end
  end

  defp process_cwd(pid) do
    case File.read_link("/proc/#{pid}/cwd") do
      {:ok, cwd} -> {:ok, cwd}
      {:error, _reason} -> :unavailable
    end
  end
end
