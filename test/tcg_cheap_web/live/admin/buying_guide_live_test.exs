defmodule TcgCheapWeb.Admin.BuyingGuideLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TcgCheap.SealedFixtures

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts

  test "requires an administrator", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/buying-guide")
  end

  test "shows per-shop fetch results and current unmatched offers", %{conn: conn} do
    fetched_at = DateTime.utc_now()
    offer!(last_seen_at: fetched_at)
    offer!(last_seen_at: fetched_at, in_stock: false)

    unmatched =
      offer!(
        last_seen_at: fetched_at,
        title: "Pokémon TCG: Mega Moonlit Tin",
        product_slug: nil,
        price: Decimal.new("149.99"),
        url: "https://colligere.pl/sklep/mega-moonlit-tin/"
      )

    offer!(
      last_seen_at: fetched_at,
      title: "Pokémon TCG: Delta Reign – Booster (PREORDER)",
      product_slug: nil
    )

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/buying-guide")

    assert has_element?(view, "#admin-buying-guide-title", "Buying guide")
    assert has_element?(view, "#admin-catalogue a[href='/admin/buying-guide']")
    assert has_element?(view, "#buying-guide-shop-colligere td:nth-of-type(2)", "4")
    assert has_element?(view, "#buying-guide-shop-colligere td:nth-of-type(3)", "2")
    assert has_element?(view, "#buying-guide-shop-colligere td:nth-of-type(4)", "1")
    assert has_element?(view, "#buying-guide-shop-lootquest td:nth-of-type(1)", "never")

    assert has_element?(view, "#unmatched-#{unmatched.id}", "Mega Moonlit Tin")
    assert has_element?(view, "#unmatched-#{unmatched.id}", "149,99 zł")

    assert has_element?(
             view,
             "#unmatched-#{unmatched.id} a[href='#{unmatched.url}'][rel='noopener nofollow']"
           )

    assert has_element?(view, "#buying-guide-unmatched-count", "1 unmatched · 1 excluded")
    refute has_element?(view, "#buying-guide-unmatched-list", "PREORDER")
  end

  test "is read only", %{conn: conn} do
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/buying-guide")
    refute has_element?(view, "#admin-buying-guide button")
    refute has_element?(view, "#admin-buying-guide form")
    assert has_element?(view, "#buying-guide-unmatched-empty")
  end

  defp authenticated_conn(conn) do
    admin =
      Accounts.register_admin!(
        %{
          email: "guide-#{System.unique_integer([:positive])}@example.test",
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        },
        authorize?: false
      )

    conn |> init_test_session(%{}) |> AuthenticationPlug.store_in_session(admin)
  end
end
