defmodule TcgCheap.Catalogue.CardPrintingMappingDecisionTest do
  use TcgCheap.DataCase, async: true

  alias Ash.Resource.Info

  alias TcgCheap.{
    Catalogue.CardPrinting,
    Catalogue.CardPrintingMappingDecision,
    Catalogue.Importer,
    Core,
    Pricing.Singles.SingleValuationSnapshot,
    Pricing.Singles.ValuationAcquisition
  }

  test "imports record one decision and unchanged imports record none" do
    id = "mapping-#{System.unique_integer([:positive])}"

    card = import_card(id)

    assert {:ok, [%{event: "imported"}]} =
             Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

    assert import_card(id).id == card.id

    assert {:ok, [%{event: "imported"}]} =
             Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)
  end

  test "correction and reopen are stale-safe, attributed, and immutable" do
    card = card("pending")
    admin = admin()

    corrected =
      Core.correct_cardmarket_mapping!(
        card,
        %{cardmarket_product_id: 123, reason: "Verified", expected_updated_at: card.updated_at},
        actor: admin
      )

    assert {corrected.mapping_status, corrected.mapping_authority,
            corrected.cardmarket_product_id} == {"matched", "administrator", 123}

    valuation = record_valuation(corrected)

    assert {:ok, [%{event: "corrected", actor_type: "administrator"}]} =
             history(card.id)

    assert {:error, _error} =
             Core.correct_cardmarket_mapping(
               card,
               %{
                 cardmarket_product_id: 456,
                 reason: "Stale",
                 expected_updated_at: card.updated_at
               },
               actor: admin
             )

    reopened =
      Core.reopen_cardmarket_mapping!(
        corrected,
        %{reason: "Recheck", expected_updated_at: corrected.updated_at},
        actor: admin
      )

    assert {reopened.mapping_status, reopened.cardmarket_product_id,
            reopened.mapping_review_reason} == {"review", nil, "Recheck"}

    assert {:ok, nil} =
             Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")

    assert [archived] =
             Core.list_single_valuation_history!(card.id, "tcgdex_cardmarket_v1")

    assert archived.id == valuation.id
    refute archived.current?

    assert {:ok, decisions} = history(card.id)
    assert List.last(decisions).event == "reopened"
    refute :update in Enum.map(Info.actions(CardPrintingMappingDecision), & &1.type)
    refute :destroy in Enum.map(Info.actions(CardPrintingMappingDecision), & &1.type)

    assert {:error, _} =
             Core.record_card_printing_mapping_decision(%{
               card_printing_id: card.id,
               event: "baseline",
               to_status: "pending",
               mapping_authority: "provider",
               actor_type: "system",
               printing_version_at: card.updated_at
             })

    assert {:error, _} =
             Core.record_card_printing_mapping_decision(
               %{
                 card_printing_id: card.id,
                 event: "corrected",
                 from_status: "pending",
                 to_status: "matched",
                 cardmarket_product_id: 456,
                 mapping_authority: "administrator",
                 printing_version_at: card.updated_at,
                 actor_type: "administrator",
                 actor_id: admin.id,
                 actor_email: admin.email
               },
               authorize?: false
             )
  end

  test "provider changes are recorded and administrator mappings survive imports" do
    id = "provider-#{System.unique_integer([:positive])}"
    card = import_card(id)
    valuation = record_valuation(card)
    Phoenix.PubSub.subscribe(TcgCheap.PubSub, ValuationAcquisition.topic(card))
    changed = import_card(id, 456, "2026-08-10T10:00:00Z")
    assert_receive {:card_mapping_changed, %{card_printing_id: card_id}}
    assert card_id == card.id
    assert changed.id == card.id
    assert {:ok, [%{event: "imported"}, %{event: "provider_updated"}]} = history(card.id)
    assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")

    refute Ash.get!(SingleValuationSnapshot, valuation.id, domain: Core, authorize?: false).current?

    admin = admin()

    corrected =
      Core.correct_cardmarket_mapping!(
        changed,
        %{
          cardmarket_product_id: 789,
          reason: "Verified",
          expected_updated_at: changed.updated_at
        },
        actor: admin
      )

    imported = import_card(id, 999, "2026-08-10T11:00:00Z")

    assert {imported.mapping_authority, imported.cardmarket_product_id, imported.mapping_status} ==
             {"administrator", 789, "matched"}

    assert imported.name == "Card"
    assert {:ok, decisions} = history(corrected.id)
    assert Enum.count(decisions, &(&1.event == "corrected")) == 1

    reopened =
      Core.reopen_cardmarket_mapping!(
        imported,
        %{reason: "Needs another review", expected_updated_at: imported.updated_at},
        actor: admin
      )

    provider_after_reopen = import_card(id, 1_001, "2026-08-10T12:00:00Z")

    assert {provider_after_reopen.mapping_authority, provider_after_reopen.mapping_status,
            provider_after_reopen.cardmarket_product_id,
            provider_after_reopen.mapping_review_reason} ==
             {"administrator", "review", nil, "Needs another review"}

    assert provider_after_reopen.mapping_updated_at == reopened.mapping_updated_at
  end

  test "mapping, valuation archival, and decision history share one transaction" do
    card = card("matched", mapping_status: "matched", cardmarket_product_id: 123)
    valuation = record_valuation(card)
    admin = admin()

    assert {:error, _forced_rollback} =
             Ash.transact(
               [CardPrinting, CardPrintingMappingDecision, SingleValuationSnapshot],
               fn ->
                 Core.correct_cardmarket_mapping!(
                   card,
                   %{
                     cardmarket_product_id: 456,
                     reason: "Transaction proof",
                     expected_updated_at: card.updated_at
                   },
                   actor: admin
                 )

                 {:error, :forced_rollback}
               end
             )

    reloaded = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert {reloaded.mapping_status, reloaded.cardmarket_product_id} == {"matched", 123}

    assert Ash.get!(SingleValuationSnapshot, valuation.id, domain: Core, authorize?: false).current?

    assert {:ok, []} = history(card.id)
  end

  test "unresolved mappings are rejected before enqueue" do
    card = card("unmatched")

    assert {:error, :unpriced_mapping} =
             ValuationAcquisition.enqueue_if_stale(card,
               request_admitter: fn -> raise "called" end
             )
  end

  defp history(id), do: Core.list_card_printing_mapping_decision_history(id, authorize?: false)

  defp import_card(id, product_id \\ 123, updated \\ nil) do
    payload = %{
      "id" => id,
      "name" => "Card",
      "localId" => "1",
      "set" => %{"id" => "set", "name" => "Set"},
      "pricing" => %{"cardmarket" => %{"idProduct" => product_id}}
    }

    payload = if updated, do: Map.put(payload, "updated", updated), else: payload

    {:ok, %{card: card}} =
      Importer.import_fetched_card(payload, %{"id" => "set", "name" => "Set"}, id,
        synced_at: DateTime.utc_now()
      )

    card
  end

  defp card(label, overrides \\ []) do
    attrs = %{
      tcgdex_id: "decision-#{label}-#{System.unique_integer([:positive])}",
      name: label,
      set_name: "Set",
      collector_number: "1"
    }

    TcgCheap.TestSupport.import_card_printing!(Map.merge(attrs, Map.new(overrides)))
  end

  defp record_valuation(card) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("10.00"),
      currency: "EUR",
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: card.cardmarket_product_id
    })
  end

  defp admin do
    TcgCheap.Accounts.register_admin!(
      %{
        email: "decision-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end
end
