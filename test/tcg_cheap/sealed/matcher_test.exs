defmodule TcgCheap.Sealed.MatcherTest do
  use ExUnit.Case, async: true

  import TcgCheap.SealedFixtures

  alias TcgCheap.Sealed.Matcher

  # Real Cardmarket names (trimmed product list) against real shop titles
  # from the six feeds (2026-10-30). Synthetic titles are marked.
  setup_all do
    rows = cardmarket_rows()
    products = Enum.map(rows, &%{id: &1.name, name: &1.name, set_name: &1.set_name})
    %{index: Matcher.index(products)}
  end

  @matches [
    {"Pokémon TCG: Pitch Black – Booster", "Pitch Black Booster"},
    {"Pokémon TCG: Mega Evolution – Pitch Black. – Booster", "Pitch Black Booster"},
    {"Pokémon TCG: Mega Evolution – Pitch Black – Sleeved Booster",
     "Pitch Black Sleeved Booster"},
    {"Pokémon TCG: Mega Evolution – Pitch Black – Booster Box", "Pitch Black Booster Box"},
    {"Pokemon TCG: ME – Pitch Black – Elite Trainer Box", "Pitch Black Elite Trainer Box"},
    {"Pokémon TCG: Mega Evolution – Chaos Rising – Booster Box (36)", "Chaos Rising Booster Box"},
    {"Pokémon TCG: Chaos Rising – Booster Bundle", "Chaos Rising Booster Bundle"},
    {"Pokémon TCG: Chaos Rising – 3-Pack Blister – Charmeleon",
     "Chaos Rising: Charmeleon 3-Pack Blister"},
    {"Pokémon TCG: Mega Evolution – Booster Box", "Mega Evolution Booster Box"},
    {"Pokémon TCG: Mega Evolution – Booster", "Mega Evolution Booster"},
    {"Pokémon TCG: Mega Evolution – Delta Reign – Booster Box", "Delta Reign Booster Box"},
    {"Pokémon TCG: Mega Evolution – Delta Reign – Elite Trainer Box",
     "Delta Reign Elite Trainer Box"},
    {"Pokémon TCG: Ascended Heroes – Elite Trainer Box – Dragonite",
     "Ascended Heroes Elite Trainer Box"},
    {"Pokémon TCG: Ascended Heroes – Mega Emboar ex Box", "Ascended Heroes: Mega Emboar ex Box"},
    {"Pokémon TCG: 30th Celebration – Elite Trainer Box", "30th Celebration Elite Trainer Box"},
    {"Pokémon TCG: 30th Celebration – Ex Box – Greninja ex", "30th Celebration: Greninja ex Box"},
    {"Pokémon TCG: 30th Celebration – Tin – Greninja ex", "30th Celebration Greninja ex Tin"},
    {"Pokémon TCG: Mega Forces Tin – Mega Dragonite ex",
     "Mega Forces Tins: Mega Dragonite ex Tin"},
    {"Pokémon TCG: Azure Legends Tin – Kyogre ex", "Azure Legends Tins: Kyogre ex Tin"},
    {"Pokémon TCG: Paradox Destinies Tin – Iron Boulder ex",
     "Paradox Destinies Tins: Iron Boulder ex Tin (EU Version)"},
    {"Pokémon TCG: First Partner – Illustration Collection – Seria 3",
     "First Partner Illustration Collection Series 3"},
    {"Pokémon TCG: Lumiose City Min Tin – Gallade", "Lumiose City: Gallade Mini Tin"},
    {"Pokémon TCG: Mega Charizard Tin – Mega Charizard X ex", "Mega Charizard X ex Tin"},
    {"Pokémon TCG: Mega Charizard X ex – Ultra-Premium Collection",
     "Mega Charizard X ex Ultra-Premium Collection"},
    {"POKÉMON TCG: 2026 POKÉMON DAY COLLECTION", "Pokémon Day 2026 Collection"},
    {"Pokémon TCG: Scarlet & Violet – Destined Rivals Booster", "Destined Rivals Booster"},
    {"Pokémon TCG: Scarlet & Violet – Destined Rivals – Elite Trainer Box",
     "Destined Rivals Elite Trainer Box"},
    {"Pokémon TCG: 151 – Booster Bundle", "151 Booster Bundle"},
    {"Pokémon TCG: 151 – Booster", "151 Booster"},
    {"Pokémon TCG: Surging Sparks – Build & Battle / Prerelease Box",
     "Surging Sparks Build & Battle Box"},
    {"Pokémon TCG: Trainer’s Toolkit (2024)", "Trainer's Toolkit 2024"},
    # Synthetic: shops do list these variants, just not today.
    {"Pokémon TCG: Pitch Black – Pokémon Center Elite Trainer Box",
     "Pitch Black Pokémon Center Elite Trainer Box"},
    {"Pokémon TCG: Pitch Black – Booster Box Case", "Pitch Black 6 Booster Box Case"},
    {"Pokémon TCG: 30th Celebration – Booster Box Case (Japanese)",
     "30th Celebration JP Booster Box Case"},
    {"Pokémon TCG: 30th Celebration – Mini Tin Display", "30th Celebration: Mini Tin Display"}
  ]

  @unmatched [
    # Another size: Cardmarket has only the 36- and 18-pack boxes.
    "Pokémon TCG – Mega Evolution: Chaos Rising – Half Booster Box",
    # Several products in one title.
    "Pokémon TCG: Mega Evolution – Ascended Heroes – Meganium ex/Emboar ex Box/Feraligatr ex Box",
    # X or Y is not said.
    "Pokémon TCG: Mega Charizard Tin – Mega Charizard",
    # Two different Pikachu tins exist; the partner is not said.
    "Pokémon TCG: 30th Celebration – Mini Tin – Night – Pikachu",
    # The blister's Pokémon is not said.
    "Pokémon TCG: Mega Evolution – Pitch Black – 3-Pack Blister",
    "Pokémon TCG: Mega Evolution – Pitch Black – Premium Checklane Blister",
    # Japanese editions never match an English product.
    "Pokémon Stellar Miracle JAPOŃSKI booster [sv7]",
    "Pokémon Mask of Change JAPOŃSKI Booster [sv6]",
    # Synthetic: a case must not fall back to a single box, or a box to a booster.
    "Pokémon TCG: Delta Reign – Booster Box Case",
    "Pokémon TCG: Pitch Black – Booster Box (Korean)"
  ]

  @excluded [
    {"Pokémon TCG: Delta Reign – Booster (PREORDER)", "preorder"},
    {"Zestaw kart Pokemon TCG: Ascended Heroes – Booster Bundle preorder", "preorder"},
    {"Pokémon TCG: Lumiose City Mini Tin – Zestaw (5 wzorów)", "zestaw"},
    {"Pokemon TCG: ME – Lumiose City – Mini Tin x10", "multiple items"},
    {"Zestaw 10 – Pokémon TCG: 30th Celebration – Mini Tin", "zestaw"},
    # Synthetic.
    {"Pokémon TCG: Pitch Black – Elite Trainer Box (pusty)", "pusty"},
    {"Pokémon TCG: Pitch Black – Koszulki na karty", "koszulki"},
    {"Pokémon TCG: Pitch Black – Booster Box 6 sztuk", "multiple items"},
    {"Pokémon TCG: Pitch Black – Booster Box – uszkodzone opakowanie", "damaged or used"},
    {"Pokémon TCG: Pitch Black – Booster Box (otwarty)", "damaged or used"},
    {"Pokémon TCG: Pitch Black – Booster Box używany", "damaged or used"},
    {"Pokémon TCG: Pitch Black – Booster Box damaged", "damaged"},
    {"Pokémon TCG: Pitch Black – Booster Box bez folii", "bez folii"}
  ]

  test "real shop titles match the right Cardmarket product", %{index: index} do
    for {title, name} <- @matches do
      assert Matcher.match(%{title: title}, index) == {:matched, name}, title
    end
  end

  test "titles that are another size, several products or underspecified stay unmatched", %{
    index: index
  } do
    for title <- @unmatched do
      assert Matcher.match(%{title: title}, index) in [:unmatched, :ambiguous], title
      assert Matcher.product_id(%{title: title}, index) == nil
    end
  end

  test "preorders, bundles of many, empty boxes and accessories are excluded", %{index: index} do
    for {title, reason} <- @excluded do
      assert Matcher.match(%{title: title}, index) == {:excluded, reason}, title
      assert Matcher.excluded?(title)
    end
  end

  test "an EAN from a manual assignment wins over the title" do
    index =
      Matcher.index(
        [%{id: :a, name: "Pitch Black Booster"}, %{id: :b, name: "Chaos Rising Booster"}],
        %{"0820650000003" => :a}
      )

    assert Matcher.match(%{title: "Chaos Rising Booster", ean: "0820650000003"}, index) ==
             {:matched, :a}

    assert Matcher.match(%{title: "Chaos Rising Booster", ean: "0000000000000"}, index) ==
             {:matched, :b}
  end

  test "an excluded title stays excluded even with a known EAN" do
    index =
      Matcher.index([%{id: :a, name: "Pitch Black Booster"}], %{"0820650000003" => :a})

    assert Matcher.match(%{title: "Pitch Black Booster PREORDER", ean: "0820650000003"}, index) ==
             {:excluded, "preorder"}
  end

  test "the most specific product wins; equally specific ones are ambiguous" do
    index =
      Matcher.index([
        %{id: :plain, name: "Pitch Black Booster"},
        %{id: :sleeved, name: "Pitch Black Sleeved Booster"}
      ])

    assert Matcher.match(%{title: "Pitch Black Sleeved Booster"}, index) == {:matched, :sleeved}

    index =
      Matcher.index([
        %{id: :a, name: "Pitch Black Booster"},
        %{id: :b, name: "Pitch Black: Booster"}
      ])

    assert Matcher.match(%{title: "Pitch Black Booster"}, index) == :ambiguous
  end

  test "at most two title words may go unexplained" do
    index = Matcher.index([%{id: :old, name: "Dragonite Tin"}])
    assert Matcher.match(%{title: "Dragonite Tin – Gold"}, index) == {:matched, :old}
    assert Matcher.match(%{title: "Mega Forces Tin – Mega Dragonite ex"}, index) == :unmatched
  end

  test "products with fewer than two significant words are never matched" do
    index = Matcher.index([%{id: :generic, name: "Pokémon Booster"}])
    assert Matcher.match(%{title: "Pokémon TCG: Pitch Black – Booster"}, index) == :unmatched
  end

  test "tokens normalize punctuation, diacritics, plurals and shop synonyms" do
    assert Matcher.tokens("Pokémon TCG: Łódź – 3pack Tins ETB (japoński)") ==
             ~w(lodz 3 pack tin elite trainer box jp)
  end
end
