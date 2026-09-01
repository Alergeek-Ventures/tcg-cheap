defmodule TcgCheap.Catalogue.PokeBoosterTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.SealedRetailers.PokeBooster

  @retailer %{source_key: "pokebooster", status: "active"}
  @now ~U[2026-08-09 12:00:00Z]

  defp fixture do
    "test/fixtures/booster_point/products.json" |> File.read!() |> Jason.decode!()
  end

  defp product(overrides \\ %{}) do
    fixture()
    |> List.first()
    |> Map.put(
      "permalink",
      "https://pokebooster.pl/produkt/pokemon-tcg-stellar-crown-booster-box/"
    )
    |> Map.put("categories", [%{"id" => 26, "name" => "Booster", "slug" => "booster"}])
    |> Map.merge(overrides)
  end

  defp options(name, extra \\ []),
    do: [plug: {Req.Test, name}, clock: fn -> @now end] ++ extra

  test "requests the category union and normalizes an eligible listing" do
    name = make_ref()
    admissions = :counters.new(1, [:atomics])

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.request_path == "/wp-json/wc/store/v1/products"
      assert conn.params["category"] == "26,27,42,57"
      assert conn.params["page"] == "1"
      assert conn.params["per_page"] == "100"

      conn |> Plug.Conn.put_resp_header("x-wp-totalpages", "1") |> Req.Test.json([product()])
    end)

    assert {:ok, [listing]} =
             PokeBooster.fetch_listings(
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
    assert listing.direct_url =~ "https://pokebooster.pl/produkt/"
    assert Decimal.equal?(listing.current_price_pln, Decimal.new("129.99"))
    assert PokeBooster.source_key() == "pokebooster"
  end

  test "excludes imports, preorders, hostile links, and newline URLs" do
    for overrides <- [
          %{"name" => "Pokémon TCG Japanese Booster"},
          %{"name" => "Pokémon TCG Booster preorder"},
          %{"permalink" => "https://evil.example/produkt/item/"},
          %{"permalink" => "https://pokebooster.pl/produkt/item/\n"}
        ] do
      name = make_ref()

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
        |> Req.Test.json([product(overrides)])
      end)

      result = PokeBooster.fetch_listings(@retailer, options(name))
      assert result in [{:ok, []}, {:error, :malformed_shape}]
    end
  end

  test "does not perform a request when budget admission rejects it" do
    name = make_ref()
    Req.Test.stub(name, fn _conn -> flunk("rejected request reached HTTP") end)

    assert {:error, {:acquisition_budget_rejected, :private_test_only}} =
             PokeBooster.fetch_listings(
               @retailer,
               options(name,
                 request_admitter: fn ->
                   {:error, {:acquisition_budget_rejected, :private_test_only}}
                 end
               )
             )
  end
end
