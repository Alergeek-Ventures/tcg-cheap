defmodule TcgCheapWeb.AnalyticsProxy do
  @moduledoc """
  Relays PostHog SDK requests through fixed, opaque same-origin routes.

  Runs before Plug.Parsers to preserve compressed event bodies. Only the
  configured ingestion host and its asset host can receive requests.
  """

  @behaviour Plug

  alias Plug.Conn
  alias TcgCheapWeb.Analytics

  @methods ~w(GET HEAD POST)
  @request_headers ~w(accept content-type content-encoding user-agent x-forwarded-for)
  @response_headers ~w(content-type content-encoding cache-control)
  @body_limit 1_000_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case proxy_path(conn.request_path) do
      {prefix, path} ->
        if Analytics.config(conn), do: proxy(conn, prefix, path), else: conn

      nil ->
        conn
    end
  end

  defp proxy(conn, prefix, path) do
    cond do
      conn.method not in @methods ->
        conn
        |> Conn.put_resp_header("allow", Enum.join(@methods, ", "))
        |> reject(:method_not_allowed)

      not safe_suffix?(conn.request_path, prefix) ->
        reject(conn, :bad_request)

      true ->
        case read_body(conn) do
          {:ok, body, conn} -> request(conn, path, body)
          {:error, status} -> reject(conn, status)
        end
    end
  end

  defp proxy_path(path) do
    Enum.find_value(Analytics.proxy_paths(), fn {original, prefix} ->
      if String.starts_with?(path, prefix),
        do: {prefix, original <> String.replace_prefix(path, prefix, "")}
    end)
  end

  defp safe_suffix?(path, prefix) do
    suffix = String.replace_prefix(path, prefix, "")

    suffix == "" or
      Regex.match?(
        ~r/^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*(?:\/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)*\/?$/,
        suffix
      )
  end

  defp read_body(conn) when conn.method in ["GET", "HEAD"], do: {:ok, "", conn}

  defp read_body(conn) do
    case Conn.read_body(conn, length: @body_limit + 1) do
      {:ok, body, conn} when byte_size(body) <= @body_limit -> {:ok, body, conn}
      {:ok, _body, _conn} -> {:error, :request_entity_too_large}
      {:more, _body, _conn} -> {:error, :request_entity_too_large}
      {:error, _reason} -> {:error, :bad_request}
    end
  end

  defp request(conn, path, body) do
    case Req.request(
           method: method(conn.method),
           url: upstream_url(path) <> query(conn),
           body: body,
           headers: request_headers(conn),
           raw: true,
           redirect: false,
           retry: false
         ) do
      {:ok, response} ->
        conn
        |> response_headers(response.headers)
        |> send_response(response.status, response.body)

      {:error, _reason} ->
        reject(conn, :bad_gateway)
    end
  end

  defp upstream_url(path) do
    host = Application.fetch_env!(:tcg_cheap, :posthog) |> Keyword.fetch!(:api_host)

    host =
      if String.starts_with?(path, ["/static/", "/array/"]),
        do: String.replace(host, ".i.posthog.com", "-assets.i.posthog.com"),
        else: host

    host <> path
  end

  defp request_headers(conn) do
    headers = Enum.filter(conn.req_headers, fn {name, _value} -> name in @request_headers end)

    if List.keymember?(headers, "x-forwarded-for", 0),
      do: headers,
      else: [{"x-forwarded-for", conn.remote_ip |> :inet.ntoa() |> to_string()} | headers]
  end

  defp response_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {name, values}, conn ->
      if name in @response_headers,
        do: Conn.put_resp_header(conn, name, List.first(List.wrap(values))),
        else: conn
    end)
  end

  defp query(%{query_string: ""}), do: ""
  defp query(%{query_string: query}), do: "?" <> query

  defp method("GET"), do: :get
  defp method("HEAD"), do: :head
  defp method("POST"), do: :post

  # sobelow_skip ["XSS.SendResp"]
  # Opaque bytes from the configured PostHog upstream, never interpolated into HTML.
  defp send_response(conn, status, body), do: conn |> Conn.send_resp(status, body) |> Conn.halt()

  defp reject(conn, status), do: conn |> Conn.send_resp(status, "") |> Conn.halt()
end
