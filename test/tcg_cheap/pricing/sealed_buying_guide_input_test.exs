defmodule TcgCheap.Pricing.SealedBuyingGuideInputTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.SealedBuyingGuideInput

  @calculated_at ~U[2026-08-09 12:00:00Z]
  @product_id "product-#{System.unique_integer([:positive])}"

  test "selects the cheapest fresh LGS per retailer and deterministic ties" do
    evidence = [
      evidence("mapping-0", "lgs-a-1", "lgs-a", "20", 0),
      evidence("mapping-1", "lgs-a-2", "lgs-a", "10", 1),
      evidence("mapping-2", "lgs-a-tie", "lgs-a", "10", 2),
      evidence("mapping-3", "lgs-b", "lgs-b", "30", 3, category: "lgs")
    ]

    assert {:ok, input} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(
                 source_evidence: evidence,
                 fresh_regular_retailer_count: 0,
                 fresh_lgs_count: 2,
                 unique_source_retailer_count: 2
               ),
               []
             )

    assert [%{retailer_id: "lgs-a", price_pln: %Decimal{} = ten}] =
             Enum.filter(input.lgs_price_evidence, &(&1.retailer_id == "lgs-a"))

    assert Decimal.equal?(ten, Decimal.new("10"))
    assert Enum.map(input.lgs_price_evidence, & &1.retailer_id) == ["lgs-a", "lgs-b"]
    assert Decimal.equal?(input.msrp_pln, Decimal.new("35"))
  end

  test "uses inclusive freshness and sold-out projection boundaries" do
    boundary = DateTime.add(@calculated_at, -7 * 86_400, :second)
    sold_boundary = DateTime.add(@calculated_at, -30 * 86_400, :second)

    evidence = [
      evidence("mapping-boundary", "lgs-boundary", "lgs-boundary", "10", 0, checked_at: boundary),
      evidence("mapping-sold", "sold-boundary", "sold-boundary", nil, 1,
        category: "regular_retailer",
        stock_status: "sold_out",
        checked_at: sold_boundary
      )
    ]

    assert {:ok, input} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(
                 source_evidence: evidence,
                 fresh_regular_retailer_count: 0,
                 fresh_lgs_count: 1,
                 sold_out_15_30_day_count: 1,
                 unique_source_retailer_count: 2,
                 latest_nonfuture_checked_at: boundary
               ),
               []
             )

    assert [%{checked_at: ^boundary}] = input.lgs_price_evidence
    assert [%{checked_at: ^sold_boundary}] = input.sold_out_price_evidence
  end

  test "accepts empty evidence with explicit mapping confidence" do
    assert {:ok, input} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(
                 source_evidence: [],
                 source_mapping_confident: true,
                 fresh_regular_retailer_count: 0,
                 unique_source_retailer_count: 0,
                 latest_nonfuture_checked_at: nil,
                 limited_reason: "no_fresh_current_offers"
               ),
               []
             )

    assert input.mapping_confident? == true
  end

  test "rejects a matching aggregate with missing or malformed mapping confidence" do
    assert {:error, :invalid_aggregate} =
             SealedBuyingGuideInput.build(
               product(),
               Map.delete(aggregate(%{}), :source_mapping_confident),
               []
             )

    assert {:error, :invalid_aggregate} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(source_mapping_confident: "true"),
               []
             )
  end

  test "rejects malformed, cross-product, confidence, state, and nonfinite prices" do
    assert {:error, :cross_product_aggregate} =
             SealedBuyingGuideInput.build(product(), aggregate(sealed_product_id: "other"), [])

    assert {:error, :malformed_source_evidence} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(
                 source_evidence: [
                   evidence("m", "x", "x", "1", 0, confidence: Decimal.new("1.1"))
                 ]
               ),
               []
             )

    assert {:error, :malformed_source_evidence} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(
                 source_evidence: [evidence("m", "x", "x", "1", 0, stock_status: "unknown")]
               ),
               []
             )

    assert {:error, :malformed_source_evidence} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(source_evidence: [evidence("m", "x", "x", "NaN", 0)]),
               []
             )
  end

  test "projection drift is excluded and the model rejects count mismatch" do
    drifted =
      evidence("mapping-drift", "lgs-drift", "lgs-drift", "10", 0,
        checked_at: DateTime.add(@calculated_at, 1, :second)
      )

    assert {:error, :source_evidence_mismatch} =
             SealedBuyingGuideInput.build(
               product(),
               aggregate(
                 source_evidence: [drifted],
                 fresh_lgs_count: 0,
                 stale_or_future_current_offer_count: 1,
                 unique_source_retailer_count: 1
               ),
               []
             )
  end

  defp product,
    do: %{id: @product_id, publication_status: "approved", msrp_pln: Decimal.new("40")}

  defp aggregate(overrides) do
    Map.merge(
      %{
        status: "limited",
        sealed_product_id: @product_id,
        calculation_version: "sealed_market_daily_v1",
        currency: "PLN",
        limited_reason: "too_few_regular_retailers",
        aggregate_date: ~D[2026-08-09],
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil,
        fresh_regular_retailer_count: 1,
        fresh_lgs_count: 0,
        recent_sold_out_0_14_day_count: 0,
        sold_out_15_30_day_count: 0,
        stale_or_future_current_offer_count: 0,
        unique_source_retailer_count: 1,
        calculated_at: @calculated_at,
        latest_nonfuture_checked_at: @calculated_at,
        source_msrp_pln: Decimal.new("35"),
        source_mapping_confident: false,
        source_evidence: [
          evidence("mapping-default", "listing-default", "retailer-default", "10", 0)
        ]
      },
      Map.new(overrides)
    )
  end

  defp evidence(mapping_id, listing_id, retailer_id, price, _index, opts \\ []) do
    checked_at = Keyword.get(opts, :checked_at, @calculated_at)
    category = Keyword.get(opts, :category, "lgs")
    stock_status = Keyword.get(opts, :stock_status, "in_stock")

    %{
      mapping_id: mapping_id,
      listing_id: listing_id,
      retailer_id: retailer_id,
      retailer_category: category,
      stock_status: stock_status,
      confidence: Keyword.get(opts, :confidence, Decimal.new("1")),
      approved_at: @calculated_at,
      price_pln: decimal(price),
      checked_at: checked_at
    }
  end

  defp decimal(nil), do: nil
  defp decimal(value), do: Decimal.new(value)
end
