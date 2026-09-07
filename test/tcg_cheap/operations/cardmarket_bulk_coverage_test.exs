defmodule TcgCheap.Operations.CardmarketBulkCoverageTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Catalogue.{CardmarketCardMappingEvidence, CardmarketExpansionMapping}
  alias TcgCheap.Core
  alias TcgCheap.Operations.CardmarketBulkCoverage
  alias TcgCheap.Operations.ImportIssues
  alias TcgCheap.Pricing.CardmarketBulk.Batch

  setup do
    {:ok, %{rows: [[id]]}} =
      TcgCheap.Repo.query(
        "INSERT INTO admins (id, email, hashed_password) VALUES (gen_random_uuid(), $1, 'test') RETURNING id",
        ["coverage-#{System.unique_integer([:positive])}@example.com"]
      )

    previous_cutover = Application.get_env(:tcg_cheap, :cardmarket_bulk_cutover)
    fixture_clock = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(1, :day)

    Process.put(:cardmarket_bulk_coverage_fixture_clock, fixture_clock)

    on_exit(fn ->
      Application.put_env(:tcg_cheap, :cardmarket_bulk_cutover, previous_cutover)
      Process.delete(:cardmarket_bulk_coverage_fixture_clock)
    end)

    {:ok, actor: %Admin{id: id}}
  end

  test "rejects invalid and non-persisted actors" do
    assert {:error, :invalid_actor} = CardmarketBulkCoverage.load(%{})

    assert {:error, :invalid_actor} =
             CardmarketBulkCoverage.load(%Admin{id: Ecto.UUID.generate()})
  end

  test "options are strict, duplicate-free, and require a UTC clock", %{actor: actor} do
    assert {:error, :invalid_cardmarket_bulk_coverage_input} =
             CardmarketBulkCoverage.load(actor,
               clock: &DateTime.utc_now/0,
               clock: &DateTime.utc_now/0
             )

    assert {:error, :invalid_cardmarket_bulk_coverage_input} =
             CardmarketBulkCoverage.load(actor, unknown: true)

    assert {:error, :invalid_clock} =
             CardmarketBulkCoverage.load(actor, clock: fn -> DateTime.now!("Europe/Warsaw") end)
  end

  test "reports canonical paper coverage without a batch", %{actor: actor} do
    _card = card("paper")
    _excluded = card("tcgp", card_set?: false)
    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.status == :no_batch
    assert report.counts.canonical_printings == 1
    assert report.counts.staged_products == 0
    assert report.counts.staged_prices == 0
    assert report.counts.current_valuations == 0
    refute report.catalogue.complete?
    assert :canonical_catalogue_complete in report.cutover.failed_checks
  end

  test "fails closed without a completed catalogue discovery run", %{actor: actor} do
    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    refute report.catalogue.complete?
    assert report.catalogue.discovered_sets == 0
    assert report.cutover.checks.canonical_catalogue_complete == false
  end

  test "fails closed for an incomplete or running catalogue run", %{actor: actor} do
    assert {:ok, _run} =
             TcgCheap.Operations.start_catalogue_sync_run(
               ["incomplete-set"],
               DateTime.add(clock(), -60, :second),
               authorize?: false
             )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    refute report.catalogue.complete?
    assert report.catalogue.running?
    assert report.cutover.checks.canonical_catalogue_complete == false
  end

  test "fails closed for a nonfuture requirement on completed discovery", %{actor: actor} do
    {:ok, run} =
      TcgCheap.Operations.start_catalogue_sync_run(
        ["future-set"],
        DateTime.add(clock(), 60, :second),
        authorize?: false
      )

    {:ok, _run} =
      TcgCheap.Operations.advance_catalogue_sync_run(
        run,
        0,
        "future-set",
        "synced",
        DateTime.add(clock(), 120, :second),
        authorize?: false
      )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    refute report.catalogue.complete?
    assert report.cutover.checks.canonical_catalogue_complete == false
  end

  test "fails closed for unresolved partial catalogue issues", %{actor: actor} do
    %{catalogue_set_id: set_id} = ready_fixture()

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_import",
               "set",
               set_id,
               {:partial_coverage, "fixture"},
               clock()
             )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.catalogue.unresolved_issue_count == 1
    refute report.cutover.checks.canonical_catalogue_complete
  end

  test "a clock before batch timestamps fails closed", %{actor: actor} do
    _batch = batch()

    assert {:error, :incoherent_batch_evidence} =
             CardmarketBulkCoverage.load(actor, clock: fn -> ~U[2026-09-01 00:00:00Z] end)
  end

  test "a nil clock result fails closed", %{actor: actor} do
    assert {:error, :invalid_clock} = CardmarketBulkCoverage.load(actor, clock: fn -> nil end)
  end

  test "source health with no observation is projected as nil", %{actor: actor} do
    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert is_nil(report.source)
  end

  test "current valuation is independent of the latest batch", %{actor: actor} do
    product_id = System.unique_integer([:positive])
    card = card(product_id)

    {:ok, valuation} =
      Core.record_single_valuation(
        %{
          card_printing_id: card.id,
          value_eur: Decimal.new("12.00"),
          currency: "EUR",
          policy_version: "cardmarket_bulk_v1",
          source: "cardmarket_bulk",
          source_metric: "avg7",
          fetched_at: ~U[2026-09-01 10:00:00Z],
          provider_updated_at: ~U[2026-09-01 09:00:00Z],
          cardmarket_product_id: product_id
        },
        authorize?: false
      )

    assert valuation.current?
    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.counts.current_valuations == 1
    assert report.counts.latest_batch_current_valuations == 0
  end

  test "latest batch distinguishes matching valuation timestamps", %{actor: actor} do
    batch = batch()
    product_id = System.unique_integer([:positive])
    card = card(product_id)
    insert_staging(batch, product_id)

    {:ok, _valuation} =
      Core.record_single_valuation(
        %{
          card_printing_id: card.id,
          value_eur: Decimal.new("12.00"),
          currency: "EUR",
          policy_version: "cardmarket_bulk_v1",
          source: "cardmarket_bulk",
          source_metric: "avg7",
          fetched_at: batch.fetched_at,
          provider_updated_at: batch.price_created_at,
          cardmarket_product_id: product_id
        },
        authorize?: false
      )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.status == :ok
    assert report.counts.staged_prices == batch.singles_price_row_count
    assert report.counts.latest_batch_current_valuations == 1
  end

  test "orders and projects the latest two batches with exact metadata", %{actor: actor} do
    previous =
      batch(%{
        product_created_at: ~U[2026-09-01 10:00:00Z],
        price_created_at: ~U[2026-09-01 10:00:00Z],
        fetched_at: ~U[2026-09-01 12:00:00Z],
        completed_at: ~U[2026-09-01 13:00:00Z],
        product_sha256: unique_hash(),
        price_sha256: unique_hash(),
        product_row_count: 2,
        price_row_count: 3,
        singles_price_row_count: 2,
        priceable_singles_count: 1
      })

    latest =
      batch(%{
        product_created_at: ~U[2026-09-02 10:00:00Z],
        price_created_at: ~U[2026-09-02 10:00:00Z],
        fetched_at: ~U[2026-09-02 12:00:00Z],
        completed_at: ~U[2026-09-02 13:00:00Z],
        product_sha256: unique_hash(),
        price_sha256: unique_hash()
      })

    insert_staging(latest, System.unique_integer([:positive]))

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.latest_batch.id == latest.id
    assert report.previous_batch.id == previous.id
    assert report.latest_batch.age_seconds == DateTime.diff(clock(), latest.completed_at)
    assert report.previous_batch.age_seconds == DateTime.diff(clock(), previous.completed_at)
    assert report.latest_batch.product_sha256 == latest.product_sha256
    assert report.latest_batch.price_sha256 == latest.price_sha256
    assert report.previous_batch.product_sha256 == previous.product_sha256
    assert report.previous_batch.price_sha256 == previous.price_sha256
    assert report.latest_batch.product_row_count == latest.product_row_count
    assert report.latest_batch.price_row_count == latest.price_row_count
    assert report.latest_batch.singles_price_row_count == latest.singles_price_row_count
    assert report.previous_batch.priceable_singles_count == previous.priceable_singles_count
  end

  test "counts canonical mapping, detail, and pricing states excluding Pocket", %{actor: actor} do
    card_with_status("pending", %{details_synced_at: nil, pricing_checked_at: nil})
    card_with_status("matched", %{details_synced_at: clock(), pricing_checked_at: nil}, 1)
    card_with_status("unmatched", %{details_synced_at: clock(), pricing_checked_at: clock()})
    card_with_status("review", %{details_enrichment_failed_at: clock()}, nil, "needs review")
    _pocket = card("pocket", card_set?: false)

    assert {:ok, %{counts: counts}} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert counts.canonical_printings == 4
    assert counts.mapping_pending == 1
    assert counts.mapping_matched == 1
    assert counts.mapping_unmatched == 1
    assert counts.mapping_review == 1
    assert counts.details_pending == 2
    assert counts.detail_failures == 1
    assert counts.pricing_check_pending == 3
  end

  test "current valuations exclude archived, other policy, and mismatched products", %{
    actor: actor
  } do
    product_id = System.unique_integer([:positive])
    card = card(product_id)
    record_valuation(card, product_id, "cardmarket_bulk_v1", false)
    record_valuation(card, product_id, "cardmarket_bulk_v1", true)
    record_valuation(card, product_id, "other_policy", true)
    other = card(product_id)
    mismatched = record_valuation(other, product_id, "cardmarket_bulk_v1", true)

    # Exercise the coverage reader's defensive mismatch filter without asking
    # the public valuation action to violate its active-policy invariant.
    TcgCheap.Repo.query!(
      "UPDATE single_valuation_snapshots SET cardmarket_product_id = $1 WHERE id = $2",
      [product_id + 1, Ecto.UUID.dump!(mismatched.id)]
    )

    assert {:ok, %{counts: counts}} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert counts.current_valuations == 1
    assert counts.latest_batch_current_valuations == 0
  end

  test "projects succeeded/current and failed/stale source health", %{actor: actor} do
    now = clock()
    insert_health("succeeded", now, DateTime.add(now, -60, :second))
    assert {:ok, %{source: source}} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert source.last_status == "succeeded"
    assert source.freshness == :current

    TcgCheap.Repo.query!(
      "DELETE FROM acquisition_source_health WHERE provider_key = 'cardmarket_bulk'"
    )

    insert_health("failed", now, DateTime.add(now, -172_800, :second))
    assert {:ok, %{source: source}} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert source.last_status == "failed"
    assert source.freshness == :stale
  end

  test "complete persisted evidence reports accurate ready cutover", %{actor: actor} do
    Application.put_env(:tcg_cheap, :cardmarket_bulk_cutover,
      relative_value_tolerance: 0.05,
      row_count_anomaly_bound: 0.10,
      minimum_coverage_gain: 1,
      minimum_coverage_ratio: 1.1,
      minimum_overlap: 1,
      minimum_agreement_ratio: 1.0
    )

    _previous =
      batch(%{
        product_row_count: 2,
        price_row_count: 2,
        singles_price_row_count: 2,
        priceable_singles_count: 2
      })

    now = clock()

    latest =
      batch(%{
        product_created_at: DateTime.add(now, -3_600, :second),
        price_created_at: DateTime.add(now, -3_600, :second),
        fetched_at: DateTime.add(now, -1_800, :second),
        completed_at: DateTime.add(now, -900, :second),
        product_row_count: 2,
        price_row_count: 2,
        singles_price_row_count: 2,
        priceable_singles_count: 2
      })

    set =
      Core.import_card_set!(
        %{
          tcgdex_id: "coverage-ready-set-#{System.unique_integer([:positive])}",
          name: "Coverage Ready Set",
          series_id: "coverage-ready",
          series_name: "Coverage Ready"
        },
        authorize?: false
      )

    mapping = approve_mapping(latest, set)

    {:ok, catalogue_run} =
      TcgCheap.Operations.start_catalogue_sync_run(
        [set.tcgdex_id],
        DateTime.add(clock(), -7_200, :second),
        authorize?: false
      )

    {:ok, _catalogue_run} =
      TcgCheap.Operations.advance_catalogue_sync_run(
        catalogue_run,
        0,
        set.tcgdex_id,
        "synced",
        DateTime.add(clock(), -3_600, :second),
        authorize?: false
      )

    cards =
      for index <- 1..2 do
        product_id = 10_000 + System.unique_integer([:positive])

        card =
          TcgCheap.TestSupport.import_card_printing!(%{
            tcgdex_id: "coverage-ready-#{System.unique_integer([:positive])}",
            name: "Ready Card #{index}",
            set_name: set.name,
            collector_number: "#{index}",
            card_set_id: set.id,
            mapping_status: "matched",
            cardmarket_product_id: product_id
          })

        insert_staging(latest, product_id)
        record_mapping_evidence(latest, mapping, card, product_id)
        {card, product_id}
      end

    [{card, product_1}, {overlap_card, product_2}] = cards
    record_ready_valuation(card, product_1, "cardmarket_bulk_v1", Decimal.new("12"), latest)

    record_ready_valuation(
      overlap_card,
      product_2,
      "cardmarket_bulk_v1",
      Decimal.new("12"),
      latest
    )

    record_ready_valuation(card, product_1, "tcgdex_cardmarket_v1", Decimal.new("12"), latest)
    insert_health("succeeded", clock(), DateTime.add(clock(), -60, :second))

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.comparison.current_bulk_count == 2
    assert report.comparison.current_tcgdex_count == 1
    assert report.comparison.overlap == 1
    assert report.comparison.overlap_value_agreement == 1
    assert report.comparison.latest_batch_valuation_count == 2
    assert report.comparison.latest_batch_approved_valuations == 2
    assert report.comparison.latest_batch_exact_valuations == 2
    assert report.comparison.latest_batch_ambiguous_or_unapproved == 0
    assert report.cutover.ready?
    assert report.cutover.failed_checks == []
  end

  test "coverage readiness treats only the administrator's exact expansion as approved", %{
    actor: actor
  } do
    %{latest: latest} = ready_fixture()

    TcgCheap.Repo.query!(
      "UPDATE cardmarket_expansion_mappings SET status = 'review', review_reason = 'Administrator exact-pair regression' WHERE source_batch_id = $1",
      [Ecto.UUID.dump!(latest.id)]
    )

    TcgCheap.Repo.query!(
      "UPDATE card_sets SET cardmarket_expansion_id = 1, cardmarket_mapping_status = 'matched', cardmarket_mapping_authority = 'administrator', cardmarket_mapping_reason = 'Administrator exact-pair regression', cardmarket_mapping_evidence_at = $1",
      [latest.completed_at]
    )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.comparison.latest_batch_approved_valuations == 2
    assert report.comparison.latest_batch_exact_valuations == 2
    assert report.comparison.latest_batch_ambiguous_or_unapproved == 0
  end

  test "fails closed for stale or failed source health", %{actor: actor} do
    ready_fixture()

    TcgCheap.Repo.query!(
      "DELETE FROM acquisition_source_health WHERE provider_key = 'cardmarket_bulk'"
    )

    insert_health("failed", clock(), DateTime.add(clock(), -172_800, :second))

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.source_healthy_and_current == false
    assert :source_healthy_and_current in report.cutover.failed_checks
  end

  for {field, label} <- [
        {:product_row_count, "product"},
        {:price_row_count, "price"},
        {:singles_price_row_count, "singles price"},
        {:priceable_singles_count, "priceable singles"}
      ] do
    test "fails closed for a cardinality anomaly in #{label} count", %{actor: actor} do
      %{latest: latest, previous: previous} = ready_fixture()
      anomalous_batch = if unquote(field) == :price_row_count, do: latest, else: previous
      anomalous_value = if unquote(field) == :price_row_count, do: 3, else: 1
      update_batch_count(anomalous_batch, unquote(field), anomalous_value)

      assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
      assert report.cutover.checks.row_count_anomaly_bounded == false
      assert :row_count_anomaly_bounded in report.cutover.failed_checks
    end
  end

  test "fails closed when mapping evidence is missing", %{actor: actor} do
    %{latest: latest} = ready_fixture()

    TcgCheap.Repo.query!(
      "DELETE FROM cardmarket_card_mapping_evidence WHERE source_batch_id = $1",
      [Ecto.UUID.dump!(latest.id)]
    )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.approved_mapping_evidence == false
    assert :approved_mapping_evidence in report.cutover.failed_checks
  end

  test "fails closed when mapping evidence is from the wrong batch", %{actor: actor} do
    %{latest: latest, previous: previous} = ready_fixture()

    TcgCheap.Repo.query!(
      "UPDATE cardmarket_card_mapping_evidence SET source_batch_id = $1 WHERE source_batch_id = $2",
      [Ecto.UUID.dump!(previous.id), Ecto.UUID.dump!(latest.id)]
    )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.approved_mapping_evidence == false
    assert :approved_mapping_evidence in report.cutover.failed_checks
  end

  test "fails closed for staged selected value or metric mismatch", %{actor: actor} do
    %{latest: latest} = ready_fixture()

    TcgCheap.Repo.query!(
      "UPDATE cardmarket_bulk_prices SET selected_metric = 'avg30' WHERE last_batch_id = $1",
      [Ecto.UUID.dump!(latest.id)]
    )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.staged_value_metric_agreement == false
    assert :staged_value_metric_agreement in report.cutover.failed_checks
  end

  test "fails closed for inadequate material coverage gain", %{actor: actor} do
    ready_fixture(minimum_coverage_gain: 2)

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.material_coverage_gain == false
    assert :material_coverage_gain in report.cutover.failed_checks
  end

  test "ignores stale bulk valuations when comparing latest coverage", %{actor: actor} do
    %{latest: latest, previous: previous} = ready_fixture(minimum_overlap: 2)

    for _ <- 1..2 do
      product_id = System.unique_integer([:positive])
      stale_card = card(product_id)

      record_ready_valuation(
        stale_card,
        product_id,
        "cardmarket_bulk_v1",
        Decimal.new("12"),
        previous
      )

      record_ready_valuation(
        stale_card,
        product_id,
        "tcgdex_cardmarket_v1",
        Decimal.new("12"),
        previous
      )
    end

    TcgCheap.Repo.query!(
      "UPDATE cardmarket_bulk_prices SET selected_metric = 'avg30' WHERE last_batch_id = $1",
      [Ecto.UUID.dump!(latest.id)]
    )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.comparison.latest_batch_valuation_count == 2
    assert report.comparison.latest_batch_exact_valuations == 0
    assert report.comparison.current_bulk_count == 0
    assert report.comparison.overlap == 0
    refute report.cutover.checks.material_coverage_gain
    refute report.cutover.checks.overlap_value_agreement
  end

  test "fails closed for insufficient overlap", %{actor: actor} do
    ready_fixture(minimum_overlap: 2)

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.overlap_value_agreement == false
    assert :overlap_value_agreement in report.cutover.failed_checks
  end

  test "fails closed when overlap is outside relative tolerance", %{actor: actor} do
    ready_fixture()

    TcgCheap.Repo.query!(
      "UPDATE single_valuation_snapshots SET value_eur = 20 WHERE policy_version = 'tcgdex_cardmarket_v1'"
    )

    assert {:ok, report} = CardmarketBulkCoverage.load(actor, clock: &clock/0)
    assert report.cutover.checks.overlap_value_agreement == false
    assert :overlap_value_agreement in report.cutover.failed_checks
  end

  defp ready_fixture(overrides \\ []) do
    Application.put_env(
      :tcg_cheap,
      :cardmarket_bulk_cutover,
      Keyword.merge(
        [
          relative_value_tolerance: 0.05,
          row_count_anomaly_bound: 0.10,
          minimum_coverage_gain: 1,
          minimum_coverage_ratio: 1.1,
          minimum_overlap: 1,
          minimum_agreement_ratio: 1.0
        ],
        overrides
      )
    )

    previous =
      batch(%{
        product_row_count: 2,
        price_row_count: 2,
        singles_price_row_count: 2,
        priceable_singles_count: 2
      })

    latest =
      batch(%{
        product_created_at: ~U[2026-09-03 10:00:00Z],
        price_created_at: ~U[2026-09-03 10:00:00Z],
        fetched_at: ~U[2026-09-03 12:00:00Z],
        completed_at: ~U[2026-09-03 13:00:00Z],
        product_row_count: 2,
        price_row_count: 2,
        singles_price_row_count: 2,
        priceable_singles_count: 2
      })

    set =
      Core.import_card_set!(
        %{
          tcgdex_id: "coverage-ready-set-#{System.unique_integer([:positive])}",
          name: "Coverage Ready Set",
          series_id: "coverage-ready",
          series_name: "Coverage Ready"
        },
        authorize?: false
      )

    mapping = approve_mapping(latest, set)

    {:ok, catalogue_run} =
      TcgCheap.Operations.start_catalogue_sync_run(
        [set.tcgdex_id],
        DateTime.add(clock(), -7_200, :second),
        authorize?: false
      )

    {:ok, _catalogue_run} =
      TcgCheap.Operations.advance_catalogue_sync_run(
        catalogue_run,
        0,
        set.tcgdex_id,
        "synced",
        DateTime.add(clock(), -3_600, :second),
        authorize?: false
      )

    cards =
      for index <- 1..2 do
        product_id = 10_000 + System.unique_integer([:positive])

        card =
          TcgCheap.TestSupport.import_card_printing!(%{
            tcgdex_id: "coverage-ready-#{System.unique_integer([:positive])}",
            name: "Ready Card #{index}",
            set_name: set.name,
            collector_number: "#{index}",
            card_set_id: set.id,
            mapping_status: "matched",
            cardmarket_product_id: product_id
          })

        insert_staging(latest, product_id)
        record_mapping_evidence(latest, mapping, card, product_id)
        {card, product_id}
      end

    [{card, product_1}, {overlap_card, product_2}] = cards
    record_ready_valuation(card, product_1, "cardmarket_bulk_v1", Decimal.new("12"), latest)

    record_ready_valuation(
      overlap_card,
      product_2,
      "cardmarket_bulk_v1",
      Decimal.new("12"),
      latest
    )

    record_ready_valuation(card, product_1, "tcgdex_cardmarket_v1", Decimal.new("12"), latest)
    insert_health("succeeded", clock(), DateTime.add(clock(), -60, :second))
    %{previous: previous, latest: latest, catalogue_set_id: set.tcgdex_id}
  end

  defp update_batch_count(batch, field, value) do
    fields =
      case field do
        field
        when field in [:product_row_count, :singles_price_row_count, :priceable_singles_count] ->
          "product_row_count = $1, price_row_count = $1, singles_price_row_count = $1, priceable_singles_count = $1"

        :price_row_count ->
          "price_row_count = $1"
      end

    TcgCheap.Repo.query!(
      "UPDATE cardmarket_bulk_batches SET #{fields} WHERE id = $2",
      [value, Ecto.UUID.dump!(batch.id)]
    )
  end

  defp clock, do: Process.get(:cardmarket_bulk_coverage_fixture_clock)

  defp card(product_id, opts \\ []) do
    attrs = %{
      tcgdex_id: "coverage-#{System.unique_integer([:positive])}",
      name: "Coverage Card",
      set_name: "Coverage Set",
      collector_number: "1",
      mapping_status: if(is_integer(product_id), do: "matched", else: "unmatched"),
      cardmarket_product_id: if(is_integer(product_id), do: product_id)
    }

    TcgCheap.TestSupport.import_card_printing!(attrs, opts)
  end

  defp card_with_status(status, attrs, product_id \\ nil, review_reason \\ nil) do
    TcgCheap.TestSupport.import_card_printing!(
      Map.merge(
        %{
          tcgdex_id: "coverage-#{status}-#{System.unique_integer([:positive])}",
          name: "Coverage Card",
          set_name: "Coverage Set",
          collector_number: "1",
          mapping_status: status,
          mapping_review_reason: review_reason,
          cardmarket_product_id: product_id
        },
        attrs
      )
    )
  end

  defp batch(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          policy_version: "cardmarket_bulk_v1",
          parser_version: "fixture",
          product_created_at: ~U[2026-09-02 10:00:00Z],
          price_created_at: ~U[2026-09-02 10:00:00Z],
          fetched_at: ~U[2026-09-02 12:00:00Z],
          completed_at: ~U[2026-09-02 13:00:00Z],
          product_sha256: unique_hash(),
          price_sha256: unique_hash(),
          product_byte_size: 1,
          price_byte_size: 1,
          product_row_count: 1,
          price_row_count: 2,
          singles_price_row_count: 1,
          priceable_singles_count: 1
        },
        overrides
      )

    Ash.create!(
      Ash.Changeset.for_create(Batch, :complete, attrs),
      authorize?: false
    )
  end

  defp unique_hash, do: :crypto.hash(:sha256, Ecto.UUID.generate()) |> Base.encode16(case: :lower)

  defp record_valuation(card, product_id, policy, current?) do
    {:ok, snapshot} =
      Core.record_single_valuation(
        %{
          card_printing_id: card.id,
          value_eur: Decimal.new("12"),
          currency: "EUR",
          policy_version: policy,
          source: "cardmarket_bulk",
          source_metric: "avg7",
          fetched_at: ~U[2026-09-01 10:00:00Z],
          provider_updated_at: ~U[2026-09-01 09:00:00Z],
          cardmarket_product_id: product_id
        },
        authorize?: false
      )

    unless current?,
      do:
        TcgCheap.Repo.query!(
          "UPDATE single_valuation_snapshots SET \"current?\" = false WHERE id = $1",
          [Ecto.UUID.dump!(snapshot.id)]
        )

    snapshot
  end

  defp insert_health(status, now, succeeded_at) do
    if status == "succeeded" do
      TcgCheap.Repo.query!(
        "INSERT INTO acquisition_source_health (provider_key,last_started_at,last_succeeded_at,last_status,consecutive_failures,circuit_failure_streak) VALUES ('cardmarket_bulk',$1,$2,'succeeded',0,0)",
        [now, succeeded_at]
      )
    else
      TcgCheap.Repo.query!(
        "INSERT INTO acquisition_source_health (provider_key,last_started_at,last_succeeded_at,last_failed_at,last_status,last_failure_category,consecutive_failures,circuit_failure_streak) VALUES ('cardmarket_bulk',$1,$2,$1,'failed','timeout',1,1)",
        [now, succeeded_at]
      )
    end
  end

  defp insert_staging(batch, product_id) do
    batch_id = Ecto.UUID.dump!(batch.id)

    TcgCheap.Repo.query!(
      "INSERT INTO cardmarket_bulk_products (cardmarket_product_id,name,category_id,category_name,expansion_id,metacard_id,source_date_added,source_updated_at,last_batch_id) VALUES ($1,'Coverage',51,'Pokémon Single',1,0,'2026-09-02',$2,$3)",
      [product_id, batch.price_created_at, batch_id]
    )

    TcgCheap.Repo.query!(
      "INSERT INTO cardmarket_bulk_prices (cardmarket_product_id,category_id,selected_metric,selected_value_eur,source_updated_at,last_batch_id) VALUES ($1,51,'avg7',12.00,$2,$3)",
      [product_id, batch.price_created_at, batch_id]
    )
  end

  defp approve_mapping(batch, set) do
    Ash.create!(
      Ash.Changeset.for_create(CardmarketExpansionMapping, :record, %{
        source_batch_id: batch.id,
        card_set_id: set.id,
        expansion_id: 1,
        status: "approved",
        authority: "system",
        anchor_count: 1,
        evidence: %{"fixture" => true}
      }),
      authorize?: false
    )
  end

  defp record_mapping_evidence(batch, mapping, card, product_id) do
    Ash.create!(
      Ash.Changeset.for_create(CardmarketCardMappingEvidence, :record, %{
        source_batch_id: batch.id,
        expansion_mapping_id: mapping.id,
        card_printing_id: card.id,
        decision: "auto_matched",
        cardmarket_product_id: product_id,
        normalized_card_name: String.downcase(card.name),
        evidence: %{"fixture" => true},
        authority: "system"
      }),
      authorize?: false
    )
  end

  defp record_ready_valuation(card, product_id, policy, value, batch) do
    Core.record_single_valuation!(
      %{
        card_printing_id: card.id,
        value_eur: value,
        currency: "EUR",
        policy_version: policy,
        source: String.replace_suffix(policy, "_v1", ""),
        source_metric: "avg7",
        fetched_at: batch.fetched_at,
        provider_updated_at: batch.price_created_at,
        cardmarket_product_id: product_id
      },
      authorize?: false
    )
  end
end
