defmodule TcgCheap.Catalogue.ListingProductMappingDecisionTest do
  use TcgCheap.DataCase, async: true

  alias Ash.Resource.Info
  alias TcgCheap.Catalogue.ListingProductMappingDecision
  alias TcgCheap.Core

  test "explicit mapping creation records one immutable system decision" do
    listing = listing_fixture()
    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing.id})

    assert {:ok, [decision]} =
             Core.list_listing_mapping_decision_history(mapping.id, authorize?: false)

    assert decision.event == "created"
    assert decision.from_status == nil
    assert decision.to_status == "pending"
    assert decision.mapping_id == mapping.id
    assert decision.mapping_updated_at == mapping.updated_at
    assert decision.actor_type == "system"
    assert decision.actor_id == nil
    assert decision.actor_email == nil
    assert {:error, _} = Core.list_listing_mapping_decision_history(mapping.id)
  end

  test "decision history has no update or destroy actions" do
    types =
      ListingProductMappingDecision
      |> Info.actions()
      |> Enum.map(& &1.type)

    refute :update in types
    refute :destroy in types
  end

  test "direct decision recording is denied without the parent change" do
    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing_fixture().id})

    assert {:error, _} =
             Core.record_listing_mapping_decision(%{
               mapping_id: mapping.id,
               event: "baseline",
               to_status: "pending",
               actor_type: "system",
               mapping_updated_at: mapping.updated_at
             })
  end

  test "anonymous catalogue and history reads are forbidden but admins can read" do
    listing = listing_fixture()
    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing.id})
    admin = admin_fixture()

    assert {:error, _} = Ash.read(TcgCheap.Catalogue.ListingProductMapping, domain: Core)
    assert {:error, _} = Core.list_admin_listing_mappings()
    assert {:error, _} = Ash.read(ListingProductMappingDecision, domain: Core)
    assert {:error, _} = Core.list_admin_listing_mapping_decisions()

    assert {:ok, _} =
             Ash.read(TcgCheap.Catalogue.ListingProductMapping, domain: Core, actor: admin)

    assert {:ok, _} = Core.list_admin_listing_mappings(actor: admin)
    assert {:ok, _} = Ash.read(ListingProductMappingDecision, domain: Core, actor: admin)
    assert {:ok, _} = Core.list_admin_listing_mapping_decisions(actor: admin)
    assert {:ok, _} = Core.list_listing_mapping_decision_history(mapping.id, actor: admin)
  end

  test "review and matched creations record safe snapshots" do
    listing = listing_fixture()
    candidate = draft_product()
    confirmed = approved_product()
    evidence = %{method: "manual_review", gtin: "4006381333931"}

    review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: listing.id,
        candidate_product_id: candidate.id,
        confidence: Decimal.new("0.75"),
        evidence: evidence,
        reason: "Needs review"
      })

    assert {:ok, [review_decision]} = history(review.id)
    assert {review_decision.event, review_decision.to_status} == {"created", "review"}

    assert {review_decision.evidence_method, review_decision.evidence_gtin} ==
             {"manual_review", "4006381333931"}

    matched =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing_fixture().id,
        confirmed_product_id: confirmed.id,
        confidence: Decimal.new("0.99"),
        evidence: evidence
      })

    assert {:ok, [matched_decision]} = history(matched.id)
    assert matched_decision.event == "created"
    assert matched_decision.to_status == "matched"
    assert matched_decision.confirmed_product_id == confirmed.id
    assert matched_decision.candidate_product_id == nil
    assert matched_decision.reason == nil
    assert matched_decision.evidence_method == "manual_review"
  end

  test "an imported mapping gets one initial snapshot across repeated imports" do
    listing = listing_fixture()
    candidate = draft_product()

    mapping =
      Core.import_listing_mapping!(%{
        retailer_listing_id: listing.id,
        candidate_product_id: candidate.id,
        confidence: Decimal.new("0.6"),
        evidence: %{method: "matcher"},
        reason: "Initial proposal"
      })

    assert {:ok, [%{event: "created", from_status: nil, to_status: "review"}]} =
             history(mapping.id)

    refreshed =
      Core.import_listing_mapping!(%{
        retailer_listing_id: listing.id,
        candidate_product_id: candidate.id,
        confidence: Decimal.new("0.7"),
        evidence: %{method: "matcher_refresh"},
        reason: "Updated proposal"
      })

    assert refreshed.id == mapping.id
    assert refreshed.reason == "Updated proposal"
    assert {:ok, [%{event: "created"}]} = history(mapping.id)
  end

  test "matched decisions retain a safe fallback when evidence has no method" do
    matched =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing_fixture().id,
        confirmed_product_id: approved_product().id,
        confidence: Decimal.new("1"),
        evidence: %{source: "legacy_matcher"}
      })

    assert {:ok, [%{evidence_method: "unspecified", evidence_gtin: nil}]} = history(matched.id)
  end

  test "approve and reject record one transition with administrator attribution" do
    admin = admin_fixture()
    review = Core.create_review_listing_mapping!(review_attrs())

    approved =
      Core.approve_listing_mapping!(
        review,
        %{
          confirmed_product_id: approved_product().id,
          confidence: Decimal.new("0.8"),
          evidence: %{method: "admin_review"},
          expected_updated_at: review.updated_at
        },
        actor: admin
      )

    assert approved.status == "matched"
    assert {:ok, decisions} = history(review.id)
    assert Enum.count(decisions, &(&1.event == "approved")) == 1
    approved_decision = List.last(decisions)
    assert {approved_decision.from_status, approved_decision.to_status} == {"review", "matched"}

    assert {approved_decision.actor_type, approved_decision.actor_id,
            to_string(approved_decision.actor_email)} ==
             {"administrator", admin.id, to_string(admin.email)}

    rejected = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing_fixture().id})

    assert {:ok, rejected} =
             Core.reject_listing_mapping(
               rejected,
               %{reason: "No match", expected_updated_at: rejected.updated_at},
               actor: admin
             )

    assert {:ok, decisions} = history(rejected.id)

    assert [
             %{event: "created"},
             %{
               event: "rejected",
               from_status: "pending",
               to_status: "rejected",
               reason: "No match"
             }
           ] = decisions
  end

  test "reopen preserves matched evidence and has rejected reset semantics" do
    admin = admin_fixture()
    product = approved_product()
    evidence = %{method: "exact_approved_gtin", gtin: "4006381333931"}

    matched =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing_fixture().id,
        confirmed_product_id: product.id,
        confidence: Decimal.new("0.91"),
        evidence: evidence
      })

    reopened =
      Core.reopen_listing_mapping!(
        matched,
        %{expected_updated_at: matched.updated_at, reason: "Correct product"},
        actor: admin
      )

    assert {reopened.status, reopened.candidate_product_id, reopened.confirmed_product_id} ==
             {"review", product.id, nil}

    assert {reopened.confidence, reopened.evidence, reopened.approved_at, reopened.rejected_at} ==
             {Decimal.new("0.91"),
              %{"method" => "exact_approved_gtin", "gtin" => "4006381333931"}, nil, nil}

    assert {:ok, decisions} = history(matched.id)

    assert %{event: "reopened", from_status: "matched", to_status: "review"} =
             List.last(decisions)

    rejected = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing_fixture().id})

    rejected =
      Core.reject_listing_mapping!(
        rejected,
        %{
          reason: "Rejected",
          expected_updated_at: rejected.updated_at
        },
        authorize?: false
      )

    reopened =
      Core.reopen_listing_mapping!(
        rejected,
        %{expected_updated_at: rejected.updated_at, reason: "Try again"},
        actor: admin
      )

    assert {reopened.status, reopened.candidate_product_id, reopened.confirmed_product_id,
            reopened.confidence, reopened.evidence} == {"review", nil, nil, nil, nil}

    assert %{event: "reopened", from_status: "rejected", to_status: "review"} =
             List.last(elem(history(rejected.id), 1))
  end

  test "stale and nonterminal reopen attempts do not change state or history" do
    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing_fixture().id})
    admin = admin_fixture()

    assert {:error, _} =
             Core.reopen_listing_mapping(
               mapping,
               %{expected_updated_at: mapping.updated_at, reason: "Not terminal"},
               actor: admin
             )

    assert Core.get_listing_mapping!(mapping.retailer_listing_id).status == "pending"
    assert {:ok, [%{event: "created"}]} = history(mapping.id)

    rejected =
      Core.reject_listing_mapping!(
        mapping,
        %{
          reason: "Rejected",
          expected_updated_at: mapping.updated_at
        },
        authorize?: false
      )

    assert {:error, _} =
             Core.reopen_listing_mapping(
               rejected,
               %{expected_updated_at: mapping.updated_at, reason: "Stale"},
               actor: admin
             )

    assert Core.get_listing_mapping!(rejected.retailer_listing_id).status == "rejected"
    assert {:ok, decisions} = history(rejected.id)
    refute Enum.any?(decisions, &(&1.event == "reopened"))
  end

  test "a stale record cannot be paired with a separately current version token" do
    stale = Core.create_review_listing_mapping!(review_attrs())

    current =
      Core.import_listing_mapping!(%{
        retailer_listing_id: stale.retailer_listing_id,
        candidate_product_id: stale.candidate_product_id,
        confidence: Decimal.new("0.8"),
        evidence: %{method: "refreshed_matcher"},
        reason: "Newer evidence"
      })

    assert current.updated_at != stale.updated_at
    assert {:ok, before_decisions} = history(stale.id)

    assert {:error, _} =
             Core.reject_listing_mapping(
               stale,
               %{reason: "Stale caller", expected_updated_at: current.updated_at},
               authorize?: false
             )

    assert Core.get_listing_mapping!(stale.retailer_listing_id).reason == "Newer evidence"
    assert history(stale.id) == {:ok, before_decisions}
  end

  test "invalid optional review evidence is omitted as one coherent pair" do
    mapping =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: listing_fixture().id,
        candidate_product_id: draft_product().id,
        confidence: Decimal.new("0.7"),
        evidence: %{method: String.duplicate("x", 65), gtin: "4006381333931"},
        reason: "Needs review"
      })

    assert {:ok, [%{evidence_method: nil, evidence_gtin: nil}]} = history(mapping.id)
  end

  test "oversized optional evidence does not block approval" do
    review = Core.create_review_listing_mapping!(review_attrs())
    too_long = String.duplicate("x", 65)

    assert {:ok, _mapping} =
             Core.approve_listing_mapping(
               review,
               %{
                 confirmed_product_id: approved_product().id,
                 confidence: Decimal.new("0.8"),
                 evidence: %{method: too_long},
                 expected_updated_at: review.updated_at
               },
               authorize?: false
             )

    assert Core.get_listing_mapping!(review.retailer_listing_id).status == "matched"
    assert {:ok, decisions} = history(review.id)

    assert %{event: "approved", evidence_method: "unspecified", evidence_gtin: nil} =
             List.last(decisions)
  end

  defp listing_fixture do
    suffix = System.unique_integer([:positive])

    retailer =
      Core.register_retailer!(%{
        slug: "decision-shop-#{suffix}",
        source_key: "decision-source-#{suffix}",
        name: "Decision Shop",
        category: "lgs"
      })

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Core.ingest_retailer_listing!(%{
      retailer_id: retailer.id,
      source_listing_id: "decision-listing-#{suffix}",
      source_title: "Decision listing",
      direct_url: "https://shop.example/decision-#{suffix}",
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now
    })
  end

  defp history(mapping_id),
    do: Core.list_listing_mapping_decision_history(mapping_id, authorize?: false)

  defp admin_fixture do
    TcgCheap.Accounts.register_admin!(
      %{
        email: "mapping-admin-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp draft_product do
    Core.create_sealed_product_draft!(%{
      slug: "mapping-draft-#{System.unique_integer([:positive])}",
      name: "Mapping Draft",
      product_type: "booster_box"
    })
  end

  defp approved_product do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "mapping-approved-#{System.unique_integer([:positive])}",
        name: "Mapping Approved",
        product_type: "booster_box",
        officially_distributed: true,
        release_date: Date.utc_today()
      })

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp review_attrs do
    %{
      retailer_listing_id: listing_fixture().id,
      candidate_product_id: draft_product().id,
      confidence: Decimal.new("0.7"),
      evidence: %{method: "matcher"},
      reason: "Needs review"
    }
  end
end
