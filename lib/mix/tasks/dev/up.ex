defmodule Mix.Tasks.Dev.Up do
  use Mix.Task
  @moduledoc "Start this worktree's database and Phoenix server."
  alias Mix.Tasks.Dev.Shared

  @container_id_regex ~r/^[0-9a-fA-F]{12,64}$/
  @ansi_sgr_regex ~r/\e\[[0-9;]*m/

  @shortdoc "Start this worktree's database and Phoenix server"
  def run(_args) do
    Shared.ensure_req_started()
    Mix.Task.run("app.config")
    env = Shared.load_env()
    branch = env["BRANCH"]
    {:ok, port} = Shared.parse_port(env["PORT"], "PORT")
    {:ok, db_port} = Shared.parse_port(env["DB_PORT"], "DB_PORT")

    env =
      Map.put(env, "DATABASE_URL", "ecto://postgres:postgres@localhost:#{db_port}/tcg_cheap_dev")

    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)
    File.write!(".server.port", "#{port}\n")

    project = Shared.project(branch)
    Shared.compose(["-p", project, "up", "-d"], compose_env(env))
    verify_compose_service(project, env, "postgres")
    wait_for_database(db_port)
    run_setup(env)
    start_server(branch, env)
    wait_for_http(port)
    print_endpoints(port, db_port)
  end

  defp wait_for_database(port) do
    pg_isready =
      System.find_executable("pg_isready") ||
        Mix.raise("pg_isready was not found; enter the devenv shell first")

    wait_until(
      fn ->
        match?(
          {_, 0},
          System.cmd(pg_isready, ["-h", "localhost", "-p", to_string(port), "-U", "postgres"],
            stderr_to_stdout: true
          )
        )
      end,
      "PostgreSQL"
    )
  end

  defp run_setup(env) do
    {output, status} = System.cmd("mix", ["setup"], env: Map.to_list(env), stderr_to_stdout: true)
    if status != 0, do: Mix.raise("mix setup failed:\n#{output}")
  end

  defp start_server(branch, env) do
    session = Shared.session(branch)

    if System.find_executable("tmux") do
      start_tmux_server(session, env)
    else
      {output, status} =
        System.cmd(
          "sh",
          [
            "-c",
            "nohup \"$1\" \"$2\" >phoenix-\"$3\".log 2>&1 & echo $!",
            "sh",
            "mix",
            "phx.server",
            Shared.sanitize_branch(branch)
          ],
          env: Map.to_list(runtime_env(env)),
          stderr_to_stdout: true
        )

      if status != 0 do
        Mix.raise("unable to start Phoenix without tmux")
      else
        File.write!(".phoenix.pid", String.trim(output) <> "\n")
      end
    end
  end

  defp start_tmux_server(session, env) do
    {_output, status} = System.cmd("tmux", ["has-session", "-t", session], stderr_to_stdout: true)

    if status == 0,
      do: System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true)

    create_tmux_session(session, env)
  end

  defp create_tmux_session(session, env) do
    tmux_env = Enum.flat_map(runtime_env(env), fn {key, value} -> ["-e", "#{key}=#{value}"] end)

    {_output, status} =
      System.cmd(
        "tmux",
        ["new-session", "-d", "-s", session] ++ tmux_env ++ ["mix", "phx.server"],
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("unable to start tmux session #{session}")
    Mix.shell().info("Started Phoenix tmux session #{session}")
  end

  defp wait_for_http(port),
    do:
      wait_until(
        fn ->
          match?(
            {:ok, %{status: status}} when status in 200..299,
            Req.get("http://localhost:#{port}/")
          )
        end,
        "Phoenix"
      )

  defp verify_compose_service(project, env, service) do
    {output, _status} =
      Shared.compose(["-p", project, "ps", "-q"], compose_env(env))

    if compose_container_ids(output) == [] do
      Mix.raise(
        "Compose project #{project} did not start service #{service}; `compose ps -q` returned no container ID. Output:\n#{output}"
      )
    end
  end

  @doc false
  def compose_container_ids(output) when is_binary(output) do
    output = Regex.replace(@ansi_sgr_regex, output, "")

    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(@container_id_regex, &1))
  end

  def compose_container_ids(_output), do: []

  defp compose_env(env), do: Map.to_list(runtime_env(env))

  defp runtime_env(env) do
    Map.merge(env, %{
      "PATH" => System.get_env("PATH", ""),
      "MIX_TAILWIND_PATH" => System.get_env("MIX_TAILWIND_PATH", ""),
      "MIX_ESBUILD_PATH" => System.get_env("MIX_ESBUILD_PATH", "")
    })
  end

  defp print_endpoints(port, db_port) do
    Mix.shell().info("Localhost: http://localhost:#{port}")
    Mix.shell().info("Tidewave: http://localhost:#{port}/tidewave/mcp")
    Mix.shell().info("Database: postgres://localhost:#{db_port}/tcg_cheap_dev")
  end

  defp wait_until(fun, label, attempts \\ 30)
  defp wait_until(_fun, label, 0), do: Mix.raise("timed out waiting for #{label}")

  defp wait_until(fun, label, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(1_000)
      wait_until(fun, label, attempts - 1)
    end
  end
end
