defmodule TcgCheap.Pricing.SealedDailyAggregatePublic do
  @moduledoc "Fail-closed validation of persisted public sealed-market aggregates."

  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @count_fields [
    :fresh_regular_retailer_count,
    :fresh_lgs_count,
    :recent_sold_out_0_14_day_count,
    :sold_out_15_30_day_count,
    :stale_or_future_current_offer_count,
    :unique_source_retailer_count
  ]

  def ready?(aggregate, now), do: ready?(aggregate, now, [])

  def ready?(aggregate, %DateTime{} = now, opts) do
    canonical?(aggregate, opts) and
      Map.get(aggregate, :status) == "ready" and
      is_nil(Map.get(aggregate, :limited_reason)) and
      finite_positive_ordered?(aggregate, [:typical_low_pln, :benchmark_pln, :typical_high_pln]) and
      Map.get(aggregate, :fresh_regular_retailer_count) >=
        SealedDailyAggregateCalculator.minimum_fresh_regular_retailers() and
      valid_times?(aggregate, now, checked_required?: true)
  rescue
    _ -> false
  end

  def ready?(_, _, _), do: false

  def limited?(aggregate, now), do: limited?(aggregate, now, [])

  def limited?(aggregate, %DateTime{} = now, opts) do
    canonical?(aggregate, opts) and
      Map.get(aggregate, :status) == "limited" and
      limited_reason_counts?(aggregate) and
      Enum.all?(
        [:benchmark_pln, :typical_low_pln, :typical_high_pln],
        &is_nil(Map.get(aggregate, &1))
      ) and
      valid_times?(aggregate, now, checked_required?: false)
  rescue
    _ -> false
  end

  def limited?(_, _, _), do: false

  def current_ready?(aggregate, now), do: current_ready?(aggregate, now, [])

  def current_ready?(aggregate, %DateTime{} = now, opts) do
    ready?(aggregate, now, opts) and
      Date.diff(DateTime.to_date(now), aggregate.aggregate_date) in 0..1 and
      DateTime.diff(now, aggregate.latest_nonfuture_checked_at, :second) in 0..(SealedDailyAggregateCalculator.policy().freshness_days *
                                                                                  86_400)
  rescue
    _ -> false
  end

  def current_ready?(_, _, _), do: false

  defp canonical?(aggregate, opts) when is_map(aggregate) and is_list(opts) do
    product_matches?(aggregate, opts) and canonical_attributes?(aggregate)
  end

  defp canonical?(_, _), do: false

  defp canonical_attributes?(aggregate) do
    Map.get(aggregate, :calculation_version) == SealedDailyAggregateCalculator.version() and
      Map.get(aggregate, :currency) == "PLN" and
      match?(%Date{}, Map.get(aggregate, :aggregate_date)) and
      nonnegative_counts?(aggregate) and
      Map.get(aggregate, :unique_source_retailer_count) >=
        Map.get(aggregate, :fresh_regular_retailer_count) + Map.get(aggregate, :fresh_lgs_count) and
      Map.get(aggregate, :recent_sold_out_0_14_day_count) <=
        Map.get(aggregate, :unique_source_retailer_count) and
      Map.get(aggregate, :sold_out_15_30_day_count) <=
        Map.get(aggregate, :unique_source_retailer_count) and
      Map.get(aggregate, :recent_sold_out_0_14_day_count) +
        Map.get(aggregate, :sold_out_15_30_day_count) <=
        Map.get(aggregate, :unique_source_retailer_count)
  end

  defp product_matches?(aggregate, opts) do
    case Keyword.fetch(opts, :sealed_product_id) do
      :error -> true
      {:ok, expected_id} -> Map.get(aggregate, :sealed_product_id) == expected_id
    end
  end

  defp nonnegative_counts?(aggregate),
    do:
      Enum.all?(
        @count_fields,
        &(is_integer(Map.get(aggregate, &1)) and Map.get(aggregate, &1) >= 0)
      )

  defp limited_reason_counts?(aggregate) do
    regular = aggregate.fresh_regular_retailer_count
    lgs = aggregate.fresh_lgs_count
    minimum = SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()

    case aggregate.limited_reason do
      "no_fresh_current_offers" -> regular == 0 and lgs == 0
      "too_few_regular_retailers" -> regular < minimum and regular + lgs > 0
      "insufficient_inliers" -> regular >= minimum
      _ -> false
    end
  end

  defp finite_positive_ordered?(aggregate, fields) do
    values = Enum.map(fields, &Map.get(aggregate, &1))

    Enum.all?(values, &finite_positive?/1) and
      Enum.chunk_every(values, 2, 1, :discard)
      |> Enum.all?(fn [left, right] -> Decimal.compare(left, right) != :gt end)
  end

  defp finite_positive?(%Decimal{} = value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt

  defp finite_positive?(_), do: false

  defp valid_times?(aggregate, now, checked_required?: required?) do
    date = Map.get(aggregate, :aggregate_date)
    calculated_at = Map.get(aggregate, :calculated_at)
    checked_at = Map.get(aggregate, :latest_nonfuture_checked_at)

    match?(%Date{}, date) and match?(%DateTime{}, calculated_at) and
      Date.compare(date, DateTime.to_date(calculated_at)) != :gt and
      DateTime.compare(calculated_at, now) != :gt and
      ((match?(%DateTime{}, checked_at) and DateTime.compare(checked_at, calculated_at) != :gt) or
         (not required? and is_nil(checked_at)))
  end
end
