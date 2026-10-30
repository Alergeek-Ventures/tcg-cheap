defmodule TcgCheapWeb.Admin.BuyingGuideLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TcgCheap.SealedFixtures

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.{Accounts, Sealed}

  setup do
    %{products: import_catalogue!()}
  end

  test "requires an administrator", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/buying-guide")
  end

  test "shows per-shop fetch results and current unmatched offers", %{
    conn: conn,
    products: products
  } do
    box = products["Pitch Black Booster Box"]
    at = DateTime.utc_now()
    offer!(product_id: box.id, last_seen_at: at)
    offer!(product_id: box.id, in_stock: false, last_seen_at: at)

    unmatched =
      offer!(
        title: "Pokémon TCG: Mega Moonlit Tin",
        price: Decimal.new("149.99"),
        url: "https://colligere.pl/sklep/mega-moonlit-tin/",
        last_seen_at: at
      )

    offer!(title: "Pokémon TCG: Delta Reign – Booster (PREORDER)", last_seen_at: at)

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/buying-guide")

    assert has_element?(view, "#admin-buying-guide-title", "Buying guide")
    assert has_element?(view, "#admin-buying-guide", "60 catalogue products")
    assert has_element?(view, "#buying-guide-shop-colligere td:nth-of-type(2)", "4")
    assert has_element?(view, "#buying-guide-shop-colligere td:nth-of-type(3)", "2")
    assert has_element?(view, "#buying-guide-shop-colligere td:nth-of-type(4)", "1")
    assert has_element?(view, "#buying-guide-shop-lootquest td:nth-of-type(1)", "never")
    assert has_element?(view, "#unmatched-#{unmatched.id}", "Mega Moonlit Tin")

    assert has_element?(
             view,
             "#unmatched-#{unmatched.id} a[href='#{unmatched.url}'][rel='noopener nofollow']"
           )

    assert has_element?(view, "#buying-guide-unmatched-count", "1 unmatched · 1 excluded")
  end

  test "assigns an offer by hand and clears the assignment", %{conn: conn, products: products} do
    offer = offer!(title: "Pokémon TCG: Mega Evolution – Pitch Black – 3-Pack Blister")
    binacle = products["Pitch Black: Binacle 3-Pack Blister"]

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/buying-guide")

    view |> element("#start-assign-#{offer.id}") |> render_click()
    assert has_element?(view, "#buying-guide-assign", "3-Pack Blister")

    view
    |> form("#buying-guide-product-search", %{product_search: %{query: "binacle"}})
    |> render_change()

    assert has_element?(view, "#result-#{binacle.id}", "Pitch Black: Binacle 3-Pack Blister")

    view |> element("#assign-#{binacle.id}") |> render_click()
    assert has_element?(view, "#flash-info", "Offer assigned")
    refute has_element?(view, "#unmatched-#{offer.id}")
    assert has_element?(view, "#manual-#{offer.id}", "Pitch Black: Binacle 3-Pack Blister")

    stored = Sealed.get_offer!(offer.id)
    assert stored.manual?
    assert stored.product_id == binacle.id
    assert Sealed.get_product_by_slug!(binacle.slug).available

    view |> element("#clear-manual-#{offer.id}") |> render_click()
    assert has_element?(view, "#unmatched-#{offer.id}")
    refute Sealed.get_offer!(offer.id).manual?
  end

  test "has no write controls other than assignment", %{conn: conn} do
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/buying-guide")
    refute has_element?(view, "#admin-buying-guide form")
    assert has_element?(view, "#buying-guide-unmatched-empty")
    assert has_element?(view, "#buying-guide-manual-empty")
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
