defmodule TcgCheapWeb.ProductLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TcgCheap.SealedFixtures

  alias TcgCheapWeb.ProductLive.NotFound

  @slug "pokemon-tcg-pitch-black-booster-box"

  defp history!(prices) do
    prices
    |> Enum.with_index(1)
    |> Enum.each(fn {price, days_ago} ->
      daily_price!(@slug, Date.add(Date.utc_today(), -days_ago), price)
    end)
  end

  defp box_offer!(attrs) do
    offer!(
      Map.merge(
        %{
          product_slug: @slug,
          title: "Pokémon TCG: Mega Evolution – Pitch Black – Booster Box",
          url: "https://colligere.pl/sklep/pokemon-tcg-mega-evolution-pitch-black-booster-box/",
          price: Decimal.new("799.94")
        },
        Map.new(attrs)
      )
    )
  end

  # Median 840: good up to 798 zł, normal up to 924 zł.
  @history ~w(820 830 840 840 840 850 860)

  test "identity, release date, Polish language and the back link", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/produkty/#{@slug}")

    assert html =~ ~s(lang="pl")
    assert has_element?(view, "#product-name", "Pitch Black Booster Box")
    assert has_element?(view, "#product-kind", "Booster Box")
    assert has_element?(view, "#product-set", "Pitch Black")
    assert has_element?(view, "#product-release", "17 lipca 2026")
    assert has_element?(view, "#product-back[href='/']")
    assert has_element?(view, "#guide-footnote", "LootQuest")
  end

  test "good price: cheapest offer, reason and whole-złoty thresholds", %{conn: conn} do
    history!(@history)
    box_offer!(price: Decimal.new("798.50"))

    box_offer!(
      shop: "cardzhouse",
      price: Decimal.new("899.99"),
      url: "https://cardzhouse.pl/product/pitch-black-booster-box/"
    )

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")

    assert has_element?(view, "#verdict-badge.verdict-good", "Dobra cena")
    assert has_element?(view, "#verdict-price", "798,50 zł")

    assert has_element?(
             view,
             "#verdict-shop a[target=_blank][rel='noopener nofollow']",
             "Colligere"
           )

    assert has_element?(view, "#verdict-reason", "Typowa cena z ostatnich 30 dni: 840 zł")

    assert has_element?(
             view,
             "#verdict-thresholds",
             "Do 798 zł – dobra, 799–924 zł – normalna, powyżej – drogo"
           )

    assert has_element?(view, "#verdict-method", "mediana")
  end

  test "normal and expensive prices", %{conn: conn} do
    history!(@history)
    offer = box_offer!(price: Decimal.new("924.99"))

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")
    assert has_element?(view, "#verdict-badge.verdict-normal", "Normalna cena")

    offer!(
      Map.from_struct(offer)
      |> Map.take([:shop, :shop_product_id, :title, :url, :product_slug])
      |> Map.put(:price, Decimal.new("925"))
    )

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")
    assert has_element?(view, "#verdict-badge.verdict-expensive", "Drogo")
  end

  test "insufficient data explains how many days are known", %{conn: conn} do
    history!(~w(820 830 840))
    box_offer!([])

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")
    assert has_element?(view, "#verdict-badge.verdict-insufficient_data", "Za mało danych")
    assert has_element?(view, "#verdict-reason", "Mamy ceny z 3 dni")
    assert has_element?(view, "#verdict-price", "799,94 zł")
    refute has_element?(view, "#verdict-thresholds")
  end

  test "out of stock shows the last known lowest price and still the thresholds", %{conn: conn} do
    history!(@history)
    box_offer!(in_stock: false)

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")
    assert has_element?(view, "#verdict-badge.verdict-out_of_stock", "Brak w sklepach")
    assert has_element?(view, "#verdict-reason", "Ostatnio najtaniej: 820,00 zł")
    assert has_element?(view, "#verdict-thresholds")
    assert has_element?(view, "#offer-list .offer-unavailable .offer-stock", "Niedostępny")
  end

  test "out of stock without any history", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")
    assert has_element?(view, "#verdict-reason", "nie znamy jeszcze jego ceny")
    assert has_element?(view, "#offer-list-empty")
    assert has_element?(view, "#price-history-empty")
  end

  test "offers are in stock first then by price, with shop, freshness and an outbound link", %{
    conn: conn
  } do
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

    expensive =
      box_offer!(
        shop: "lootquest",
        price: Decimal.new("999.99"),
        url: "https://lootquest.pl/produkt/pitch-black-booster-box/",
        last_seen_at: yesterday
      )

    cheap_unavailable =
      box_offer!(
        shop: "cardzhouse",
        price: Decimal.new("700"),
        in_stock: false,
        url: "https://cardzhouse.pl/product/pitch-black-booster-box/"
      )

    cheap = box_offer!([])

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")

    assert has_element?(view, "#offer-list > li:nth-child(2)#offers-#{cheap.id}")
    assert has_element?(view, "#offer-list > li:nth-child(3)#offers-#{expensive.id}")
    assert has_element?(view, "#offer-list > li:nth-child(4)#offers-#{cheap_unavailable.id}")
    assert has_element?(view, "#offers-#{expensive.id} .offer-checked", "wczoraj")
    assert has_element?(view, "#offers-#{cheap.id} .offer-checked", "dziś")

    assert has_element?(
             view,
             "#offers-#{cheap.id} a.offer-link[href='#{cheap.url}'][target=_blank][rel='noopener nofollow']"
           )
  end

  test "the 90-day chart is server-rendered SVG with a text summary", %{conn: conn} do
    history!(@history)
    daily_price!(@slug, Date.add(Date.utc_today(), -20), nil)
    daily_price!(@slug, Date.add(Date.utc_today(), -21), "900")

    {:ok, view, _html} = live(conn, ~p"/produkty/#{@slug}")
    assert has_element?(view, "#price-history svg[role=img] polyline.price-chart-line")
    assert has_element?(view, "#price-history svg line.price-chart-dot")
    assert has_element?(view, "#price-history svg line.price-chart-typical")
    assert has_element?(view, "#price-history-summary", "od 820,00 zł do 900,00 zł")
  end

  test "an unknown product is a 404", %{conn: conn} do
    assert_raise NotFound, fn -> live(conn, ~p"/produkty/nope") end
    assert NotFound.exception([]).plug_status == 404
  end
end
