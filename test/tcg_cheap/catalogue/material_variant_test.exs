defmodule TcgCheap.Catalogue.MaterialVariantTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.{CardmarketMapping, MaterialVariant}

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

  test "unmapped promotional details do not poison mapped ordinary details" do
    classification =
      CardmarketMapping.classify(
        %{},
        %{},
        [
          %{
            "type" => "normal",
            "subtype" => "unlimited",
            "size" => "standard",
            "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
          },
          %{
            "type" => "reverse",
            "subtype" => "unlimited",
            "size" => "standard",
            "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
          },
          %{"type" => "stamped", "stamp" => "cosmos"},
          %{"type" => "stamped", "stamp" => "gold"}
        ]
      )

    assert classification == %{
             status: "matched",
             reason: nil,
             cardmarket_product_id: 851_190
           }
  end

  test "mapped material descriptors and conflicting IDs require review" do
    for detail <- [
          %{
            "type" => "normal",
            "foil" => "pokeball",
            "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
          },
          %{
            "type" => "normal",
            "size" => "oversized",
            "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
          }
        ] do
      assert CardmarketMapping.classify(%{}, %{}, [detail]).status == "review"
    end

    assert CardmarketMapping.classify(
             %{},
             %{},
             [
               %{"pricing" => %{"cardmarket" => %{"idProduct" => 1}}},
               %{"pricing" => %{"cardmarket" => %{"idProduct" => 2}}}
             ]
           ).reason == "multiple Cardmarket product IDs"
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
