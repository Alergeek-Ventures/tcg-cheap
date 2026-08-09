defmodule TcgCheapWeb.AdminAuth do
  @moduledoc "Administrator route and LiveView authentication boundary."

  use TcgCheapWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Plug.Conn, only: [halt: 1, put_session: 3]

  alias TcgCheap.Accounts.Admin

  def init(opts), do: opts

  def call(%{assigns: %{current_admin: %Admin{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_session(:admin_return_to, Phoenix.Controller.current_path(conn))
    |> Phoenix.Controller.put_flash(:error, "Sign in to open the review desk.")
    |> Phoenix.Controller.redirect(to: ~p"/admin/sign-in")
    |> halt()
  end

  def on_mount(:require_admin, _params, _session, %{assigns: %{current_admin: %Admin{}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:require_admin, _params, _session, socket) do
    {:halt,
     socket
     |> assign(:current_admin, nil)
     |> Phoenix.LiveView.put_flash(:error, "Sign in to open the review desk.")
     |> Phoenix.LiveView.redirect(to: ~p"/admin/sign-in")}
  end
end
