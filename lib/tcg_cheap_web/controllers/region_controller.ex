defmodule TcgCheapWeb.RegionController do
  @moduledoc """
  Which region a visitor sees: the region control (and the region hint)
  switches them to another; the root, Poland's home page, sends a visitor who
  chose another region to theirs (`TcgCheapWeb.ChosenRegion`).
  """

  use TcgCheapWeb, :controller

  alias TcgCheapWeb.{Locale, Paths, Region}

  @doc """
  Poland's home page moved from `/pl/` to the root: permanently, its query
  (a search, a campaign's params) along.
  """
  def polish_home(conn, _params) do
    path = Paths.page_path(Region.poland(), :home)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: if(conn.query_string == "", do: path, else: path <> "?" <> conn.query_string))
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
