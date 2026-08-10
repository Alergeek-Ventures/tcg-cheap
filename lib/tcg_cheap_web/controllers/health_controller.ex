defmodule TcgCheapWeb.HealthController do
  use TcgCheapWeb, :controller

  alias TcgCheap.Operations.Health

  def live(conn, _params) do
    respond(conn, 200, %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    })
  end

  def index(conn, _params) do
    result = Health.check()
    status = if result.status == "healthy", do: 200, else: 503

    respond(conn, status, result)
  end

  defp respond(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(body)
  end
end
