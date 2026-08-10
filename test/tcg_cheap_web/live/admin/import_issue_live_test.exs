defmodule TcgCheapWeb.Admin.ImportIssueLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TcgCheap.Accounts
  alias TcgCheap.Operations
  alias TcgCheap.Operations.ImportIssue
  alias TcgCheap.Operations.ImportIssues

  test "anonymous visitors are redirected and non-admin reads are forbidden", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/sign-in"}}} =
             live(conn, "/admin/operations/import-issues")

    assert {:error, _} = Ash.read(ImportIssue, domain: Operations)
  end

  test "authenticated index and show expose only normalized issue evidence", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    provider_key = "sealed_retailer:shop_#{suffix}"
    target_key = Ecto.UUID.generate()
    now = ~U[2026-01-02 03:04:05.000000Z]

    assert :ok =
             ImportIssues.record(
               provider_key,
               "sealed_retailer_refresh",
               "listing_validation",
               "retailer",
               target_key,
               {:malformed_listing, {:bearer_secret, "payload-secret"}},
               now
             )

    latest_target = Ecto.UUID.generate()

    assert :ok =
             ImportIssues.record(
               provider_key,
               "sealed_retailer_refresh",
               "listing_validation",
               "retailer",
               latest_target,
               {:malformed_response, :latest},
               DateTime.add(now, 1, :second)
             )

    {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)
    issue = Enum.find(issues, &(&1.provider_key == provider_key and &1.target_key == target_key))
    assert issue
    conn = authenticated_conn(conn)

    {:ok, index, _html} = live(conn, "/admin/operations/import-issues")
    assert has_element?(index, "td", provider_key)
    assert has_element?(index, "td", target_key)
    assert has_element?(index, "td", "malformed_response")
    assert has_element?(index, "td", "2026")
    assert has_element?(index, "td", latest_target)
    assert has_element?(index, "a", "Import issues")
    refute has_element?(index, "a[href*='/edit']")
    refute has_element?(index, "button", "Delete")
    refute has_element?(index, "body", "payload-secret")

    {:ok, show, _html} = live(conn, "/admin/operations/import-issues/#{issue.id}/show")
    assert has_element?(show, "p", provider_key)
    assert has_element?(show, "p", target_key)
    assert has_element?(show, "p", "2026")
    refute has_element?(show, "body", "payload-secret")
    refute has_element?(show, "a[href*='/edit']")
    refute has_element?(show, "button", "Delete")

    assert get(conn, "/admin/operations/import-issues/#{issue.id}/edit").status == 404
  end

  defp authenticated_conn(conn) do
    email = "import-issues-admin-#{System.unique_integer([:positive])}@example.test"
    password = "correct horse battery staple"

    Accounts.register_admin!(
      %{email: email, password: password, password_confirmation: password},
      authorize?: false
    )

    conn
    |> post(~p"/admin/sign-in", %{"admin" => %{"email" => email, "password" => password}})
    |> recycle()
  end
end
