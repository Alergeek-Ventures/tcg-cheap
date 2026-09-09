defmodule TcgCheap.Pricing.CardmarketBulk.LatestBatchRecoveryWorkerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Catalogue.CardmarketCrosswalk
  alias TcgCheap.Catalogue.CardPrinting
  alias TcgCheap.Core
  alias TcgCheap.Pricing.CardmarketBulk.LatestBatchRecoveryWorker
  alias TcgCheap.Pricing.CardmarketBulk.{Price, Product}

  test "rejects invalid arguments" do
    assert {:discard, :malformed_job_args} =
             LatestBatchRecoveryWorker.perform(%Oban.Job{args: %{}})

    assert {:discard, :malformed_job_args} =
             LatestBatchRecoveryWorker.perform(%Oban.Job{args: %{"revision" => "wrong"}})

    assert {:discard, :malformed_job_args} =
             LatestBatchRecoveryWorker.perform(%Oban.Job{
               args: %{"revision" => "cardmarket_mapping_recovery_v1", "extra" => true}
             })
  end

  test "discards when no succeeded batch exists" do
    assert {:discard, :no_succeeded_batch} =
             LatestBatchRecoveryWorker.perform(%Oban.Job{
               args: %{"revision" => "cardmarket_mapping_recovery_v1"}
             })
  end

  test "enqueue is revisioned and the second enqueue conflicts" do
    first = LatestBatchRecoveryWorker.enqueue()
    second = LatestBatchRecoveryWorker.enqueue()

    assert {:ok, first_job} = first
    assert {:ok, second_job} = second
    assert first_job.id == second_job.id
    refute first_job.conflict?
    assert second_job.conflict?
    assert first_job.args == %{"revision" => "cardmarket_mapping_recovery_v1"}
  end

  test "recovers the latest batch end to end with database persistence idempotence" do
    suffix = System.unique_integer([:positive])
    set_id = "lillie-recovery-set-#{suffix}"
    card_id = "lillie-recovery-card-#{suffix}"
    evidence_at = ~U[2025-01-01 00:00:00Z]
    product_created_at = ~U[2026-09-08 10:00:00Z]
    price_created_at = ~U[2026-09-08 11:00:00.000000Z]
    fetched_at = ~U[2026-09-08 12:00:00.000000Z]
    completed_at = ~U[2026-09-08 13:00:00.000000Z]

    set_payload = %{
      "id" => set_id,
      "name" => "Mega Evolution",
      "series" => "Mega Evolution",
      "releaseDate" => "2025-01-01",
      "images" => %{"logo" => "logo.webp", "symbol" => "symbol.webp"},
      "legal" => %{"standard" => true, "expanded" => false},
      "printedTotal" => 132,
      "total" => 188
    }

    card_payload = %{
      "id" => card_id,
      "name" => "Lillie's Determination",
      "localId" => "119",
      "set" => %{"id" => set_id},
      "legal" => %{"standard" => true, "expanded" => false},
      "pricing" => %{
        "cardmarket" => %{"idProduct" => 851_190, "updated" => "2025-01-01T00:00:00Z"}
      },
      "variants_detailed" => [
        %{
          "type" => "normal",
          "subtype" => "unlimited",
          "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
        },
        %{
          "type" => "reverse",
          "subtype" => "unlimited",
          "pricing" => %{"cardmarket" => %{"idProduct" => 851_190}}
        },
        %{"type" => "stamped", "stamp" => "cosmos"}
      ]
    }

    set =
      Core.import_card_set!(
        %{
          tcgdex_id: set_id,
          name: "Mega Evolution",
          series_id: "mega-evolution",
          series_name: "Mega Evolution",
          release_date: ~D[2025-01-01],
          logo_url: "logo.webp",
          symbol_url: "symbol.webp",
          official_count: 132,
          total_count: 188,
          standard_legal: true,
          expanded_legal: false,
          source_payload: set_payload
        },
        authorize?: false
      )

    card =
      CardPrinting
      |> Ash.Changeset.for_create(:import, %{
        tcgdex_id: card_id,
        name: card_payload["name"],
        set_name: set.name,
        collector_number: "119",
        card_set_id: set.id,
        source_payload: card_payload,
        mapping_status: "review",
        mapping_authority: "provider",
        mapping_review_reason: "firstEdition variant",
        mapping_updated_at: evidence_at,
        last_synced_at: evidence_at,
        details_synced_at: evidence_at
      })
      |> Ash.create!(authorize?: false)

    anchor =
      CardPrinting
      |> Ash.Changeset.for_create(:import, %{
        tcgdex_id: "lillie-recovery-anchor-#{suffix}",
        name: "Mega Anchor",
        set_name: set.name,
        collector_number: "120",
        card_set_id: set.id,
        source_payload: %{"id" => "lillie-recovery-anchor-#{suffix}", "set" => %{"id" => set_id}},
        mapping_status: "matched",
        mapping_authority: "provider",
        cardmarket_product_id: 851_191
      })
      |> Ash.create!(authorize?: false)

    assert {:ok, _} =
             Core.record_card_printing_mapping_decision(
               %{
                 card_printing_id: card.id,
                 event: "imported",
                 to_status: "review",
                 mapping_authority: "provider",
                 reason: "firstEdition variant",
                 source_mapping_evidence_at: evidence_at,
                 printing_version_at: card.updated_at,
                 actor_type: "system"
               },
               authorize?: false
             )

    hash = fn value -> :crypto.hash(:sha256, value) |> Base.encode16(case: :lower) end

    batch =
      Core.complete_cardmarket_bulk_batch!(
        %{
          policy_version: "cardmarket_bulk_v1",
          parser_version: "test",
          product_created_at: product_created_at,
          price_created_at: price_created_at,
          fetched_at: fetched_at,
          completed_at: completed_at,
          product_sha256: hash.("products"),
          price_sha256: hash.("prices"),
          product_byte_size: 1,
          price_byte_size: 1,
          product_row_count: 1,
          price_row_count: 1,
          singles_price_row_count: 1,
          priceable_singles_count: 1
        },
        authorize?: false
      )

    Ash.create!(
      Ash.Changeset.for_create(Product, :upsert, %{
        cardmarket_product_id: 851_190,
        name: "Lillie's Determination",
        category_id: 51,
        category_name: "Pokémon Single",
        expansion_id: 77,
        metacard_id: 0,
        source_date_added: "2026-09-08",
        source_updated_at: product_created_at,
        last_batch_id: batch.id
      }),
      authorize?: false
    )

    Ash.create!(
      Ash.Changeset.for_create(Product, :upsert, %{
        cardmarket_product_id: 851_191,
        name: anchor.name,
        category_id: 51,
        category_name: "Pokémon Single",
        expansion_id: 77,
        metacard_id: 0,
        source_date_added: "2026-09-08",
        source_updated_at: product_created_at,
        last_batch_id: batch.id
      }),
      authorize?: false
    )

    assert {:ok, _crosswalk_summary} = CardmarketCrosswalk.run(batch)

    assert {:ok, existing_evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert Enum.any?(
             existing_evidence,
             &(&1.card_printing_id == card.id and &1.decision == "review")
           )

    Ash.create!(
      Ash.Changeset.for_create(Price, :upsert, %{
        cardmarket_product_id: 851_190,
        category_id: 51,
        avg7: Decimal.new("0.52"),
        selected_metric: "avg7",
        selected_value_eur: Decimal.new("0.52"),
        source_updated_at: price_created_at,
        last_batch_id: batch.id
      }),
      authorize?: false
    )

    job = %Oban.Job{args: %{"revision" => "cardmarket_mapping_recovery_v1"}}
    assert :ok = LatestBatchRecoveryWorker.perform(job)
    assert :ok = LatestBatchRecoveryWorker.perform(job)

    recovered = Core.get_card_printing_by_tcgdex_id!(card_id, authorize?: false)

    assert {recovered.mapping_status, recovered.mapping_authority,
            recovered.cardmarket_product_id} ==
             {"matched", "provider", 851_190}

    history = Core.list_card_printing_mapping_decision_history!(card.id, authorize?: false)
    assert Enum.count(history, &(&1.event == "provider_updated")) == 1

    assert {:ok, [mapping]} =
             Core.list_cardmarket_expansion_mappings_for_batch(batch.id, authorize?: false)

    assert {mapping.card_set_id, mapping.expansion_id, mapping.status, mapping.anchor_count} ==
             {set.id, 77, "approved", 1}

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert Enum.count(evidence, &(&1.card_printing_id == card.id and &1.decision == "review")) ==
             1

    assert Enum.count(evidence, &(&1.card_printing_id == card.id and &1.decision == "anchor")) ==
             1

    assert Enum.any?(evidence, fn item ->
             item.card_printing_id == card.id and
               item.evidence["anchor_cardmarket_product_id"] == 851_190
           end)

    assert {:ok, valuation} = Core.get_current_single_valuation(card.id, "cardmarket_bulk_v1")

    assert {valuation.source, valuation.source_metric, valuation.fetched_at,
            valuation.provider_updated_at, valuation.cardmarket_product_id} ==
             {"cardmarket_bulk", "avg7", fetched_at, price_created_at, 851_190}

    assert Decimal.equal?(valuation.value_eur, Decimal.new("0.52"))
    assert length(Core.list_single_valuation_history!(card.id, "cardmarket_bulk_v1")) == 1
  end
end
