defmodule TcgCheapWeb.SetCanonical do
  @moduledoc """
  Permanent redirects to a set page's current URL before LiveView renders.

  The products list with `?rozszerzenie=<id>` and a set page under a name it no
  longer has both belong at `/rozszerzenia/<name>-<id>`. BrowseLive would patch there too,
  but a patch on the first render answers 302, and Google keeps a temporarily
  redirected URL in its results instead of the set page.

  The card list lives at `/karty`; `/?widok=karty` redirects there, keeping
  its filters.

  Paths are the current region's; `TcgCheapWeb.LegacyPaths` and the root
  resolve the region-less URLs with `resolve/2` in one hop.
  """

  use TcgCheapWeb, :verified_routes

  import Plug.Conn

  alias TcgCheap.Sealed.Guide
  alias TcgCheapWeb.{Paths, SEO}

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    # Nested params cannot be carried over; BrowseLive ignores them anyway.
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
  # Only the home page takes the `widok=karty` view parameter.
  def resolve(path_params, %{"widok" => "karty"} = params) when map_size(path_params) == 0,
    do: {:ok, Paths.cards(), Map.delete(params, "widok")}

  def resolve(path_params, params) do
    with {:ok, id, params} <- expansion(path_params, params),
         name when is_binary(name) <- Map.get(Guide.expansion_names([id]), id) do
      {:ok, SEO.Expansion.path(id, name), params}
    else
      _unknown -> :error
    end
  end

  defp expansion(%{"slug" => slug}, params) do
    with {:ok, id} <- Paths.expansion_id(slug), do: {:ok, id, params}
  end

  defp expansion(_path_params, %{"rozszerzenie" => id} = params) when is_binary(id) do
    with {:ok, id} <- Paths.expansion_id_param(id),
         do: {:ok, id, Map.delete(params, "rozszerzenie")}
  end

  defp expansion(_path_params, _params), do: :error
end
