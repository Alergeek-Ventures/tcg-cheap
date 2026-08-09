defmodule TcgCheap.Pricing.SealedDailyAggregateTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core
  alias TcgCheap.Repo

  @version "sealed_market_daily_v1"

  test "app invariants reject invalid state, counts, prices, and future dates" do
    product = product()

    for overrides <- [
          %{currency: "EUR"},
          %{
            status: "ready",
            limited_reason: "too_few_regular_retailers",
            benchmark_pln: nil,
            typical_low_pln: nil,
            typical_high_pln: nil
          },
          %{status: "limited", limited_reason: nil},
          %{fresh_regular_retailer_count: 4},
          %{latest_nonfuture_checked_at: nil},
          %{latest_nonfuture_checked_at: ~U[2026-08-08 13:00:00Z]},
          %{fresh_lgs_count: -1},
          %{unique_source_retailer_count: 5},
          %{
            status: "limited",
            limited_reason: "too_few_regular_retailers",
            benchmark_pln: nil,
            typical_low_pln: nil,
            typical_high_pln: nil
          },
          %{
            benchmark_pln: "NaN",
            typical_low_pln: Decimal.new("1"),
            typical_high_pln: Decimal.new("2")
          },
          %{aggregate_date: ~D[2026-08-10]}
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.record_sealed_daily_aggregate(attrs(product, overrides))
    end
  end

  test "upserts same identity, protects newer data from stale writes, and retains versions" do
    product = product()
    date = ~D[2026-08-08]

    newer =
      attrs(product, %{
        aggregate_date: date,
        calculated_at: ~U[2026-08-08 13:00:00Z],
        benchmark_pln: Decimal.new("14")
      })

    older = %{newer | calculated_at: ~U[2026-08-08 12:00:00Z], benchmark_pln: Decimal.new("11")}

    assert {:ok, first} = Core.record_sealed_daily_aggregate(newer)
    assert {:error, %Ash.Error.Invalid{}} = Core.record_sealed_daily_aggregate(older)
    assert {:ok, same} = Core.get_latest_sealed_daily_aggregate(product.id, @version, date)
    assert same.id == first.id
    assert Decimal.equal?(same.benchmark_pln, Decimal.new("14"))

    assert {:ok, _v2} =
             Core.record_sealed_daily_aggregate(
               attrs(product, %{
                 aggregate_date: date,
                 calculation_version: "sealed_market_daily_v2",
                 benchmark_pln: Decimal.new("13")
               })
             )

    assert {:ok, latest} = Core.get_latest_sealed_daily_aggregate(product.id, @version, date)
    assert latest.calculation_version == @version
    assert Decimal.equal?(latest.benchmark_pln, Decimal.new("14"))
  end

  test "same-day same-version upsert accepts a newer calculation then rejects a stale regression" do
    product = product()

    older =
      attrs(product, %{
        calculated_at: ~U[2026-08-08 10:00:00Z],
        latest_nonfuture_checked_at: ~U[2026-08-08 09:00:00Z],
        benchmark_pln: Decimal.new("11")
      })

    newer = %{older | calculated_at: ~U[2026-08-08 11:00:00Z], benchmark_pln: Decimal.new("14")}
    stale = %{older | calculated_at: ~U[2026-08-08 09:00:00Z], benchmark_pln: Decimal.new("10")}

    assert {:ok, initial} = Core.record_sealed_daily_aggregate(older)
    assert {:ok, updated} = Core.record_sealed_daily_aggregate(newer)
    assert updated.id == initial.id
    assert Decimal.equal?(updated.benchmark_pln, Decimal.new("14"))
    assert {:error, %Ash.Error.Invalid{}} = Core.record_sealed_daily_aggregate(stale)

    assert {:ok, current} =
             Core.get_latest_sealed_daily_aggregate(product.id, @version, ~D[2026-08-08])

    assert Decimal.equal?(current.benchmark_pln, Decimal.new("14"))
    assert DateTime.compare(current.calculated_at, newer.calculated_at) == :eq
  end

  test "database constraints reject malformed rows and restrict parent deletion" do
    product = product()

    assert_db_rejects(
      attrs(product, %{
        status: "ready",
        limited_reason: "too_few_regular_retailers",
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil
      })
    )

    assert_db_rejects(attrs(product, %{fresh_lgs_count: -1}))
    assert_db_rejects(attrs(product, %{unique_source_retailer_count: 5}))

    assert_db_rejects(
      attrs(product, %{
        status: "limited",
        limited_reason: "too_few_regular_retailers",
        benchmark_pln: nil,
        typical_low_pln: nil,
        typical_high_pln: nil
      })
    )

    assert {:ok, _} =
             Repo.query(
               "INSERT INTO sealed_daily_aggregates (sealed_product_id, aggregate_date, calculation_version, currency, status, benchmark_pln, typical_low_pln, typical_high_pln, fresh_regular_retailer_count, fresh_lgs_count, recent_sold_out_0_14_day_count, sold_out_15_30_day_count, stale_or_future_current_offer_count, unique_source_retailer_count, latest_nonfuture_checked_at, calculated_at) VALUES ($1, $2, $3, $4, $5, '12', '10', '15', 5, 1, 0, 0, 0, 6, $6, $7)",
               [
                 Ecto.UUID.dump!(product.id),
                 ~D[2026-08-08],
                 @version,
                 "PLN",
                 "ready",
                 ~U[2026-08-08 11:00:00Z],
                 ~U[2026-08-08 12:00:00Z]
               ]
             )

    for {column, value} <- [
          {"fresh_regular_retailer_count", "4"},
          {"unique_source_retailer_count", "5"},
          {"latest_nonfuture_checked_at", "NULL"},
          {"latest_nonfuture_checked_at", "'2026-08-08 13:00:00+00'"}
        ] do
      assert {:error, %Postgrex.Error{}} =
               Repo.query(
                 "UPDATE sealed_daily_aggregates SET #{column} = #{value} WHERE sealed_product_id = $1",
                 [Ecto.UUID.dump!(product.id)]
               )
    end

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_daily_aggregates SET benchmark_pln = 'NaN'::numeric WHERE sealed_product_id = $1",
               [Ecto.UUID.dump!(product.id)]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_daily_aggregates SET aggregate_date = $2 WHERE sealed_product_id = $1",
               [Ecto.UUID.dump!(product.id), ~D[2026-08-10]]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "INSERT INTO sealed_daily_aggregates (sealed_product_id, aggregate_date, calculation_version, currency, status, benchmark_pln, typical_low_pln, typical_high_pln, fresh_regular_retailer_count, fresh_lgs_count, recent_sold_out_0_14_day_count, sold_out_15_30_day_count, stale_or_future_current_offer_count, unique_source_retailer_count, calculated_at) VALUES ($1, $2, $3, $4, $5, '12', '10', '15', 5, 1, 0, 0, 0, 1, $6)",
               [
                 Ecto.UUID.dump!(Ecto.UUID.generate()),
                 ~D[2026-08-08],
                 @version,
                 "PLN",
                 "ready",
                 ~U[2026-08-08 12:00:00Z]
               ]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query("DELETE FROM sealed_products WHERE id = $1", [Ecto.UUID.dump!(product.id)])
  end

  test "latest and history are explicitly versioned, bounded, and deterministic" do
    product = product()

    for {date, calculated_at} <- [
          {~D[2026-08-01], ~U[2026-08-01 10:00:00Z]},
          {~D[2026-08-02], ~U[2026-08-02 10:00:00Z]},
          {~D[2026-08-03], ~U[2026-08-03 10:00:00Z]}
        ] do
      assert {:ok, _} =
               Core.record_sealed_daily_aggregate(
                 attrs(product, %{
                   aggregate_date: date,
                   calculated_at: calculated_at,
                   latest_nonfuture_checked_at: DateTime.add(calculated_at, -60, :second)
                 })
               )
    end

    assert {:ok, history} =
             Core.list_sealed_daily_aggregate_history(
               product.id,
               @version,
               ~D[2026-08-01],
               ~D[2026-08-02]
             )

    assert Enum.map(history, & &1.aggregate_date) == [~D[2026-08-01], ~D[2026-08-02]]

    assert {:ok, nil} =
             Core.get_latest_sealed_daily_aggregate(
               product.id,
               "sealed_market_daily_v2",
               ~D[2026-08-03]
             )
  end

  test "latest ready lookup preserves a usable snapshot after a limited day" do
    product = product()

    assert {:ok, ready} =
             Core.record_sealed_daily_aggregate(
               attrs(product, %{
                 aggregate_date: ~D[2026-08-01],
                 latest_nonfuture_checked_at: ~U[2026-08-01 11:00:00Z],
                 calculated_at: ~U[2026-08-01 12:00:00Z]
               })
             )

    assert {:ok, limited} =
             Core.record_sealed_daily_aggregate(
               attrs(product, %{
                 status: "limited",
                 limited_reason: "too_few_regular_retailers",
                 benchmark_pln: nil,
                 typical_low_pln: nil,
                 typical_high_pln: nil,
                 fresh_regular_retailer_count: 4
               })
             )

    assert {:ok, latest} =
             Core.get_latest_sealed_daily_aggregate(product.id, @version, ~D[2026-08-08])

    assert latest.id == limited.id

    assert {:ok, latest_ready} =
             Core.get_latest_ready_sealed_daily_aggregate(
               product.id,
               @version,
               ~D[2026-08-08]
             )

    assert latest_ready.id == ready.id
  end

  defp product do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "aggregate-#{System.unique_integer([:positive])}",
        name: "Aggregate Product",
        product_type: "booster_box",
        officially_distributed: true,
        release_date: ~D[2026-08-01]
      })

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp attrs(product, overrides) do
    Map.merge(
      %{
        sealed_product_id: product.id,
        aggregate_date: ~D[2026-08-08],
        calculation_version: @version,
        currency: "PLN",
        status: "ready",
        limited_reason: nil,
        benchmark_pln: Decimal.new("12.00"),
        typical_low_pln: Decimal.new("10.00"),
        typical_high_pln: Decimal.new("15.00"),
        fresh_regular_retailer_count: 5,
        fresh_lgs_count: 1,
        recent_sold_out_0_14_day_count: 2,
        sold_out_15_30_day_count: 1,
        stale_or_future_current_offer_count: 0,
        unique_source_retailer_count: 6,
        latest_nonfuture_checked_at: ~U[2026-08-08 11:00:00Z],
        calculated_at: ~U[2026-08-08 12:00:00Z]
      },
      overrides
    )
  end

  defp assert_db_rejects(values) do
    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "INSERT INTO sealed_daily_aggregates (sealed_product_id, aggregate_date, calculation_version, currency, status, limited_reason, benchmark_pln, typical_low_pln, typical_high_pln, fresh_regular_retailer_count, fresh_lgs_count, recent_sold_out_0_14_day_count, sold_out_15_30_day_count, stale_or_future_current_offer_count, unique_source_retailer_count, latest_nonfuture_checked_at, calculated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)",
               Enum.map(
                 [
                   :sealed_product_id,
                   :aggregate_date,
                   :calculation_version,
                   :currency,
                   :status,
                   :limited_reason,
                   :benchmark_pln,
                   :typical_low_pln,
                   :typical_high_pln,
                   :fresh_regular_retailer_count,
                   :fresh_lgs_count,
                   :recent_sold_out_0_14_day_count,
                   :sold_out_15_30_day_count,
                   :stale_or_future_current_offer_count,
                   :unique_source_retailer_count,
                   :latest_nonfuture_checked_at,
                   :calculated_at
                 ],
                 fn
                   :sealed_product_id -> Ecto.UUID.dump!(Map.fetch!(values, :sealed_product_id))
                   key -> Map.fetch!(values, key)
                 end
               )
             )
  end
end
