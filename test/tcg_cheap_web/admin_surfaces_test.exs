defmodule TcgCheapWeb.AdminSurfacesTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheapWeb.ObanResolver

  describe "administrator surfaces" do
    test "unauthenticated HTTP access redirects to sign in", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/admin/dashboard")) == "/admin/sign-in"
      assert redirected_to(get(conn, ~p"/admin/oban")) == "/admin/sign-in"
    end

    test "an unauthenticated targeted review route redirects to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} =
               live(conn, ~p"/admin/review/mappings/00000000-0000-0000-0000-000000000000")
    end

    test "an authenticated administrator can render the runtime dashboard", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/dashboard/home"}}} =
               live(authenticated_conn(conn), ~p"/admin/dashboard")

      assert {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/dashboard/home")

      assert view.module == Phoenix.LiveDashboard.PageLive
    end

    test "authenticated dashboard responses use a per-request CSP nonce", %{conn: conn} do
      first_response = conn |> authenticated_conn() |> get(~p"/admin/dashboard/home")
      second_response = conn |> authenticated_conn() |> get(~p"/admin/dashboard/home")

      [first_policy] = get_resp_header(first_response, "content-security-policy")
      [second_policy] = get_resp_header(second_response, "content-security-policy")

      [first_script_src] = Regex.run(~r/(script-src[^;]*)/, first_policy, capture: :all_but_first)

      [second_script_src] =
        Regex.run(~r/(script-src[^;]*)/, second_policy, capture: :all_but_first)

      assert [first_nonce] =
               Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, first_policy,
                 capture: :all_but_first
               )

      assert [second_nonce] =
               Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, second_policy,
                 capture: :all_but_first
               )

      assert get_resp_header(first_response, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(first_response, "x-permitted-cross-domain-policies") == ["none"]

      assert get_resp_header(first_response, "referrer-policy") == [
               "strict-origin-when-cross-origin"
             ]

      assert first_nonce != second_nonce
      refute first_script_src =~ "'unsafe-inline'"
      refute second_script_src =~ "'unsafe-inline'"
      assert first_policy =~ "font-src 'self' data:"
    end

    test "an authenticated administrator can render the Oban dashboard", %{conn: conn} do
      start_oban_metrics()
      assert {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/oban")

      assert view.module == Oban.Web.DashboardLive
    end

    test "the admin sidebar links to both runtime surfaces", %{conn: conn} do
      assert {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/review")

      assert has_element?(
               view,
               "#admin-catalogue a[href='/admin/dashboard']",
               "Runtime dashboard"
             )

      assert has_element?(view, "#admin-catalogue a[href='/admin/oban']", "Oban dashboard")
    end
  end

  describe "Oban resolver" do
    test "resolves the current administrator from the connection", %{conn: conn} do
      admin = admin()
      conn = %{conn | assigns: Map.put(conn.assigns, :current_admin, admin)}

      assert ObanResolver.resolve_user(conn) == admin
      assert ObanResolver.resolve_access(admin) == :all
      assert ObanResolver.resolve_instances(admin) == :all
    end

    test "denies missing or non-administrator users explicitly" do
      assert ObanResolver.resolve_access(nil) == {:forbidden, "/admin/sign-in"}
      assert ObanResolver.resolve_access(%{}) == {:forbidden, "/admin/sign-in"}
      assert ObanResolver.resolve_instances(nil) == []
      assert ObanResolver.resolve_instances(%{}) == []
    end
  end

  defp authenticated_conn(conn) do
    conn
    |> init_test_session(%{})
    |> AuthenticationPlug.store_in_session(admin())
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "admin-surface-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp start_oban_metrics do
    conf = Oban.config()
    {:ok, met_pid} = Oban.Met.start_link(conf: conf)
    sonar_conf = %{conf | testing: :disabled}
    sonar_name = Oban.Registry.via(Oban, Oban.Sonar)
    {:ok, sonar_pid} = Oban.Sonar.start_link(conf: sonar_conf, name: sonar_name)
    Process.unlink(met_pid)
    Process.unlink(sonar_pid)

    ExUnit.Callbacks.on_exit(fn ->
      Supervisor.stop(met_pid)
      GenServer.stop(sonar_pid)
    end)
  end
end
