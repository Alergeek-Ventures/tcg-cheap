defmodule TcgCheapWeb.RegionController do
  @moduledoc """
  Which region a visitor sees: the root sends them to theirs, the region
  control (and the region hint) switches them to another.
  """

  use TcgCheapWeb, :controller

  alias TcgCheapWeb.{LegacyPaths, Locale, Paths, Region}

  # The products list's filters (`TcgCheapWeb.BrowseLive`) and `widok`, the
  # card list's former view parameter.
  @list_params ~w(q rodzaj wersja rozszerzenie widok)

  @doc """
  The root redirects to the region the visitor chose (the `region` cookie),
  else to their country's (Cloudflare's `cf-ipcountry`), else to Poland's,
  which crawlers get. A temporary, uncached redirect, as it differs by
  visitor; no other page redirects by country. Other query params (a
  campaign's) go along.

  The root with the list's filters is a URL from before the region prefixes
  that search engines still hold: it moves permanently, in one hop, to its
  Polish page (`TcgCheapWeb.LegacyPaths.home/1`).
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
  one (`Paths.switch/2`), else to its home page, in the region's own
  language – a visitor who changes country gets that country's version.
  Choosing the current region keeps the language and dismisses the region
  hint.
  """
  def switch(conn, %{"code" => code} = params) do
    case Region.fetch(code) do
      {:ok, region} ->
        path = params["path"] |> Locale.local_path() |> URI.parse() |> Map.fetch!(:path)

        conn
        |> Locale.put_region_cookie(region)
        |> put_region_language(region, path)
        |> put_resp_header("cache-control", "private, no-store")
        |> redirect(to: Paths.switch(path || "/", region))

      :error ->
        conn |> put_status(:not_found) |> text("")
    end
  end

  defp put_region_language(conn, region, path) do
    case Paths.parse(path || "/") do
      {:ok, %Region{code: code}, _page} when code == region.code -> conn
      _other -> Locale.put_language_cookie(conn, region.language)
    end
  end
end
