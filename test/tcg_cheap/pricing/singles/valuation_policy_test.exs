defmodule TcgCheap.Pricing.Singles.ValuationPolicyTest do
  use ExUnit.Case, async: false

  alias TcgCheap.Pricing.Singles.ValuationPolicy

  setup do
    previous = Application.get_env(:tcg_cheap, :public_singles_valuation_policy)
    on_exit(fn -> Application.put_env(:tcg_cheap, :public_singles_valuation_policy, previous) end)
    :ok
  end

  test "defaults and malformed values fail closed" do
    Application.delete_env(:tcg_cheap, :public_singles_valuation_policy)
    assert ValuationPolicy.requested_policy() == ValuationPolicy.tcgdex_policy()

    Application.put_env(:tcg_cheap, :public_singles_valuation_policy, "not-a-policy")
    assert ValuationPolicy.requested_policy() == ValuationPolicy.tcgdex_policy()

    assert ValuationPolicy.selection(readiness: %{ready?: true}) ==
             ValuationPolicy.tcgdex_policy()
  end

  test "bulk requires explicit request and ready evidence" do
    Application.put_env(:tcg_cheap, :public_singles_valuation_policy, "cardmarket_bulk_v1")

    assert ValuationPolicy.selection(readiness: %{ready?: false}) ==
             ValuationPolicy.tcgdex_policy()

    assert ValuationPolicy.selection(readiness: %{ready?: true}) == ValuationPolicy.bulk_policy()
  end

  test "selection accepts only a single readiness option" do
    Application.put_env(
      :tcg_cheap,
      :public_singles_valuation_policy,
      ValuationPolicy.bulk_policy()
    )

    assert ValuationPolicy.selection(readiness: %{ready?: true}) == ValuationPolicy.bulk_policy()

    assert ValuationPolicy.selection(readiness: %{ready?: true}, readiness: %{ready?: true}) ==
             ValuationPolicy.tcgdex_policy()

    assert ValuationPolicy.selection(%{readiness: %{ready?: true}}) ==
             ValuationPolicy.tcgdex_policy()

    assert ValuationPolicy.selection(readiness: :not_a_readiness_report) ==
             ValuationPolicy.tcgdex_policy()
  end

  test "injected readiness does not load coverage from the database" do
    Application.put_env(
      :tcg_cheap,
      :public_singles_valuation_policy,
      ValuationPolicy.bulk_policy()
    )

    assert ValuationPolicy.selection(readiness: %{ready?: true}) == ValuationPolicy.bulk_policy()
  end
end
