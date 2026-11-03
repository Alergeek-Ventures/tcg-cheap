defmodule TcgCheapWeb.LegacyRedirectController do
  use TcgCheapWeb, :controller

  def home(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/")
  end
end
