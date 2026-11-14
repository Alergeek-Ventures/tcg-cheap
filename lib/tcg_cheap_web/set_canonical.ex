defmodule TcgCheapWeb.SetCanonical do
  @moduledoc """
  Permanent redirects to a set page's current URL before LiveView renders.

  The products list with `?rozszerzenie=<id>` and a set page under an old name
  both belong at `/rozszerzenia/<name>-<id>`. HomeLive would patch there too,
  but a patch on the first render answers 302, and Google keeps a temporarily
  redirected URL in its results instead of the set page.

  The card list moved from `/?widok=karty` to `/karty`, keeping its filters.

  Paths are the current region's; `TcgCheapWeb.LegacyPaths` and the root
  resolve the paths before regions with `resolve/2` in one hop.
  """

  use TcgCheapWeb, :verified_routes

  import Plug.Conn

  alias TcgCheap.Sealed.Guide
  alias TcgCheapWeb.{Paths, SEO}

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    # Nested params cannot be carried over; HomeLive ignores them anyway.
    with true <- Enum.all?(conn.query_params, fn {_key, value} -> is_binary(value) end),
         {:ok, path, params} <- resolve(conn.path_params, conn.query_params),
         true <- path != conn.request_path do
      location = if params == %{}, do: path, else: path <> "?" <> URI.encode_query(params)
      conn |> put_resp_header("location", location) |> send_resp(301, "") |> halt()
    else
      _ -> conn
    end
  end

  @doc """
  The current URL of the list or set page with these path params (a set's
  `slug`, none for the home page) and query params, without the params it
  absorbed; :error when the page has no other URL.
  """
  @spec resolve(map(), %{String.t() => String.t()}) ::
          {:ok, String.t(), %{String.t() => String.t()}} | :error
  # Only the home page had the cards view.
  def resolve(path_params, %{"widok" => "karty"} = params) when map_size(path_params) == 0,
    do: {:ok, Paths.cards(), Map.delete(params, "widok")}

  def resolve(path_params, params) do
    with {:ok, id, params} <- expansion(path_params, params),
         name when is_binary(name) <- Map.get(Guide.expansion_names([id]), id) do
      {:ok, SEO.expansion_path(id, name), params}
    else
      _unknown -> :error
    end
  end

  defp expansion(%{"slug" => slug}, params) do
    case Regex.run(~r/-(\d+)\z/, slug) do
      [_, id] -> parse_id(id, params)
      nil -> :error
    end
  end

  defp expansion(_path_params, %{"rozszerzenie" => id} = params) when is_binary(id),
    do: parse_id(id, Map.delete(params, "rozszerzenie"))

  defp expansion(_path_params, _params), do: :error

  defp parse_id(value, params) do
    case Integer.parse(value) do
      {id, ""} when id in 1..9_999_999 -> {:ok, id, params}
      _ -> :error
    end
  end
end
