defmodule TcgCheap.Catalogue.CardmarketMappingTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.CardmarketMapping

  test "extracts scalar and direct map third party Cardmarket identities" do
    assert CardmarketMapping.identity_ids(%{"thirdParty" => %{"cardmarket" => 851_190}}) == [
             851_190
           ]

    assert CardmarketMapping.identity_ids(%{
             "thirdParty" => %{"cardmarket" => %{"idProduct" => 851_190}}
           }) == [851_190]
  end

  test "rejects scalar third party and unrelated nested providers" do
    card = %{
      "thirdParty" => 851_190,
      "other" => %{"thirdParty" => %{"cardmarket" => 851_190}},
      "pricing" => %{"tcgplayer" => %{"idProduct" => 851_190}},
      "prices" => %{"cardmarket" => %{"idProduct" => 851_190}},
      "nested" => %{"cardmarket" => %{"idProduct" => 851_190}}
    }

    assert CardmarketMapping.identity_ids(card) == []
  end

  test "ignores malformed, nonpositive, provider and price values" do
    card = %{
      "pricing" => %{"cardmarket" => %{"idProduct" => 0}, "tcgplayer" => %{"idProduct" => 2}},
      "thirdParty" => %{"cardmarket" => "bad", "tcgplayer" => 851_190},
      "prices" => %{"idProduct" => 851_190}
    }

    assert CardmarketMapping.identity_ids(card) == []

    assert CardmarketMapping.classify(card) == %{
             status: "unmatched",
             reason: nil,
             cardmarket_product_id: nil
           }
  end

  test "mapped stamped material remains review" do
    card = %{
      "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}},
      "variants_detailed" => [
        %{
          "type" => "stamped",
          "stamp" => "cosmos",
          "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
        }
      ]
    }

    assert %{status: "review", reason: "stamped variant: cosmos"} =
             CardmarketMapping.classify(card)
  end

  test "extracts identities from realistic detailed list and map entries" do
    card = %{
      "variants_detailed" => %{
        "normal" => %{
          "type" => "normal",
          "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
        },
        "reverse" => %{
          "type" => "reverse",
          "thirdParty" => %{"cardmarket" => %{"idProduct" => 851_190}}
        },
        "promo" => %{"type" => "promo", "prices" => %{"cardmarket" => %{"idProduct" => 2}}}
      }
    }

    assert CardmarketMapping.identity_ids(card) == [851_190]
  end

  test "ignores malformed and nonpositive IDs on accepted paths" do
    card = %{
      "pricing" => %{"cardmarket" => %{"idProduct" => 0}},
      "thirdParty" => %{"cardmarket" => %{"idProduct" => -1}},
      "variants_detailed" => [
        %{"type" => "normal", "pricing" => %{"cardmarket" => %{"idProduct" => "1"}}},
        %{"type" => "reverse", "thirdParty" => %{"cardmarket" => %{"idProduct" => nil}}}
      ]
    }

    assert CardmarketMapping.identity_ids(card) == []
  end
end
