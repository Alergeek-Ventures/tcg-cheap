defmodule TcgCheap.Pricing.Singles.ValuationPolicyTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.ValuationPolicy

  test "bulk is the only deterministic public selection" do
    assert ValuationPolicy.requested_policy() == ValuationPolicy.bulk_policy()
    assert ValuationPolicy.default_policy() == ValuationPolicy.bulk_policy()
    assert ValuationPolicy.selection() == ValuationPolicy.bulk_policy()
    assert ValuationPolicy.selection(readiness: %{ready?: false}) == ValuationPolicy.bulk_policy()
    assert ValuationPolicy.selection(readiness: %{ready?: true}) == ValuationPolicy.bulk_policy()
    assert ValuationPolicy.selection(%{readiness: :ignored}) == ValuationPolicy.bulk_policy()
  end

  test "historical TCGdex is not selectable" do
    assert ValuationPolicy.current_valuation(
             %{cardmarket_product_id: 1},
             ValuationPolicy.tcgdex_policy()
           ) == nil
  end
end
