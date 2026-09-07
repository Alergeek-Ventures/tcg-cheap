defmodule TcgCheap.Catalogue.MaterialVariantTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.MaterialVariant

  test "preserves importer material flags and deterministic reasons" do
    for {key, reason} <- [
          {"firstEdition", "firstEdition variant"},
          {"wPromo", "wPromo variant"},
          {"jumbo", "jumbo variant"},
          {"preRelease", "preRelease variant"}
        ] do
      material = MaterialVariant.descriptors(%{key => true}, %{})
      assert MaterialVariant.conflict?(material)
      assert MaterialVariant.reason(material) == reason
    end

    stamped = MaterialVariant.descriptors(%{}, %{"stamp" => "  cosmos  ", "stamps" => ["gold"]})
    assert stamped.stamps == ["cosmos", "gold"]
    assert MaterialVariant.reason(stamped) == "stamped variant: cosmos,gold"
  end

  test "non-default subtype size and foil are material identities" do
    material =
      MaterialVariant.descriptors(
        %{},
        %{
          "type" => "normal",
          "subtype" => "shadowless",
          "size" => "oversized",
          "foil" => "pokeball"
        }
      )

    assert material.identities == [
             ~s([{"foil", "pokeball"}, {"size", "oversized"}, {"subtype", "shadowless"}])
           ]

    assert MaterialVariant.conflict?(material)

    assert MaterialVariant.reason(material) ==
             "material descriptor: " <>
               ~s([{"foil", "pokeball"}, {"size", "oversized"}, {"subtype", "shadowless"}])
  end

  test "normal reverse holo and default unlimited standard are not conflicts" do
    for type <- ["normal", "reverse", "holo"] do
      material =
        MaterialVariant.descriptors(
          %{},
          %{"type" => type, "subtype" => "unlimited", "size" => "standard"}
        )

      refute MaterialVariant.conflict?(material)
      assert MaterialVariant.reason(material) == nil
    end

    refute MaterialVariant.conflict?(%{"firstEdition" => false, "wPromo" => false})
  end

  test "detects obvious Cardmarket markers but allows benign names" do
    for name <- [
          "Charizard 1st Edition",
          "Pikachu Promo",
          "Stamped Eevee",
          "Jumbo Snorlax",
          "Mew Pre-Release"
        ] do
      assert MaterialVariant.obvious_cardmarket_marker?(name)
    end

    for name <- ["First Aid Kit", "Promontory", "Stampede", "Jumbos", "Release Radar"] do
      refute MaterialVariant.obvious_cardmarket_marker?(name)
    end

    refute MaterialVariant.obvious_cardmarket_marker?(nil)
  end
end
