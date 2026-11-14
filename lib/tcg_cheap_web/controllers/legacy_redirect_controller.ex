defmodule TcgCheapWeb.LegacyRedirectController do
  use TcgCheapWeb, :controller

  alias TcgCheapWeb.{Paths, Region}

  def home(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: Paths.page_path(Region.poland(), :home))
  end
end
