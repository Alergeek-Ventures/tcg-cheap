defmodule TcgCheapWeb.LocaleController do
  use TcgCheapWeb, :controller

  def update(conn, params) do
    conn
    |> put_session(:locale, TcgCheapWeb.Locale.normalize(params["locale"]))
    |> redirect(to: TcgCheapWeb.Locale.local_path(params["return_to"]))
  end
end
