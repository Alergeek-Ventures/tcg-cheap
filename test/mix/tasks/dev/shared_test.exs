defmodule Mix.Tasks.Dev.SharedTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dev.Shared

  test "parses simple dotenv values and comments" do
    assert Shared.parse_dotenv("# comment\nexport PORT=4004\nNAME=\"hello world\"\n") == %{
             "PORT" => "4004",
             "NAME" => "hello world"
           }
  end

  test "sanitizes branch identifiers" do
    assert Shared.sanitize_branch("Feature/Big Thing") == "feature-big-thing"
  end

  test "uses the original branch to prevent identity collisions" do
    assert Shared.worktree_id("Feature/Foo") != Shared.worktree_id("Feature-Foo")
    assert Shared.project("Feature/Foo") == "tcg-cheap-#{Shared.worktree_id("Feature/Foo")}"
    assert Shared.session("Feature/Foo") == "tcg-cheap-#{Shared.worktree_id("Feature/Foo")}"
    assert Shared.worktree_id("main") == "main"
  end

  test "validates ports" do
    assert Shared.parse_port("5436") == {:ok, 5436}
    assert {:error, _} = Shared.parse_port("70000", "DB_PORT")
  end
end
