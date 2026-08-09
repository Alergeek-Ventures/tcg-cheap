defmodule TcgCheapWeb.AdminSessionController do
  use TcgCheapWeb, :controller

  alias AshAuthentication.Phoenix.Controller, as: AuthenticationController
  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Accounts.Admin
  alias TcgCheapWeb.AdminLoginLimiter

  def new(%{assigns: %{current_admin: %Admin{}}} = conn, _params) do
    redirect(conn, to: ~p"/admin/review")
  end

  def new(conn, _params) do
    render(conn, :new,
      page_title: "Admin sign in",
      form: Phoenix.Component.to_form(%{"email" => ""}, as: :admin)
    )
  end

  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    with :ok <- AdminLoginLimiter.reserve(conn.remote_ip, email),
         {:ok, admin} <-
           Accounts.sign_in_admin(%{email: email, password: password},
             context: %{private: %{ash_authentication?: true}}
           ) do
      AdminLoginLimiter.clear(conn.remote_ip, email)
      return_to = get_session(conn, :admin_return_to) || ~p"/admin/review"

      conn
      |> renew_session()
      |> AuthenticationPlug.store_in_session(admin)
      |> assign(:current_admin, admin)
      |> redirect(to: return_to)
    else
      {:error, retry_after} when is_integer(retry_after) ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> put_flash(:error, "Too many sign-in attempts. Wait and try again.")
        |> render(:new,
          page_title: "Admin sign in",
          form: Phoenix.Component.to_form(%{"email" => email}, as: :admin)
        )

      {:error, _error} ->
        conn
        |> put_flash(:error, "Email or password is incorrect.")
        |> put_status(:unauthorized)
        |> render(:new,
          page_title: "Admin sign in",
          form: Phoenix.Component.to_form(%{"email" => email}, as: :admin)
        )
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Enter an email and password.")
    |> put_status(:unprocessable_entity)
    |> render(:new,
      page_title: "Admin sign in",
      form: Phoenix.Component.to_form(%{"email" => ""}, as: :admin)
    )
  end

  def delete(conn, _params) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      TcgCheapWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> AuthenticationController.clear_session(:tcg_cheap)
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/admin/sign-in")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> Plug.Conn.clear_session()
  end
end
