defmodule TcgCheap.Sealed.CatalogueImportTest do
  use TcgCheap.DataCase, async: false

  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{CatalogueImport, CatalogueImportWorker}

  test "imports the real catalogue with prices and records today's Cardmarket trend" do
    products = import_catalogue!()

    assert map_size(products) == 60
    box = products["Pitch Black Booster Box"]
    assert box.kind == :booster_box
    assert box.set_name == "Pitch Black"
    assert %Decimal{} = box.cardmarket_trend
    assert box.cardmarket_price_updated_on == ~D[2026-10-30]
    refute box.available

    [today] = Sealed.list_price_history!(box.id, Date.utc_today())
    assert Decimal.equal?(today.cardmarket_trend, box.cardmarket_trend)
    assert today.lowest_price == nil
  end

  test "re-importing updates prices in place, keeps slugs and products that disappear" do
    products = import_catalogue!()
    box = products["Pitch Black Booster Box"]

    changed =
      cardmarket_file(:prices)
      |> Jason.decode!()
      |> update_in(["priceGuides"], fn rows ->
        Enum.map(rows, fn
          %{"idProduct" => id} = row when id == box.cardmarket_id -> Map.put(row, "trend", 123.45)
          row -> row
        end)
      end)
      |> Jason.encode!()

    trimmed =
      cardmarket_file(:products)
      |> Jason.decode!()
      |> update_in(["products"], &Enum.reject(&1, fn row -> row["name"] == "151 Booster" end))
      |> Jason.encode!()

    stub_cardmarket(trimmed, changed)

    assert {:ok, %{products: 59}} =
             CatalogueImport.run(request_options: [plug: {Req.Test, CatalogueImport}])

    after_import = Map.new(Sealed.list_products!(), &{&1.name, &1})
    assert map_size(after_import) == 60
    assert Decimal.equal?(after_import["Pitch Black Booster Box"].cardmarket_trend, "123.45")
    assert after_import["Pitch Black Booster Box"].slug == box.slug
  end

  test "matches existing offers against the imported catalogue" do
    offer = offer!(title: "Pokémon TCG: Mega Evolution – Pitch Black – Booster Box")
    products = import_catalogue!()

    assert Sealed.get_offer!(offer.id).product_id == products["Pitch Black Booster Box"].id
    assert Sealed.get_product_by_slug!(products["Pitch Black Booster Box"].slug).available
  end

  test "a failed or malformed download writes nothing" do
    Req.Test.stub(CatalogueImport, &Plug.Conn.send_resp(&1, 503, "down"))
    assert {:error, _} = CatalogueImport.run(request_options: [plug: {Req.Test, CatalogueImport}])

    stub_cardmarket(
      cardmarket_file(:products),
      ~s({"version":1,"createdAt":"nope","priceGuides":[]})
    )

    assert {:error, _} = CatalogueImport.run(request_options: [plug: {Req.Test, CatalogueImport}])

    assert Sealed.list_products!() == []
  end

  test "the worker uses the configured stub and is scheduled daily" do
    stub_cardmarket()
    assert :ok = CatalogueImportWorker.perform(%Oban.Job{args: %{}})
    assert length(Sealed.list_products!()) == 60

    {Oban.Plugins.Cron, opts} =
      :tcg_cheap
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> List.keyfind(Oban.Plugins.Cron, 0)

    assert Enum.any?(Keyword.fetch!(opts, :crontab), &match?({_, CatalogueImportWorker, _}, &1))
  end
end
