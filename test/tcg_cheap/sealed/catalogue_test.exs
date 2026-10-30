defmodule TcgCheap.Sealed.CatalogueTest do
  use ExUnit.Case, async: true

  import TcgCheap.SealedFixtures

  alias TcgCheap.Pricing.CardmarketBulk.Adapter
  alias TcgCheap.Sealed.{Catalogue, Kinds}

  setup_all do
    rows = cardmarket_rows()
    %{rows: rows, by_name: Map.new(rows, &{&1.name, &1})}
  end

  test "parses the real sealed product list and keeps only sealed price rows" do
    {:ok, products} = Adapter.parse_sealed_products(cardmarket_file(:products))
    {:ok, prices} = Adapter.parse_sealed_prices(cardmarket_file(:prices))

    assert products.source_rows == 63
    assert prices.total_rows == 64
    assert length(prices.rows) == 63
    refute Enum.any?(prices.rows, &(&1.category_id == 51))
  end

  test "drops coins and lots, keeps cases and non-English editions", %{
    rows: rows,
    by_name: by_name
  } do
    assert length(rows) == 60
    refute Map.has_key?(by_name, "30th Celebration: Espeon Coin")
    refute Map.has_key?(by_name, "World Championships 2026 Paradise Resort Full Set")
    assert by_name["30th Celebration JP Booster Box Case"].kind == :case
    assert by_name["30th Celebration Simplified Chinese Booster Box"].kind == :booster_box
  end

  test "maps Cardmarket categories and names to kinds", %{by_name: by_name} do
    assert by_name["Pitch Black Booster"].kind == :booster
    assert by_name["Pitch Black Booster Box"].kind == :booster_box
    assert by_name["Pitch Black Booster Bundle"].kind == :booster_bundle
    assert by_name["Pitch Black Elite Trainer Box"].kind == :elite_trainer_box
    assert by_name["Pitch Black 10 Elite Trainer Box Case"].kind == :case
    assert by_name["Pitch Black 6 Booster Box Case"].kind == :case
    assert by_name["30th Celebration: Mini Tin Display"].kind == :case
    assert by_name["30th Celebration Greninja ex Tin"].kind == :tin
    assert by_name["Pitch Black: Binacle 3-Pack Blister"].kind == :blister
    assert by_name["Pitch Black: Main Set"].kind == :card_set
    assert by_name["Pokémon Day 2026 Collection"].kind == :collection
    assert Enum.all?(Map.values(by_name), &(&1.kind in Kinds.all()))
  end

  test "derives set names from names sharing an expansion", %{by_name: by_name} do
    assert by_name["Pitch Black Booster"].set_name == "Pitch Black"
    assert by_name["Pitch Black: Binacle 3-Pack Blister"].set_name == "Pitch Black"
    assert by_name["Chaos Rising Booster Box (18 Boosters)"].set_name == "Chaos Rising"
    assert by_name["30th Celebration: Mini Tin Display"].set_name == "30th Celebration"
  end

  test "a lone product takes the text before a colon, or no set" do
    product = fn id, name ->
      %Adapter.Product{id_product: id, name: name, category_id: 1015, id_expansion: id}
    end

    assert Catalogue.set_names([product.(1, "Lumiose City: Gallade Mini Tin")]) == %{
             1 => "Lumiose City"
           }

    assert Catalogue.set_names([product.(2, "Pokémon Day 2026 Collection")]) == %{2 => nil}
  end

  test "mixed expansions use the prefix shared by most names" do
    names = [
      "Delta Reign Booster",
      "Delta Reign Booster Box",
      "Delta Reign: Seel 3-Pack Blister",
      "Mega Rayquaza ex Premium Tournament Collection"
    ]

    products =
      for {name, id} <- Enum.with_index(names),
          do: %Adapter.Product{id_product: id, name: name, category_id: 52, id_expansion: 7}

    assert Catalogue.set_names(products) == %{7 => "Delta Reign"}
  end

  test "carries the Cardmarket prices and dates", %{by_name: by_name} do
    row = by_name["Pitch Black Booster Box"]
    assert %Decimal{} = row.cardmarket_trend
    assert row.cardmarket_price_updated_on == ~D[2026-10-30]
    assert %Date{} = row.cardmarket_added_on
  end

  test "slugs are readable, unique and URL safe", %{rows: rows, by_name: by_name} do
    slugs = Enum.map(rows, & &1.slug)
    assert slugs == Enum.uniq(slugs)
    assert Enum.all?(slugs, &String.match?(&1, ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/))

    assert by_name["Pitch Black Pokémon Center Elite Trainer Box"].slug ==
             "pitch-black-pokemon-center-elite-trainer-box-885543"
  end

  test "search text is normalized and includes the kind label and synonyms", %{by_name: by_name} do
    text = by_name["Pitch Black Elite Trainer Box"].search_text
    assert String.starts_with?(text, " ")
    assert text =~ "pitch black elite trainer box"
    assert text =~ " etb"
  end
end
