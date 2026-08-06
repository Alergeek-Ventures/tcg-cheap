defmodule Mix.Tasks.Dev.DownTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dev.Down

  test "signals only a Phoenix server in the current worktree" do
    assert Down.safe_to_signal?("mix phx.server", "/worktree", "/worktree")
    refute Down.safe_to_signal?("mix phx.server", "/other", "/worktree")
    refute Down.safe_to_signal?("sleep 100", "/worktree", "/worktree")
  end

  test "refuses unverifiable process working directories" do
    refute Down.safe_to_signal?("mix phx.server", nil, "/worktree")
  end
end
