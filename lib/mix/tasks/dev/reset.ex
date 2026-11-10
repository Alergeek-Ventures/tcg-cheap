defmodule Mix.Tasks.Dev.Reset do
  use Mix.Task
  @moduledoc "Stop local services and remove this worktree's database volume."
  alias Mix.Tasks.Dev.Shared

  @shortdoc "Stop local services and remove this worktree's database volume"
  def run(args) do
    env = Shared.load_env()
    # Before dev.down removes the containers that identify the project.
    project = Shared.project(env["BRANCH"])
    Mix.Task.run("dev.down", args)
    Shared.compose(["-p", project, "down", "-v"], Map.to_list(env))
  end
end
