defmodule TcgCheap.Pricing.SealedBuyingGuideSnapshotTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedDailyAggregateRevision
  alias TcgCheap.Repo

  @version "sealed_buying_model_v1"
  @calculated ~U[2026-08-08 12:00:00Z]

  test "accepts ready and limited model output while retaining limited reference and centers" do
    product = product()
    aggregate = aggregate(product)

    assert {:ok, ready} =
             Core.record_sealed_buying_guide_snapshot(ready_attrs(product, aggregate))

    assert ready.status == "ready"

    assert {:ok, limited} =
             Core.record_sealed_buying_guide_snapshot(
               limited_attrs(product, aggregate, %{
                 reference_price_pln: d("99"),
                 regular_benchmark_pln: d("100")
               })
             )

    assert limited.status == "limited"
    assert limited.reference_price_pln == d("99")
    assert limited.regular_benchmark_pln == d("100")
  end

  test "rejects malformed state, money, time, confidence, and factors" do
    product = product()
    aggregate = aggregate(product)

    for overrides <- [
          %{model_version: "model_v1"},
          %{currency: "EUR"},
          %{status: "ready", limited_reason: "low_confidence"},
          %{status: "limited", limited_reason: "nope"},
          %{great_price_max_pln: d("20"), fair_price_max_pln: d("19")},
          %{confidence: d("1.1")},
          %{explanation_factors: []},
          %{explanation_factors: ["unknown"]},
          %{explanation_factors: ["market_benchmark", "market_benchmark"]},
          %{expected_source_aggregate_date: ~D[2026-08-09]},
          %{calculated_at: DateTime.add(@calculated, -1, :second)},
          %{trend: "insufficient_history", trend_change: d("0.1")},
          %{trend: "stable", trend_change: d("-1")}
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.record_sealed_buying_guide_snapshot(
                 Map.merge(ready_attrs(product, aggregate), overrides)
               )
    end
  end

  test "upserts newer calculations, rejects stale calculations, and preserves date/version history" do
    product = product()
    aggregate = aggregate(product)
    attrs = ready_attrs(product, aggregate)
    assert {:ok, first} = Core.record_sealed_buying_guide_snapshot(attrs)

    assert {:ok, newer} =
             Core.record_sealed_buying_guide_snapshot(%{
               attrs
               | calculated_at: ~U[2026-08-08 13:00:00Z],
                 reference_price_pln: d("14")
             })

    assert newer.id == first.id
    assert newer.reference_price_pln == d("14")

    assert {:error, %Ash.Error.Invalid{}} =
             Core.record_sealed_buying_guide_snapshot(%{
               attrs
               | calculated_at: ~U[2026-08-08 11:00:00Z]
             })

    assert {:ok, _v2} =
             Core.record_sealed_buying_guide_snapshot(%{
               attrs
               | model_version: "sealed_buying_model_v2"
             })

    next_aggregate = aggregate(product, ~D[2026-08-09])

    assert {:ok, _limited} =
             Core.record_sealed_buying_guide_snapshot(
               limited_attrs(product, next_aggregate, %{reference_price_pln: d("99")})
             )

    assert {:ok, latest_limited} =
             Core.get_latest_sealed_buying_guide_snapshot(product.id, @version, ~D[2026-08-09])

    assert latest_limited.status == "limited"

    assert {:ok, latest_ready} =
             Core.get_latest_ready_sealed_buying_guide_snapshot(
               product.id,
               @version,
               ~D[2026-08-09]
             )

    assert latest_ready.id == first.id

    assert {:ok, history} =
             Core.list_sealed_buying_guide_snapshot_history(
               product.id,
               @version,
               ~D[2026-08-08],
               ~D[2026-08-09]
             )

    assert Enum.map(history, & &1.guide_date) == [~D[2026-08-08], ~D[2026-08-09]]
  end

  test "derives product from source aggregate instead of caller input" do
    source_product = product()
    other_product = product()
    aggregate = aggregate(source_product)

    assert {:ok, snapshot} =
             Core.record_sealed_buying_guide_snapshot(ready_attrs(source_product, aggregate))

    assert snapshot.sealed_product_id == source_product.id
    assert snapshot.source_aggregate_calculated_at == aggregate.calculated_at

    assert {:error, %Ash.Error.Invalid{}} =
             Core.record_sealed_buying_guide_snapshot(
               ready_attrs(source_product, aggregate)
               |> Map.put(:sealed_product_id, other_product.id)
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Core.record_sealed_buying_guide_snapshot(
               ready_attrs(source_product, aggregate)
               |> Map.put(
                 :expected_source_aggregate_calculated_at,
                 DateTime.add(@calculated, 1, :second)
               )
             )
  end

  test "rejects stale or mismatched expected aggregate revisions" do
    product = product()
    aggregate = aggregate(product)
    attrs = ready_attrs(product, aggregate)

    for overrides <- [
          %{expected_source_aggregate_date: ~D[2026-08-07]},
          %{expected_source_aggregate_calculated_at: DateTime.add(@calculated, 1, :second)},
          %{expected_source_aggregate_fingerprint: String.duplicate("0", 64)},
          %{expected_source_history_fingerprint: String.duplicate("0", 64)}
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.record_sealed_buying_guide_snapshot(Map.merge(attrs, overrides))
    end

    assert {:ok, snapshot} = Core.record_sealed_buying_guide_snapshot(attrs)
    assert snapshot.guide_date == aggregate.aggregate_date
    assert snapshot.source_aggregate_fingerprint == fingerprint(aggregate)
  end

  test "database constraints and restrictive parent references remain enforced" do
    product = product()
    aggregate = aggregate(product)
    snapshot = Core.record_sealed_buying_guide_snapshot!(ready_attrs(product, aggregate))

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_buying_guide_snapshots SET confidence = '2' WHERE id = $1",
               [Ecto.UUID.dump!(snapshot.id)]
             )

    for column <- ~w(great_price_max_pln fair_price_max_pln expensive_price_max_pln) do
      assert {:error, %Postgrex.Error{}} =
               Repo.query(
                 "UPDATE sealed_buying_guide_snapshots SET #{column} = 'NaN' WHERE id = $1",
                 [Ecto.UUID.dump!(snapshot.id)]
               )
    end

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_buying_guide_snapshots SET trend = 'stable', trend_change = NULL WHERE id = $1",
               [Ecto.UUID.dump!(snapshot.id)]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_buying_guide_snapshots SET status = 'limited' WHERE id = $1",
               [Ecto.UUID.dump!(snapshot.id)]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_buying_guide_snapshots SET explanation_factors = ARRAY['unknown'] WHERE id = $1",
               [Ecto.UUID.dump!(snapshot.id)]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_buying_guide_snapshots SET source_history_fingerprint = 'invalid' WHERE id = $1",
               [Ecto.UUID.dump!(snapshot.id)]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query(
               "UPDATE sealed_buying_guide_snapshots SET guide_date = '2026-08-09' WHERE id = $1",
               [Ecto.UUID.dump!(snapshot.id)]
             )

    assert {:error, %Postgrex.Error{}} =
             Repo.query("DELETE FROM sealed_daily_aggregates WHERE id = $1", [
               Ecto.UUID.dump!(aggregate.id)
             ])

    assert {:error, %Postgrex.Error{}} =
             Repo.query("DELETE FROM sealed_products WHERE id = $1", [Ecto.UUID.dump!(product.id)])
  end

  defp product do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "guide-#{System.unique_integer([:positive])}",
        name: "Guide Product",
        product_type: "booster_box",
        officially_distributed: true,
        release_date: ~D[2026-08-01]
      })

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp aggregate(product, date \\ ~D[2026-08-08]) do
    calculated_at = DateTime.new!(date, ~T[12:00:00])

    Core.record_sealed_daily_aggregate!(%{
      sealed_product_id: product.id,
      aggregate_date: date,
      calculation_version: "sealed_market_daily_v1",
      currency: "PLN",
      status: "ready",
      benchmark_pln: d("100"),
      typical_low_pln: d("90"),
      typical_high_pln: d("110"),
      fresh_regular_retailer_count: 8,
      fresh_lgs_count: 0,
      recent_sold_out_0_14_day_count: 0,
      sold_out_15_30_day_count: 0,
      stale_or_future_current_offer_count: 0,
      unique_source_retailer_count: 8,
      latest_nonfuture_checked_at: calculated_at,
      calculated_at: calculated_at,
      source_evidence: [evidence(calculated_at)]
    })
  end

  defp ready_attrs(_product, aggregate),
    do: %{
      source_aggregate_id: aggregate.id,
      expected_source_aggregate_date: aggregate.aggregate_date,
      expected_source_aggregate_calculated_at: aggregate.calculated_at,
      expected_source_aggregate_fingerprint: fingerprint(aggregate),
      expected_source_history_fingerprint: history_fingerprint(aggregate),
      model_version: @version,
      currency: "PLN",
      status: "ready",
      limited_reason: nil,
      reference_price_pln: d("100"),
      great_price_max_pln: d("90"),
      fair_price_max_pln: d("105"),
      expensive_price_max_pln: d("120"),
      confidence: d("0.8"),
      trend: "stable",
      trend_change: d("0"),
      availability: "abundant",
      availability_trend: "stable",
      regular_benchmark_pln: d("100"),
      msrp_pln: nil,
      lgs_median_pln: nil,
      sold_out_center_pln: nil,
      explanation_factors: [
        "market_benchmark",
        "trend_stable",
        "availability_abundant",
        "availability_trend_stable"
      ],
      calculated_at: aggregate.calculated_at
    }

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

  defp limited_attrs(product, aggregate, overrides),
    do:
      Map.merge(ready_attrs(product, aggregate), %{
        status: "limited",
        limited_reason: "low_confidence",
        great_price_max_pln: nil,
        fair_price_max_pln: nil,
        expensive_price_max_pln: nil,
        explanation_factors: [
          "market_benchmark",
          "trend_stable",
          "availability_abundant",
          "availability_trend_stable"
        ]
      })
      |> Map.merge(overrides)

  defp d(value), do: Decimal.new(value)

  defp fingerprint(aggregate) do
    {:ok, value} = SealedDailyAggregateRevision.fingerprint(aggregate)
    value
  end

  defp evidence(calculated_at) do
    %{
      mapping_id: "snapshot-mapping-#{System.unique_integer([:positive])}",
      listing_id: "snapshot-listing-#{System.unique_integer([:positive])}",
      retailer_id: "snapshot-retailer-#{System.unique_integer([:positive])}",
      retailer_category: "regular_retailer",
      stock_status: "in_stock",
      confidence: d("1"),
      approved_at: calculated_at,
      price_pln: d("100"),
      checked_at: calculated_at
    }
  end
end
