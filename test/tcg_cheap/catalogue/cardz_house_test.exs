defmodule TcgCheap.Catalogue.CardzHouseTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.SealedRetailers.CardzHouse

  @retailer %{source_key: "cardzhouse", status: "active"}

  defp options(name, extra \\ []),
    do: [plug: {Req.Test, name}, clock: fn -> ~U[2026-08-09 12:00:00Z] end] ++ extra

  defp fixture do
    "test/fixtures/cardz_house/products.json" |> File.read!() |> Jason.decode!()
  end

  test "requests the fixed category and fields, then keeps only the eligible listing" do
    name = make_ref()
    admissions = :counters.new(1, [:atomics])
    requests = :counters.new(1, [:atomics])

    Req.Test.stub(name, fn conn ->
      :counters.add(requests, 1, 1)
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.request_path == "/wp-json/wc/store/v1/products"

      assert conn.params == %{
               "_fields" =>
                 "id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder",
               "category" => "742",
               "page" => "1",
               "per_page" => "100"
             }

      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(fixture())
    end)

    assert {:ok, [listing]} =
             CardzHouse.fetch_listings(
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
    assert listing.source_listing_id == "8393"
    assert listing.source_title == "Pokémon TCG: 151 – Booster Bundle"
    assert listing.direct_url == "https://cardzhouse.pl/product/pokemon-tcg-151-booster-bundle/"
    assert Decimal.equal?(listing.current_price_pln, Decimal.new("599.99"))
    assert listing.stock_status == "sold_out"

    assert Map.keys(listing.source_payload) |> Enum.sort() ==
             ~w(categories id is_in_stock is_on_backorder is_purchasable name permalink prices tags)
  end

  test "fails closed for hostile product links" do
    name = make_ref()
    [product | _] = fixture()

    Req.Test.stub(name, fn conn ->
      body = [Map.put(product, "permalink", "https://evil.example/product/151/")]
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(body)
    end)

    assert {:error, :malformed_shape} = CardzHouse.fetch_listings(@retailer, options(name))
  end

  test "rejects same-host product links with a trailing newline" do
    name = make_ref()
    [product | _] = fixture()

    Req.Test.stub(name, fn conn ->
      body = [Map.put(product, "permalink", "https://cardzhouse.pl/product/pokemon-151/\n")]
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(body)
    end)

    assert {:error, :malformed_shape} = CardzHouse.fetch_listings(@retailer, options(name))
  end

  test "handles active disabled and invalid retailers" do
    assert {:error, :retailer_disabled} =
             CardzHouse.fetch_listings(%{@retailer | status: "disabled"}, [])

    assert {:error, :invalid_retailer} = CardzHouse.fetch_listings(%{}, [])
    assert CardzHouse.source_key() == "cardzhouse"
  end
end
