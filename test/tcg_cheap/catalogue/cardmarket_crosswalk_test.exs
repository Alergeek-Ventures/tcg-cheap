defmodule TcgCheap.Catalogue.CardmarketCrosswalkTest do
  use TcgCheap.DataCase, async: true

  alias Ash.Resource.Info

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.CardmarketCardMappingEvidence
  alias TcgCheap.Catalogue.CardmarketCrosswalk
  alias TcgCheap.Catalogue.CardmarketExpansionMapping
  alias TcgCheap.Core

  @product_namespace System.unique_integer([:positive]) * 1_000

  test "normalised unique names match and record anchor/evidence/history" do
    batch = batch()
    set = set()
    anchor = card(set, "Anchor", mapping_status: "matched", product_id: 101)
    pending = card(set, "  pIkAcHu  ")
    product(batch, 7, "anchor", 101)
    product(batch, 7, "Pikachu", 102)

    assert {:ok, summary} = CardmarketCrosswalk.run(batch)
    assert summary.auto_matched == 1
    assert summary.preserved == 1
    assert summary.approved_expansions == 1

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert Enum.map(evidence, & &1.decision) |> Enum.sort() == ["anchor", "auto_matched"]
    assert Enum.find(evidence, &(&1.card_printing_id == pending.id)).authority == "system"

    assert {:ok, history} =
             Core.list_card_printing_mapping_decision_history(pending.id, authorize?: false)

    assert Enum.count(history, &(&1.event == "provider_updated")) == 1
    assert anchor.cardmarket_product_id == remapped_product_id(101)
  end

  test "brief cards with candidates are reviewed instead of name matched" do
    batch = batch()
    set = set()
    card(set, "Anchor", mapping_status: "matched", product_id: 101)
    brief = card(set, "Pikachu", details_synced_at: nil)
    product(batch, 7, "anchor", 101)
    product(batch, 7, "pikachu", 102)

    assert {:ok, summary} = CardmarketCrosswalk.run(batch)
    assert summary.auto_matched == 0
    assert summary.review == 1

    assert {:ok, refreshed} =
             Core.get_card_printing_by_tcgdex_id(brief.tcgdex_id, authorize?: false)

    assert refreshed.mapping_status == "review"

    assert refreshed.mapping_review_reason ==
             "cardmarket_bulk_v1:material variant evidence incomplete"
  end

  test "non-bijective expansion pairs are review" do
    batch = batch()
    set_a = set()
    set_b = set()
    card(set_a, "A", mapping_status: "matched", product_id: 201)
    card(set_a, "B", mapping_status: "matched", product_id: 202)
    card(set_b, "C", mapping_status: "matched", product_id: 203)
    product(batch, 1, "A", 201)
    product(batch, 2, "B", 202)
    product(batch, 1, "C", 203)

    assert {:ok, summary} = CardmarketCrosswalk.run(batch)
    assert summary.approved_expansions == 0
    assert summary.review_expansions == 3

    assert {:ok, mappings} =
             Core.list_cardmarket_expansion_mappings_for_batch(batch.id, authorize?: false)

    assert Enum.count(mappings, &(&1.status == "review")) == 3
  end

  test "administrator expansion approval applies only to the exact staged pair" do
    batch = batch()
    set = set()
    printing = card(set, "Exact", mapping_status: "matched", product_id: 601)
    card(set, "Second", mapping_status: "matched", product_id: 602)
    product(batch, 8, "exact", 601)
    product(batch, 8, "second", 602)
    product(batch, 9, "exact", 602)

    Repo.query!(
      "UPDATE card_sets SET cardmarket_expansion_id = $1, cardmarket_mapping_status = 'matched', cardmarket_mapping_authority = 'administrator', cardmarket_mapping_evidence_at = $2, cardmarket_mapping_reason = $3 WHERE id = $4",
      [8, DateTime.utc_now(), "Administrator exact-pair approval", Ecto.UUID.dump!(set.id)]
    )

    assert {:ok, summary} = CardmarketCrosswalk.run(batch)
    assert summary.approved_expansions == 1

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert {:ok, mappings} =
             Core.list_cardmarket_expansion_mappings_for_batch(batch.id, authorize?: false)

    exact_id = Enum.find(mappings, &(&1.expansion_id == 8)).id
    other_id = Enum.find(mappings, &(&1.expansion_id == 9)).id

    assert Enum.any?(
             evidence,
             &(&1.card_printing_id == printing.id and &1.expansion_mapping_id == exact_id)
           )

    refute Enum.any?(
             evidence,
             &(&1.card_printing_id == printing.id and &1.expansion_mapping_id == other_id)
           )
  end

  test "duplicate names, variants, markers and reused products are review" do
    batch = batch()
    set = set()
    duplicate_a = card(set, "Mew")
    duplicate_b = card(set, " mew ")
    variant = card(set, "Eevee", variant_data: %{"firstEdition" => true})
    marker = card(set, "Snorlax 1st Edition")
    reused = card(set, "Bulbasaur")
    staged_duplicate = card(set, "Pidgey")
    anchor = card(set, "Anchor", mapping_status: "matched", product_id: 301)

    for {name, id} <- [
          {"mew", 302},
          {"eevee", 303},
          {"snorlax 1st edition", 304},
          {"bulbasaur", 305}
        ] do
      product(batch, 3, name, id)
    end

    product(batch, 3, "mew", 306)
    product(batch, 3, "pidgey", 307)
    product(batch, 3, "pidgey", 308)

    product(batch, 3, "anchor", 301)
    other = card(set, "Other", mapping_status: "matched", product_id: 305)
    assert {:ok, _summary} = CardmarketCrosswalk.run(batch)
    assert duplicate_a.id != duplicate_b.id and other.id != anchor.id

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    reasons = evidence |> Enum.map(& &1.review_reason) |> Enum.reject(&is_nil/1)
    assert Enum.any?(reasons, &String.contains?(&1, "duplicate canonical name"))

    assert Enum.any?(reasons, &String.contains?(&1, "material variant conflict"))
    assert Enum.any?(reasons, &String.contains?(&1, "obvious Cardmarket marker"))
    assert Enum.any?(reasons, &String.contains?(&1, "product already mapped globally"))
    assert reused.id != anchor.id

    for printing <- [duplicate_a, duplicate_b, variant, marker, reused] do
      assert {:ok, refreshed} =
               Core.get_card_printing_by_tcgdex_id(printing.tcgdex_id, authorize?: false)

      assert refreshed.mapping_status == "review"
    end

    assert Enum.any?(
             evidence,
             &(&1.review_reason == "cardmarket_bulk_v1:duplicate staged product name")
           )

    assert {:ok, refreshed} =
             Core.get_card_printing_by_tcgdex_id(staged_duplicate.tcgdex_id, authorize?: false)

    assert refreshed.mapping_status == "review"
  end

  test "missing candidates are unmatched and owned mappings are preserved" do
    batch = batch()
    set = set()
    missing = card(set, "Missing")

    admin =
      card(set, "Admin", mapping_status: "review", reason: "manual", authority: "administrator")

    unrelated =
      card(set, "Provider", mapping_status: "review", reason: "manual", authority: "provider")

    card(set, "Anchor", mapping_status: "matched", product_id: 401)
    product(batch, 4, "anchor", 401)
    assert {:ok, _} = CardmarketCrosswalk.run(batch)

    assert {:ok, refreshed} =
             Core.get_card_printing_by_tcgdex_id(missing.tcgdex_id, authorize?: false)

    assert refreshed.mapping_status == "pending"

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert Enum.any?(
             evidence,
             &(&1.card_printing_id == missing.id and &1.decision == "unmatched")
           )

    assert {:ok, preserved} =
             Core.get_card_printing_by_tcgdex_id(admin.tcgdex_id, authorize?: false)

    assert {preserved.mapping_status, preserved.mapping_authority,
            preserved.mapping_review_reason} ==
             {"review", "administrator", "manual"}

    assert {:ok, provider} =
             Core.get_card_printing_by_tcgdex_id(unrelated.tcgdex_id, authorize?: false)

    assert {provider.mapping_status, provider.mapping_authority, provider.mapping_review_reason} ==
             {"review", "provider", "manual"}
  end

  test "reruns are idempotent and immutable resources are protected" do
    batch = batch()
    set = set()
    card(set, "Anchor", mapping_status: "matched", product_id: 501)
    unique_card = card(set, "Unique")
    product(batch, 5, "anchor", 501)
    product(batch, 5, "unique", 502)
    assert {:ok, first} = CardmarketCrosswalk.run(batch)

    assert {:ok, before} =
             Core.get_card_printing_by_tcgdex_id(unique_card.tcgdex_id, authorize?: false)

    assert {:ok, second} = CardmarketCrosswalk.run(batch)
    assert second.already_processed == 2
    assert first.auto_matched == 1

    assert {:ok, after_rerun} =
             Core.get_card_printing_by_tcgdex_id(unique_card.tcgdex_id, authorize?: false)

    assert after_rerun.updated_at == before.updated_at
    assert after_rerun.mapping_updated_at == before.mapping_updated_at

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert length(evidence) == 2

    assert Enum.all?([CardmarketCardMappingEvidence, CardmarketExpansionMapping], fn resource ->
             actions = Info.actions(resource) |> Enum.map(& &1.type)
             :update not in actions and :destroy not in actions
           end)

    assert {:error, _} = Core.record_cardmarket_card_mapping_evidence(%{}, authorize?: true)
  end

  test "administrator-owned cards survive replay with superseded auto-match evidence" do
    admin =
      Accounts.register_admin!(
        %{
          email: "crosswalk-replay-admin-#{System.unique_integer([:positive])}@example.test",
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        },
        authorize?: false
      )

    batch = batch()
    set = set()
    anchor_a = card(set, "Anchor A", mapping_status: "matched", product_id: 801)
    anchor_b = card(set, "Anchor B", mapping_status: "matched", product_id: 802)
    administrator_card = card(set, "Administrator", details_synced_at: DateTime.utc_now())

    product(batch, 21, "anchor a", 801)
    product(batch, 21, "administrator", 803)
    product(batch, 22, "anchor b", 802)
    product(batch, 22, "administrator", 804)

    assert {:ok, _first} = CardmarketCrosswalk.run(batch)

    assert {:ok, mappings} =
             Core.list_cardmarket_expansion_mappings_for_batch(batch.id, authorize?: false)

    mapping_a = Enum.find(mappings, &(&1.expansion_id == 21))
    mapping_b = Enum.find(mappings, &(&1.expansion_id == 22))
    assert {:ok, approved_a} = approve_set(set, mapping_a, admin, "Approve A")
    assert {:ok, _replay_a} = CardmarketCrosswalk.run(batch)

    Repo.query!(
      "UPDATE card_printings SET mapping_authority = 'administrator' WHERE id = $1",
      [Ecto.UUID.dump!(administrator_card.id)]
    )

    assert {:ok, approved_b} = approve_set(approved_a, mapping_b, admin, "Correct to B")
    assert approved_b.cardmarket_expansion_id == 22
    assert {:ok, summary} = CardmarketCrosswalk.run(batch)
    assert summary.preserved == 3

    assert {:ok, unchanged} =
             Core.get_card_printing_by_tcgdex_id(administrator_card.tcgdex_id, authorize?: false)

    assert {unchanged.mapping_status, unchanged.mapping_authority,
            unchanged.cardmarket_product_id} ==
             {"matched", "administrator", remapped_product_id(803)}

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert Enum.any?(evidence, fn row ->
             row.card_printing_id == administrator_card.id and
               row.expansion_mapping_id == mapping_a.id and row.decision == "auto_matched"
           end)

    assert Enum.any?(evidence, fn row ->
             row.card_printing_id == administrator_card.id and
               row.expansion_mapping_id == mapping_b.id and row.decision == "review" and
               row.authority == "administrator" and get_in(row.evidence, ["preserved"]) == true
           end)

    assert {:ok, refreshed_anchor_a} =
             Core.get_card_printing_by_tcgdex_id(anchor_a.tcgdex_id, authorize?: false)

    assert refreshed_anchor_a.cardmarket_product_id == remapped_product_id(801)

    assert {:ok, refreshed_anchor_b} =
             Core.get_card_printing_by_tcgdex_id(anchor_b.tcgdex_id, authorize?: false)

    assert refreshed_anchor_b.cardmarket_product_id == remapped_product_id(802)
  end

  test "corrected expansion replays safely with immutable evidence and archived valuation" do
    admin =
      Accounts.register_admin!(
        %{
          email: "crosswalk-admin-#{System.unique_integer([:positive])}@example.test",
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        },
        authorize?: false
      )

    batch = batch()
    set = set()
    anchor_a = card(set, "Anchor A", mapping_status: "matched", product_id: 701)
    anchor_b = card(set, "Anchor B", mapping_status: "matched", product_id: 702)
    target = card(set, "Target", details_synced_at: DateTime.utc_now())

    admin_card =
      card(set, "Admin", mapping_status: "matched", product_id: 703, authority: "administrator")

    product(batch, 11, "anchor a", 701)
    product(batch, 11, "target", 704)
    product(batch, 12, "anchor b", 702)
    product(batch, 12, "target", 705)
    product(batch, 12, "admin", 703)

    assert {:ok, first} = CardmarketCrosswalk.run(batch)
    assert first.review_expansions == 2

    assert {:ok, mappings} =
             Core.list_cardmarket_expansion_mappings_for_batch(batch.id, authorize?: false)

    mapping_a = Enum.find(mappings, &(&1.expansion_id == 11))
    mapping_b = Enum.find(mappings, &(&1.expansion_id == 12))

    assert {:ok, approved_a} = approve_set(set, mapping_a, admin, "Approve A")
    assert {:ok, first_replay} = CardmarketCrosswalk.run(batch)
    assert first_replay.auto_matched == 1

    assert {:ok, matched_a} =
             Core.get_card_printing_by_tcgdex_id(target.tcgdex_id, authorize?: false)

    assert matched_a.cardmarket_product_id == remapped_product_id(704)

    valuation =
      Core.record_single_valuation!(%{
        card_printing_id: target.id,
        value_eur: Decimal.new("12.00"),
        currency: "EUR",
        policy_version: "cardmarket_bulk_v1",
        source: "cardmarket_bulk",
        source_metric: "avg7",
        fetched_at: batch.fetched_at,
        provider_updated_at: batch.price_created_at,
        cardmarket_product_id: matched_a.cardmarket_product_id
      })

    assert {:ok, approved_b} = approve_set(approved_a, mapping_b, admin, "Correct to B")
    assert approved_b.cardmarket_expansion_id == 12
    assert {:ok, corrected} = CardmarketCrosswalk.run(batch)
    assert corrected.auto_matched == 1

    assert {:ok, matched_b} =
             Core.get_card_printing_by_tcgdex_id(target.tcgdex_id, authorize?: false)

    assert matched_b.cardmarket_product_id == remapped_product_id(705)
    assert {:ok, nil} = Core.get_current_single_valuation(target.id, "cardmarket_bulk_v1")
    assert [archived] = Core.list_single_valuation_history!(target.id, "cardmarket_bulk_v1")
    assert archived.id == valuation.id and not archived.current?

    assert {:ok, evidence} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    target_evidence = Enum.filter(evidence, &(&1.card_printing_id == target.id))

    assert Enum.any?(
             target_evidence,
             &(&1.expansion_mapping_id == mapping_a.id and &1.decision == "auto_matched")
           )

    assert Enum.any?(
             target_evidence,
             &(&1.expansion_mapping_id == mapping_b.id and &1.decision == "auto_matched")
           )

    assert {:ok, unchanged_anchor_a} =
             Core.get_card_printing_by_tcgdex_id(anchor_a.tcgdex_id, authorize?: false)

    assert unchanged_anchor_a.cardmarket_product_id == remapped_product_id(701)

    assert {:ok, unchanged_anchor_b} =
             Core.get_card_printing_by_tcgdex_id(anchor_b.tcgdex_id, authorize?: false)

    assert unchanged_anchor_b.cardmarket_product_id == remapped_product_id(702)

    assert {:ok, unchanged_admin} =
             Core.get_card_printing_by_tcgdex_id(admin_card.tcgdex_id, authorize?: false)

    assert {unchanged_admin.mapping_authority, unchanged_admin.cardmarket_product_id} ==
             {"administrator", remapped_product_id(703)}

    evidence_count = length(evidence)

    history_count =
      length(Core.list_card_printing_mapping_decision_history!(target.id, authorize?: false))

    updated_at = matched_b.updated_at
    mapping_updated_at = matched_b.mapping_updated_at
    assert {:ok, third} = CardmarketCrosswalk.run(batch)
    assert third.already_processed == 4

    assert {:ok, after_third} =
             Core.get_card_printing_by_tcgdex_id(target.tcgdex_id, authorize?: false)

    assert {after_third.updated_at, after_third.mapping_updated_at} ==
             {updated_at, mapping_updated_at}

    assert {:ok, evidence_after} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert length(evidence_after) == evidence_count

    assert length(Core.list_card_printing_mapping_decision_history!(target.id, authorize?: false)) ==
             history_count

    Repo.query!(
      "UPDATE card_sets SET cardmarket_expansion_id = $1, cardmarket_mapping_status = 'matched', cardmarket_mapping_authority = 'administrator' WHERE id = $2",
      [11, Ecto.UUID.dump!(set.id)]
    )

    assert {:ok, reverted} = CardmarketCrosswalk.run(batch)
    assert reverted.auto_matched == 1

    assert {:ok, matched_a_again} =
             Core.get_card_printing_by_tcgdex_id(target.tcgdex_id, authorize?: false)

    assert matched_a_again.cardmarket_product_id == remapped_product_id(704)

    assert {:ok, evidence_after_revert} =
             Core.list_cardmarket_card_mapping_evidence_for_batch(batch.id, authorize?: false)

    assert length(evidence_after_revert) == evidence_count

    evidence_a = Enum.find(target_evidence, &(&1.expansion_mapping_id == mapping_a.id))

    assert {:error, _} =
             Core.cardmarket_bulk_review_card_printing(
               unchanged_anchor_b,
               %{
                 expected_updated_at: unchanged_anchor_b.updated_at,
                 evidence_timestamp: batch.fetched_at,
                 reason: "wrong card",
                 superseded_evidence_id: evidence_a.id
               },
               authorize?: false
             )
  end

  defp approve_set(set, mapping, admin, reason),
    do:
      Core.approve_cardmarket_expansion(
        set,
        %{source_mapping_id: mapping.id, reason: reason, expected_updated_at: set.updated_at},
        actor: admin
      )

  defp batch do
    now =
      DateTime.utc_now()
      |> DateTime.truncate(:microsecond)
      |> DateTime.add(System.unique_integer([:positive]), :microsecond)

    suffix = unique("batch")

    attrs = %{
      policy_version: "tcgdex_cardmarket_v1",
      parser_version: "test",
      product_created_at: now,
      price_created_at: now,
      fetched_at: now,
      completed_at: now,
      product_sha256: :crypto.hash(:sha256, "products-#{suffix}") |> Base.encode16(case: :lower),
      price_sha256: :crypto.hash(:sha256, "prices-#{suffix}") |> Base.encode16(case: :lower),
      product_byte_size: 1,
      price_byte_size: 1,
      product_row_count: 1,
      price_row_count: 1,
      singles_price_row_count: 1,
      priceable_singles_count: 1
    }

    Core.complete_cardmarket_bulk_batch!(attrs, authorize?: false)
  end

  defp set do
    id = unique("set")

    Core.import_card_set!(%{tcgdex_id: id, name: id, series_id: "series", series_name: "Series"},
      authorize?: false
    )
  end

  defp card(set, name, opts \\ []) do
    TcgCheap.TestSupport.import_card_printing!(
      %{
        tcgdex_id: unique("card"),
        name: name,
        set_name: set.name,
        collector_number: unique("n"),
        card_set_id: set.id,
        mapping_status: Keyword.get(opts, :mapping_status, "pending"),
        mapping_authority: Keyword.get(opts, :authority, "provider"),
        mapping_review_reason: Keyword.get(opts, :reason),
        cardmarket_product_id: remapped_product_id(Keyword.get(opts, :product_id)),
        variant_data: Keyword.get(opts, :variant_data, %{}),
        details_synced_at: Keyword.get(opts, :details_synced_at, DateTime.utc_now())
      },
      scoped?: false
    )
  end

  defp product(batch, expansion, name, id) do
    Core.upsert_cardmarket_bulk_product!(
      %{
        cardmarket_product_id: remapped_product_id(id),
        name: name,
        category_id: 51,
        category_name: "Pokémon Single",
        expansion_id: expansion,
        metacard_id: remapped_product_id(id),
        source_date_added: "2026-09-01",
        last_batch_id: batch.id,
        source_updated_at: DateTime.utc_now()
      },
      authorize?: false
    )
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp remapped_product_id(nil), do: nil
  defp remapped_product_id(id), do: @product_namespace + id
end
