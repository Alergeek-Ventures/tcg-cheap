defmodule TcgCheapWeb.HealthControllerTest do
  use TcgCheapWeb.ConnCase, async: false

  test "health includes the deployed revision in a secret-safe no-store projection", %{conn: conn} do
    with_source_commit(" 0123456789abcdef0123456789abcdef01234567 ", fn ->
      conn = get(conn, "/health")
      body = json_response(conn, 200)

      assert body["status"] == "healthy"
      assert body["revision"] == "0123456789abcdef0123456789abcdef01234567"
      assert is_binary(body["timestamp"])
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert Map.keys(body) |> Enum.sort() == ["checks", "revision", "status", "timestamp"]
      assert Enum.all?(body["checks"], fn {_name, check} -> check["status"] == "ok" end)
    end)
  end

  test "liveness includes the same revision and remains dependency-independent", %{conn: conn} do
    with_source_commit(String.duplicate("a", 64), fn ->
      conn = get(conn, "/health/live")
      body = json_response(conn, 200)

      assert body["status"] == "healthy"
      assert body["revision"] == String.duplicate("a", 64)
      assert is_binary(body["timestamp"])
      assert Map.keys(body) |> Enum.sort() == ["revision", "status", "timestamp"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end)
  end

  test "missing and blank SOURCE_COMMIT values normalize to unknown", %{conn: conn} do
    for source_commit <- [nil, "", "   \t\n"] do
      with_source_commit(source_commit, fn ->
        body = conn |> get("/health/live") |> json_response(200)
        assert body["revision"] == "unknown"
      end)
    end
  end

  test "malformed and oversized SOURCE_COMMIT values do not echo", %{conn: conn} do
    for source_commit <- ["deployed-revision", "123456z", String.duplicate("a", 65)] do
      with_source_commit(source_commit, fn ->
        body = conn |> get("/health/live") |> json_response(200)
        assert body["revision"] == "unknown"
        refute body["revision"] == source_commit
      end)
    end
  end

  defp with_source_commit(source_commit, fun) do
    previous = System.get_env("SOURCE_COMMIT")

    if is_nil(source_commit) do
      System.delete_env("SOURCE_COMMIT")
    else
      System.put_env("SOURCE_COMMIT", source_commit)
    end

    try do
      fun.()
    after
      if is_nil(previous) do
        System.delete_env("SOURCE_COMMIT")
      else
        System.put_env("SOURCE_COMMIT", previous)
      end
    end
  end
end
