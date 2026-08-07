defmodule TcgCheap.Pricing.Singles.ValuationHistorySinceTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  test "reads only records at or after the cutoff for the exact card and policy" do
    card = create_card_printing("primary")
    other_card = create_card_printing("other")
    policy = "policy-#{System.unique_integer([:positive])}"
    other_policy = "other-policy-#{System.unique_integer([:positive])}"
    since = ~U[2026-07-10 00:00:00.000000Z]

    old = record(card, policy, ~U[2026-07-09 23:59:59.000000Z])
    included = record(card, policy, since)
    later = record(card, policy, ~U[2026-07-11 00:00:00.000000Z])
    _wrong_policy = record(card, other_policy, ~U[2026-07-10 01:00:00.000000Z])
    _wrong_card = record(other_card, policy, ~U[2026-07-10 02:00:00.000000Z])

    assert [result_included, result_later] =
             Core.list_single_valuation_history_since!(card.id, policy, since)

    assert result_included.id == included.id
    assert result_later.id == later.id
    refute Enum.any?([result_included, result_later], &(&1.id == old.id))
  end

  defp create_card_printing(label) do
    suffix = System.unique_integer([:positive])

    Core.create_card_printing!(%{
      tcgdex_id: "history-#{label}-#{suffix}",
      name: "History Card",
      set_name: "Base Set",
      collector_number: "#{suffix}"
    })
  end

  defp record(card, policy, fetched_at) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("10.00"),
      policy_version: policy,
      source: "test",
      source_metric: "avg7",
      fetched_at: fetched_at
    })
  end
end
