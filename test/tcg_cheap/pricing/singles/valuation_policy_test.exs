defmodule TcgCheap.Pricing.Singles.ValuationPolicyTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.ValuationPolicy

  test "bulk is the only deterministic public policy" do
    assert ValuationPolicy.policy_version() == "cardmarket_bulk_v1"
  end

  test "current valuation requires the exact bulk relationship" do
    assert ValuationPolicy.current_valuation(%{cardmarket_product_id: 1}) == nil
  end
end
