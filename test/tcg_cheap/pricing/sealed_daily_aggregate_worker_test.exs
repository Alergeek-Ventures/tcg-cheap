defmodule TcgCheap.Pricing.SealedDailyAggregateWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedDailyAggregateWorker

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
    assert {:cancel, :malformed_job_args} = perform_job(job(%{"unexpected" => true}), [])
  end

  test "configures one worker and both ordered daily cron entries" do
    oban = Application.fetch_env!(:tcg_cheap, Oban)
    assert Keyword.get(oban, :queues)[:sealed_aggregates] == 1

    crontab =
      oban
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, options} -> Keyword.fetch!(options, :crontab)
        _ -> nil
      end)

    assert {"0 15 * * *", TcgCheap.Pricing.ExchangeRateWorker, [args: nbp_args]} =
             Enum.at(crontab, 0)

    assert nbp_args == %{source: "nbp", table: "A", base_currency: "EUR", quote_currency: "PLN"}
    assert {"0 16 * * *", SealedDailyAggregateWorker, [args: %{}]} = Enum.at(crontab, 1)
  end

  test "cancels malformed clock configuration and clock results" do
    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, :bad)
    assert {:cancel, :invalid_clock_configuration} = perform_job(job(), [])
    Application.put_env(:tcg_cheap, :sealed_daily_aggregate_clock, fn -> ~D[2026-08-09] end)
    assert {:cancel, :invalid_clock} = perform_job(job(), [])
  end

  test "skips products with no mappings without creating fake history" do
    product = product()
    assert :ok = perform_job(job(), [])

    assert {:ok, nil} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               @version,
               DateTime.to_date(@as_of)
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
  end
end
