defmodule TcgCheapWeb.HealthControllerTest do
  use TcgCheapWeb.ConnCase, async: false

  test "health is public JSON and returns a secret-safe no-store projection", %{conn: conn} do
    conn = get(conn, "/health")
    body = json_response(conn, 200)

    assert body["status"] == "healthy"
    assert is_binary(body["timestamp"])
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert Map.keys(body) |> Enum.sort() == ["checks", "status", "timestamp"]
    assert Enum.all?(body["checks"], fn {_name, check} -> check["status"] == "ok" end)
  end

  test "liveness is dependency-independent and not cached", %{conn: conn} do
    conn = get(conn, "/health/live")
    body = json_response(conn, 200)

    assert body["status"] == "healthy"
    assert is_binary(body["timestamp"])
    assert Map.keys(body) |> Enum.sort() == ["status", "timestamp"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end
