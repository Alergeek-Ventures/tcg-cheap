defmodule TcgCheapWeb.McpAuth do
  @moduledoc """
  Admits MCP requests carrying `Authorization: Bearer <MCP_API_TOKEN>`.

  The token is compared in constant time. Without a configured token (the
  `MCP_API_TOKEN` environment variable unset) every request is refused. The
  router skips this plug in development.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with expected when is_binary(expected) <- token(),
         ["Bearer " <> given] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(digest(given), digest(expected)) do
      conn
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="tcg_cheap_mcp"))
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"unauthorized"}))
        |> halt()
    end
  end

  # Equal-length digests keep the comparison from leaking the token length.
  defp digest(token), do: :crypto.hash(:sha256, token)

  defp token, do: Application.get_env(:tcg_cheap, __MODULE__, [])[:token]
end
