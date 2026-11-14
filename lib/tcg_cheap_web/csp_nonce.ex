defmodule TcgCheapWeb.CSPNonce do
  @moduledoc false

  import Plug.Conn

  alias TcgCheap.Sealed.ExternalImage

  @nonce_bytes 18
  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes) |> Base.encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce))
  end

  # base-uri, form-action and frame-ancestors do not fall back to default-src,
  # so they are listed explicitly.
  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "connect-src 'self' ws: wss:",
        "img-src #{Enum.join(ExternalImage.csp_sources(), " ")}",
        "style-src 'self' 'unsafe-inline'",
        "font-src 'self' data:",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'self'",
        "object-src 'none'"
      ],
      "; "
    )
  end
end
