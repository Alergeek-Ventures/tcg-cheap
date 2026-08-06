defmodule Mix.Tasks.Dev.Shared do
  @moduledoc "Shared, deliberately small primitives for the local lifecycle tasks."

  @compose_file "local/compose.yml"

  def sanitize_branch(branch) when is_binary(branch) do
    branch
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "main"
      value -> String.slice(value, 0, 40)
    end
  end

  def sanitize_branch(_), do: "main"

  def worktree_id(branch) when is_binary(branch) do
    branch = String.trim(branch)

    if branch == "main" do
      "main"
    else
      sanitized = sanitize_branch(branch)
      hash = :crypto.hash(:sha256, branch) |> Base.encode16(case: :lower) |> String.slice(0, 8)
      "#{sanitized}-#{hash}"
    end
  end

  def worktree_id(_), do: "main"
  def session(branch), do: "tcg-cheap-#{worktree_id(branch)}"

  def parse_dotenv(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.reduce(%{}, &parse_dotenv_line/2)
  end

  def parse_dotenv(_), do: %{}

  defp parse_dotenv_line(line, acc) do
    line = String.trim(line)

    if line == "" or String.starts_with?(line, "#") do
      acc
    else
      parse_dotenv_assignment(line, acc)
    end
  end

  defp parse_dotenv_assignment(line, acc) do
    case Regex.run(~r/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/, line,
           capture: :all_but_first
         ) do
      [key, value] -> Map.put(acc, key, unquote_value(value))
      _ -> acc
    end
  end

  def parse_port(value, name \\ "port") do
    case Integer.parse(to_string(value)) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _ -> {:error, "#{name} must be an integer between 1 and 65535"}
    end
  end

  def load_env do
    values =
      case File.read(".env.local") do
        {:ok, content} -> parse_dotenv(content)
        _ -> defaults()
      end

    values = Map.merge(defaults(), values)

    values =
      case System.get_env("BRANCH") do
        nil -> values
        branch -> Map.put(values, "BRANCH", branch)
      end

    File.write!(
      ".env.local",
      Enum.map_join(values, "\n", fn {key, value} -> "#{key}=#{value}" end) <> "\n"
    )

    Enum.each(values, fn {key, value} -> System.put_env(key, value) end)
    values
  end

  def defaults do
    branch = System.get_env("BRANCH", "main")
    db_port = System.get_env("DB_PORT", "5436")
    port = System.get_env("PORT", "4004")

    %{
      "PORT" => port,
      "DB_PORT" => db_port,
      "BRANCH" => branch,
      "DATABASE_URL" => "ecto://postgres:postgres@localhost:#{db_port}/tcg_cheap_dev"
    }
  end

  def compose_runtime do
    cond do
      executable?("distrobox-host-exec") and executable?("podman") ->
        {"distrobox-host-exec", ["podman"]}

      executable?("podman") ->
        {"podman", []}

      executable?("docker") ->
        {"docker", []}

      true ->
        {:error,
         "No container runtime found (need distrobox-host-exec + podman, podman, or docker)"}
    end
  end

  def compose(args, env \\ []) do
    case compose_runtime() do
      {runtime, prefix} when is_binary(runtime) ->
        {output, status} =
          System.cmd(runtime, prefix ++ ["compose", "-f", @compose_file] ++ args,
            env: Enum.into(env, []),
            stderr_to_stdout: true
          )

        if status != 0, do: Mix.raise("compose command failed (exit #{status}):\n#{output}")
        {output, status}

      {:error, message} ->
        Mix.raise(message)
    end
  end

  def project(branch), do: "tcg-cheap-#{worktree_id(branch)}"
  def compose_file, do: @compose_file

  def ensure_req_started do
    case Application.ensure_all_started(:req) do
      {:ok, _apps} -> :ok
      {:error, reason} -> Mix.raise("unable to start HTTP client: #{inspect(reason)}")
    end
  end

  defp executable?(name), do: System.find_executable(name) != nil

  defp unquote_value(value) do
    value = String.trim(value)

    if String.length(value) >= 2 and String.first(value) in ["\"", "'"] and
         String.last(value) == String.first(value), do: String.slice(value, 1..-2//1), else: value
  end
end
