defmodule TcgCheap.Catalogue.LegacyCardmarketMappingRecoveryTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Catalogue.{CardPrinting, CardSet}
  alias TcgCheap.Catalogue.LegacyCardmarketMappingRecovery
  alias TcgCheap.Core
  alias TcgCheap.Repo

  test "recovers a proven old provider review and preserves the complete set" do
    suffix = System.unique_integer([:positive])
    set_id = "recovery-set-#{suffix}"
    card_id = "recovery-card-#{suffix}"
    evidence_at = ~U[2025-01-01 00:00:00Z]

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
      Core.import_card_set!(%{
        tcgdex_id: set_id,
        name: set_payload["name"],
        series_name: "Mega Evolution",
        release_date: ~D[2025-01-01],
        logo_url: "logo.webp",
        symbol_url: "symbol.webp",
        official_count: 132,
        total_count: 188,
        standard_legal: true,
        expanded_legal: false,
        source_payload: set_payload
      })

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

    record_history!(card, evidence_at)
    assert card.mapping_review_reason == "firstEdition variant"

    assert {:ok, %{scanned: 1, recovered: 1, unchanged: 0}} =
             LegacyCardmarketMappingRecovery.run()

    recovered = Core.get_card_printing_by_tcgdex_id!(card_id, authorize?: false)

    {:ok, [persisted_set]} =
      CardSet
      |> Ash.Query.for_read(:by_tcgdex_id, %{tcgdex_id: set_id})
      |> Ash.Query.select([
        :source_payload,
        :series_name,
        :release_date,
        :logo_url,
        :symbol_url,
        :official_count,
        :total_count,
        :standard_legal,
        :expanded_legal
      ])
      |> Ash.read(authorize?: false)

    assert {recovered.mapping_status, recovered.mapping_authority,
            recovered.cardmarket_product_id} ==
             {"matched", "provider", 851_190}

    assert persisted_set.source_payload == set_payload

    assert {persisted_set.series_name, persisted_set.release_date, persisted_set.logo_url,
            persisted_set.symbol_url, persisted_set.official_count, persisted_set.total_count,
            persisted_set.standard_legal, persisted_set.expanded_legal} ==
             {"Mega Evolution", ~D[2025-01-01], "logo.webp", "symbol.webp", 132, 188, true, false}

    assert {:ok,
            [%{event: "imported"}, %{event: "provider_updated", cardmarket_product_id: 851_190}]} =
             Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

    assert {:ok, %{scanned: 0, recovered: 0, unchanged: 0}} =
             LegacyCardmarketMappingRecovery.run()

    assert {:ok, history} =
             Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

    assert Enum.count(history, &(&1.event == "provider_updated")) == 1
  end

  test "counts unsupported, unverified, missing, and ambiguous rows without changing them" do
    suffix = System.unique_integer([:positive])

    set =
      Core.import_card_set!(%{
        tcgdex_id: "set-#{suffix}",
        name: "Set",
        source_payload: %{"id" => "set-#{suffix}", "name" => "Set"}
      })

    rows = [
      {"unsupported", "ordinary reason", %{}, false},
      {"malformed", "firstEdition variant", %{"set" => 42}, true},
      {"missing", "firstEdition variant", nil, true},
      {"unverified", "firstEdition variant", %{}, false},
      {"ambiguous", "firstEdition variant",
       %{
         "id" => "ambiguous",
         "name" => "Card",
         "localId" => "1",
         "set" => %{"id" => set.tcgdex_id},
         "pricing" => %{"cardmarket" => %{"idProduct" => 1}},
         "variants_detailed" => [
           %{"type" => "normal", "pricing" => %{"cardmarket" => %{"idProduct" => 1}}},
           %{"type" => "reverse", "pricing" => %{"cardmarket" => %{"idProduct" => 2}}},
           %{"type" => "stamped", "stamp" => "cosmos"}
         ]
       }, true},
      {"bad_card", "firstEdition variant",
       %{"id" => "not a/card", "set" => %{"id" => set.tcgdex_id}}, true},
      {"bad_set", "firstEdition variant",
       %{"id" => "valid-card", "set" => %{"id" => "not/a set"}}, true}
    ]

    Enum.each(rows, fn {id, reason, payload, qualifying?} ->
      attrs = %{
        tcgdex_id: "#{id}-#{suffix}",
        name: "Card",
        set_name: "Set",
        collector_number: id,
        card_set_id: set.id,
        source_payload: payload,
        mapping_status: "review",
        mapping_authority: "provider",
        mapping_review_reason: reason,
        mapping_updated_at: if(qualifying?, do: ~U[2025-01-01 00:00:00Z])
      }

      card =
        CardPrinting |> Ash.Changeset.for_create(:import, attrs) |> Ash.create!(authorize?: false)

      if qualifying?, do: record_history!(card, card.mapping_updated_at)
    end)

    malformed_context_set =
      Core.import_card_set!(
        %{
          tcgdex_id: "context-set-#{suffix}",
          name: "Context Set",
          source_payload: %{"id" => "malformed/set", "name" => "Context Set"}
        },
        authorize?: false
      )

    context_card =
      minimal_card_with_payload!(
        malformed_context_set,
        "malformed-context",
        %{"id" => "context-card-#{suffix}", "set" => %{"id" => malformed_context_set.tcgdex_id}},
        ~U[2025-01-01 00:00:00Z]
      )

    record_history!(context_card, context_card.mapping_updated_at)

    malformed_persisted_id =
      CardPrinting
      |> Ash.Changeset.for_create(:import, %{
        tcgdex_id: "not a/card-#{suffix}",
        name: "Malformed persisted ID",
        set_name: set.name,
        collector_number: "malformed-persisted-id",
        card_set_id: set.id,
        source_payload: %{
          "id" => "valid-persisted-payload-#{suffix}",
          "set" => %{"id" => set.tcgdex_id}
        },
        mapping_status: "review",
        mapping_authority: "provider",
        mapping_review_reason: "firstEdition variant",
        mapping_updated_at: ~U[2025-01-01 00:00:00Z]
      })
      |> Ash.create!(authorize?: false)

    record_history!(malformed_persisted_id, malformed_persisted_id.mapping_updated_at)

    missing_timestamp =
      minimal_card_with_payload!(
        set,
        "missing-timestamp",
        %{"id" => "missing-timestamp-#{suffix}", "set" => %{"id" => set.tcgdex_id}},
        nil
      )

    record_history!(missing_timestamp, nil)

    administrator_card =
      CardPrinting
      |> Ash.Changeset.for_create(:import, %{
        tcgdex_id: "administrator-#{suffix}",
        name: "Administrator-owned",
        set_name: "Set",
        collector_number: "admin",
        card_set_id: set.id,
        source_payload: %{"id" => "administrator-#{suffix}"},
        mapping_status: "matched",
        mapping_authority: "administrator",
        cardmarket_product_id: 7,
        mapping_review_reason: nil,
        mapping_updated_at: DateTime.utc_now()
      })
      |> Ash.create!(authorize?: false)

    assert {:ok, result} = LegacyCardmarketMappingRecovery.run()
    assert result.scanned == 10
    assert result.recovered == 0
    assert result.unchanged == 10
    assert result.categories.unsupported_reason == 1
    assert result.categories.unverified_history == 2
    assert result.categories.missing_payload == 1
    assert result.categories.malformed_payload == 5
    assert result.categories.still_ambiguous == 1

    preserved =
      Core.get_card_printing_by_tcgdex_id!(administrator_card.tcgdex_id, authorize?: false)

    assert {preserved.mapping_status, preserved.mapping_authority,
            preserved.cardmarket_product_id} ==
             {"matched", "administrator", 7}
  end

  test "accepts baseline and provider_updated decisions only for the current review" do
    suffix = System.unique_integer([:positive])
    set = minimal_set!(suffix)
    evidence_at = ~U[2025-01-01 00:00:00Z]

    baseline = minimal_card!(set, suffix, "baseline", 851_201, evidence_at)
    updated = minimal_card!(set, suffix, "updated", 851_202, evidence_at)

    record_history!(baseline, evidence_at, event: "baseline")
    record_history!(updated, evidence_at, event: "provider_updated", from_status: "review")

    assert {:ok, %{scanned: 2, recovered: 2, unchanged: 0}} =
             LegacyCardmarketMappingRecovery.run()

    for {card, product_id, event, provider_updated_count} <- [
          {baseline, 851_201, "baseline", 1},
          {updated, 851_202, "provider_updated", 2}
        ] do
      recovered = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id, authorize?: false)

      assert {recovered.mapping_status, recovered.mapping_authority,
              recovered.cardmarket_product_id} == {"matched", "provider", product_id}

      assert {:ok, history} =
               Core.list_card_printing_mapping_decision_history(card.id, authorize?: false)

      assert Enum.any?(history, &(&1.event == event))
      assert Enum.count(history, &(&1.event == "provider_updated")) == provider_updated_count
    end
  end

  test "fails closed for stale reason, source evidence, and printing version" do
    suffix = System.unique_integer([:positive])
    set = minimal_set!(suffix)
    evidence_at = ~U[2025-01-01 00:00:00Z]

    for {label, field} <- [{"reason", :reason}, {"source", :source}, {"version", :version}] do
      card = minimal_card!(set, suffix, label, 851_210 + :erlang.phash2(label, 10), evidence_at)

      opts =
        case field do
          :reason -> [reason: "other reason"]
          :source -> [source_mapping_evidence_at: DateTime.add(evidence_at, 1, :second)]
          :version -> [printing_version_at: DateTime.add(card.updated_at, 1, :second)]
        end

      record_history!(card, evidence_at, opts)
    end

    assert {:ok, result} = LegacyCardmarketMappingRecovery.run()
    assert result.recovered == 0
    assert result.categories.unverified_history == 3
  end

  test "scans 501 supported-reason rows with unverified history across a page boundary" do
    suffix = System.unique_integer([:positive])
    set = minimal_set!(suffix)
    now = DateTime.utc_now()

    rows =
      for index <- 1..501 do
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          tcgdex_id: "page-card-#{suffix}-#{index}",
          name: "Card",
          set_name: set.name,
          collector_number: "#{index}",
          card_set_id: Ecto.UUID.dump!(set.id),
          source_payload: %{},
          mapping_status: "review",
          mapping_authority: "provider",
          mapping_review_reason: "firstEdition variant",
          mapping_updated_at: now,
          last_synced_at: now,
          details_synced_at: now,
          updated_at: now
        }
      end

    assert {501, nil} = Repo.insert_all("card_printings", rows)
    assert {:ok, result} = LegacyCardmarketMappingRecovery.run(page_size: 500, max_scan: 501)

    assert {result.scanned, result.unchanged, result.categories.unverified_history} ==
             {501, 501, 501}
  end

  test "rejects over-cap recoverable rows before mutation" do
    suffix = System.unique_integer([:positive])
    set = minimal_set!(suffix)
    evidence_at = ~U[2025-01-01 00:00:00Z]
    first = minimal_card!(set, suffix, "cap-a", 851_301, evidence_at)
    second = minimal_card!(set, suffix, "cap-b", 851_302, evidence_at)
    record_history!(first, evidence_at)
    record_history!(second, evidence_at)
    before_first = Core.list_card_printing_mapping_decision_history!(first.id, authorize?: false)

    before_second =
      Core.list_card_printing_mapping_decision_history!(second.id, authorize?: false)

    assert {:error, {:persistence, {:scan_cap_exceeded, 1}}} =
             LegacyCardmarketMappingRecovery.run(max_scan: 1)

    unchanged = Core.get_card_printing_by_tcgdex_id!(first.tcgdex_id, authorize?: false)
    assert unchanged.mapping_status == "review"
    unchanged = Core.get_card_printing_by_tcgdex_id!(second.tcgdex_id, authorize?: false)
    assert unchanged.mapping_status == "review"

    assert Core.list_card_printing_mapping_decision_history!(first.id, authorize?: false) ==
             before_first

    assert Core.list_card_printing_mapping_decision_history!(second.id, authorize?: false) ==
             before_second

    refute Enum.any?(before_first, &(&1.event == "provider_updated"))
    refute Enum.any?(before_second, &(&1.event == "provider_updated"))
  end

  defp record_history!(card, evidence_at, opts \\ []) do
    assert {:ok, _} =
             Core.record_card_printing_mapping_decision(
               %{
                 card_printing_id: card.id,
                 event: Keyword.get(opts, :event, "imported"),
                 from_status: Keyword.get(opts, :from_status),
                 to_status: "review",
                 mapping_authority: "provider",
                 reason: Keyword.get(opts, :reason, card.mapping_review_reason),
                 source_mapping_evidence_at:
                   Keyword.get(opts, :source_mapping_evidence_at, evidence_at),
                 printing_version_at: Keyword.get(opts, :printing_version_at, card.updated_at),
                 actor_type: "system"
               },
               authorize?: false
             )
  end

  defp minimal_set!(suffix) do
    id = "minimal-set-#{suffix}"

    Core.import_card_set!(
      %{tcgdex_id: id, name: "Set", source_payload: %{"id" => id, "name" => "Set"}},
      authorize?: false
    )
  end

  defp minimal_card!(set, suffix, label, product_id, evidence_at) do
    id = "minimal-card-#{label}-#{suffix}"

    payload = %{
      "id" => id,
      "name" => "Card #{label}",
      "localId" => "1",
      "set" => %{"id" => set.tcgdex_id},
      "pricing" => %{
        "cardmarket" => %{"idProduct" => product_id, "updated" => "2025-01-01T00:00:00Z"}
      },
      "variants_detailed" => [
        %{"type" => "normal", "pricing" => %{"cardmarket" => %{"idProduct" => product_id}}}
      ]
    }

    minimal_card_with_payload!(set, label, payload, evidence_at)
  end

  defp minimal_card_with_payload!(set, label, payload, mapping_updated_at) do
    CardPrinting
    |> Ash.Changeset.for_create(:import, %{
      tcgdex_id: payload["id"],
      name: "Card #{label}",
      set_name: set.name,
      collector_number: "1",
      card_set_id: set.id,
      source_payload: payload,
      mapping_status: "review",
      mapping_authority: "provider",
      mapping_review_reason: "firstEdition variant",
      mapping_updated_at: mapping_updated_at,
      last_synced_at: mapping_updated_at,
      details_synced_at: mapping_updated_at
    })
    |> Ash.create!(authorize?: false)
  end
end
