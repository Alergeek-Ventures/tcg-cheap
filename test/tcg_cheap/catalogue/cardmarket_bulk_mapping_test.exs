defmodule TcgCheap.Catalogue.CardmarketBulkMappingTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  @evidence ~U[2026-09-01 12:00:00Z]

  test "matches pending, unmatched, and prior bulk reviews" do
    for status <- ["pending", "unmatched"] do
      card = card(status: status)
      updated_at = card.updated_at

      assert {:ok, matched} =
               Core.cardmarket_bulk_auto_match_card_printing(
                 card,
                 %{
                   expected_updated_at: updated_at,
                   evidence_timestamp: @evidence,
                   cardmarket_product_id: 1001
                 },
                 authorize?: false
               )

      assert {matched.mapping_status, matched.mapping_authority, matched.cardmarket_product_id} ==
               {"matched", "provider", 1001}
    end

    reviewed = card(status: "review", reason: "cardmarket_bulk_v1:old")

    assert {:ok, matched} =
             Core.cardmarket_bulk_auto_match_card_printing(
               reviewed,
               %{
                 expected_updated_at: reviewed.updated_at,
                 evidence_timestamp: @evidence,
                 cardmarket_product_id: 1002
               },
               authorize?: false
             )

    assert {matched.mapping_status, matched.mapping_review_reason} == {"matched", nil}
  end

  test "reviews with exactly one bulk prefix and can update prior bulk review" do
    card = card(status: "pending")

    assert {:ok, reviewed} =
             Core.cardmarket_bulk_review_card_printing(
               card,
               %{
                 expected_updated_at: card.updated_at,
                 evidence_timestamp: @evidence,
                 reason: "Needs review"
               },
               authorize?: false
             )

    assert reviewed.mapping_review_reason == "cardmarket_bulk_v1:Needs review"

    assert {:ok, reviewed_again} =
             Core.cardmarket_bulk_review_card_printing(
               reviewed,
               %{
                 expected_updated_at: reviewed.updated_at,
                 evidence_timestamp: @evidence,
                 reason: "cardmarket_bulk_v1:Needs review"
               },
               authorize?: false
             )

    assert reviewed_again.mapping_review_reason == "cardmarket_bulk_v1:Needs review"
  end

  test "rejects stale, actor-owned, matched, and unrelated review states" do
    stale = card(status: "pending")

    assert {:error, _} =
             Core.cardmarket_bulk_auto_match_card_printing(
               stale,
               %{
                 expected_updated_at: DateTime.add(stale.updated_at, -1, :second),
                 evidence_timestamp: @evidence,
                 cardmarket_product_id: 1003
               },
               authorize?: false
             )

    admin =
      TcgCheap.Accounts.register_admin!(
        %{
          email: "bulk-#{System.unique_integer([:positive])}@example.test",
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        },
        authorize?: false
      )

    for current <- [
          card(status: "matched", product_id: 1004, authority: "provider"),
          card(status: "matched", product_id: 1005, authority: "administrator"),
          card(status: "review", reason: "manual review", authority: "provider"),
          card(
            status: "review",
            reason: "cardmarket_bulk_v1:administrator",
            authority: "administrator"
          )
        ] do
      assert {:error, _} =
               Core.cardmarket_bulk_review_card_printing(
                 current,
                 %{
                   expected_updated_at: current.updated_at,
                   evidence_timestamp: @evidence,
                   reason: "new"
                 },
                 authorize?: false
               )

      assert {:ok, unchanged} = Core.get_card_printing_by_tcgdex_id(current.tcgdex_id)

      assert {unchanged.mapping_status, unchanged.mapping_authority,
              unchanged.mapping_review_reason} ==
               {current.mapping_status, current.mapping_authority, current.mapping_review_reason}
    end

    actor_card = card(status: "pending")

    assert {:error, _} =
             Core.cardmarket_bulk_auto_match_card_printing(
               actor_card,
               %{
                 expected_updated_at: actor_card.updated_at,
                 evidence_timestamp: @evidence,
                 cardmarket_product_id: 1006
               },
               actor: admin,
               authorize?: false
             )
  end

  test "same-state same-reason is a no-op and successful changes record one system decision" do
    card = card(status: "pending")

    assert {:ok, reviewed} =
             Core.cardmarket_bulk_review_card_printing(
               card,
               %{
                 expected_updated_at: card.updated_at,
                 evidence_timestamp: @evidence,
                 reason: "same"
               },
               authorize?: false
             )

    timestamp = reviewed.mapping_updated_at

    assert {:ok, noop} =
             Core.cardmarket_bulk_review_card_printing(
               reviewed,
               %{
                 expected_updated_at: reviewed.updated_at,
                 evidence_timestamp: DateTime.add(@evidence, 1, :day),
                 reason: "cardmarket_bulk_v1:same"
               },
               authorize?: false
             )

    assert noop.mapping_updated_at == timestamp

    assert {:ok, decisions} =
             Core.list_card_printing_mapping_decision_history(noop.id, authorize?: false)

    assert Enum.count(decisions, &(&1.event == "provider_updated")) == 1

    assert [%{actor_type: "system", actor_id: nil, actor_email: nil}] =
             Enum.filter(decisions, &(&1.event == "provider_updated"))
  end

  test "forged superseded evidence cannot archive a current valuation" do
    card = card(status: "matched", product_id: 1010)

    valuation =
      Core.record_single_valuation!(%{
        card_printing_id: card.id,
        value_eur: Decimal.new("10.00"),
        currency: "EUR",
        policy_version: "cardmarket_bulk_v1",
        source: "cardmarket_bulk",
        source_metric: "avg7",
        fetched_at: @evidence,
        provider_updated_at: @evidence,
        cardmarket_product_id: 1010
      })

    assert {:error, _} =
             Core.cardmarket_bulk_review_card_printing(
               card,
               %{
                 expected_updated_at: card.updated_at,
                 evidence_timestamp: @evidence,
                 reason: "forged",
                 superseded_evidence_id: Ecto.UUID.generate()
               },
               authorize?: false
             )

    assert {:ok, current} = Core.get_current_single_valuation(card.id, "cardmarket_bulk_v1")
    assert current.id == valuation.id
    assert current.current?
  end

  defp card(opts) do
    status = Keyword.get(opts, :status, "pending")

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: "bulk-#{System.unique_integer([:positive])}",
      name: "Bulk card",
      set_name: "Bulk set",
      collector_number: "1",
      mapping_status: status,
      mapping_review_reason: Keyword.get(opts, :reason),
      cardmarket_product_id: Keyword.get(opts, :product_id),
      mapping_authority: Keyword.get(opts, :authority, "provider")
    })
  end
end
