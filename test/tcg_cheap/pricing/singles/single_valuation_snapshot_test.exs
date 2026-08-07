defmodule TcgCheap.Pricing.Singles.SingleValuationSnapshotTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  test "retains aggregate provenance and archives a prior current snapshot" do
    card = create_card_printing()

    valuation =
      Core.record_single_valuation!(%{
        card_printing_id: card.id,
        value_eur: Decimal.new("411.69"),
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex_cardmarket",
        source_metric: "avg7",
        fetched_at: ~U[2026-08-07 12:00:00.000000Z],
        provider_updated_at: ~U[2026-08-07 08:03:04.828000Z],
        cardmarket_product_id: 273_699
      })

    assert valuation.current?
    assert valuation.currency == "EUR"
    assert Decimal.equal?(valuation.value_eur, Decimal.new("411.69"))

    assert [current] = Core.list_current_single_valuations!(card.id)
    assert current.id == valuation.id

    archived = Core.archive_single_valuation!(valuation)

    refute archived.current?
    assert [] = Core.list_current_single_valuations!(card.id)
  end

  test "uses the TCGdex ID as a unique exact-printing identity" do
    card = create_card_printing()

    assert fetched = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert fetched.id == card.id

    assert {:error, error} =
             Core.create_card_printing(%{
               tcgdex_id: card.tcgdex_id,
               name: "Duplicate",
               set_name: "Base Set",
               collector_number: "4"
             })

    assert Exception.message(error) =~ "has already been taken"
  end

  test "rejects non-positive values and non-EUR aggregate snapshots" do
    card = create_card_printing()

    assert {:error, zero_value_error} =
             Core.record_single_valuation(snapshot_attributes(card, %{value_eur: Decimal.new(0)}))

    assert Exception.message(zero_value_error) =~ "must be greater than 0"

    assert {:error, currency_error} =
             Core.record_single_valuation(snapshot_attributes(card, %{currency: "PLN"}))

    assert Exception.message(currency_error) =~ "expected one of \"EUR\""
  end

  defp create_card_printing do
    suffix = System.unique_integer([:positive])

    Core.create_card_printing!(%{
      tcgdex_id: "base1-4-#{suffix}",
      name: "Charizard",
      set_name: "Base Set",
      collector_number: "4"
    })
  end

  defp snapshot_attributes(card, overrides) do
    Map.merge(
      %{
        card_printing_id: card.id,
        value_eur: Decimal.new("411.69"),
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex_cardmarket",
        source_metric: "avg7",
        fetched_at: ~U[2026-08-07 12:00:00.000000Z]
      },
      overrides
    )
  end
end
