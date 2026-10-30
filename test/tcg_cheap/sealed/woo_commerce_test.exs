defmodule TcgCheap.Sealed.WooCommerceTest do
  use ExUnit.Case, async: true

  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed.{Shops, WooCommerce}

  @plug {Req.Test, WooCommerce}

  defp fetch(shop_key \\ "colligere", opts \\ []) do
    {:ok, shop} = Shops.fetch(shop_key)
    WooCommerce.fetch(shop, Keyword.put(opts, :plug, @plug))
  end

  defp product(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 16_799,
        "name" => "Pokémon TCG: Mega Evolution &#8211; Pitch Black &#8211; Booster",
        "permalink" =>
          "https://colligere.pl/sklep/pokemon-tcg-mega-evolution-pitch-black-booster/",
        "sku" => "",
        "prices" => %{"price" => "2495", "currency_code" => "PLN", "currency_minor_unit" => 2},
        "images" => [%{"src" => "https://colligere.pl/wp-content/uploads/booster.webp"}],
        "categories" => [%{"slug" => "pokemon-tcg"}],
        "is_purchasable" => true,
        "is_in_stock" => true,
        "is_on_backorder" => false
      },
      overrides
    )
  end

  describe "real feed fixtures" do
    test "normalizes Colligere products" do
      stub_feed([feed("colligere")])
      assert {:ok, offers} = fetch()

      booster = Enum.find(offers, &(&1.shop_product_id == "16799"))
      assert booster.title == "Pokémon TCG: Mega Evolution – Pitch Black – Booster"
      assert Decimal.equal?(booster.price, "24.95")
      assert booster.in_stock

      assert booster.url ==
               "https://colligere.pl/sklep/pokemon-tcg-mega-evolution-pitch-black-booster/"

      assert String.starts_with?(booster.image_url, "https://colligere.pl/wp-content/uploads/")
      assert length(offers) == 4
    end

    test "drops products outside the shop's sealed categories" do
      stub_feed([feed("lootquest")])
      assert {:ok, offers} = fetch("lootquest")

      titles = Enum.map(offers, & &1.title)
      assert "Pokémon TCG: 30th Celebration – Elite Trainer Box" in titles
      refute Enum.any?(titles, &String.contains?(&1, "PRO-Binder"))
      assert length(offers) == length(feed("lootquest")) - 1
    end

    test "reads every page up to the reported total" do
      [first | rest] = feed("cardzhouse")
      stub_feed([[first], rest])

      assert {:ok, offers} = fetch("cardzhouse")
      assert length(offers) == length(feed("cardzhouse"))
    end
  end

  describe "untrusted product fields" do
    test "backorders and unpurchasable products are not in stock" do
      stub_feed([
        [
          product(%{"id" => 1, "is_on_backorder" => true}),
          product(%{"id" => 2, "is_purchasable" => false}),
          product(%{"id" => 3, "is_in_stock" => false})
        ]
      ])

      assert {:ok, offers} = fetch()
      assert Enum.map(offers, & &1.in_stock) == [false, false, false]
    end

    test "skips products with an invalid id, title, permalink or price" do
      long_title = String.duplicate("a", 301)

      stub_feed([
        [
          product(%{"id" => 1}),
          product(%{"id" => -2}),
          product(%{"id" => "3"}),
          product(%{"id" => 4, "name" => ""}),
          product(%{"id" => 5, "name" => long_title}),
          product(%{"id" => 6, "permalink" => "http://colligere.pl/sklep/a/"}),
          product(%{"id" => 7, "permalink" => "https://evil.example/sklep/a/"}),
          product(%{"id" => 8, "permalink" => "https://colligere.pl.evil.example/sklep/a/"}),
          product(%{"id" => 9, "permalink" => "https://user@colligere.pl/sklep/a/"}),
          product(%{"id" => 10, "permalink" => "https://colligere.pl/sklep/a/?redirect=x"}),
          product(%{"id" => 11, "permalink" => "https://colligere.pl:8443/sklep/a/"}),
          product(%{"id" => 12, "permalink" => "https://colligere.pl/wp-admin/a/"}),
          product(%{
            "id" => 13,
            "prices" => %{"price" => "0", "currency_code" => "PLN", "currency_minor_unit" => 2}
          }),
          product(%{
            "id" => 14,
            "prices" => %{"price" => "12.5", "currency_code" => "PLN", "currency_minor_unit" => 2}
          }),
          product(%{
            "id" => 15,
            "prices" => %{"price" => "2495", "currency_code" => "EUR", "currency_minor_unit" => 2}
          }),
          product(%{
            "id" => 16,
            "prices" => %{"price" => "2495", "currency_code" => "PLN", "currency_minor_unit" => 9}
          }),
          product(%{"id" => 17, "prices" => nil}),
          "not a product"
        ]
      ])

      assert {:ok, [offer]} = fetch()
      assert offer.shop_product_id == "1"
    end

    test "parses prices in minor units" do
      stub_feed([
        [
          product(%{
            "id" => 1,
            "prices" => %{
              "price" => "129999",
              "currency_code" => "PLN",
              "currency_minor_unit" => 2
            }
          }),
          product(%{
            "id" => 2,
            "prices" => %{"price" => "150", "currency_code" => "PLN", "currency_minor_unit" => 0}
          })
        ]
      ])

      assert {:ok, [first, second]} = fetch()
      assert Decimal.equal?(first.price, "1299.99")
      assert Decimal.equal?(second.price, "150")
    end

    test "keeps images only from the shop's own HTTPS host" do
      stub_feed([
        [
          product(%{"id" => 1, "images" => [%{"src" => "https://evil.example/x.webp"}]}),
          product(%{"id" => 2, "images" => [%{"src" => "javascript:alert(1)"}]}),
          product(%{"id" => 3, "images" => "nope"})
        ]
      ])

      assert {:ok, offers} = fetch()
      assert Enum.all?(offers, &is_nil(&1.image_url))
    end

    test "decodes entities and reads EANs only from 12–13 digit SKUs with a valid check digit" do
      stub_feed([
        [
          product(%{
            "id" => 1,
            "name" => "Booster &amp; Box &#x2013; &quot;151&quot; &bogus;",
            "sku" => "196214144606"
          }),
          product(%{"id" => 2, "sku" => "0196214144606"}),
          product(%{"id" => 3, "sku" => "196214146273-1-1"}),
          product(%{"id" => 4, "sku" => "0196214144607"})
        ]
      ])

      assert {:ok, [first, second, third, fourth]} = fetch()
      assert first.title == "Booster & Box – \"151\" &bogus;"
      assert first.ean == "0196214144606"
      assert second.ean == "0196214144606"
      assert third.ean == nil
      assert fourth.ean == nil
    end

    test "returns each shop product once" do
      stub_feed([[product(%{"id" => 1}), product(%{"id" => 1, "name" => "duplicate"})]])
      assert {:ok, [offer]} = fetch()
      assert offer.title =~ "Pitch Black"
    end
  end

  describe "hostile or broken responses fail the whole fetch" do
    test "HTTP errors and redirects" do
      Req.Test.stub(WooCommerce, &Plug.Conn.send_resp(&1, 503, "down"))
      assert {:error, {:http_status, 503}} = fetch()

      Req.Test.stub(WooCommerce, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://evil.example/")
        |> Plug.Conn.send_resp(302, "")
      end)

      assert {:error, {:http_status, 302}} = fetch()
    end

    test "transport errors" do
      Req.Test.stub(WooCommerce, &Req.Test.transport_error(&1, :timeout))
      assert {:error, {:transport, Req.TransportError}} = fetch()
    end

    test "malformed JSON or a non-list body" do
      Req.Test.stub(WooCommerce, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
        |> Plug.Conn.send_resp(200, "{nope")
      end)

      assert {:error, :malformed_response} = fetch()

      Req.Test.stub(WooCommerce, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
        |> Req.Test.json(%{"code" => "x"})
      end)

      assert {:error, :malformed_response} = fetch()
    end

    test "missing, invalid or changing pagination" do
      Req.Test.stub(WooCommerce, &Req.Test.json(&1, [product()]))
      assert {:error, :malformed_pagination} = fetch()

      Req.Test.stub(WooCommerce, fn conn ->
        conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "0") |> Req.Test.json([product()])
      end)

      assert {:error, :malformed_pagination} = fetch()

      counter = :counters.new(1, [])

      Req.Test.stub(WooCommerce, fn conn ->
        :counters.add(counter, 1, 1)
        total = if :counters.get(counter, 1) == 1, do: "2", else: "3"
        conn |> Plug.Conn.put_resp_header("x-wp-totalpages", total) |> Req.Test.json([product()])
      end)

      assert {:error, :pagination_changed} = fetch()
    end

    test "more pages than the shop's bound" do
      Req.Test.stub(WooCommerce, fn conn ->
        conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "4") |> Req.Test.json([product()])
      end)

      assert {:error, :too_many_pages} = fetch()
    end

    test "oversized responses" do
      Req.Test.stub(WooCommerce, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
        |> Plug.Conn.send_resp(200, String.duplicate(" ", 2_000_001))
      end)

      assert {:error, :response_too_large} = fetch()
    end
  end

  test "requests only the shop's fixed endpoint and categories" do
    test_pid = self()

    Req.Test.stub(WooCommerce, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test_pid, {:request, conn.host, conn.request_path, conn.query_params})
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json([])
    end)

    assert {:ok, []} = fetch("pokebooster")
    assert_received {:request, "pokebooster.pl", "/wp-json/wc/store/v1/products", params}
    assert params["category"] == "26,27,42,57"
    assert params["per_page"] == "100"
  end
end
