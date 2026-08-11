defmodule TcgCheap.Catalogue.RecentlyTrackedCardPrintingsTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  test "returns locally tracked cards in deterministic order with a hard cap" do
    cards =
      Enum.map(1..12, fn index ->
        TcgCheap.TestSupport.import_card_printing!(%{
          tcgdex_id: "recent-#{System.unique_integer([:positive])}-#{index}",
          name: "Recent #{index}",
          set_name: "Recent Set",
          collector_number: "#{index}",
          last_synced_at: DateTime.add(~U[2026-08-10 12:00:00Z], -index, :second)
        })
      end)

    _untracked =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "untracked-#{System.unique_integer([:positive])}",
        name: "Untracked",
        set_name: "Recent Set",
        collector_number: "untracked"
      })

    assert {:ok, result} = Core.list_recently_tracked_card_printings()
    assert length(result) == 10
    expected = Enum.take(Enum.map(cards, & &1.id), 10)
    assert Enum.map(result, & &1.id) == expected
  end

  test "loads an optional current valuation without selecting private source fields" do
    card =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "valued-recent-#{System.unique_integer([:positive])}",
        name: "Valued recent",
        set_name: "Recent Set",
        collector_number: "1",
        cardmarket_product_id: System.unique_integer([:positive]),
        mapping_status: "matched",
        last_synced_at: ~U[2026-08-10 12:00:00Z]
      })

    valuation =
      Core.record_single_valuation!(%{
        card_printing_id: card.id,
        value_eur: Decimal.new("12.50"),
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex_cardmarket",
        source_metric: "avg7",
        fetched_at: ~U[2026-08-10 12:00:00Z],
        cardmarket_product_id: card.cardmarket_product_id
      })

    assert {:ok, [result]} = Core.list_recently_tracked_card_printings()
    assert result.tcgdex_cardmarket_v1_current_valuation.id == valuation.id
    assert %Ash.NotLoaded{} = result.source_payload
    assert %Ash.NotLoaded{} = result.variant_data
    assert %Ash.NotLoaded{} = result.search_name
  end
end
