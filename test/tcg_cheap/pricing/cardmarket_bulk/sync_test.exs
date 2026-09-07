Code.require_file("test/tcg_cheap/pricing/cardmarket_bulk/test_helper.exs")

defmodule TcgCheap.Pricing.CardmarketBulk.SyncTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Pricing.CardmarketBulk.{Batch, Price, Product, RawResponse, Sync}
  alias TcgCheap.Pricing.CardmarketBulk.{FakeAdapter, TestHelper}
  alias TcgCheap.Repo

  defp opts(
         fixture,
         now \\ ~U[2026-09-03 12:00:00Z],
         created_at \\ ~U[2026-09-03 10:00:00Z],
         product_id \\ nil
       ) do
    product_id = product_id || System.unique_integer([:positive])

    [
      adapter: FakeAdapter,
      adapter_options: [
        request_options: [fixture: fixture, product_id: product_id, created_at: created_at]
      ],
      request_admitter: fn ->
        send(self(), :admitted)
        :ok
      end,
      clock: fn -> now end,
      completion_clock: fn -> DateTime.add(now, 1, :hour) end
    ]
  end

  defp count(table), do: Repo.one!(from r in table, select: count(r.id))

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

  test "writes one complete batch, gzip evidence, and latest staging, and admits both fetches" do
    assert {:ok, %{batch: batch, persisted?: true}} = Sync.run(opts(:good))
    assert_receive :admitted
    assert_receive :admitted
    refute_receive :admitted
    assert count(Batch) == 2
    assert count(RawResponse) == 2
    assert count(Product) == 1
    assert count(Price) == 1

    products =
      Ash.Query.for_read(RawResponse, :read, %{})
      |> Ash.Query.select([:endpoint_kind, :source_url, :body, :sha256])
      |> Ash.read!(authorize?: false)

    assert Enum.map(products, & &1.source_url) |> Enum.sort() == [
             TestHelper.price_url(),
             TestHelper.product_url()
           ]

    for raw <- products do
      body = :zlib.gunzip(raw.body)
      assert byte_size(body) > 0
      assert raw.sha256 == :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    end

    assert DateTime.compare(batch.product_created_at, ~U[2026-09-03 10:00:00Z]) == :eq

    assert Product
           |> Ash.Query.for_read(:read, %{})
           |> Ash.read!(authorize?: false)
           |> Enum.map(& &1.last_batch_id) == [batch.id]

    assert Price
           |> Ash.Query.for_read(:read, %{})
           |> Ash.read!(authorize?: false)
           |> Enum.map(& &1.last_batch_id) == [batch.id]
  end

  test "stages an unavailable price with null selected metric and value" do
    assert {:ok, %{batch: batch}} = Sync.run(opts(:unavailable))

    [price] = Ash.read!(Ash.Query.for_read(Price, :read, %{}), authorize?: false)
    assert price.last_batch_id == batch.id
    assert is_nil(price.selected_metric)
    assert is_nil(price.selected_value_eur)
  end

  test "an exact rerun is idempotent" do
    run_opts = opts(:good)
    assert {:ok, first} = Sync.run(run_opts)
    assert {:ok, second} = Sync.run(run_opts)
    assert first.batch.id == second.batch.id
    refute second.persisted?
    assert count(Batch) == 2
    assert count(RawResponse) == 2
    assert count(Product) == 1
    assert count(Price) == 1
  end

  test "a product and price identity mismatch creates nothing" do
    assert {:error, {:identity_mismatch, _, _, _}} = Sync.run(opts(:mismatch))
    assert count(Batch) == 1
    assert Enum.all?([RawResponse, Product, Price], &(count(&1) == 0))
  end

  test "a staging failure preserves failed lifecycle evidence and rolls back projection" do
    assert {:error, _} = Sync.run(opts(:invalid_product))
    assert count(Batch) == 2
    assert count(RawResponse) == 2
    assert Enum.all?([Product, Price], &(count(&1) == 0))

    batch =
      Batch
      |> Ash.Query.for_read(:read, %{})
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.status == "failed"))

    assert batch.status == "failed"
    assert batch.failure_summary == "cardmarket bulk pipeline failed"
  end

  test "an older upstream source is rejected after a newer batch" do
    first_opts = opts(:good)

    product_id =
      get_in(first_opts, [:adapter_options, :request_options]) |> Keyword.fetch!(:product_id)

    assert {:ok, _} = Sync.run(first_opts)

    assert {:error, {:stale_source_batch, _}} =
             Sync.run(opts(:good, ~U[2026-09-03 13:00:00Z], ~U[2026-09-03 09:00:00Z], product_id))

    assert count(Batch) == 2
  end

  test "rejects every row-count anomaly without changing the successful projection" do
    product_id = System.unique_integer([:positive])

    assert {:ok, %{batch: baseline}} =
             Sync.run(opts(:good, ~U[2026-09-03 12:00:00Z], ~U[2026-09-03 10:00:00Z], product_id))

    [product_before] = Ash.read!(Ash.Query.for_read(Product, :read, %{}), authorize?: false)
    [price_before] = Ash.read!(Ash.Query.for_read(Price, :read, %{}), authorize?: false)

    for anomaly <- [
          :product_row_count,
          :price_row_count,
          :singles_price_row_count,
          :priceable_singles_count
        ] do
      assert {:error, {:malformed, {:row_count_anomaly, ^anomaly}}} =
               Sync.run(
                 opts(
                   {:anomaly, anomaly},
                   ~U[2026-09-03 13:00:00Z],
                   ~U[2026-09-03 11:00:00Z],
                   product_id
                 )
               )
    end

    assert count(Batch) == 2
    assert count(RawResponse) == 2
    [product_after] = Ash.read!(Ash.Query.for_read(Product, :read, %{}), authorize?: false)
    [price_after] = Ash.read!(Ash.Query.for_read(Price, :read, %{}), authorize?: false)

    assert {product_after.last_batch_id, product_after.name} ==
             {product_before.last_batch_id, product_before.name}

    assert {price_after.last_batch_id, price_after.selected_value_eur} ==
             {price_before.last_batch_id, price_before.selected_value_eur}

    assert baseline.status == "succeeded"
  end

  test "after-stage failure rolls back callback and projection writes but retains failed batch" do
    parent = self()

    callback = fn _batch ->
      Repo.query!("UPDATE cardmarket_bulk_products SET name = name")
      send(parent, :callback_mutated_database)

      {:error, :callback_failed}
    end

    assert {:error, :callback_failed} = Sync.run(Keyword.put(opts(:good), :after_stage, callback))
    assert_receive :callback_mutated_database
    assert count(Product) == 0
    assert count(Price) == 0
    assert count(Batch) == 2
    assert count(RawResponse) == 2

    [failed] =
      Ash.read!(Ash.Query.for_read(Batch, :read, %{}), authorize?: false)
      |> Enum.filter(&(&1.status == "failed"))

    assert failed.failure_summary == "cardmarket bulk pipeline failed"
  end

  test "rerunning an exact failed identity reuses evidence and promotes" do
    run_opts = opts(:good)
    failing = Keyword.put(run_opts, :after_stage, fn _ -> {:error, :nope} end)
    assert {:error, :nope} = Sync.run(failing)

    [failed_batch] =
      Ash.read!(Ash.Query.for_read(Batch, :read, %{}), authorize?: false)
      |> Enum.filter(&(&1.status == "failed"))

    assert {:ok, %{batch: batch, persisted?: true}} = Sync.run(run_opts)
    assert batch.id == failed_batch.id
    assert batch.status == "succeeded"
    assert count(Batch) == 2
    assert count(RawResponse) == 2
  end

  test "reuses product evidence across a new price batch but stores changed price evidence" do
    product_id = System.unique_integer([:positive])

    assert {:ok, first} =
             Sync.run(opts(:good, ~U[2026-09-03 12:00:00Z], ~U[2026-09-03 10:00:00Z], product_id))

    [product_raw] =
      Ash.read!(Ash.Query.for_read(RawResponse, :read, %{}), authorize?: false)
      |> Enum.filter(&(&1.endpoint_kind == "products"))

    assert {:ok, _} =
             Sync.run(
               opts(
                 {:sha, product_raw.sha256, String.duplicate("d", 64)},
                 ~U[2026-09-03 13:00:00Z],
                 ~U[2026-09-03 11:00:00Z],
                 product_id
               )
             )

    assert count(RawResponse) == 3
    assert first.batch.id != nil
    changed = String.duplicate("e", 64)

    assert {:ok, _} =
             Sync.run(
               opts(
                 {:sha, changed, String.duplicate("f", 64)},
                 ~U[2026-09-03 14:00:00Z],
                 ~U[2026-09-03 12:00:00Z],
                 product_id
               )
             )

    assert count(RawResponse) == 5
  end

  test "completion clock runs after callback and stores its exact UTC value" do
    parent = self()
    completion = ~U[2026-09-03 14:00:00Z]

    callback = fn _ ->
      send(parent, :callback_done)
      :ok
    end

    run_opts =
      opts(:good)
      |> Keyword.put(:after_stage, callback)
      |> Keyword.put(:completion_clock, fn ->
        send(parent, :completion_clock_called)
        completion
      end)

    assert {:ok, %{batch: batch}} = Sync.run(run_opts)

    assert_receive :callback_done
    assert_receive :completion_clock_called
    assert DateTime.compare(batch.completed_at, completion) == :eq

    invalid_opts =
      Keyword.put(
        opts(:good, ~U[2026-09-03 15:00:00Z], ~U[2026-09-03 13:00:00Z]),
        :completion_clock,
        fn -> DateTime.from_naive!(~N[2026-09-03 15:00:00], "Europe/Warsaw") end
      )

    assert {:error, {:malformed, :invalid_completion_clock}} = Sync.run(invalid_opts)

    [failed] =
      Ash.read!(Ash.Query.for_read(Batch, :read, %{}), authorize?: false)
      |> Enum.filter(&(&1.status == "failed"))

    assert failed.completed_at != nil
  end

  test "exact succeeded rerun never invokes after-stage" do
    run_opts = opts(:good)
    assert {:ok, _} = Sync.run(run_opts)
    callback = fn _ -> raise "must not run" end

    assert {:ok, %{persisted?: false}} =
             Sync.run(Keyword.put(run_opts, :after_stage, callback))
  end
end
