defmodule TcgCheap.Pricing.SealedDailyAggregateWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Repo

  alias TcgCheap.Pricing.{
    SealedBuyingGuideWorker,
    SealedDailyAggregateRevision,
    SealedDailyAggregateWorker
  }

  @as_of ~U[2026-08-09 12:00:00Z]
  @version "sealed_market_daily_v1"

  setup do
    previous = Application.get_env(:tcg_cheap, :sealed_daily_aggregate_clock)
    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, fn -> @as_of end)
    on_exit(fn -> Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, previous) end)
    :ok
  end

  test "uses canonical empty args, queue, and active uniqueness" do
    first = Oban.insert!(SealedDailyAggregateWorker.new(%{}))
    second = Oban.insert!(SealedDailyAggregateWorker.new(%{}))
    assert first.id == second.id
    assert first.queue == "sealed_aggregates"
    assert first.args == %{}
    assert first.max_attempts == 5
    assert {:cancel, :malformed_job_args} = perform_job(job(%{"unexpected" => true}), [])
  end

  test "configures one worker and both ordered daily cron entries" do
    oban = Application.fetch_env!(:tcg_cheap, Oban)
    assert Keyword.get(oban, :queues)[:sealed_aggregates] == 1
    assert Keyword.get(oban, :queues)[:sealed_buying_guides] == 1

    crontab =
      oban
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, options} -> Keyword.fetch!(options, :crontab)
        _ -> nil
      end)

    assert {"*/15 * * * *", TcgCheap.Catalogue.SinglesScopeBootstrapWorker,
            [args: %{"policy_version" => 2}]} =
             Enum.at(crontab, 0)

    assert {"0 14 * * *", TcgCheap.Pricing.Singles.ValuationRefreshWorker, [args: %{}]} =
             Enum.at(crontab, 1)

    assert {"0 15 * * *", TcgCheap.Pricing.ExchangeRateWorker, [args: nbp_args]} =
             Enum.at(crontab, 2)

    assert nbp_args == %{source: "nbp", table: "A", base_currency: "EUR", quote_currency: "PLN"}
    assert {"0 16 * * *", SealedDailyAggregateWorker, [args: %{}]} = Enum.at(crontab, 3)
  end

  test "cancels malformed clock configuration and clock results" do
    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, :bad)
    assert {:cancel, :invalid_clock_configuration} = perform_job(job(), [])
    refute_enqueued(repo: TcgCheap.Repo, worker: SealedBuyingGuideWorker)
    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, fn -> ~D[2026-08-09] end)
    assert {:cancel, :invalid_clock} = perform_job(job(), [])
  end

  test "skips products with no mappings without creating fake history" do
    product = product()
    assert :ok = perform_job(job(), [])
    refute_enqueued(repo: TcgCheap.Repo, worker: SealedBuyingGuideWorker)

    assert {:ok, nil} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               @version,
               DateTime.to_date(@as_of)
             )
  end

  test "skips mappings approved after the captured as-of time" do
    product = product()
    add_offer(product, "future", "10")

    Repo.query!(
      "UPDATE listing_product_mappings SET approved_at = $1 WHERE confirmed_product_id = $2",
      [
        DateTime.add(@as_of, 1, :second),
        Ecto.UUID.dump!(product.id)
      ]
    )

    assert :ok = perform_job(job(), [])
    refute_enqueued(repo: TcgCheap.Repo, worker: SealedBuyingGuideWorker)

    assert {:ok, nil} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               @version,
               DateTime.to_date(@as_of)
             )
  end

  test "rolls back an aggregate when guide enqueue fails" do
    previous = Application.get_env(:tcg_cheap, :sealed_daily_aggregate_enqueue)

    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_enqueue, fn _ ->
      {:error, :injected}
    end)

    on_exit(fn -> restore_env(:sealed_daily_aggregate_enqueue, previous) end)

    product = product()
    add_offer(product, "enqueue-failure", "10")
    assert {:error, :guide_enqueue_failed} = perform_job(job(), [])

    assert {:ok, nil} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               @version,
               DateTime.to_date(@as_of)
             )
  end

  test "historical aggregate changes enqueue every guide that consumes the changed day" do
    historical_as_of = DateTime.add(@as_of, -7, :day)
    product = product()
    add_offer(product, "historical-dependent", "10")

    Repo.query!(
      "UPDATE listing_product_mappings SET approved_at = $1 WHERE confirmed_product_id = $2",
      [historical_as_of, Ecto.UUID.dump!(product.id)]
    )

    future =
      Core.record_sealed_daily_aggregate!(%{
        sealed_product_id: product.id,
        aggregate_date: DateTime.to_date(@as_of),
        calculation_version: @version,
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

    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, fn -> historical_as_of end)

    assert :ok = perform_job(job(), [])

    assert {:ok, historical} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               @version,
               DateTime.to_date(historical_as_of)
             )

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SealedBuyingGuideWorker,
      args: guide_args(historical)
    )

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SealedBuyingGuideWorker,
      args: guide_args(future)
    )
  end

  test "persists limited and ready aggregates and remains idempotent" do
    limited_product = product()
    add_offer(limited_product, "limited", "10")
    assert :ok = perform_job(job(), [])

    assert {:ok, limited} =
             Core.get_latest_sealed_daily_aggregate(
               limited_product.id,
               @version,
               DateTime.to_date(@as_of)
             )

    assert limited.status == "limited"
    assert limited.limited_reason == "too_few_regular_retailers"
    assert limited.source_msrp_pln == nil

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SealedBuyingGuideWorker,
      args: guide_args(limited)
    )

    assert [%{mapping_id: mapping_id, listing_id: listing_id, price_pln: %Decimal{}}] =
             limited.source_evidence

    assert is_binary(mapping_id) and is_binary(listing_id)

    ready_product = product()
    for index <- 1..5, do: add_offer(ready_product, "ready-#{index}", Integer.to_string(index))
    assert :ok = perform_job(job(), [])

    assert {:ok, ready} =
             Core.get_latest_sealed_daily_aggregate(
               ready_product.id,
               @version,
               DateTime.to_date(@as_of)
             )

    assert ready.status == "ready"
    assert length(ready.source_evidence) == 5
    assert_enqueued(repo: TcgCheap.Repo, worker: SealedBuyingGuideWorker, args: guide_args(ready))

    assert Enum.all?(
             ready.source_evidence,
             &match?(%{mapping_id: _, retailer_id: _, price_pln: %Decimal{}}, &1)
           )

    assert Decimal.equal?(ready.benchmark_pln, Decimal.new("3.00"))
    assert :ok = perform_job(job(), [])

    assert {:ok, history} =
             Core.list_sealed_daily_aggregate_history(
               ready_product.id,
               @version,
               Date.add(DateTime.to_date(@as_of), -30),
               DateTime.to_date(@as_of)
             )

    assert length(history) == 1
  end

  test "aggregate revision fingerprint ignores evidence ordering but tracks price and identity changes" do
    product = product()
    add_offer(product, "fingerprint", "10")
    assert :ok = perform_job(job(), [])

    assert {:ok, aggregate} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               @version,
               DateTime.to_date(@as_of)
             )

    assert {:ok, fingerprint} = SealedDailyAggregateRevision.fingerprint(aggregate)

    assert {:ok, reordered} =
             SealedDailyAggregateRevision.fingerprint(%{
               aggregate
               | source_evidence: Enum.reverse(aggregate.source_evidence)
             })

    assert reordered == fingerprint

    [row | rest] = aggregate.source_evidence

    assert {:ok, changed_price} =
             SealedDailyAggregateRevision.fingerprint(%{
               aggregate
               | source_evidence: [
                   %{row | price_pln: Decimal.add(row.price_pln, Decimal.new("1"))} | rest
                 ]
             })

    refute changed_price == fingerprint

    assert {:ok, changed_identity} =
             SealedDailyAggregateRevision.fingerprint(%{
               aggregate
               | source_evidence: [%{row | listing_id: "different-listing"} | rest]
             })

    refute changed_identity == fingerprint
  end

  test "aggregate revision canonicalizes decimal scale and datetime precision" do
    product = product()
    add_offer(product, "canonical", "10")
    assert :ok = perform_job(job(), [])

    {:ok, aggregate} =
      Core.get_latest_sealed_daily_aggregate(product.id, @version, DateTime.to_date(@as_of))

    {:ok, fingerprint} = SealedDailyAggregateRevision.fingerprint(aggregate)
    [row] = aggregate.source_evidence

    equivalent = %{
      aggregate
      | source_evidence: [
          %{
            row
            | price_pln: Decimal.new("10.00"),
              checked_at: %{row.checked_at | microsecond: {0, 0}}
          }
        ]
    }

    assert {:ok, ^fingerprint} = SealedDailyAggregateRevision.fingerprint(equivalent)

    assert {:error, :malformed_aggregate_revision} =
             SealedDailyAggregateRevision.fingerprint(%{aggregate | currency: <<255>>})

    assert {:error, :malformed_aggregate_revision} =
             SealedDailyAggregateRevision.fingerprint(%{
               aggregate
               | currency: %{unsupported: true}
             })
  end

  defp job(args \\ %{}) do
    %Oban.Job{
      args: args,
      worker: Atom.to_string(SealedDailyAggregateWorker),
      queue: "sealed_aggregates",
      attempt: 1,
      max_attempts: 5,
      scheduled_at: @as_of,
      attempted_at: @as_of,
      inserted_at: @as_of
    }
  end

  defp guide_args(aggregate) do
    {:ok, changeset} = SealedBuyingGuideWorker.new_for_aggregate(aggregate)
    changeset.changes.args
  end

  defp product do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "worker-#{System.unique_integer([:positive])}",
        name: "Worker Product",
        product_type: "booster_box",
        officially_distributed: true,
        release_date: DateTime.to_date(@as_of)
      })

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp add_offer(product, suffix, price) do
    retailer =
      Core.register_retailer!(%{
        slug: "worker-retailer-#{suffix}-#{System.unique_integer([:positive])}",
        source_key: "worker-source-#{suffix}-#{System.unique_integer([:positive])}",
        name: "Worker Shop",
        category: "regular_retailer",
        homepage_url: "https://shop.example"
      })

    listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: retailer.id,
        source_listing_id: "worker-listing-#{suffix}-#{System.unique_integer([:positive])}",
        source_title: "Worker Listing",
        direct_url: "https://shop.example/worker/#{suffix}",
        gtin: "4006381333931",
        current_price_pln: Decimal.new(price),
        stock_status: "in_stock",
        first_seen_at: @as_of,
        last_seen_at: @as_of,
        last_checked_at: @as_of
      })

    mapping =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing.id,
        confirmed_product_id: product.id,
        confidence: Decimal.new("1"),
        evidence: %{source: "test"}
      })

    assert %DateTime{} = mapping.approved_at

    Repo.query!("UPDATE listing_product_mappings SET approved_at = $1 WHERE id = $2", [
      @as_of,
      Ecto.UUID.dump!(mapping.id)
    ])
  end

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
