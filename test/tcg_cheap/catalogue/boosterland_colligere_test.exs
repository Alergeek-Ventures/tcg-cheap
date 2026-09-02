defmodule TcgCheap.Catalogue.BoosterlandColligereTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.SealedRetailers.{Boosterland, Colligere}

  @now ~U[2026-09-02 12:00:00Z]

  defp product(host, path, category, overrides) do
    %{
      "id" => 901,
      "name" => "Pokémon TCG Booster Bundle",
      "permalink" => "https://#{host}/sklep/#{path}/",
      "prices" => %{"price" => "12999", "currency_code" => "PLN", "currency_minor_unit" => 2},
      "categories" => [
        %{"id" => category, "slug" => if(category == 40, do: "pokemon", else: "pokemon-tcg")}
      ],
      "tags" => [],
      "images" => [%{"src" => "https://cdn.#{host}/wp-content/uploads/item.webp"}],
      "is_purchasable" => true,
      "is_in_stock" => true,
      "is_on_backorder" => false
    }
    |> Map.merge(overrides)
  end

  defp fetch(adapter, source, host, category, name, overrides \\ %{}, extra \\ []) do
    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.request_path == "/wp-json/wc/store/v1/products"
      assert conn.params["category"] == Integer.to_string(category)
      assert conn.params["page"] == "1"
      assert conn.params["per_page"] == "100"

      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
      |> Req.Test.json([product(host, "pokemon-tcg-booster-bundle", category, overrides)])
    end)

    adapter_fetch(adapter, source, name, extra)
  end

  defp adapter_fetch(Boosterland, source, name, extra),
    do:
      Boosterland.fetch_listings(
        %{source_key: source, status: "active"},
        [plug: {Req.Test, name}, clock: fn -> @now end] ++ extra
      )

  defp adapter_fetch(Colligere, source, name, extra),
    do:
      Colligere.fetch_listings(
        %{source_key: source, status: "active"},
        [plug: {Req.Test, name}, clock: fn -> @now end] ++ extra
      )

  test "Boosterland uses its exact endpoint policy and normalizes listings" do
    name = make_ref()

    assert {:ok, [listing]} =
             fetch(
               Boosterland,
               "boosterland",
               "boosterland.pl",
               40,
               name,
               %{
                 "permalink" =>
                   "https://boosterland.pl/sklep/pokemon/30-lecie/pokemon-tcg-30th-celebration-binder-collection/",
                 "images" => [
                   %{"src" => "https://boosterland.pl/wp-content/uploads/2026/08/binder.jpg"}
                 ]
               }
             )

    assert listing.source_listing_id == "901"
    assert Decimal.equal?(listing.current_price_pln, Decimal.new("129.99"))
    assert listing.image_url == "https://boosterland.pl/wp-content/uploads/2026/08/binder.jpg"
    assert listing.stock_status == "in_stock"

    assert listing.direct_url ==
             "https://boosterland.pl/sklep/pokemon/30-lecie/pokemon-tcg-30th-celebration-binder-collection/"

    assert Boosterland.source_key() == "boosterland"
  end

  test "Colligere uses its exact endpoint policy and normalizes listings" do
    name = make_ref()
    assert {:ok, [listing]} = fetch(Colligere, "colligere", "colligere.pl", 23, name)
    assert Decimal.equal?(listing.current_price_pln, Decimal.new("129.99"))
    assert listing.stock_status == "in_stock"
    assert Colligere.source_key() == "colligere"
  end

  test "both adapters exclude non-English, accessories, preorders and hostile URLs" do
    cases = [
      %{"name" => "Pokémon TCG Japanese Booster"},
      %{"name" => "Pokémon TCG Booster preorder"},
      %{"name" => "Pokémon TCG sleeves"},
      %{"permalink" => "https://evil.example/sklep/item/"},
      %{"permalink" => "https://boosterland.pl/sklep/item/\n"},
      %{"permalink" => "https://boosterland.pl/sklep/Pokemon/item/"},
      %{"permalink" => "https://boosterland.pl/sklep/pokemon//item/"},
      %{"permalink" => "https://boosterland.pl/sklep/pokemon/../item/"},
      %{"permalink" => "https://boosterland.pl/sklep/pokemon/%69tem/"},
      %{"permalink" => "https://boosterland.pl/sklep/pokemon/item/?ref=home"},
      %{"permalink" => "https://boosterland.pl/sklep/pokemon/item/#details"},
      %{"permalink" => "https://boosterland.pl/sklep/a/b/c/d/e/f/"}
    ]

    for overrides <- cases do
      for {adapter, source, host, category} <- [
            {Boosterland, "boosterland", "boosterland.pl", 40},
            {Colligere, "colligere", "colligere.pl", 23}
          ] do
        name = make_ref()
        result = fetch(adapter, source, host, category, name, overrides)
        assert result in [{:ok, []}, {:error, :malformed_shape}]
      end
    end
  end

  test "budget rejection and retailer state fail closed" do
    name = make_ref()
    Req.Test.stub(name, fn _conn -> flunk("rejected request reached HTTP") end)

    assert {:error, {:acquisition_budget_rejected, :test}} =
             Boosterland.fetch_listings(
               %{source_key: "boosterland", status: "active"},
               plug: {Req.Test, name},
               request_admitter: fn -> {:error, {:acquisition_budget_rejected, :test}} end
             )

    assert {:error, :retailer_disabled} =
             Colligere.fetch_listings(%{source_key: "colligere", status: "disabled"}, [])

    assert {:error, :invalid_retailer} = Colligere.fetch_listings(%{}, [])
  end
end
