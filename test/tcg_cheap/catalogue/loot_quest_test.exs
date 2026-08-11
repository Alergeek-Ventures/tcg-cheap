defmodule TcgCheap.Catalogue.LootQuestTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.SealedRetailers.LootQuest

  @retailer %{source_key: "lootquest", status: "active"}

  defp options(name, extra \\ []),
    do:
      [
        plug: {Req.Test, name},
        clock: fn -> ~U[2026-08-09 12:00:00Z] end
      ] ++ extra

  defp fixture do
    "test/fixtures/loot_quest/products.json" |> File.read!() |> Jason.decode!()
  end

  test "requests the fixed endpoint and normalizes the observed fixture" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.request_path == "/wp-json/wc/store/v1/products"
      assert conn.params["category"] == "55"
      assert conn.params["page"] == "1"
      assert conn.params["_fields"] =~ "tags"
      assert conn.params["_fields"] =~ "is_on_backorder"
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(fixture())
    end)

    assert {:ok, [listing]} = LootQuest.fetch_listings(@retailer, options(name))
    assert listing.source_listing_id == "165955"
    assert listing.source_title == "Pokémon TCG: First Partner Illustration Collection – Series 3"

    assert listing.direct_url ==
             "https://lootquest.pl/produkt/pokemon-tcg-first-partner-illustration-collection-series-3/"

    assert Decimal.equal?(listing.current_price_pln, Decimal.new("249.99"))
    assert listing.stock_status == "in_stock"
    assert Map.has_key?(listing.source_payload, "tags")
    refute Map.has_key?(listing.source_payload, "backorders_allowed")
  end

  test "uses total-pages headers and preserves page order" do
    name = make_ref()
    admissions = :counters.new(1, [:atomics])
    [first | _] = fixture()

    products = [
      first,
      first
      |> Map.put("id", 165_956)
      |> Map.put("name", "Pokémon TCG: Second Collection")
      |> Map.put("permalink", "https://lootquest.pl/produkt/pokemon-tcg-second-collection/"),
      first
      |> Map.put("id", 165_957)
      |> Map.put("name", "Pokémon TCG: Third Collection")
      |> Map.put("permalink", "https://lootquest.pl/produkt/pokemon-tcg-third-collection/")
    ]

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      page = conn.params["page"]
      body = if page == "1", do: Enum.take(products, 2), else: Enum.drop(products, 2)
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "2") |> Req.Test.json(body)
    end)

    assert {:ok, listings} =
             LootQuest.fetch_listings(
               @retailer,
               options(name,
                 per_page: 2,
                 request_admitter: fn ->
                   :counters.add(admissions, 1, 1)
                   :ok
                 end
               )
             )

    assert Enum.map(listings, & &1.source_listing_id) == ["165955", "165956", "165957"]
    assert :counters.get(admissions, 1) == 2
  end

  test "stops pagination before a rejected outbound request" do
    name = make_ref()
    attempts = :counters.new(1, [:atomics])
    [product | _] = fixture()

    Req.Test.stub(name, fn conn ->
      :counters.add(attempts, 1, 1)
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "2") |> Req.Test.json([product])
    end)

    admissions = :counters.new(1, [:atomics])

    admitter = fn ->
      :counters.add(admissions, 1, 1)

      if :counters.get(admissions, 1) == 1,
        do: :ok,
        else: {:error, {:acquisition_budget_rejected, :hourly_limit_reached}}
    end

    assert {:error, {:acquisition_budget_rejected, :hourly_limit_reached}} =
             LootQuest.fetch_listings(
               @retailer,
               options(name, per_page: 1, request_admitter: admitter)
             )

    assert :counters.get(admissions, 1) == 2
    assert :counters.get(attempts, 1) == 1
  end

  test "reports a page-count change after the first page as transient" do
    name = make_ref()
    [product | _] = fixture()

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      pages = if conn.params["page"] == "1", do: "2", else: "3"
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", pages) |> Req.Test.json([product])
    end)

    assert {:error, :pagination_changed} =
             LootQuest.fetch_listings(@retailer, options(name, per_page: 1))
  end

  test "rejects malformed pagination and hostile product links" do
    name = make_ref()
    Req.Test.stub(name, fn conn -> Req.Test.json(conn, fixture()) end)
    assert {:error, :malformed_pagination} = LootQuest.fetch_listings(@retailer, options(name))

    name = make_ref()

    bad =
      fixture()
      |> List.first()
      |> Map.put("permalink", "https://evil.example/product")
      |> List.wrap()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(bad)
    end)

    assert {:error, :malformed_shape} = LootQuest.fetch_listings(@retailer, options(name))
  end

  test "rejects same-host product links with a trailing newline" do
    name = make_ref()
    [product | _] = fixture()

    Req.Test.stub(name, fn conn ->
      body = [Map.put(product, "permalink", "https://lootquest.pl/produkt/valid-product/\n")]
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(body)
    end)

    assert {:error, :malformed_shape} = LootQuest.fetch_listings(@retailer, options(name))
  end

  test "does not retry HTTP failures or re-admit the request" do
    name = make_ref()
    admissions = :counters.new(1, [:atomics])
    requests = :counters.new(1, [:atomics])

    Req.Test.stub(name, fn conn ->
      :counters.add(requests, 1, 1)
      conn |> Plug.Conn.put_status(503) |> Req.Test.text("")
    end)

    assert {:error, {:http_error, %{status: 503}}} =
             LootQuest.fetch_listings(
               @retailer,
               options(name,
                 request_admitter: fn ->
                   :counters.add(admissions, 1, 1)
                   :ok
                 end
               )
             )

    assert :counters.get(admissions, 1) == 1
    assert :counters.get(requests, 1) == 1
  end

  test "rejects unsafe options and bounded totals" do
    assert {:error, :invalid_options} = LootQuest.fetch_listings(@retailer, per_page: 101)

    assert {:error, :invalid_options} =
             LootQuest.fetch_listings(@retailer, per_page: 100, max_pages: 11)

    assert {:error, :invalid_options} =
             LootQuest.fetch_listings(@retailer, retry: false, retry: false)

    assert {:error, :invalid_retailer} = LootQuest.fetch_listings(%{}, [])

    assert {:error, :retailer_disabled} =
             LootQuest.fetch_listings(%{@retailer | status: "disabled"}, [])

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "3") |> Req.Test.json([])
    end)

    assert {:error, :invalid_pagination} =
             LootQuest.fetch_listings(@retailer, options(name, max_pages: 2))
  end

  test "rejects oversized pages and response bodies before normalization" do
    [product | _] = fixture()
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
      |> Req.Test.json([product, product])
    end)

    assert {:error, :malformed_pagination} =
             LootQuest.fetch_listings(@retailer, options(name, per_page: 1))

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
      |> Req.Test.text(String.duplicate("x", 2_000_001))
    end)

    assert {:error, :response_too_large} = LootQuest.fetch_listings(@retailer, options(name))
  end

  test "classifies HTTP, transport, JSON, and shape failures" do
    for {status, expected} <- [
          {429, {:error, {:rate_limited, %{status: 429, retry_after_seconds: nil}}}},
          {503, {:error, {:http_error, %{status: 503}}}},
          {404, {:error, {:http_error, %{status: 404}}}}
        ] do
      name = make_ref()
      Req.Test.stub(name, &(&1 |> Plug.Conn.put_status(status) |> Req.Test.text("")))
      assert ^expected = LootQuest.fetch_listings(@retailer, options(name))
    end

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.text("{")
    end)

    assert {:error, :malformed_json} = LootQuest.fetch_listings(@retailer, options(name))

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(%{})
    end)

    assert {:error, :malformed_shape} = LootQuest.fetch_listings(@retailer, options(name))

    name = make_ref()
    Req.Test.stub(name, &Req.Test.transport_error(&1, :closed))

    assert {:error, {:transport_error, %Req.TransportError{reason: :closed}}} =
             LootQuest.fetch_listings(@retailer, options(name))
  end

  test "does not follow redirects and retains bounded retry-after seconds" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_status(302)
      |> Plug.Conn.put_resp_header("location", "http://127.0.0.1/internal")
      |> Req.Test.text("")
    end)

    assert {:error, {:http_error, %{status: 302}}} =
             LootQuest.fetch_listings(@retailer, options(name))

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Plug.Conn.put_resp_header("retry-after", "120")
      |> Req.Test.text("")
    end)

    assert {:error, {:rate_limited, %{status: 429, retry_after_seconds: 120}}} =
             LootQuest.fetch_listings(@retailer, options(name))
  end

  test "strictly validates source fields and skips preorders and imports" do
    [eligible, imported] = fixture()

    preorder =
      eligible
      |> Map.put("id", 165_958)
      |> Map.put("name", "Pokémon TCG: Future Collection")
      |> Map.put("permalink", "https://lootquest.pl/produkt/pokemon-tcg-future-collection/")
      |> Map.put("tags", [%{"slug" => "pokemon-tcg-preorder"}])

    backorder =
      eligible
      |> Map.put("id", 165_959)
      |> Map.put("permalink", "https://lootquest.pl/produkt/pokemon-tcg-backorder/")
      |> Map.put("is_on_backorder", true)

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
      |> Req.Test.json([eligible, imported, preorder, backorder])
    end)

    assert {:ok, [%{source_listing_id: "165955"}]} =
             LootQuest.fetch_listings(@retailer, options(name))

    malformed = Map.delete(eligible, "is_on_backorder")
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json([malformed])
    end)

    assert {:error, :malformed_shape} = LootQuest.fetch_listings(@retailer, options(name))
  end

  test "normalizes sold-out prices and safely decodes supported entities" do
    [product | _] = fixture()

    product =
      product
      |> Map.put("name", "Box &#8222;A&#8221; &amp; &#xD800;")
      |> Map.put("prices", %{
        "price" => "249",
        "currency_code" => "PLN",
        "currency_minor_unit" => 0
      })
      |> Map.put("is_purchasable", false)
      |> Map.put("is_in_stock", false)

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json([product])
    end)

    assert {:ok, [listing]} = LootQuest.fetch_listings(@retailer, options(name))
    assert listing.source_title == "Box „A” & &#xD800;"
    assert listing.current_price_pln == Decimal.new(249)
    assert listing.stock_status == "sold_out"
  end
end
