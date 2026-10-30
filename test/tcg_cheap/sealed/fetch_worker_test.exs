defmodule TcgCheap.Sealed.FetchWorkerTest do
  use TcgCheap.DataCase, async: false

  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{FetchWorker, Refresh, Shops}

  setup do
    %{products: import_catalogue!()}
  end

  defp perform(shop), do: FetchWorker.perform(%Oban.Job{args: %{"shop" => shop}})
  defp today, do: Date.utc_today()
  defp daily(product), do: Sealed.list_price_history!(product.id, today()) |> List.first()
  defp reload(product), do: Sealed.get_product_by_slug!(product.slug)

  test "stores offers, matches them and records today's lowest price", %{products: products} do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    offers = Sealed.list_offers!()
    assert length(offers) == 4
    booster = Enum.find(offers, &(&1.shop_product_id == "16799"))
    assert booster.product_id == products["Pitch Black Booster"].id

    assert Decimal.equal?(daily(products["Pitch Black Booster"]).lowest_price, "24.95")
    assert daily(products["Pitch Black Booster"]).shops_in_stock == 1
    assert %Decimal{} = daily(products["Pitch Black Booster"]).cardmarket_trend

    box = reload(products["Pitch Black Booster Box"])
    assert box.available
    assert Decimal.equal?(box.lowest_price, "799.94")
    assert String.starts_with?(box.image_url, "https://colligere.pl/")
  end

  test "a second shop and a price change update the lowest price", %{products: products} do
    booster = products["Pitch Black Booster"]
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")
    stub_feed([feed("cardzhouse")])
    assert :ok = perform("cardzhouse")
    assert daily(booster).shops_in_stock == 2

    cheaper =
      Enum.map(feed("colligere"), fn
        %{"id" => 16_799} = product -> put_in(product, ["prices", "price"], "2199")
        product -> product
      end)

    stub_feed([cheaper])
    assert :ok = perform("colligere")
    assert Decimal.equal?(daily(booster).lowest_price, "21.99")
    assert Decimal.equal?(reload(booster).lowest_price, "21.99")
  end

  test "offers missing from a shop's latest fetch stop counting", %{products: products} do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")
    stub_feed([Enum.reject(feed("colligere"), &(&1["id"] == 16_799))])
    assert :ok = perform("colligere")

    assert %{lowest_price: nil, shops_in_stock: 0} = daily(products["Pitch Black Booster"])
    refute reload(products["Pitch Black Booster"]).available
  end

  test "manual assignments survive automatic matching and feed the EAN index", %{
    products: products
  } do
    pc_etb = products["Pitch Black Pokémon Center Elite Trainer Box"]

    manual =
      offer!(
        shop: "lootquest",
        title: "Pokémon TCG: Pitch Black – Booster",
        ean: "0820650000003",
        product_id: pc_etb.id,
        manual?: true
      )

    sibling = offer!(shop: "cardzhouse", title: "Coś zupełnie innego", ean: "0820650000003")

    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    assert Sealed.get_offer!(manual.id).product_id == pc_etb.id
    assert Sealed.get_offer!(sibling.id).product_id == pc_etb.id
  end

  test "a failed fetch writes nothing" do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")
    before = {Sealed.list_offers!(), Sealed.list_daily_prices_on!(today())}

    Req.Test.stub(Sealed.WooCommerce, &Plug.Conn.send_resp(&1, 500, "boom"))
    assert {:error, {:http_status, 500}} = perform("colligere")

    Req.Test.stub(Sealed.WooCommerce, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      if conn.query_params["page"] == "1",
        do:
          conn
          |> Plug.Conn.put_resp_header("x-wp-totalpages", "2")
          |> Req.Test.json(feed("cardzhouse")),
        else: Plug.Conn.send_resp(conn, 500, "boom")
    end)

    assert {:error, {:http_status, 500}} = perform("cardzhouse")
    assert {Sealed.list_offers!(), Sealed.list_daily_prices_on!(today())} == before
  end

  test "a shop listing no products counts as a failed fetch and writes nothing", %{
    products: products
  } do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")
    offers = Sealed.list_offers!()
    stub_feed([[]])
    {:ok, shop} = Shops.fetch("colligere")

    assert {:error, :empty_feed} =
             Refresh.run(shop, req_options: [plug: {Req.Test, Sealed.WooCommerce}])

    assert Sealed.list_offers!() == offers
    assert Decimal.equal?(daily(products["Pitch Black Booster"]).lowest_price, "24.95")
  end

  test "rejects unknown shops and malformed arguments" do
    assert {:cancel, :unknown_shop} = perform("evil.example")
    assert {:cancel, :malformed_args} = FetchWorker.perform(%Oban.Job{args: %{}})
  end

  test "jobs are unique per shop and every shop is scheduled daily" do
    assert {:ok, first} = FetchWorker.enqueue("colligere")
    assert {:ok, %{conflict?: true, id: id}} = FetchWorker.enqueue("colligere")
    assert id == first.id

    {Oban.Plugins.Cron, opts} =
      :tcg_cheap
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> List.keyfind(Oban.Plugins.Cron, 0)

    scheduled =
      for {_expr, FetchWorker, job_opts} <- Keyword.fetch!(opts, :crontab),
          do: job_opts[:args]["shop"]

    assert Enum.sort(scheduled) == Enum.sort(Shops.keys())
  end
end
