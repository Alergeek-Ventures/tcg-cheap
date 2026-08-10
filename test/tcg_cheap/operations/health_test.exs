defmodule TcgCheap.Operations.HealthTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Operations.Health

  test "projects healthy callbacks without exposing callback details" do
    result =
      Health.check(
        database: fn -> :ok end,
        oban: fn -> {:ok, %{queue_count: 2}} end,
        acquisition_budget: fn -> {:ok, %{provider_count: 3}} end
      )

    assert result.status == "healthy"
    assert result.checks.database == %{status: "ok", message: "database ready"}
    assert result.checks.oban == %{status: "ok", message: "oban ready", queue_count: 2}
    refute inspect(result) =~ "secret-marker"
  end

  test "fails closed for errors, malformed results, and thrown callbacks" do
    result =
      Health.check(
        database: fn -> raise "secret-marker" end,
        oban: fn -> {:ok, %{secret: "secret-marker"}} end,
        acquisition_budget: fn -> throw(:secret_marker) end
      )

    assert result.status == "unhealthy"
    assert Enum.all?(result.checks, fn {_name, check} -> check.status == "error" end)
    refute inspect(result) =~ "secret-marker"
    refute inspect(result) =~ "secret_marker"
  end

  test "requires the exact result schema for each check" do
    result =
      Health.check(
        database: fn -> {:ok, %{}} end,
        oban: fn -> {:ok, %{provider_count: 3}} end,
        acquisition_budget: fn -> {:ok, %{provider_count: -1}} end
      )

    assert result.status == "unhealthy"
    assert Enum.all?(result.checks, fn {_name, check} -> check.status == "error" end)
  end
end
