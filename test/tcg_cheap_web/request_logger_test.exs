defmodule TcgCheapWeb.RequestLoggerTest do
  use TcgCheapWeb.ConnCase, async: false

  alias Phoenix.LiveDashboard.RequestLogger

  test "a dashboard-issued request logger token enables request-scoped metadata", %{conn: conn} do
    stream = "request-logger-test"
    token = RequestLogger.sign(TcgCheapWeb.Endpoint, "request_logger", stream)
    Logger.metadata([])

    conn = get(conn, "/?request_logger=#{URI.encode_www_form(token)}")

    assert RequestLogger.param_key(conn) == {"request_logger", "request_logger"}

    assert Logger.metadata()[:logger_pubsub_backend] ==
             {TcgCheap.PubSub, RequestLogger.topic(stream)}
  after
    Logger.metadata([])
  end
end
