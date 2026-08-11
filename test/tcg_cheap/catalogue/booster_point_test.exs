defmodule TcgCheap.Catalogue.BoosterPointTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.SealedRetailers.BoosterPoint

  @retailer %{source_key: "boosterpoint", status: "active"}
  @now ~U[2026-08-09 12:00:00Z]

  defp fixture do
    "test/fixtures/booster_point/products.json" |> File.read!() |> Jason.decode!()
  end

  defp options(name, extra \\ []) do
    [plug: {Req.Test, name}, clock: fn -> @now end] ++ extra
  end

  test "requests the fixed endpoint and keeps only eligible sealed stock" do
    name = make_ref()
    admissions = :counters.new(1, [:atomics])

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      assert conn.request_path == "/wp-json/wc/store/v1/products"

      assert conn.params == %{
               "_fields" =>
                 "id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder",
               "category" => "61",
               "page" => "1",
               "per_page" => "100"
             }

      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json(fixture())
    end)

    assert {:ok, [listing]} =
             BoosterPoint.fetch_listings(
               @retailer,
               options(name,
                 request_admitter: fn ->
                   :counters.add(admissions, 1, 1)
                   :ok
                 end
               )
             )

    assert :counters.get(admissions, 1) == 1
    assert listing.source_listing_id == "301001"
    assert listing.source_title == "Pokémon TCG: Stellar Crown Booster Box & Display"

    assert listing.direct_url ==
             "https://boosterpoint.pl/produkt/pokemon-tcg-stellar-crown-booster-box/"

    assert Decimal.equal?(listing.current_price_pln, Decimal.new("129.99"))
    assert listing.stock_status == "in_stock"

    assert listing.source_payload ==
             Enum.into(fixture() |> List.first(), %{}, fn {key, value} -> {key, value} end)

    assert Map.keys(listing.source_payload) |> Enum.sort() ==
             ~w(categories id is_in_stock is_on_backorder is_purchasable name permalink prices tags)
  end

  test "rejects hostile links and retailer states" do
    bad =
      fixture()
      |> List.first()
      |> Map.put("permalink", "https://evil.example/produkt/item/")

    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json([bad])
    end)

    assert {:error, :malformed_shape} = BoosterPoint.fetch_listings(@retailer, options(name))

    name = make_ref()

    trailing_newline =
      fixture()
      |> List.first()
      |> Map.put("permalink", "https://boosterpoint.pl/produkt/valid-product/\n")

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
      |> Req.Test.json([trailing_newline])
    end)

    assert {:error, :malformed_shape} = BoosterPoint.fetch_listings(@retailer, options(name))

    assert {:error, :retailer_disabled} =
             BoosterPoint.fetch_listings(%{@retailer | status: "disabled"}, [])

    assert {:error, :invalid_retailer} = BoosterPoint.fetch_listings(%{}, [])
  end

  test "does not admit a request when the acquisition budget rejects it" do
    name = make_ref()
    Req.Test.stub(name, fn _conn -> flunk("rejected request reached HTTP") end)

    assert {:error, {:acquisition_budget_rejected, :private_test_only}} =
             BoosterPoint.fetch_listings(
               @retailer,
               options(name,
                 request_admitter: fn ->
                   {:error, {:acquisition_budget_rejected, :private_test_only}}
                 end
               )
             )
  end
end
