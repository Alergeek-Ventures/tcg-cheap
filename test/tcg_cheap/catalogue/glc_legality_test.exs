defmodule TcgCheap.Catalogue.GlcLegalityTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.GlcLegality

  defp card(overrides),
    do:
      Map.merge(
        %{tcgdex_id: "local-1", name: "Pikachu", category: "Pokemon"},
        Map.new(overrides)
      )

  test "exposes the versioned local policy" do
    assert GlcLegality.policy_version() == "glc_local_2026-04-20"
  end

  test "allows eligible trainers and ordinary pokemon" do
    assert GlcLegality.legal?(card(category: "Trainer"))
    assert GlcLegality.legal?(card(%{}))
  end

  test "rejects every rule-box naming family" do
    for name <- [
          "Charizard ex",
          "Charizard EX",
          "Charizard GX",
          "Charizard V",
          "Charizard VMAX",
          "Charizard VSTAR",
          "Charizard V-UNION",
          "Charizard BREAK",
          "Radiant Charizard",
          "Mew ◇"
        ] do
      refute GlcLegality.legal?(card(name: name))
    end
  end

  test "rejects every exact banned printing" do
    for id <-
          ~w[xy4-99 xy4-118 sm5-114 xy7-74 sm10-165 sm7-133 sma-SV85 swsh4.5-21 sm11-205 swsh4-50 sm3.5-45 smp-SM85 sm12-83 swsh2-174 swsh2-209 xy4-93] do
      refute GlcLegality.legal?(card(tcgdex_id: id))
    end
  end

  test "rejects every Double Colorless Energy printing" do
    assert GlcLegality.legal?(
             card(category: "Trainer", name: "Double Colorless Energy", tcgdex_id: "base1-86")
           ) == false

    assert GlcLegality.legal?(card(name: "Double Colorless Energy", tcgdex_id: "swsh1-1")) ==
             false
  end

  test "a different printing with the same pokemon name remains eligible" do
    assert GlcLegality.legal?(card(tcgdex_id: "other-1", name: "Pikachu"))
  end

  test "rejects energy, unknown, and nil categories" do
    refute GlcLegality.legal?(card(category: "Energy"))
    refute GlcLegality.legal?(card(category: "Other"))
    refute GlcLegality.legal?(card(category: nil))
  end

  test "does not reject non-matching substrings" do
    for name <- ["Vileplume", "Gengar", "Exeggcute", "GX marker", "Breakwater"] do
      assert GlcLegality.legal?(card(name: name))
    end
  end
end
