defmodule TcgCheapWeb.HomeLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed.Refresh

  setup do
    %{products: import_catalogue!()}
  end

  test "renders the Polish promise, search, kinds and navigation", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ ~s(lang="pl")
    assert has_element?(view, "#guide-title", "Sprawdź, czy cena jest dobra")
    assert has_element?(view, "#guide-search-form input#guide-search-query[name=q]")
    assert has_element?(view, "label[for=guide-search-query]", "Szukaj produktu")
    assert has_element?(view, "#kind-all[aria-current]", "Wszystkie")
    assert has_element?(view, "#kind-elite_trainer_box", "Elite Trainer Box")
    assert has_element?(view, "#site-nav-buying[aria-current=page][href='/']", "Zakupy")
    assert has_element?(view, "#site-nav-trading[href='/trade']", "Wymiany")
    assert has_element?(view, "#guide-result-count", "60 produktów")
    assert has_element?(view, "#guide-footnote", "Cardmarket")
  end

  test "products in stock in Poland come first, then the newest", %{
    conn: conn,
    products: products
  } do
    box = products["Pitch Black Booster Box"]
    offer!(product_id: box.id)
    Refresh.recompute(DateTime.utc_now())

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#guide-products > li:nth-child(2)#product-#{box.slug}")
    assert has_element?(view, "#product-#{box.slug} .guide-product-price", "799,94\u00A0zł")
    assert has_element?(view, "#product-#{box.slug} .guide-product-price", "Colligere")
  end

  test "pages with Pokaż więcej", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#guide-products > li.guide-product", "")
    assert view |> element("#guide-products") |> render() |> count_rows() == 30

    view |> element("#guide-more") |> render_click()
    assert view |> element("#guide-products") |> render() |> count_rows() == 60
    refute has_element?(view, "#guide-more")
  end

  test "searching filters through the database and keeps the query in the URL", %{
    conn: conn,
    products: products
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> form("#guide-search-form", %{q: "pitch black etb"}) |> render_change()
    assert_patch(view, "/?q=pitch+black+etb")

    assert has_element?(view, "#product-#{products["Pitch Black Elite Trainer Box"].slug}")

    assert has_element?(
             view,
             "#product-#{products["Pitch Black Pokémon Center Elite Trainer Box"].slug}"
           )

    refute has_element?(view, "#product-#{products["Pitch Black Booster"].slug}")
  end

  test "kind chips filter and combine with the query", %{conn: conn, products: products} do
    {:ok, view, _html} = live(conn, ~p"/?q=pitch")
    view |> element("#kind-booster") |> render_click()
    assert_patch(view, "/?q=pitch&rodzaj=booster")

    assert has_element?(view, "#kind-booster[aria-current]")
    assert has_element?(view, "#product-#{products["Pitch Black Booster"].slug}")
    assert has_element?(view, "#product-#{products["Pitch Black Sleeved Booster"].slug}")
    refute has_element?(view, "#product-#{products["Pitch Black Booster Box"].slug}")
    assert has_element?(view, "#guide-result-count", "2 produkty")
  end

  test "an unknown kind is ignored and no results show the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?rodzaj=nope")
    assert has_element?(view, "#kind-all[aria-current]")

    {:ok, view, _html} = live(conn, ~p"/?q=digimon")
    assert has_element?(view, "#guide-products-empty")
    assert has_element?(view, "#guide-result-count", "0 produktów")
  end

  test "out-of-stock rows show the Cardmarket reference in złoty", %{
    conn: conn,
    products: products
  } do
    exchange_rate!("4.2500")
    box = products["Pitch Black Booster Box"]

    {:ok, view, _html} = live(conn, ~p"/?q=pitch black booster box")
    expected = box.cardmarket_trend |> Decimal.mult("4.25") |> TcgCheapWeb.Polish.zloty()

    assert has_element?(
             view,
             "#product-#{box.slug} .guide-product-price",
             "Cardmarket ≈ #{expected}"
           )

    assert has_element?(view, "#verdict-#{box.slug}.verdict-out_of_stock")
  end

  defp count_rows(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query("li.guide-product") |> Enum.count()
end
