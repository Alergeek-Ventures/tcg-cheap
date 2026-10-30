defmodule TcgCheap.Sealed.FetchWorkerTest do
  use TcgCheap.DataCase, async: false

  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Catalogue, FetchWorker, Refresh, Shops}

  @booster "pokemon-tcg-pitch-black-booster-pack"
  @booster_box "pokemon-tcg-pitch-black-booster-box"

  defp perform(shop), do: FetchWorker.perform(%Oban.Job{args: %{"shop" => shop}})

  defp today, do: Date.utc_today()

  defp daily(slug) do
    Sealed.list_price_history!(slug, today()) |> List.first()
  end

  test "stores every seen offer with its match and records today's lowest prices" do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    offers = Sealed.list_offers!()
    assert length(offers) == 4
    assert Enum.all?(offers, &(&1.shop == "colligere"))

    booster = Enum.find(offers, &(&1.shop_product_id == "16799"))
    assert booster.product_slug == @booster
    assert Decimal.equal?(booster.price, "24.95")

    assert Decimal.equal?(daily(@booster).lowest_price, "24.95")
    assert daily(@booster).shops_in_stock == 1
    assert Decimal.equal?(daily(@booster_box).lowest_price, "799.94")

    # Every catalogue product gets today's row, stocked or not.
    assert length(Sealed.list_daily_prices_since!(today())) == length(Catalogue.all())

    assert %{lowest_price: nil, shops_in_stock: 0} =
             daily("pokemon-tcg-scarlet-violet-151-booster-bundle")
  end

  test "a second fetch updates offers in place and takes the cheapest shop" do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")
    stub_feed([feed("cardzhouse")])
    assert :ok = perform("cardzhouse")

    assert Decimal.equal?(daily(@booster).lowest_price, "24.95")
    assert daily(@booster).shops_in_stock == 2

    cheaper =
      Enum.map(feed("colligere"), fn
        %{"id" => 16_799} = product -> put_in(product, ["prices", "price"], "2199")
        product -> product
      end)

    stub_feed([cheaper])
    assert :ok = perform("colligere")

    assert length(Enum.filter(Sealed.list_offers!(), &(&1.shop == "colligere"))) == 4
    assert Decimal.equal?(daily(@booster).lowest_price, "21.99")
  end

  test "offers missing from a shop's latest fetch stop counting" do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    without_booster = Enum.reject(feed("colligere"), &(&1["id"] == 16_799))
    stub_feed([without_booster])
    assert :ok = perform("colligere")

    assert %{lowest_price: nil} = daily(@booster)
    refute Enum.any?(Sealed.current_offers(DateTime.utc_now()), &(&1.shop_product_id == "16799"))
  end

  test "re-matches every stored offer, including other shops'" do
    offer =
      offer!(
        shop: "lootquest",
        title: "Pokémon TCG: Pitch Black – Booster",
        product_slug: "stale-slug"
      )

    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    assert Ash.get!(Sealed.Offer, offer.id, domain: Sealed).product_slug == @booster
  end

  test "out-of-stock and stale offers do not set the lowest price" do
    offer!(shop: "lootquest", price: Decimal.new("10"), in_stock: false)

    offer!(
      shop: "cardzhouse",
      price: Decimal.new("11"),
      last_seen_at: DateTime.add(DateTime.utc_now(), -4, :day)
    )

    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    assert Decimal.equal?(daily(@booster).lowest_price, "24.95")
  end

  test "a failed fetch writes nothing" do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")
    before = {Sealed.list_offers!(), Sealed.list_daily_prices_since!(today())}

    Req.Test.stub(Sealed.WooCommerce, &Plug.Conn.send_resp(&1, 500, "boom"))
    assert {:error, {:http_status, 500}} = perform("colligere")

    page_two_fails = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      if conn.query_params["page"] == "1",
        do:
          conn
          |> Plug.Conn.put_resp_header("x-wp-totalpages", "2")
          |> Req.Test.json(feed("cardzhouse")),
        else: Plug.Conn.send_resp(conn, 500, "boom")
    end

    Req.Test.stub(Sealed.WooCommerce, page_two_fails)
    assert {:error, {:http_status, 500}} = perform("cardzhouse")

    assert {Sealed.list_offers!(), Sealed.list_daily_prices_since!(today())} == before
  end

  test "rejects unknown shops and malformed arguments" do
    assert {:cancel, :unknown_shop} = perform("evil.example")
    assert {:cancel, :malformed_args} = FetchWorker.perform(%Oban.Job{args: %{}})
  end

  test "jobs are unique per shop" do
    assert {:ok, first} = FetchWorker.enqueue("colligere")
    assert {:ok, second} = FetchWorker.enqueue("colligere")
    assert second.conflict?
    assert first.id == second.id
    assert {:ok, %{conflict?: false}} = FetchWorker.enqueue("lootquest")
  end

  test "every shop has a daily cron entry" do
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

  test "an empty feed still refreshes daily prices" do
    stub_feed([feed("colligere")])
    assert :ok = perform("colligere")

    Req.Test.stub(Sealed.WooCommerce, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json([])
    end)

    {:ok, shop} = Shops.fetch("boosterland")

    assert {:ok, %{offers: 0}} =
             Refresh.run(shop, req_options: [plug: {Req.Test, Sealed.WooCommerce}])

    assert Decimal.equal?(daily(@booster).lowest_price, "24.95")
  end
end
