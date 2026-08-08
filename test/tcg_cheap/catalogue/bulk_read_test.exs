defmodule TcgCheap.Catalogue.BulkReadTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  defp token(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "bulk printing read returns requested cards with local set and current policy valuation" do
    suffix = token("bulk")

    set =
      Core.import_card_set!(%{
        tcgdex_id: "set-#{suffix}",
        name: "Set #{suffix}"
      })

    first =
      Core.import_card_printing!(%{
        tcgdex_id: "card-a-#{suffix}",
        name: "Card A #{suffix}",
        set_name: set.name,
        collector_number: "1",
        card_set_id: set.id,
        mapping_status: "pending"
      })

    second =
      Core.import_card_printing!(%{
        tcgdex_id: "card-b-#{suffix}",
        name: "Card B #{suffix}",
        set_name: set.name,
        collector_number: "2",
        card_set_id: set.id,
        mapping_status: "pending"
      })

    Core.record_single_valuation!(%{
      card_printing_id: first.id,
      value_eur: Decimal.new("1.25"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "test",
      source_metric: "trend",
      fetched_at: DateTime.utc_now()
    })

    results =
      Core.list_card_printings_by_tcgdex_ids!([
        first.tcgdex_id,
        second.tcgdex_id,
        "missing-#{suffix}"
      ])

    assert Enum.map(results, & &1.tcgdex_id) |> Enum.sort() ==
             Enum.sort([first.tcgdex_id, second.tcgdex_id])

    assert Enum.all?(results, &(&1.card_set.tcgdex_id == set.tcgdex_id))
    assert first_result = Enum.find(results, &(&1.tcgdex_id == first.tcgdex_id))
    assert first_result.tcgdex_cardmarket_v1_current_valuation.value_eur == Decimal.new("1.25")

    assert Enum.find(results, &(&1.tcgdex_id == second.tcgdex_id)).tcgdex_cardmarket_v1_current_valuation ==
             nil
  end

  test "rejects more than one hundred IDs before querying" do
    ids = Enum.map(1..101, &"card-#{&1}-#{token("limit")}")
    assert {:error, _error} = Core.list_card_printings_by_tcgdex_ids(ids)
  end
end
