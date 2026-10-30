defmodule TcgCheapWeb.ProductLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed.Refresh
  alias TcgCheapWeb.ProductLive.NotFound

  setup do
    product =
      product!(
        name: "Pitch Black Booster Box",
        cardmarket_trend: Decimal.new("200.00"),
        cardmarket_low: Decimal.new("180.00"),
        cardmarket_avg: Decimal.new("190.00"),
        cardmarket_price_updated_on: Date.utc_today()
      )

    %{product: product}
  end

  defp history!(product, prices) do
    prices
    |> Enum.with_index(1)
    |> Enum.each(fn {price, days_ago} ->
      daily_price!(product.id, Date.add(Date.utc_today(), -days_ago), price)
    end)
  end

  defp box_offer!(product, attrs \\ []) do
    offer = offer!(Map.merge(%{product_id: product.id}, Map.new(attrs)))
    Refresh.recompute(DateTime.utc_now())
    offer
  end

  # Median 840: good up to 798 zł, normal up to 924 zł.
  @history ~w(820 830 840 840 840 850 860)

  test "identity, Cardmarket date, Polish language and the back link", %{
    conn: conn,
    product: product
  } do
    {:ok, view, html} = live(conn, ~p"/produkty/#{product.slug}")

    assert html =~ ~s(lang="pl")
    assert has_element?(view, "#product-name", "Pitch Black Booster Box")
    assert has_element?(view, "#product-kind", "Booster Box")
    assert has_element?(view, "#product-set", "Pitch Black")
    assert has_element?(view, "#product-added", "od 30 kwietnia 2026")
    assert has_element?(view, "#product-back[href='/']")
    assert has_element?(view, ".product-image-placeholder svg[aria-label='Brak zdjęcia']")
  end

  test "good price from Polish history with whole-złoty thresholds", %{
    conn: conn,
    product: product
  } do
    history!(product, @history)

    box_offer!(product,
      price: Decimal.new("798"),
      image_url: "https://colligere.pl/wp-content/uploads/box.webp"
    )

    box_offer!(product,
      shop: "cardzhouse",
      price: Decimal.new("899.99"),
      url: "https://cardzhouse.pl/product/pitch-black-booster-box/"
    )

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")

    assert has_element?(view, "#verdict-badge.verdict-good", "Dobra cena")
    assert has_element?(view, "#verdict-price", "798,00\u00A0zł")

    assert has_element?(
             view,
             "#verdict-shop a[target=_blank][rel='noopener nofollow']",
             "Colligere"
           )

    assert has_element?(view, "#verdict-reason", "Typowa cena z ostatnich 30 dni: 840\u00A0zł")

    assert has_element?(view, "#verdict-difference", "Teraz o 42\u00A0zł (5%) taniej.")

    assert has_element?(
             view,
             "#verdict-thresholds #threshold-good[aria-current]",
             "do 798\u00A0zł"
           )

    assert has_element?(view, "#verdict-thresholds #threshold-normal", "do 924\u00A0zł")
    assert has_element?(view, "#verdict-thresholds #threshold-expensive", "powyżej 924\u00A0zł")
    refute has_element?(view, "#threshold-normal[aria-current]")

    assert has_element?(view, ".product-image img[src^='https://colligere.pl/']")
  end

  test "normal and expensive prices", %{conn: conn, product: product} do
    history!(product, @history)
    offer = box_offer!(product, price: Decimal.new("924"))
    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    assert has_element?(view, "#verdict-badge.verdict-normal", "Normalna cena")

    box_offer!(product, shop_product_id: offer.shop_product_id, price: Decimal.new("924.01"))
    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    assert has_element?(view, "#verdict-badge.verdict-expensive", "Drogo")
  end

  test "without enough Polish history the Cardmarket trend is the reference", %{
    conn: conn,
    product: product
  } do
    exchange_rate!("4.2000")
    history!(product, ~w(820 830))
    box_offer!(product, price: Decimal.new("790"))

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")

    # 200 € × 4.20 = 840 zł.
    assert has_element?(
             view,
             "#verdict-reason",
             "Typowa cena na Cardmarket (europejska giełda, bez wysyłki): 840\u00A0zł"
           )

    assert has_element?(view, "#verdict-badge.verdict-good")
    assert has_element?(view, "#cardmarket-trend", "200,00\u00A0€")
    assert has_element?(view, "#cardmarket-trend", "840\u00A0zł")
    assert has_element?(view, "#cardmarket-low", "180,00\u00A0€")
    assert has_element?(view, "#product-cardmarket", "4,2")
  end

  test "insufficient data without Polish history or a rate", %{conn: conn, product: product} do
    history!(product, ~w(820 830 840))
    box_offer!(product)

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    assert has_element?(view, "#verdict-badge.verdict-insufficient_data", "Za mało danych")
    # Three past days plus today's offer.
    assert has_element?(view, "#verdict-reason", "Znamy ceny dopiero z 4 dni")
    refute has_element?(view, "#verdict-thresholds")
  end

  test "out of stock shows the last known lowest price", %{conn: conn, product: product} do
    history!(product, @history)
    box_offer!(product, in_stock: false)

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    assert has_element?(view, "#verdict-badge.verdict-out_of_stock", "Brak na stanie")
    assert has_element?(view, "#verdict-reason", "Ostatnio najtaniej: 820,00\u00A0zł")
    assert has_element?(view, "#threshold-good")
    refute has_element?(view, "#verdict-thresholds [aria-current]")
    refute has_element?(view, "#verdict-difference")
    assert has_element?(view, "#offer-list .offer-unavailable .offer-stock", "Brak na stanie")
  end

  test "offers are in stock first then by price, with freshness and an outbound link", %{
    conn: conn,
    product: product
  } do
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

    expensive =
      offer!(
        product_id: product.id,
        shop: "lootquest",
        price: Decimal.new("999.99"),
        url: "https://lootquest.pl/produkt/pitch-black-booster-box/",
        last_seen_at: yesterday
      )

    unavailable =
      offer!(
        product_id: product.id,
        shop: "cardzhouse",
        price: Decimal.new("700"),
        in_stock: false,
        url: "https://cardzhouse.pl/product/pitch-black-booster-box/"
      )

    cheap = box_offer!(product)

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")

    assert has_element?(view, "#offer-list > li:nth-child(2)#offers-#{cheap.id}")
    assert has_element?(view, "#offer-list > li:nth-child(3)#offers-#{expensive.id}")
    assert has_element?(view, "#offer-list > li:nth-child(4)#offers-#{unavailable.id}")
    assert has_element?(view, "#offers-#{expensive.id} .offer-checked", "wczoraj")

    assert has_element?(
             view,
             "#offers-#{cheap.id} a.offer-link[href='#{cheap.url}'][target=_blank][rel='noopener nofollow']"
           )
  end

  test "the chart shows the Polish lowest price and the Cardmarket trend in złoty", %{
    conn: conn,
    product: product
  } do
    exchange_rate!("4.0000")

    for days_ago <- 1..5 do
      daily_price!(product.id, Date.add(Date.utc_today(), -days_ago), "820",
        cardmarket_trend: "210"
      )
    end

    daily_price!(product.id, Date.add(Date.utc_today(), -20), "900")

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    assert has_element?(view, "#price-history svg[role=img] polyline.price-chart-shops")
    assert has_element?(view, "#price-history svg polyline.price-chart-cardmarket")
    assert has_element?(view, "#price-history svg line.price-chart-dot")

    assert has_element?(
             view,
             "#price-history-summary-shops",
             "820,00\u00A0zł–900,00\u00A0zł"
           )

    assert has_element?(view, "#price-history-summary-cardmarket", "840,00\u00A0zł")
  end

  test "a single day of history is a sentence, not a chart", %{conn: conn, product: product} do
    exchange_rate!("4.0000")
    daily_price!(product.id, Date.utc_today(), "820", cardmarket_trend: "210")

    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    refute has_element?(view, "#price-history svg")

    assert has_element?(
             view,
             "#price-history-single",
             "820,00\u00A0zł w sklepach i 840,00\u00A0zł na Cardmarket"
           )
  end

  test "no history yet", %{conn: conn, product: product} do
    {:ok, view, _html} = live(conn, ~p"/produkty/#{product.slug}")
    assert has_element?(view, "#price-history-empty")
    assert has_element?(view, "#offer-list-empty")
  end

  test "an unknown product is a 404", %{conn: conn} do
    assert_raise NotFound, fn -> live(conn, ~p"/produkty/nope") end
    assert NotFound.exception([]).plug_status == 404
  end
end
