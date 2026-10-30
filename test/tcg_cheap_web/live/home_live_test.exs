defmodule TcgCheapWeb.HomeLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed.Catalogue

  @booster "pokemon-tcg-pitch-black-booster-pack"

  test "renders the Polish promise, search, navigation and every product newest first", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ ~s(lang="pl")
    assert has_element?(view, "#guide-title", "Sprawdź, czy cena jest dobra")
    assert has_element?(view, "#guide-search-form input#guide-search-query[name=q]")
    assert has_element?(view, "label[for=guide-search-query]", "Szukaj produktu")
    assert has_element?(view, "#site-nav-buying[aria-current=page][href='/']", "Zakupy")
    assert has_element?(view, "#site-nav-trading[href='/trade']", "Wymiany")
    assert has_element?(view, "#guide-footnote", "Ceny bez kosztów wysyłki")
    refute has_element?(view, "#mode-switch")

    count = length(Catalogue.all())
    assert has_element?(view, "#guide-result-count", "#{count} produktów")

    [newest | _] = Catalogue.all()
    assert has_element?(view, "#guide-products > li:nth-child(2)#product-#{newest.slug}")
  end

  test "rows show the cheapest current offer, its shop and the verdict", %{conn: conn} do
    offer!(price: Decimal.new("24.95"))
    offer!(shop: "lootquest", price: Decimal.new("29.99"))
    offer!(shop: "cardzhouse", price: Decimal.new("19.99"), in_stock: false)

    {:ok, view, _html} = live(conn, ~p"/")

    row = "#product-#{@booster}"
    assert has_element?(view, "#{row} a[href='/produkty/#{@booster}']")
    assert has_element?(view, "#{row} .guide-product-price", "24,95 zł")
    assert has_element?(view, "#{row} .guide-product-price", "Colligere")
    assert has_element?(view, "#verdict-#{@booster}.verdict-insufficient_data", "Za mało danych")

    assert has_element?(
             view,
             "#verdict-pokemon-tcg-scarlet-violet-151-booster-bundle.verdict-out_of_stock",
             "Brak w sklepach"
           )
  end

  test "a judged price shows its verdict on the list", %{conn: conn} do
    for days_ago <- 1..7, do: daily_price!(@booster, Date.add(Date.utc_today(), -days_ago), "30")
    offer!(price: Decimal.new("24.95"))

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#verdict-#{@booster}.verdict-good", "Dobra cena")
  end

  test "searching filters the list and keeps the query in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> form("#guide-search-form", %{q: "pitch black booster box"}) |> render_change()
    assert_patch(view, "/?q=pitch+black+booster+box")

    assert has_element?(view, "#product-pokemon-tcg-pitch-black-booster-box")
    refute has_element?(view, "#product-#{@booster}")
    assert has_element?(view, "#guide-result-count", "1 produkt")
    assert has_element?(view, "#guide-results-title", "Wyniki wyszukiwania")
  end

  test "a query in the URL is applied on load, and no results shows the empty state", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/?q=etb 151")
    assert has_element?(view, "#guide-search-query[value='etb 151']")
    assert has_element?(view, "#product-pokemon-tcg-scarlet-violet-151-elite-trainer-box")

    {:ok, view, _html} = live(conn, ~p"/?q=digimon")
    assert has_element?(view, "#guide-products-empty", "digimon")
    assert has_element?(view, "#guide-result-count", "0 produktów")
  end

  test "clearing the search shows everything again", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?q=pitch")
    view |> form("#guide-search-form", %{q: "  "}) |> render_change()
    assert_patch(view, ~p"/")
    assert has_element?(view, "#guide-result-count", "#{length(Catalogue.all())} produktów")
  end
end
