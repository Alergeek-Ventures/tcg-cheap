defmodule TcgCheapWeb.HomeLiveTest do
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase

  test "GET / renders the foundation homepage", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "TCG Cheap"
    assert html =~ "Ash + LiveView foundation ready"
  end
end
