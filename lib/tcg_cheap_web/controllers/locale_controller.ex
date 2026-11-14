defmodule TcgCheapWeb.LocaleController do
  @moduledoc """
  The `/lang/:locale` links (the language control works without JavaScript):
  remembers the language in its cookie (`TcgCheapWeb.Locale`) and returns to
  the page. An unknown language leaves the choice as it was.
  """

  use TcgCheapWeb, :controller

  alias TcgCheapWeb.{Locale, Region}

  def update(conn, params) do
    conn =
      case Region.language(params["locale"]) do
        nil -> conn
        language -> Locale.put_language_cookie(conn, language)
      end

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> redirect(to: Locale.local_path(params["return_to"]))
  end
end
