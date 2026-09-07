Code.require_file("test/tcg_cheap/pricing/cardmarket_bulk/test_helper.exs")

defmodule TcgCheap.Pricing.CardmarketBulk.MaterializerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Pricing.CardmarketBulk.{Batch, FakeAdapter, Materializer, Sync}

  setup do
    Ash.create!(
      Ash.Changeset.for_create(Batch, :complete, %{
        policy_version: Sync.policy_version(),
        parser_version: "fixture",
        product_created_at: ~U[2026-09-02 10:00:00Z],
        price_created_at: ~U[2026-09-02 10:00:00Z],
        fetched_at: ~U[2026-09-02 12:00:00Z],
        completed_at: ~U[2026-09-02 13:00:00Z],
        product_sha256: String.duplicate("a", 64),
        price_sha256: String.duplicate("b", 64),
        product_byte_size: 1,
        price_byte_size: 1,
        product_row_count: 1,
        price_row_count: 1,
        singles_price_row_count: 1,
        priceable_singles_count: 1
      }),
      authorize?: false
    )

    :ok
  end

  defp sync_batch(product_id, fixture \\ :good) do
    opts = [
      adapter: FakeAdapter,
      adapter_options: [request_options: [fixture: fixture, product_id: product_id]],
      clock: fn -> ~U[2026-09-03 12:00:00Z] end,
      completion_clock: fn -> ~U[2026-09-03 13:00:00Z] end,
      request_admitter: fn -> :ok end
    ]

    {:ok, %{batch: batch}} = Sync.run(opts)
    batch
  end

  defp card(product_id, suffix, set) do
    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: "base1-#{suffix}-#{System.unique_integer([:positive])}",
      name: "Fixture Card",
      set_name: "Base Set",
      collector_number: "1",
      mapping_status: "matched",
      cardmarket_product_id: product_id,
      card_set_id: set && set.id
    })
  end

  defp set do
    id = "materializer-set-#{System.unique_integer([:positive])}"

    Core.import_card_set!(
      %{tcgdex_id: id, name: id, series_id: id, series_name: id},
      authorize?: false
    )
  end

  defp approve_mapping(batch, set, status \\ "approved") do
    Core.record_cardmarket_expansion_mapping!(
      %{
        source_batch_id: batch.id,
        card_set_id: set.id,
        expansion_id: 2,
        status: status,
        authority: "system",
        anchor_count: 1,
        evidence: %{"fixture" => true},
        review_reason: if(status == "review", do: "Needs administrator review")
      },
      authorize?: false
    )
  end

  defp record_evidence(batch, mapping, card, decision, product_id) do
    Core.record_cardmarket_card_mapping_evidence!(
      %{
        source_batch_id: batch.id,
        expansion_mapping_id: mapping.id,
        card_printing_id: card.id,
        decision: decision,
        cardmarket_product_id: product_id,
        normalized_card_name: "fixture card",
        authority: "system",
        evidence: %{"fixture" => true}
      },
      authorize?: false
    )
  end

  test "materializes only approved mappings and preserves selected value, metric, and source timestamps" do
    product_id = System.unique_integer([:positive])
    batch = sync_batch(product_id)
    set = set()
    matched = card(product_id, "approved", set)
    mapping = approve_mapping(batch, set)
    record_evidence(batch, mapping, matched, "anchor", product_id)

    _unmapped =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "unmapped-#{System.unique_integer([:positive])}",
        name: "Unmapped",
        set_name: "Base Set",
        collector_number: "2",
        mapping_status: "pending"
      })

    assert {:ok, %{materialized: 1}} = Materializer.run(batch)
    assert {:ok, valuation} = Core.get_current_single_valuation(matched.id, "cardmarket_bulk_v1")
    assert Decimal.equal?(valuation.value_eur, Decimal.new("12.34"))
    assert valuation.source_metric == "avg7"
    assert valuation.fetched_at == batch.fetched_at
    assert valuation.provider_updated_at == batch.price_created_at
    assert valuation.source == "cardmarket_bulk"
  end

  test "does not materialize an unmapped product" do
    product_id = System.unique_integer([:positive])
    batch = sync_batch(product_id)

    card_set = set()
    card = card(product_id, "without-approved-mapping", card_set)

    assert {:ok, %{materialized: 0}} = Materializer.run(batch)
    assert {:ok, nil} = Core.get_current_single_valuation(card.id, "cardmarket_bulk_v1")
  end

  test "approved expansion state without exact card evidence is rejected" do
    product_id = System.unique_integer([:positive])
    batch = sync_batch(product_id)
    card_set = set()
    card = card(product_id, "without-evidence", card_set)
    approve_mapping(batch, card_set)

    assert {:ok, %{materialized: 0, unapproved_mapping: 1}} = Materializer.run(batch)
    assert {:ok, nil} = Core.get_current_single_valuation(card.id, "cardmarket_bulk_v1")
  end

  test "administrator CardSet state approves only the exact expansion pair" do
    product_id = System.unique_integer([:positive])
    other_product_id = product_id + 1
    batch = sync_batch(product_id)
    set = set()
    exact = card(product_id, "administrator-exact", set)
    other = card(other_product_id, "administrator-other", set)
    mapping = approve_mapping(batch, set, "review")
    record_evidence(batch, mapping, exact, "auto_matched", product_id)
    upsert_product(batch, other_product_id, 999)
    upsert_price(batch, other_product_id)

    TcgCheap.Repo.query!(
      "UPDATE card_sets SET cardmarket_expansion_id = 2, cardmarket_mapping_status = 'matched', cardmarket_mapping_authority = 'administrator', cardmarket_mapping_reason = 'Exact administrator review', cardmarket_mapping_evidence_at = $1 WHERE id = $2",
      [batch.completed_at, Ecto.UUID.dump!(set.id)]
    )

    assert {:ok, %{materialized: 1, unapproved_mapping: 1}} = Materializer.run(batch)
    assert {:ok, _} = Core.get_current_single_valuation(exact.id, "cardmarket_bulk_v1")
    assert {:ok, nil} = Core.get_current_single_valuation(other.id, "cardmarket_bulk_v1")
  end

  test "does not combine a price from another batch" do
    product_id = System.unique_integer([:positive])
    first = sync_batch(product_id)
    set = set()
    card = card(product_id, "different-batch", set)
    approve_mapping(first, set)
    second = sync_batch(product_id + 1)

    assert {:ok, %{unapproved_mapping: 1}} = Materializer.run(second)
    assert {:ok, nil} = Core.get_current_single_valuation(card.id, "cardmarket_bulk_v1")
    assert first.id != second.id
  end

  test "rerunning the same batch is idempotent" do
    product_id = System.unique_integer([:positive])
    batch = sync_batch(product_id)
    set = set()
    card = card(product_id, "rerun", set)
    mapping = approve_mapping(batch, set)
    record_evidence(batch, mapping, card, "anchor", product_id)

    assert {:ok, %{materialized: 1}} = Materializer.run(batch)
    assert {:ok, %{already_materialized: 1}} = Materializer.run(batch)
    assert [valuation] = Core.list_single_valuation_history!(card.id, "cardmarket_bulk_v1")
    assert valuation.current?
  end

  test "concurrent materialization of the same batch records one snapshot" do
    product_id = System.unique_integer([:positive])
    batch = sync_batch(product_id)
    card_set = set()
    card = card(product_id, "concurrent", card_set)
    mapping = approve_mapping(batch, card_set)
    record_evidence(batch, mapping, card, "anchor", product_id)
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Materializer.run(batch)
          end
        end)
      end

    assert_receive {:ready, first_task}, 5_000
    assert_receive {:ready, second_task}, 5_000
    send(first_task, :go)
    send(second_task, :go)

    results = Enum.map(tasks, &Task.await(&1, 10_000))

    assert Enum.count(results, &match?({:ok, %{materialized: 1}}, &1)) == 1
    assert Enum.count(results, &match?({:ok, %{already_materialized: 1}}, &1)) == 1
    assert [valuation] = Core.list_single_valuation_history!(card.id, "cardmarket_bulk_v1")
    assert valuation.current?
  end

  defp upsert_product(batch, product_id, expansion_id) do
    Core.upsert_cardmarket_bulk_product!(
      %{
        cardmarket_product_id: product_id,
        name: "Other",
        category_id: 51,
        category_name: "Pokémon Single",
        expansion_id: expansion_id,
        metacard_id: product_id,
        source_date_added: "2026-09-02",
        last_batch_id: batch.id,
        source_updated_at: batch.price_created_at
      },
      authorize?: false
    )
  end

  defp upsert_price(batch, product_id) do
    Core.upsert_cardmarket_bulk_price!(
      %{
        cardmarket_product_id: product_id,
        category_id: 51,
        selected_metric: "avg7",
        selected_value_eur: Decimal.new("12.34"),
        avg7: Decimal.new("12.34"),
        last_batch_id: batch.id,
        source_updated_at: batch.price_created_at
      },
      authorize?: false
    )
  end
end
