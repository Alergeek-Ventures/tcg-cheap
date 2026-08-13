defmodule TcgCheapWeb.AdminSessionControllerTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TcgCheap.Accounts

  test "sign-in page is the only public administrator account surface", %{conn: conn} do
    conn = get(conn, ~p"/admin/sign-in")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#admin-login-form") |> Enum.any?()
    assert document |> LazyHTML.query("a[href*='register']") |> Enum.empty?()
  end

  test "password sign-in renews the session and grants review access", %{conn: conn} do
    email = unique_email()
    provision_admin(email, "correct horse battery staple")

    conn =
      post(conn, ~p"/admin/sign-in", %{
        "admin" => %{"email" => email, "password" => "correct horse battery staple"}
      })

    assert redirected_to(conn) == ~p"/admin/review"

    assert {:ok, view, _html} = conn |> recycle() |> live(~p"/admin/review")
    assert has_element?(view, "#admin-review")
    assert has_element?(view, "#admin-catalogue-sign-out")
  end

  test "an unauthenticated review request redirects to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/review")
  end

  test "authentication failures remain generic", %{conn: conn} do
    conn =
      post(conn, ~p"/admin/sign-in", %{
        "admin" => %{"email" => unique_email(), "password" => "incorrect password"}
      })

    document = conn |> html_response(401) |> LazyHTML.from_document()
    assert document |> LazyHTML.query("#admin-login-flash") |> Enum.any?()
    refute document |> LazyHTML.query("[href*='register']") |> Enum.any?()
  end

  test "throttled sign-in failures remain generic", %{conn: conn} do
    conn = %{conn | remote_ip: {198, 51, 100, rem(System.unique_integer([:positive]), 200) + 1}}
    email = unique_email()

    conn =
      Enum.reduce(1..6, conn, fn _attempt, conn ->
        post(conn, ~p"/admin/sign-in", %{
          "admin" => %{"email" => email, "password" => "incorrect password"}
        })
      end)

    document = conn |> html_response(429) |> LazyHTML.from_document()
    assert document |> LazyHTML.query("#admin-login-flash") |> Enum.any?()
    assert get_resp_header(conn, "retry-after") != []
    refute document |> LazyHTML.query("[href*='register']") |> Enum.any?()
  end

  defp provision_admin(email, password) do
    Accounts.register_admin!(
      %{email: email, password: password, password_confirmation: password},
      authorize?: false
    )
  end

  defp unique_email do
    "web-admin-#{System.unique_integer([:positive])}@example.test"
  end
end
