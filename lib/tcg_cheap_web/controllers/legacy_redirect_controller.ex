defmodule TcgCheapWeb.LegacyRedirectController do
  use TcgCheapWeb, :controller

  alias TcgCheapWeb.LegacyPaths

  # These region-less entry points keep their query and land on their final
  # page in one hop, as the root does its filters (`TcgCheapWeb.SetCanonical`).
  def home(conn, _params) do
    {path, query} = LegacyPaths.home(conn.query_params)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: if(query == "", do: path, else: path <> "?" <> query))
  end
end
