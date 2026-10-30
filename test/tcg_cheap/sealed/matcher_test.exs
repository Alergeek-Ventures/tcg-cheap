defmodule TcgCheap.Sealed.MatcherTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Sealed.{Matcher, Product}

  # Real titles from the shops' Store API feeds (2026-10-30), except the
  # synthetic exclusion examples marked below.
  @matches [
    {"Pokémon TCG: Pitch Black – Booster", "pokemon-tcg-pitch-black-booster-pack"},
    {"Pokémon TCG: Mega Evolution – Pitch Black. – Booster",
     "pokemon-tcg-pitch-black-booster-pack"},
    {"Pokémon TCG: Mega Evolution – Pitch Black – Sleeved Booster",
     "pokemon-tcg-pitch-black-booster-pack"},
    {"Pokémon TCG: Mega Evolution – Pitch Black – Booster Box",
     "pokemon-tcg-pitch-black-booster-box"},
    {"Pokemon TCG: ME – Pitch Black – Elite Trainer Box",
     "pokemon-tcg-pitch-black-elite-trainer-box"},
    {"Pokémon TCG: Mega Evolution – Pitch Black – 3-Pack Blister",
     "pokemon-tcg-pitch-black-3-pack-blister-binacle"},
    {"Pokémon TCG: Mega Evolution – Chaos Rising – Booster Box (36)",
     "pokemon-tcg-mega-evolution-chaos-rising-booster-box"},
    {"Pokémon TCG: Chaos Rising – Booster Bundle",
     "pokemon-tcg-mega-evolution-chaos-rising-booster-bundle"},
    {"Pokémon TCG: Chaos Rising – 3-Pack Blister – Charmeleon",
     "pokemon-tcg-mega-evolution-chaos-rising-3-pack-blister"},
    {"Pokémon TCG: Mega Evolution – Booster Box", "pokemon-tcg-mega-evolution-booster-box"},
    {"Pokémon TCG: Mega Evolution – Booster", "pokemon-tcg-mega-evolution-booster-pack"},
    {"Pokémon TCG: Phantasmal Flames – Elite Trainer Box – Charizard",
     "pokemon-tcg-mega-evolution-phantasmal-flames-elite-trainer-box"},
    {"Pokémon TCG: Ascended Heroes – Elite Trainer Box – Dragonite",
     "pokemon-tcg-mega-evolution-ascended-heroes-elite-trainer-box"},
    {"Pokémon TCG: Mega Evolution – Ascended Heroes – Booster Bundle",
     "pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle"},
    {"Pokémon TCG: Mega Evolution – Ascended Heroes – Emboar ex",
     "pokemon-tcg-mega-evolution-ascended-heroes-mega-emboar-ex-box"},
    {"Pokémon TCG: 30th Celebration – Elite Trainer Box",
     "pokemon-tcg-30th-celebration-elite-trainer-box"},
    {"Pokémon TCG: 30th Celebration – Ex Box – Greninja ex",
     "pokemon-tcg-30th-celebration-greninja-ex-box"},
    {"Pokémon TCG: 30th Celebration – Greninja ex Tin",
     "pokemon-tcg-30th-celebration-greninja-ex-tin"},
    {"Pokémon TCG: 30th Celebration – Tin – Sylveon ex",
     "pokemon-tcg-30th-celebration-sylveon-ex-tin"},
    {"Pokémon TCG: 30th Celebration – Mini Tin – Night – Greninja",
     "pokemon-tcg-30th-celebration-mini-tin"},
    {"Pokémon TCG: 30th Celebration – Mini Tin – Losowy Wariant",
     "pokemon-tcg-30th-celebration-mini-tin"},
    {"Pokémon TCG: 30th Celebration – 2-pack Blister – Eevee",
     "pokemon-tcg-30th-celebration-two-pack-blister"},
    {"Pokémon TCG: 30th Celebration – Battle Deck – Umbreon ex",
     "pokemon-tcg-30th-celebration-battle-deck-umbreon-ex"},
    {"Pokémon TCG: First Partner – Illustration Collection – Seria 3",
     "pokemon-tcg-first-partner-illustration-collection-series-3"},
    {"Pokémon TCG: Lumiose City Min Tin – Gallade", "pokemon-tcg-lumiose-city-mini-tin"},
    {"Pokémon TCG: Mega Charizard Tin – Mega Charizard X ex",
     "pokemon-tcg-mega-charizard-x-ex-tin"},
    {"Pokémon TCG: Mega Charizard X ex – Ultra-Premium Collection",
     "pokemon-tcg-mega-charizard-x-ex-ultra-premium-collection"},
    {"POKÉMON TCG: 2026 POKÉMON DAY COLLECTION", "pokemon-tcg-pokemon-day-2026-collection"},
    {"Pokémon TCG: Scarlet & Violet – Destined Rivals Booster",
     "pokemon-tcg-scarlet-violet-destined-rivals-booster-pack"},
    {"Pokémon TCG: Scarlet & Violet – Destined Rivals – Elite Trainer Box",
     "pokemon-tcg-scarlet-violet-destined-rivals-elite-trainer-box"},
    {"Pokémon TCG: Prismatic Evolutions – Super Premium Collection",
     "pokemon-tcg-scarlet-violet-prismatic-evolutions-super-premium-collection"},
    {"Pokémon TCG: 151 – Booster Bundle", "pokemon-tcg-scarlet-violet-151-booster-bundle"},
    {"Pokémon TCG: 151 – Booster", "pokemon-tcg-scarlet-violet-151-booster-pack"},
    {"Pokémon TCG: Black Bolt – Elite Trainer Box",
     "pokemon-tcg-scarlet-violet-black-bolt-elite-trainer-box"}
  ]

  # Real titles that must stay unmatched: other products, other sizes, or ambiguous.
  @unmatched [
    "Pokémon TCG – Mega Evolution: Chaos Rising – Half Booster Box",
    "Pokémon TCG: Mega Evolution – Ascended Heroes – Meganium ex/Emboar ex Box/Feraligatr ex Box",
    "Pokémon TCG: Mega Charizard Tin – Mega Charizard",
    "Pokémon TCG: Mega Evolution – Pitch Black – Checklane Blister",
    "Pokémon TCG: Mega Evolution – Pitch Black – Premium Checklane Blister",
    "Pokemon TCG: 30th Celebration – 3pack Tech Sticker – Lucario – 3-Pack Blister",
    "Pokémon TCG: 30th Celebration – Ultra-Premium Collection – Day (Espeon ex)",
    "Pokémon TCG: Black Bolt & White Flare – Poster Collection",
    "Pokémon TCG: Prismatic Evolutions – Surprise Box",
    "Pokémon TCG: Surging Sparks – Build & Battle / Prerelease Box",
    "Pokémon TCG: Trick or Trade – BOOster (edycja 2024)",
    "Pokémon Center Tohoku Special Box",
    "Pokémon TCG: Mega Evolution – Delta Reign – Booster Box"
  ]

  @excluded [
    {"Pokémon TCG: Delta Reign – Booster (PREORDER)", "preorder"},
    {"Zestaw kart Pokemon TCG: Ascended Heroes – Booster Bundle preorder", "preorder"},
    {"Pokémon Mask of Change JAPOŃSKI Booster [sv6]", "japonski"},
    {"Pokémon TCG: Lumiose City Mini Tin – Zestaw (5 wzorów)", "zestaw"},
    {"Pokemon TCG: ME – Lumiose City – Mini Tin x10", "multiple items"},
    {"Zestaw 10 – Pokémon TCG: 30th Celebration – Mini Tin", "zestaw"},
    {"Pokémon TCG: Mega Evolution – Phantasmal Flames – Mini Portfolio", "portfolio"},
    # Synthetic titles for exclusions no shop currently lists.
    {"Pokémon TCG: Pitch Black – Booster Box Case (6 sztuk)", "case"},
    {"Pokémon TCG: Pitch Black – Elite Trainer Box (pusty)", "pusty"},
    {"Pokémon TCG: Pitch Black – Booster (Korean)", "korean"},
    {"Pokémon TCG: Chaos Rising – Booster Box (Chinese)", "chinese"},
    {"Pokémon TCG: Pitch Black – Koszulki na karty", "koszulki"}
  ]

  describe "real shop titles" do
    test "match exactly one catalogue product" do
      for {title, slug} <- @matches do
        assert Matcher.match(%{title: title}) == {:matched, slug}, title
      end
    end

    test "stay unmatched when they are another product, size or ambiguous" do
      for title <- @unmatched do
        assert Matcher.match(%{title: title}) in [:unmatched, :ambiguous], title
        assert Matcher.product_slug(%{title: title}) == nil
      end
    end

    test "non-English editions, preorders, bundles, empty boxes and accessories are excluded" do
      for {title, reason} <- @excluded do
        assert Matcher.match(%{title: title}) == {:excluded, reason}, title
        assert Matcher.excluded?(title)
      end
    end
  end

  describe "rules" do
    test "an exact EAN wins over the title" do
      products = [
        product("a", [["pitch black"], ["booster"]], eans: ["0820650000001"]),
        product("b", [["chaos rising"]])
      ]

      assert Matcher.match(%{title: "Chaos Rising", ean: "0820650000001"}, products) ==
               {:matched, "a"}
    end

    test "an unknown EAN falls back to the title" do
      products = [product("a", [["pitch black"]], eans: ["0820650000001"])]

      assert Matcher.match(%{title: "Pitch Black", ean: "0000000000000"}, products) ==
               {:matched, "a"}
    end

    test "exclusions are checked before the EAN" do
      products = [product("a", [["pitch black"]], eans: ["0820650000001"])]

      assert Matcher.match(%{title: "Pitch Black (PREORDER)", ean: "0820650000001"}, products) ==
               {:excluded, "preorder"}
    end

    test "two matching products make the offer ambiguous" do
      products = [product("a", [["pitch black"]]), product("b", [["booster"]])]
      assert Matcher.match(%{title: "Pitch Black Booster"}, products) == :ambiguous
    end

    test "terms match whole words only, with alternatives per group" do
      products = [product("a", [["etb", "elite trainer box"], ["151"]])]
      assert Matcher.match(%{title: "151 ETB"}, products) == {:matched, "a"}
      assert Matcher.match(%{title: "1510 ETB"}, products) == :unmatched
      assert Matcher.match(%{title: "151 ETBs"}, products) == :unmatched
    end

    test "product exclusions veto a match" do
      products = [product("a", [["booster"]], exclude: ["bundle"])]
      assert Matcher.match(%{title: "Booster Bundle"}, products) == :unmatched
    end
  end

  test "normalize/1 strips case, diacritics and punctuation" do
    assert Matcher.normalize("Pokémon TCG: Łódź – „Scarlet & Violet” 3-Pack") ==
             "pokemon tcg lodz scarlet and violet 3 pack"
  end

  defp product(slug, terms, opts \\ []) do
    %Product{
      slug: slug,
      name: slug,
      kind: :booster,
      terms: terms,
      exclude: Keyword.get(opts, :exclude, []),
      eans: Keyword.get(opts, :eans, [])
    }
  end
end
