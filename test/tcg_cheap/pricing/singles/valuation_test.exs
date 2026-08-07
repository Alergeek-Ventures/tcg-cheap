defmodule TcgCheap.Pricing.Singles.ValuationTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.{Offer, Valuation}

  defp offer(seller, price, attrs \\ []) do
    struct!(
      Offer,
      Keyword.merge(
        [
          seller_key: seller,
          language: :en,
          condition: :near_mint,
          ships_to_poland?: true,
          price_eur: Decimal.new(price)
        ],
        attrs
      )
    )
  end

  test "chooses the five lowest sellers" do
    offers =
      for {seller, price} <- [
            {"a", "1"},
            {"b", "2"},
            {"c", "3"},
            {"d", "4"},
            {"e", "5"},
            {"f", "6"}
          ],
          do: offer(seller, price)

    assert {:ok, result} = Valuation.calculate_default_v1(offers)
    assert result.value_eur == Decimal.new("3.00")
    assert result.qualifying_seller_count == 5
  end

  test "averages four sellers below the five-seller cutoff" do
    assert {:ok, result} =
             Valuation.calculate_default_v1([
               offer("a", "1"),
               offer("b", "2"),
               offer("c", "3"),
               offer("d", "4")
             ])

    assert result.value_eur == Decimal.new("2.50")
    assert result.qualifying_seller_count == 4
  end

  test "keeps only each seller's lowest listing" do
    assert {:ok, result} =
             Valuation.calculate_default_v1([
               offer("seller", "9"),
               offer("seller", "3"),
               offer("other", "5")
             ])

    assert result.value_eur == Decimal.new("4.00")
    assert result.qualifying_seller_count == 2
  end

  test "averages one to four sellers" do
    assert {:ok, result} =
             Valuation.calculate_default_v1([offer("a", "1"), offer("b", "2"), offer("c", "2")])

    assert result.value_eur == Decimal.new("1.67")
  end

  test "filters non-qualifying offers" do
    invalid = [
      offer("language", "1", language: :de),
      offer("condition", "1", condition: :excellent),
      offer("shipping", "1", ships_to_poland?: false),
      offer("", "1"),
      offer("   ", "1"),
      offer("zero", "0"),
      offer("negative", "-1"),
      offer("nan", "NaN"),
      offer("infinity", "Infinity"),
      %Offer{
        seller_key: "malformed",
        language: :en,
        condition: :near_mint,
        ships_to_poland?: true,
        price_eur: %Decimal{coef: :bad}
      },
      %Offer{
        seller_key: "negative-coefficient",
        language: :en,
        condition: :near_mint,
        ships_to_poland?: true,
        price_eur: %Decimal{sign: 1, coef: -1, exp: 0}
      }
    ]

    assert Valuation.calculate_default_v1(invalid) == {:error, :no_qualifying_offers}
  end

  test "rounds half up to two decimal places" do
    assert {:ok, result} = Valuation.calculate_default_v1([offer("a", "1.005")])
    assert result.value_eur == Decimal.new("1.01")
    assert result.preset_version == :default_v1
    assert result.method == :five_lowest_distinct_sellers
  end
end
