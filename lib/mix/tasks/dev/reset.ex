defmodule Mix.Tasks.Dev.Reset do
  use Mix.Task
  @moduledoc "Stop local services and remove this worktree's database volume."
  alias Mix.Tasks.Dev.Shared

  @shortdoc "Stop local services and remove this worktree's database volume"
  def run(args) do
    Mix.Task.run("dev.down", args)
    env = Shared.load_env()
    Shared.compose(["-p", Shared.project(env["BRANCH"]), "down", "-v"], Map.to_list(env))
  end
end
