defmodule TcgCheapWeb.LegacyRedirectController do
  use TcgCheapWeb, :controller

  alias TcgCheapWeb.LegacyPaths

  # Old entry points keep their query and land on its final page in one hop,
  # like any other old home URL.
  def home(conn, _params) do
    {path, query} = LegacyPaths.home(conn.query_params)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: if(query == "", do: path, else: path <> "?" <> query))
  end
end
