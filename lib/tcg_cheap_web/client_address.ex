defmodule TcgCheapWeb.ClientAddress do
  @moduledoc false

  alias Plug.Conn

  @doc """
  The visitor's address as a string: the `CF-Connecting-IP` header when present,
  otherwise the first `X-Forwarded-For` entry, otherwise `conn.remote_ip`.

  Behind the production reverse proxy `conn.remote_ip` is the proxy's address
  for every visitor, so the forwarded headers are the only source of the
  visitor's own address. They are trustworthy because requests reach the app
  only through that proxy (and Cloudflare in front of it), which sets them. A
  request that reaches the app directly can choose its own value, so use the
  result to group requests (rate-limit keys, geolocation), never to authorize
  them; a per-account limit still bounds attempts on any single account.
  """
  @spec get(Conn.t()) :: String.t()
  def get(conn) do
    case Conn.get_req_header(conn, "cf-connecting-ip") ++
           Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] -> value |> String.split(",", parts: 2) |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
