defmodule TcgCheap.Catalogue.CardmarketExpansionReviewTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.{CardSet, CardSetCardmarketMappingDecision}
  alias TcgCheap.Core
  alias TcgCheap.Pricing.CardmarketBulk.{Batch, MappingReplayWorker}

  test "approval records canonical state, immutable history, and a decision-specific replay" do
    admin = admin()
    set = card_set("approval")
    batch = batch(:succeeded)
    first = mapping(batch, set, 101)

    assert {:ok, approved} =
             Core.approve_cardmarket_expansion(
               set,
               %{
                 source_mapping_id: first.id,
                 reason: "Confirmed by expansion evidence",
                 expected_updated_at: set.updated_at
               },
               actor: admin
             )

    assert {approved.cardmarket_expansion_id, approved.cardmarket_mapping_status,
            approved.cardmarket_mapping_authority, approved.cardmarket_mapping_reason} ==
             {101, "matched", "administrator", "Confirmed by expansion evidence"}

    assert approved.cardmarket_mapping_evidence_at == batch.completed_at

    [decision] = decisions()

    assert {decision.event, decision.card_set_id, decision.source_mapping_id,
            decision.source_batch_id, decision.actor_id, to_string(decision.actor_email),
            decision.to_expansion_id, decision.card_set_version_at} ==
             {"approved", set.id, first.id, batch.id, admin.id, to_string(admin.email), 101,
              approved.updated_at}

    assert [%{args: %{"batch_id" => batch_id, "decision_id" => decision_id}}] =
             all_enqueued(repo: TcgCheap.Repo, worker: MappingReplayWorker)

    assert {batch_id, decision_id} == {batch.id, decision.id}
  end

  test "correction appends history, while the original version is stale" do
    admin = admin()
    set = card_set("correction")
    batch = batch(:succeeded)
    first = mapping(batch, set, 201)
    second = mapping(batch, set, 202)

    assert {:ok, approved} = approve(set, first, admin, "Initial decision")
    assert {:ok, corrected} = approve(approved, second, admin, "Corrected decision")

    assert {:error, _} =
             Core.approve_cardmarket_expansion(
               corrected,
               %{
                 source_mapping_id: first.id,
                 reason: "Stale correction",
                 expected_updated_at: approved.updated_at
               },
               actor: admin
             )

    assert {:ok, unchanged} = Ash.get(CardSet, set.id, authorize?: false, action: :read)

    assert {unchanged.cardmarket_expansion_id, unchanged.cardmarket_mapping_reason} ==
             {202, "Corrected decision"}

    assert Enum.map(decisions(), & &1.to_expansion_id) == [201, 202]
    assert Enum.map(decisions(), & &1.event) == ["approved", "corrected"]
    assert length(all_enqueued(repo: TcgCheap.Repo, worker: MappingReplayWorker)) == 2

    assert Enum.uniq(
             Enum.map(
               all_enqueued(repo: TcgCheap.Repo, worker: MappingReplayWorker),
               & &1.args["decision_id"]
             )
           )
           |> length() == 2
  end

  test "nil and non-admin actors are forbidden, and direct history writes remain forbidden" do
    admin = admin()
    set = card_set("authorization")
    source = mapping(batch(:succeeded), set, 301)
    before = length(decisions())

    for actor <- [nil, %{id: Ecto.UUID.generate()}] do
      assert {:error, _} =
               Core.approve_cardmarket_expansion(
                 set,
                 %{
                   source_mapping_id: source.id,
                   reason: "Should fail",
                   expected_updated_at: set.updated_at
                 },
                 actor: actor
               )
    end

    assert {:error, _} =
             Core.record_card_set_cardmarket_mapping_decision(
               valid_decision_attrs(set, source, admin),
               actor: admin
             )

    assert length(decisions()) == before
  end

  test "invalid sources and duplicate administrator expansions have no side effects" do
    admin = admin()
    set = card_set("sources")
    wrong_set = card_set("wrong-set")
    succeeded = batch(:succeeded)
    staged = batch(:staged)
    failed = batch(:failed)
    wrong = mapping(succeeded, wrong_set, 401)
    approved_source = mapping(succeeded, set, 402, status: "approved")
    staged_source = mapping(staged, set, 403)
    failed_source = mapping(failed, set, 404)

    for source <- [wrong, approved_source, staged_source, failed_source] do
      assert {:error, _} = approve(set, source, admin, "Rejected source")
    end

    first = mapping(succeeded, set, 405)
    other_set = card_set("duplicate")
    assert {:ok, _} = approve(set, first, admin, "Unique expansion")
    duplicate = mapping(succeeded, other_set, 405)
    assert {:error, _} = approve(other_set, duplicate, admin, "Duplicate expansion")

    assert {:ok, unchanged} = Ash.get(CardSet, other_set.id, authorize?: false, action: :read)
    assert unchanged.cardmarket_expansion_id == nil
    assert length(decisions()) == 1
    assert all_enqueued(repo: TcgCheap.Repo, worker: MappingReplayWorker) |> length() == 1
  end

  test "canonical import upsert preserves administrator mapping fields" do
    admin = admin()
    set = card_set("upsert")
    source_batch = batch(:succeeded)
    source = mapping(source_batch, set, 501)
    {:ok, approved} = approve(set, source, admin, "Keep this canonical decision")

    imported =
      Core.import_card_set!(
        %{
          tcgdex_id: approved.tcgdex_id,
          name: "Updated canonical name",
          series_id: approved.series_id,
          series_name: "Updated series"
        },
        authorize?: false
      )

    assert {imported.cardmarket_expansion_id, imported.cardmarket_mapping_status,
            imported.cardmarket_mapping_authority, imported.cardmarket_mapping_evidence_at,
            imported.cardmarket_mapping_reason} ==
             {501, "matched", "administrator", approved.cardmarket_mapping_evidence_at,
              "Keep this canonical decision"}
  end

  test "replay accepts a succeeded decision path and discards non-succeeded batches" do
    admin = admin()
    set = card_set("replay")
    succeeded = batch(:succeeded)
    source = mapping(succeeded, set, 601)

    {:ok, decision} =
      Core.record_card_set_cardmarket_mapping_decision(valid_decision_attrs(set, source, admin),
        authorize?: false
      )

    assert :ok =
             MappingReplayWorker.perform(%Oban.Job{
               args: %{"batch_id" => succeeded.id, "decision_id" => decision.id}
             })

    staged = batch(:staged)
    staged_source = mapping(staged, set, 602)

    {:ok, staged_decision} =
      Core.record_card_set_cardmarket_mapping_decision(
        valid_decision_attrs(set, staged_source, admin),
        authorize?: false
      )

    assert {:discard, :batch_not_succeeded} =
             MappingReplayWorker.perform(%Oban.Job{
               args: %{"batch_id" => staged.id, "decision_id" => staged_decision.id}
             })
  end

  defp approve(set, source, admin, reason) do
    Core.approve_cardmarket_expansion(
      set,
      %{source_mapping_id: source.id, reason: reason, expected_updated_at: set.updated_at},
      actor: admin
    )
  end

  defp valid_decision_attrs(set, source, admin) do
    %{
      card_set_id: set.id,
      source_mapping_id: source.id,
      source_batch_id: source.source_batch_id,
      event: "approved",
      to_expansion_id: source.expansion_id,
      reason: "Recorded evidence",
      card_set_version_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      actor_id: admin.id,
      actor_email: to_string(admin.email)
    }
  end

  defp decisions do
    {:ok, rows} =
      Ash.read(Ash.Query.for_read(CardSetCardmarketMappingDecision, :read, %{}),
        authorize?: false
      )

    Enum.sort_by(rows, & &1.inserted_at)
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "expansion-admin-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp card_set(label) do
    Core.import_card_set!(
      %{
        tcgdex_id: "review-#{label}-#{System.unique_integer([:positive])}",
        name: "Review #{label}",
        series_id: "series",
        series_name: "Series"
      },
      authorize?: false
    )
  end

  defp batch(kind) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs = %{
      policy_version: "cardmarket_bulk_v1",
      parser_version: "review-test",
      product_created_at: now,
      price_created_at: now,
      fetched_at: now,
      completed_at: now,
      product_sha256: hash(),
      price_sha256: hash(),
      product_byte_size: 1,
      price_byte_size: 1,
      product_row_count: 1,
      price_row_count: 1,
      singles_price_row_count: 1,
      priceable_singles_count: 1
    }

    case kind do
      :succeeded ->
        Core.complete_cardmarket_bulk_batch!(attrs, authorize?: false)

      :staged ->
        Ash.create!(Ash.Changeset.for_create(Batch, :stage, Map.delete(attrs, :completed_at)),
          authorize?: false
        )

      :failed ->
        staged =
          Ash.create!(Ash.Changeset.for_create(Batch, :stage, Map.delete(attrs, :completed_at)),
            authorize?: false
          )

        Ash.update!(
          Ash.Changeset.for_update(staged, :fail, %{
            completed_at: now,
            failure_summary: "fixture failure"
          }),
          authorize?: false
        )
    end
  end

  defp mapping(batch, set, expansion, opts \\ []) do
    Core.record_cardmarket_expansion_mapping!(
      %{
        source_batch_id: batch.id,
        card_set_id: set.id,
        expansion_id: expansion,
        status: Keyword.get(opts, :status, "review"),
        authority: "system",
        anchor_count: 1,
        evidence: %{fixture: true},
        review_reason:
          if(Keyword.get(opts, :status, "review") == "review", do: "Needs administrator review")
      },
      authorize?: false
    )
  end

  defp hash, do: :crypto.hash(:sha256, Ecto.UUID.generate()) |> Base.encode16(case: :lower)
end
