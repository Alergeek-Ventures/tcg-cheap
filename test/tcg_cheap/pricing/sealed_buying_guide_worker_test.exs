defmodule TcgCheap.Pricing.SealedBuyingGuideWorkerTest do
  use TcgCheap.DataCase, async: false

  import Ecto.Query
  import Oban.Testing

  alias TcgCheap.Core

  alias TcgCheap.Pricing.{
    SealedBuyingGuideWorker,
    SealedDailyAggregateRevision,
    SealedDailyAggregateWorker
  }

  alias TcgCheap.Repo

  @as_of ~U[2026-08-09 12:00:00Z]

  setup do
    previous_aggregate = Application.get_env(:tcg_cheap, :sealed_daily_aggregate_clock)
    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, fn -> @as_of end)

    on_exit(fn ->
      Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, previous_aggregate)
    end)

    :ok
  end

  test "canonical source revision args, queue, uniqueness, and timeout" do
    aggregate = aggregate_for(product())
    {:ok, changeset} = SealedBuyingGuideWorker.new_for_aggregate(aggregate)
    first = Oban.insert!(changeset)
    second = Oban.insert!(SealedBuyingGuideWorker.new_for_aggregate(aggregate) |> elem(1))
    assert first.id == second.id
    assert first.queue == "sealed_buying_guides"

    assert first.args == %{
             source_aggregate_id: aggregate.id,
             source_aggregate_calculated_at: DateTime.to_iso8601(aggregate.calculated_at),
             source_aggregate_fingerprint: fingerprint(aggregate),
             source_history_fingerprint: history_fingerprint(aggregate)
           }

    assert SealedBuyingGuideWorker.timeout(first) == :timer.minutes(10)
    assert {:cancel, :malformed_job_args} = perform_job(job(%{"bad" => true}), [])
  end

  test "a newer fingerprint queues a successor while the prior revision executes" do
    aggregate = aggregate_for(product())
    first = Oban.insert!(SealedBuyingGuideWorker.new_for_aggregate(aggregate) |> elem(1))

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.id), set: [state: "executing"])

    newer = %{
      aggregate
      | source_evidence: [
          %{hd(aggregate.source_evidence) | price_pln: Decimal.new("11")}
        ]
    }

    {:ok, successor} = SealedBuyingGuideWorker.new_for_aggregate(newer)
    assert {:ok, inserted} = Oban.insert(successor)
    assert inserted.id != first.id

    assert inserted.args[:source_aggregate_fingerprint] !=
             first.args[:source_aggregate_fingerprint]
  end

  test "a supporting history revision changes job identity" do
    product = product()
    history_date = Date.add(DateTime.to_date(@as_of), -7)
    record_ready(product, history_date, "6")
    aggregate = aggregate_for(product)

    first = Oban.insert!(SealedBuyingGuideWorker.new_for_aggregate(aggregate) |> elem(1))
    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.id), set: [state: "executing"])

    record_ready(product, history_date, "7", DateTime.new!(history_date, ~T[13:00:00]))

    second = Oban.insert!(SealedBuyingGuideWorker.new_for_aggregate(aggregate) |> elem(1))

    assert second.id != first.id
    assert second.args[:source_aggregate_fingerprint] == first.args[:source_aggregate_fingerprint]
    assert second.args[:source_history_fingerprint] != first.args[:source_history_fingerprint]
  end

  test "a history change during calculation prevents stale output and queues a successor" do
    product = product()
    history_date = Date.add(DateTime.to_date(@as_of), -7)
    old_history = record_ready(product, history_date, "6")
    aggregate = aggregate_for(product)
    stale_args = guide_args(aggregate)

    record_ready(product, history_date, "7", DateTime.new!(history_date, ~T[13:00:00]))

    previous = Application.get_env(:tcg_cheap, :sealed_buying_guide_history_reader)

    Application.put_env(:tcg_cheap, :sealed_buying_guide_history_reader, fn _, _, _, _, _ ->
      {:ok, [old_history]}
    end)

    on_exit(fn -> restore_env(:sealed_buying_guide_history_reader, previous) end)

    assert :ok = perform_job(job(stale_args), [])

    assert {:ok, nil} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               aggregate.aggregate_date
             )

    {:ok, successor} = SealedBuyingGuideWorker.new_for_aggregate(aggregate)

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SealedBuyingGuideWorker,
      args: successor.changes.args
    )

    assert successor.changes.args[:source_history_fingerprint] !=
             stale_args["source_history_fingerprint"]
  end

  test "source timestamp args survive clock and scheduled-date changes" do
    aggregate = aggregate_for(product())

    assert :ok =
             perform_job(
               %{job(guide_args(aggregate)) | scheduled_at: ~U[2026-08-10 12:00:00Z]},
               []
             )

    assert {:ok, snapshot} =
             Core.get_latest_sealed_buying_guide_snapshot(
               aggregate.sealed_product_id,
               "sealed_buying_model_v1",
               aggregate.aggregate_date
             )

    assert snapshot.calculated_at == aggregate.calculated_at
  end

  test "retries when history reading fails" do
    aggregate = aggregate_for(product())
    args = guide_args(aggregate)
    previous = Application.get_env(:tcg_cheap, :sealed_buying_guide_history_reader)

    Application.put_env(:tcg_cheap, :sealed_buying_guide_history_reader, fn _, _, _, _, _ ->
      {:error, :boom}
    end)

    on_exit(fn ->
      restore_env(:sealed_buying_guide_history_reader, previous)
    end)

    assert {:error, :history_read_failed} = perform_job(job(args), [])
  end

  test "cancels a malformed or missing source aggregate" do
    product = product()
    assert {:cancel, :malformed_job_args} = perform_job(job(%{}), [])

    assert {:cancel, :source_aggregate_not_found} =
             perform_job(
               job(%{
                 "source_aggregate_id" => Ecto.UUID.generate(),
                 "source_aggregate_calculated_at" => DateTime.to_iso8601(@as_of),
                 "source_aggregate_fingerprint" => String.duplicate("0", 64),
                 "source_history_fingerprint" => String.duplicate("0", 64)
               }),
               []
             )

    assert {:ok, nil} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               DateTime.to_date(@as_of)
             )
  end

  test "superseded or tampered source revisions do not persist" do
    product = product()
    aggregate = aggregate_for(product)
    args = guide_args(aggregate)

    assert :ok =
             perform_job(
               job(Map.put(args, "source_aggregate_fingerprint", String.duplicate("0", 64))),
               []
             )

    assert :ok =
             perform_job(
               job(
                 Map.put(
                   args,
                   "source_aggregate_calculated_at",
                   DateTime.to_iso8601(DateTime.add(@as_of, -1, :second))
                 )
               ),
               []
             )

    assert {:ok, nil} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               aggregate.aggregate_date
             )
  end

  test "persists a limited snapshot and is idempotent for the same day" do
    product = product()
    add_offer(product, "limited", "10", confidence: Decimal.new("0.5"))
    assert :ok = perform_job(aggregate_job(), [])

    assert {:ok, aggregate} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               "sealed_market_daily_v1",
               DateTime.to_date(@as_of)
             )

    assert [%{mapping_id: _, listing_id: _, price_pln: %Decimal{}}] = aggregate.source_evidence
    assert :ok = perform_job(job(guide_args(aggregate)), [])
    assert :ok = perform_job(job(guide_args(aggregate)), [])

    assert {:ok, snapshot} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               DateTime.to_date(@as_of)
             )

    assert snapshot.status == "limited"
    assert snapshot.limited_reason == "uncertain_mapping"
    assert snapshot.guide_date == DateTime.to_date(@as_of)
    assert DateTime.compare(snapshot.calculated_at, @as_of) == :eq

    assert {:ok, history} =
             Core.list_sealed_buying_guide_snapshot_history(
               product.id,
               "sealed_buying_model_v1",
               DateTime.to_date(@as_of),
               DateTime.to_date(@as_of)
             )

    assert length(history) == 1

    assert snapshot.explanation_factors == [
             "market_data_limited",
             "trend_insufficient_history",
             "availability_balanced",
             "availability_trend_insufficient_history"
           ]
  end

  test "fails closed when persisted source evidence is altered or empty" do
    product = product()
    add_offer(product, "evidence", "10")
    assert :ok = perform_job(aggregate_job(), [])

    assert {:ok, aggregate} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               "sealed_market_daily_v1",
               DateTime.to_date(@as_of)
             )

    Repo.query!(
      "UPDATE sealed_daily_aggregates SET source_evidence = '{}'::jsonb[] WHERE id = $1",
      [
        Ecto.UUID.dump!(aggregate.id)
      ]
    )

    tampered = %{aggregate | source_evidence: []}
    assert {:cancel, :source_evidence_mismatch} = perform_job(job(guide_args(tampered)), [])
  end

  test "persists Limited data from a coherent aggregate with no relevant evidence" do
    product = product()

    aggregate =
      Core.record_sealed_daily_aggregate!(%{
        sealed_product_id: product.id,
        aggregate_date: DateTime.to_date(@as_of),
        calculation_version: "sealed_market_daily_v1",
        currency: "PLN",
        status: "limited",
        limited_reason: "no_fresh_current_offers",
        fresh_regular_retailer_count: 0,
        fresh_lgs_count: 0,
        recent_sold_out_0_14_day_count: 0,
        sold_out_15_30_day_count: 0,
        stale_or_future_current_offer_count: 0,
        unique_source_retailer_count: 0,
        latest_nonfuture_checked_at: nil,
        calculated_at: @as_of,
        source_mapping_confident: true,
        source_evidence: []
      })

    assert :ok = perform_job(job(guide_args(aggregate)), [])

    assert {:ok, snapshot} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               aggregate.aggregate_date
             )

    assert snapshot.status == "limited"
    assert snapshot.limited_reason == "limited_market_aggregate"
  end

  test "persists a ready snapshot with history and exact model components" do
    product = product(Decimal.new("10"))
    for index <- 1..5, do: add_offer(product, "ready-#{index}", Integer.to_string(index + 5))

    record_ready(product, Date.add(DateTime.to_date(@as_of), -14), "5")
    record_ready(product, Date.add(DateTime.to_date(@as_of), -7), "6")
    assert :ok = perform_job(aggregate_job(), [])

    assert {:ok, aggregate} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               "sealed_market_daily_v1",
               DateTime.to_date(@as_of)
             )

    Repo.query!("UPDATE sealed_products SET msrp_pln = '99' WHERE id = $1", [
      Ecto.UUID.dump!(product.id)
    ])

    assert :ok = perform_job(job(guide_args(aggregate)), [])

    assert {:ok, snapshot} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               DateTime.to_date(@as_of)
             )

    assert snapshot.status == "ready"
    assert Decimal.equal?(snapshot.confidence, Decimal.new("0.69"))
    assert Decimal.equal?(snapshot.reference_price_pln, Decimal.new("8.63"))
    assert Decimal.equal?(snapshot.regular_benchmark_pln, Decimal.new("8"))
    assert Decimal.equal?(snapshot.msrp_pln, Decimal.new("10"))
    assert Decimal.equal?(snapshot.great_price_max_pln, Decimal.new("6.00"))
    assert Decimal.equal?(snapshot.fair_price_max_pln, Decimal.new("9.23"))
    assert Decimal.equal?(snapshot.expensive_price_max_pln, Decimal.new("10.53"))

    assert snapshot.explanation_factors == [
             "market_benchmark",
             "msrp",
             "trend_rising",
             "availability_balanced",
             "availability_trend_stable"
           ]
  end

  test "cancels when an LGS projection drifted after its source aggregate" do
    product = product(Decimal.new("10"))
    add_offer(product, "regular", "8")
    add_offer(product, "lgs", "9", category: "lgs")

    assert :ok = perform_job(aggregate_job(), [])

    assert {:ok, aggregate} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               "sealed_market_daily_v1",
               DateTime.to_date(@as_of)
             )

    lgs_mapping =
      Core.list_public_listing_mappings_for_product!(product.id)
      |> Enum.find(&(&1.retailer_listing.retailer.category == "lgs"))

    listing = lgs_mapping.retailer_listing
    drifted_at = DateTime.add(@as_of, 1, :second)

    Core.ingest_retailer_listing!(%{
      retailer_id: listing.retailer_id,
      source_listing_id: listing.source_listing_id,
      source_title: listing.source_title,
      direct_url: listing.direct_url,
      gtin: listing.gtin,
      current_price_pln: Decimal.new("99"),
      stock_status: listing.stock_status,
      first_seen_at: listing.first_seen_at,
      last_seen_at: drifted_at,
      last_checked_at: drifted_at
    })

    assert :ok = perform_job(job(guide_args(aggregate)), [])

    assert {:ok, snapshot} =
             Core.get_latest_sealed_buying_guide_snapshot(
               product.id,
               "sealed_buying_model_v1",
               aggregate.aggregate_date
             )

    assert snapshot.status == "limited"
    assert snapshot.limited_reason == "limited_market_aggregate"
    assert Decimal.equal?(snapshot.lgs_median_pln, Decimal.new("9"))
    assert Decimal.equal?(snapshot.reference_price_pln, Decimal.new("9.71"))
  end

  defp job(args) do
    %Oban.Job{
      args: args,
      worker: Atom.to_string(SealedBuyingGuideWorker),
      queue: "sealed_buying_guides",
      attempt: 1,
      max_attempts: 5,
      scheduled_at: @as_of,
      attempted_at: @as_of,
      inserted_at: @as_of
    }
  end

  defp guide_args(aggregate) do
    {:ok, changeset} = SealedBuyingGuideWorker.new_for_aggregate(aggregate)
    Map.new(changeset.changes.args, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp fingerprint(aggregate) do
    {:ok, value} = SealedDailyAggregateRevision.fingerprint(aggregate)
    value
  end

  defp history_fingerprint(aggregate) do
    {:ok, history} =
      Core.list_sealed_daily_aggregate_history(
        aggregate.sealed_product_id,
        aggregate.calculation_version,
        Date.add(aggregate.aggregate_date, -30),
        Date.add(aggregate.aggregate_date, -1)
      )

    {:ok, value} = SealedDailyAggregateRevision.history_fingerprint(history)
    value
  end

  defp aggregate_for(product) do
    Core.record_sealed_daily_aggregate!(%{
      sealed_product_id: product.id,
      aggregate_date: DateTime.to_date(@as_of),
      calculation_version: "sealed_market_daily_v1",
      currency: "PLN",
      status: "limited",
      limited_reason: "too_few_regular_retailers",
      fresh_regular_retailer_count: 1,
      fresh_lgs_count: 0,
      recent_sold_out_0_14_day_count: 0,
      sold_out_15_30_day_count: 0,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: 1,
      latest_nonfuture_checked_at: @as_of,
      calculated_at: @as_of,
      source_msrp_pln: Decimal.new("10"),
      source_evidence: [
        %{
          mapping_id: "worker-mapping-#{System.unique_integer([:positive])}",
          listing_id: "worker-listing-#{System.unique_integer([:positive])}",
          retailer_id: "worker-retailer-#{System.unique_integer([:positive])}",
          retailer_category: "regular_retailer",
          stock_status: "in_stock",
          confidence: Decimal.new("0.5"),
          approved_at: @as_of,
          price_pln: Decimal.new("10"),
          checked_at: @as_of
        }
      ]
    })
  end

  defp aggregate_job do
    %Oban.Job{
      args: %{},
      worker: Atom.to_string(SealedDailyAggregateWorker),
      queue: "sealed_aggregates",
      attempt: 1,
      max_attempts: 5,
      scheduled_at: @as_of,
      attempted_at: @as_of,
      inserted_at: @as_of
    }
  end

  defp product(msrp \\ nil) do
    attrs = %{
      slug: "guide-worker-#{System.unique_integer([:positive])}",
      name: "Guide Worker Product",
      product_type: "booster_box",
      officially_distributed: true,
      release_date: DateTime.to_date(@as_of),
      msrp_pln: msrp,
      msrp_source: if(msrp, do: "test", else: nil),
      description: "A complete guide worker sealed product record.",
      contents: ["36 booster packs"],
      pack_count: 36,
      cards_per_pack: 10,
      official_url: "https://www.pokemon.com/products/guide-worker",
      details_source: "Guide worker test catalogue",
      details_source_url: "https://www.pokemon.com/details/guide-worker",
      image_url: "https://assets.pokemon.com/guide-#{System.unique_integer([:positive])}.jpg",
      image_source: "Official product images",
      image_source_url: "https://www.pokemon.com/images/guide-worker"
    }

    draft = Core.create_sealed_product_draft!(attrs)

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp add_offer(product, suffix, price, opts \\ []) do
    retailer =
      Core.register_retailer!(%{
        slug: "guide-retailer-#{suffix}-#{System.unique_integer([:positive])}",
        source_key: "guide-source-#{suffix}-#{System.unique_integer([:positive])}",
        name: "Guide Shop",
        category: Keyword.get(opts, :category, "regular_retailer"),
        homepage_url: "https://shop.example"
      })

    listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: retailer.id,
        source_listing_id: "guide-listing-#{suffix}-#{System.unique_integer([:positive])}",
        source_title: "Guide Listing",
        direct_url: "https://shop.example/guide/#{suffix}",
        gtin: "4006381333931",
        current_price_pln: Decimal.new(price),
        stock_status: "in_stock",
        first_seen_at: @as_of,
        last_seen_at: @as_of,
        last_checked_at: @as_of
      })

    Core.create_matched_listing_mapping!(%{
      retailer_listing_id: listing.id,
      confirmed_product_id: product.id,
      confidence: Keyword.get(opts, :confidence, Decimal.new("1")),
      evidence: %{source: "test"}
    })

    Repo.query!(
      "UPDATE listing_product_mappings SET approved_at = $1 WHERE retailer_listing_id = $2",
      [@as_of, Ecto.UUID.dump!(listing.id)]
    )
  end

  defp record_ready(product, date, price, calculated_at \\ nil) do
    calculated_at = calculated_at || DateTime.new!(date, ~T[12:00:00])

    Core.record_sealed_daily_aggregate!(%{
      sealed_product_id: product.id,
      aggregate_date: date,
      calculation_version: "sealed_market_daily_v1",
      currency: "PLN",
      status: "ready",
      limited_reason: nil,
      benchmark_pln: Decimal.new(price),
      typical_low_pln: Decimal.sub(Decimal.new(price), Decimal.new("2")),
      typical_high_pln: Decimal.add(Decimal.new(price), Decimal.new("2")),
      fresh_regular_retailer_count: 5,
      fresh_lgs_count: 0,
      recent_sold_out_0_14_day_count: 0,
      sold_out_15_30_day_count: 0,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: 5,
      latest_nonfuture_checked_at: calculated_at,
      calculated_at: calculated_at
    })
  end

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
