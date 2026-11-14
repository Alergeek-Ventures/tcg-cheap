defmodule TcgCheapWeb.RegionController do
  @moduledoc """
  Which region a visitor sees: the root sends them to theirs, the region
  control (and the region hint) switches them to another.
  """

  use TcgCheapWeb, :controller

  alias TcgCheapWeb.{LegacyPaths, Locale, Paths, Region}

  # The products list's filters (`TcgCheapWeb.HomeLive`) and its old cards view.
  @list_params ~w(q rodzaj wersja rozszerzenie widok)

  @doc """
  The root redirects to the region the visitor chose (the `region` cookie),
  else to their country's (Cloudflare's `cf-ipcountry`), else to Poland's,
  which crawlers get. A temporary, uncached redirect, as it differs by
  visitor; no other page redirects by country. Other query params (a
  campaign's) go along.

  The home page before regions with the list's filters is an old Polish URL
  like the others: it moves permanently, in one hop, to its Polish page
  (`TcgCheapWeb.LegacyPaths.home/1`).
  """
  def root(conn, _params) do
    conn = conn |> fetch_cookies() |> fetch_query_params()

    if Enum.any?(@list_params, &Map.has_key?(conn.query_params, &1)) do
      {path, query} = LegacyPaths.home(conn.query_params)

      conn
      |> put_status(:moved_permanently)
      |> redirect(to: if(query == "", do: path, else: path <> "?" <> query))
    else
      region =
        case Region.fetch(conn.cookies[Locale.region_cookie()]) do
          {:ok, region} -> region
          :error -> conn |> get_req_header("cf-ipcountry") |> List.first() |> Region.for_country()
        end

      path = Paths.page_path(region, :home)
      path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("vary", "cookie")
      |> redirect(to: path)
    end
  end

  @doc """
  Switches to a region and remembers it: to the same page there when it has
  one (`Paths.switch/2`), else to its home page. Choosing the current
  region dismisses the region hint.
  """
  def switch(conn, %{"code" => code} = params) do
    case Region.fetch(code) do
      {:ok, region} ->
        path = params["path"] |> Locale.local_path() |> URI.parse() |> Map.fetch!(:path)

        conn
        |> Locale.put_region_cookie(region)
        |> put_resp_header("cache-control", "private, no-store")
        |> redirect(to: Paths.switch(path || "/", region))

      :error ->
        conn |> put_status(:not_found) |> text("")
    end
  end
end
