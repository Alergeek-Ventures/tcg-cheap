defmodule TcgCheapWeb.ChosenRegion do
  @moduledoc """
  The root is Poland's home page, for everyone who has not chosen a region:
  visitors from another region's country see it with the region hint
  (`TcgCheapWeb.Locale`), as search engines see it, never a redirect by
  country. A visitor who chose another region (the `region` cookie, set only
  by the region control) goes to that region's home page instead, its query
  along: a temporary, uncached redirect, as it differs by visitor.
  """

  import Plug.Conn

  alias TcgCheapWeb.{Locale, Paths, Region}

  def init(opts), do: opts

  def call(conn, _opts) do
    # Added to the markdown negotiation's `accept`, not in its place.
    conn =
      conn |> fetch_cookies() |> update_resp_header("vary", "cookie", &(&1 <> ", cookie"))

    with {:ok, region} <- Region.fetch(conn.cookies[Locale.region_cookie()]),
         false <- Region.poland?(region) do
      path = Paths.page_path(region, :home)
      path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> Phoenix.Controller.redirect(to: path)
      |> halt()
    else
      _poland_or_none -> conn
    end
  end
end
