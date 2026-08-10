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
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "card-a-#{suffix}",
        name: "Card A #{suffix}",
        set_name: set.name,
        collector_number: "1",
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      })

    second =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "card-b-#{suffix}",
        name: "Card B #{suffix}",
        set_name: set.name,
        collector_number: "2",
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      })

    Core.record_single_valuation!(%{
      card_printing_id: first.id,
      value_eur: Decimal.new("1.25"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "test",
      source_metric: "trend",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: first.cardmarket_product_id
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

  test "bulk printing read does not preload a current valuation from another Cardmarket product" do
    suffix = token("stale-bulk")

    card =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "card-#{suffix}",
        name: "Card #{suffix}",
        set_name: "Set #{suffix}",
        collector_number: "1",
        mapping_status: "matched",
        cardmarket_product_id: 303
      })

    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("7.77"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "test",
      source_metric: "trend",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: card.cardmarket_product_id
    })

    Repo.query!(
      "UPDATE single_valuation_snapshots SET cardmarket_product_id = $1 WHERE card_printing_id = $2",
      [404, Ecto.UUID.dump!(card.id)]
    )

    assert [result] = Core.list_card_printings_by_tcgdex_ids!([card.tcgdex_id])
    assert result.tcgdex_cardmarket_v1_current_valuation == nil
  end
end
