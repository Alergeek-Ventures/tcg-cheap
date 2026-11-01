defmodule TcgCheapWeb.CSPNonce do
  @moduledoc false

  import Plug.Conn

  alias TcgCheap.Catalogue.ExternalImage

  @nonce_bytes 18
  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes) |> Base.encode64(padding: false)

    {analytics_scripts, analytics_connections} =
      case TcgCheapWeb.Analytics.config(conn) do
        nil -> {"", ""}
        config -> {" #{config.asset_host}", " #{config.api_host}"}
      end

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header(
      "content-security-policy",
      "default-src 'self'; script-src 'self' 'nonce-#{nonce}'#{analytics_scripts}; connect-src 'self' ws: wss:#{analytics_connections}; img-src #{ExternalImage.csp_sources() |> Enum.join(" ")}; style-src 'self' 'unsafe-inline'; font-src 'self' data:"
    )
  end
end
