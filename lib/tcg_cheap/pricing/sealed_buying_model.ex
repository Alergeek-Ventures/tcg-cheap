defmodule TcgCheap.Pricing.SealedBuyingModel do
  @moduledoc """
  Pure, provisional v1 buying guidance for sealed products.

  Band cutoffs belong to the cheaper preceding band: ceilings are inclusive and
  the next band's lower bound is exclusive.
  """

  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @version "sealed_buying_model_v1"
  @day 86_400
  @freshness_days 7
  @history_window_days 30
  @trend_threshold Decimal.new("0.05")
  @recent_sold_out_days 14
  @sold_out_window_days 30
  @availability_change_threshold 2
  @regular_target 8
  @history_target 3
  @span_target 7
  @lgs_target 2
  @sold_out_target 2
  @sold_out_majority_multiplier 2
  @confidence_threshold Decimal.new("0.65")
  @availability_thresholds %{
    abundant_regular_minimum: 8,
    abundant_recent_sold_out_maximum: 1,
    scarce_regular_maximum: 5,
    scarce_recent_sold_out_minimum: 3,
    scarce_recent_sold_out_majority_multiplier: @sold_out_majority_multiplier
  }
  @sold_out_recency_weights %{
    days_0_to_14_inclusive: Decimal.new("1.00"),
    days_15_to_30_inclusive: Decimal.new("0.35")
  }
  @band_multipliers %{
    great: Decimal.new("0.90"),
    fair: Decimal.new("1.05"),
    expensive: Decimal.new("1.20")
  }
  @trend_adjustments %{
    rising: Decimal.new("0.02"),
    stable: Decimal.new("0"),
    falling: Decimal.new("-0.02"),
    insufficient_history: Decimal.new("0")
  }
  @availability_adjustments %{
    abundant: Decimal.new("-0.02"),
    balanced: Decimal.new("0"),
    scarce: Decimal.new("0.02")
  }
  @availability_trend_adjustments %{
    improving: Decimal.new("-0.01"),
    stable: Decimal.new("0"),
    tightening: Decimal.new("0.01"),
    insufficient_history: Decimal.new("0")
  }
  @expensive_minimum_high_multiplier Decimal.new("1.05")
  @arithmetic_context %Decimal.Context{
    precision: 34,
    rounding: :half_up,
    emax: 6144,
    emin: -6143,
    flags: [],
    traps: [:invalid_operation, :division_by_zero]
  }
  @limited_reasons [
    :uncertain_mapping,
    :limited_market_aggregate,
    :stale_market_evidence,
    :insufficient_history,
    :low_confidence,
    :invalid_band_boundaries
  ]

  @component_weights %{
    regular_benchmark: Decimal.new("0.55"),
    msrp: Decimal.new("0.25"),
    lgs_median: Decimal.new("0.10"),
    sold_out_center: Decimal.new("0.10")
  }
  @component_order [:regular_benchmark, :msrp, :lgs_median, :sold_out_center]

  @confidence_weights %{
    regular_coverage: Decimal.new("0.30"),
    history: Decimal.new("0.25"),
    evidence_freshness: Decimal.new("0.15"),
    msrp_presence: Decimal.new("0.10"),
    lgs_support: Decimal.new("0.10"),
    sold_out_support: Decimal.new("0.10")
  }

  @spec version() :: String.t()
  def version, do: @version

  @spec limited_reasons() :: [atom()]
  def limited_reasons, do: @limited_reasons

  @spec policy() :: map()
  def policy do
    %{
      version: @version,
      aggregate_freshness: %{
        max_age_days: @freshness_days,
        boundary: :inclusive,
        future_checked_at?: false
      },
      component_weights: @component_weights,
      sold_out_recency_weights: @sold_out_recency_weights,
      history: %{
        window_days: @history_window_days,
        minimum_unique_ready_points: @history_target,
        minimum_span_days: @span_target,
        trend_threshold: @trend_threshold
      },
      availability: @availability_thresholds,
      confidence: %{
        weights: @confidence_weights,
        regular_coverage_target: @regular_target,
        history_points_target: @history_target,
        history_span_days_target: @span_target,
        lgs_support_target: @lgs_target,
        sold_out_support_target: @sold_out_target,
        ready_threshold: @confidence_threshold,
        hard_requirements: %{
          mapping_confident?: true,
          market_status: "ready",
          minimum_regular_coverage:
            SealedDailyAggregateCalculator.minimum_fresh_regular_retailers(),
          minimum_unique_ready_points: @history_target,
          minimum_history_span_days: @span_target
        }
      },
      bands: %{
        base_multipliers: @band_multipliers,
        trend_adjustments: @trend_adjustments,
        availability_adjustments: @availability_adjustments,
        expensive_minimum_high_multiplier: @expensive_minimum_high_multiplier,
        availability_trend_adjustments: @availability_trend_adjustments,
        guardrails: %{
          great_ceiling_maximum: :typical_low,
          fair_ceiling_minimum: :benchmark,
          expensive_ceiling_minimum: :typical_high
        }
      },
      availability_trend: %{
        coverage_change_threshold: @availability_change_threshold,
        sold_out_change_threshold: @availability_change_threshold
      },
      aggregate_delegation: %{
        source_version: SealedDailyAggregateCalculator.version(),
        center: :median,
        outlier_policy: %{method: :tukey_iqr, iqr_multiplier: Decimal.new("1.5")}
      },
      rounding: %{scale: 2, mode: :half_up},
      arithmetic_context: @arithmetic_context
    }
  end

  @spec calculate(map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def calculate(input, %DateTime{} = as_of) when is_map(input) do
    Decimal.Context.with(@arithmetic_context, fn -> calculate_in_context(input, as_of) end)
  end

  def calculate(_, _), do: {:error, :malformed_input}

  defp calculate_in_context(input, as_of) do
    with {:ok, current} <- validate_current(Map.get(input, :current_aggregate), as_of),
         {:ok, history} <- validate_history(Map.get(input, :history), current, as_of),
         {:ok, msrp} <- validate_msrp(Map.get(input, :msrp_pln)),
         {:ok, lgs} <- validate_lgs(Map.get(input, :lgs_price_evidence), current),
         {:ok, sold_out} <- validate_sold_out(Map.get(input, :sold_out_price_evidence), as_of),
         {:ok, sold_out} <- normalize_sold_out(sold_out, current),
         {:ok, mapping_confident?} <- validate_mapping(Map.get(input, :mapping_confident?)) do
      assemble(
        current,
        history,
        msrp,
        lgs,
        sold_out,
        mapping_confident?,
        as_of
      )
    end
  end

  defp assemble(current, history, msrp, lgs, sold_out, mapping_confident?, as_of) do
    points = eligible_points(current, history, as_of)
    span = history_span(points, current)
    fresh? = fresh?(Map.get(current, :latest_nonfuture_checked_at), as_of)
    confidence = confidence(current, points, span, fresh?, msrp, lgs, sold_out)
    reason = hard_reason(mapping_confident?, current, fresh?, points, span, confidence)
    trend = trend(points, current, span)
    availability = availability(current)
    availability_trend = availability_trend(points, current, span)
    centers = centers(current, msrp, lgs, sold_out, as_of)

    result = %{
      model_version: @version,
      currency: "PLN",
      status: if(is_nil(reason), do: "ready", else: "limited"),
      limited_reason: reason,
      reference_price_pln: blended_reference(centers),
      great_price_max_pln: nil,
      fair_price_max_pln: nil,
      expensive_price_max_pln: nil,
      buying_bands: [],
      confidence: round2(confidence),
      trend: trend,
      trend_change: trend_change(points, current, span),
      availability: availability,
      availability_trend: availability_trend,
      component_centers: centers,
      explanation_factors: explanation_factors(centers, trend, availability, availability_trend)
    }

    if is_nil(reason) do
      case calculate_bands(
             result.reference_price_pln,
             current,
             trend,
             availability,
             availability_trend
           ) do
        {:ok, bands} ->
          {:ok, Map.merge(result, bands)}

        {:limited, limited_reason} ->
          {:ok, %{result | status: "limited", limited_reason: limited_reason}}
      end
    else
      {:ok, result}
    end
  end

  defp validate_current(current, as_of), do: validate_aggregate(current, as_of, nil)

  defp validate_history(history, current, as_of) when is_list(history) do
    current_date = Map.get(current, :aggregate_date)

    Enum.reduce_while(history, {:ok, []}, fn item, {:ok, acc} ->
      case validate_aggregate(item, as_of, current_date) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> reverse_ok()
    |> validate_history_consistency(current)
  end

  defp validate_history(_, _, _), do: {:error, :malformed_history}

  defp validate_history_consistency({:ok, history}, current) do
    duplicate_conflict? =
      history
      |> Enum.group_by(& &1.aggregate_date)
      |> Enum.any?(fn {_date, entries} ->
        entries |> Enum.map(&history_projection/1) |> Enum.uniq() |> length() > 1
      end)

    current_conflict? =
      Enum.any?(history, fn aggregate ->
        aggregate.aggregate_date == current.aggregate_date and
          history_projection(aggregate) != history_projection(current)
      end)

    if duplicate_conflict? or current_conflict?,
      do: {:error, :conflicting_history_projection},
      else: {:ok, history}
  end

  defp validate_history_consistency(error, _current), do: error

  defp history_projection(aggregate) do
    Enum.map(
      [
        :status,
        :calculation_version,
        :currency,
        :limited_reason,
        :benchmark_pln,
        :typical_low_pln,
        :typical_high_pln,
        :fresh_regular_retailer_count,
        :fresh_lgs_count,
        :recent_sold_out_0_14_day_count,
        :sold_out_15_30_day_count
      ],
      &Map.get(aggregate, &1)
    )
  end

  defp validate_aggregate(aggregate, as_of, current_date) when is_map(aggregate) do
    if valid_aggregate_state?(aggregate) and valid_aggregate_date?(aggregate, as_of, current_date) and
         valid_aggregate_timestamp?(aggregate, as_of) and valid_counts?(aggregate) and
         coherent_money?(aggregate) and coherent_state_reason?(aggregate) do
      {:ok, aggregate}
    else
      {:error, :malformed_aggregate}
    end
  end

  defp validate_aggregate(_, _, _), do: {:error, :malformed_aggregate}

  defp valid_aggregate_state?(aggregate) do
    required = [
      :status,
      :calculation_version,
      :currency,
      :limited_reason,
      :aggregate_date,
      :benchmark_pln,
      :typical_low_pln,
      :typical_high_pln,
      :fresh_regular_retailer_count,
      :fresh_lgs_count,
      :recent_sold_out_0_14_day_count,
      :sold_out_15_30_day_count,
      :stale_or_future_current_offer_count,
      :unique_source_retailer_count,
      :calculated_at,
      :latest_nonfuture_checked_at
    ]

    Enum.all?(required, &Map.has_key?(aggregate, &1)) and
      Map.get(aggregate, :status) in ["ready", "limited"] and
      Map.get(aggregate, :currency) == "PLN" and
      Map.get(aggregate, :calculation_version) == SealedDailyAggregateCalculator.version()
  end

  defp valid_aggregate_date?(aggregate, as_of, current_date) do
    date = Map.get(aggregate, :aggregate_date)

    calculated_at = Map.get(aggregate, :calculated_at)

    match?(%Date{}, date) and match?(%DateTime{}, calculated_at) and
      Date.compare(date, DateTime.to_date(as_of)) != :gt and
      DateTime.compare(calculated_at, as_of) != :gt and DateTime.to_date(calculated_at) == date and
      (is_nil(current_date) or Date.compare(date, current_date) != :gt)
  end

  defp valid_aggregate_timestamp?(aggregate, as_of) do
    timestamp = Map.get(aggregate, :latest_nonfuture_checked_at)
    calculated_at = Map.get(aggregate, :calculated_at)

    (Map.get(aggregate, :status) == "limited" and is_nil(timestamp)) or
      (valid_timestamp?(timestamp, as_of) and DateTime.compare(timestamp, calculated_at) != :gt)
  end

  defp coherent_money?(%{status: "ready"} = aggregate) do
    prices =
      Enum.map([:benchmark_pln, :typical_low_pln, :typical_high_pln], &Map.get(aggregate, &1))

    Enum.all?(prices, &valid_price?/1) and
      Decimal.compare(Enum.at(prices, 1), Enum.at(prices, 0)) != :gt and
      Decimal.compare(Enum.at(prices, 0), Enum.at(prices, 2)) != :gt and
      Map.get(aggregate, :fresh_regular_retailer_count) >=
        SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()
  end

  defp coherent_money?(%{status: "limited"} = aggregate),
    do:
      Enum.all?(
        [:benchmark_pln, :typical_low_pln, :typical_high_pln],
        &is_nil(Map.get(aggregate, &1))
      )

  defp coherent_money?(_), do: false

  defp coherent_state_reason?(%{status: "ready", limited_reason: nil}), do: true

  defp coherent_state_reason?(%{status: "limited", limited_reason: reason} = aggregate) do
    regular = aggregate.fresh_regular_retailer_count
    lgs = aggregate.fresh_lgs_count

    reason in ["no_fresh_current_offers", "too_few_regular_retailers", "insufficient_inliers"] and
      ((reason == "no_fresh_current_offers" and regular == 0 and lgs == 0) or
         (reason == "too_few_regular_retailers" and
            regular < SealedDailyAggregateCalculator.minimum_fresh_regular_retailers() and
            regular + lgs > 0) or
         (reason == "insufficient_inliers" and
            regular >= SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()))
  end

  defp coherent_state_reason?(_), do: false

  defp valid_counts?(aggregate) do
    fields = [
      :fresh_regular_retailer_count,
      :fresh_lgs_count,
      :recent_sold_out_0_14_day_count,
      :sold_out_15_30_day_count,
      :stale_or_future_current_offer_count,
      :unique_source_retailer_count
    ]

    Enum.all?(fields, &(is_integer(Map.get(aggregate, &1)) and Map.get(aggregate, &1) >= 0)) and
      aggregate.unique_source_retailer_count >=
        aggregate.fresh_regular_retailer_count + aggregate.fresh_lgs_count and
      aggregate.recent_sold_out_0_14_day_count <= aggregate.unique_source_retailer_count and
      aggregate.sold_out_15_30_day_count <= aggregate.unique_source_retailer_count and
      aggregate.recent_sold_out_0_14_day_count + aggregate.sold_out_15_30_day_count <=
        aggregate.unique_source_retailer_count
  end

  defp valid_timestamp?(%DateTime{} = timestamp, as_of),
    do: DateTime.diff(as_of, timestamp, :second) >= 0

  defp valid_timestamp?(_, _), do: false

  defp validate_msrp(nil), do: {:ok, nil}

  defp validate_msrp(value),
    do: if(valid_price?(value), do: {:ok, value}, else: {:error, :invalid_price})

  defp validate_lgs(values, aggregate) when is_list(values) do
    count = Map.get(aggregate, :fresh_lgs_count)

    if length(values) == count and Enum.all?(values, &valid_lgs_row?(&1, aggregate.calculated_at)) and
         length(Enum.uniq_by(values, & &1.retailer_id)) == count,
       do: {:ok, Enum.sort_by(values, & &1.retailer_id)},
       else: {:error, :invalid_lgs_evidence}
  end

  defp validate_lgs(_, _), do: {:error, :invalid_lgs_evidence}

  defp valid_lgs_row?(
         %{retailer_id: id, price_pln: price, checked_at: %DateTime{} = checked} = row,
         calculated_at
       )
       when is_binary(id) and byte_size(id) > 0 and map_size(row) == 3 do
    valid_price?(price) and DateTime.compare(checked, calculated_at) != :gt and
      DateTime.diff(calculated_at, checked, :second) in 0..(@freshness_days * @day)
  end

  defp valid_lgs_row?(_, _), do: false

  defp validate_sold_out(values, as_of) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn
      %{retailer_id: id, price_pln: price, checked_at: %DateTime{} = checked} = item, {:ok, acc}
      when is_binary(id) and byte_size(id) > 0 ->
        cond do
          DateTime.compare(checked, as_of) == :gt -> {:halt, {:error, :future_evidence}}
          not is_nil(price) and not valid_price?(price) -> {:halt, {:error, :invalid_price}}
          true -> {:cont, {:ok, [item | acc]}}
        end

      _, _ ->
        {:halt, {:error, :malformed_sold_out_evidence}}
    end)
    |> reverse_ok()
  end

  defp validate_sold_out(_, _), do: {:error, :malformed_sold_out_evidence}

  defp normalize_sold_out(values, aggregate) do
    with :ok <- evidence_before_calculated(values, aggregate.calculated_at),
         {:ok, latest} <- latest_sold_out_rows(values),
         filtered <-
           Enum.filter(
             latest,
             &(DateTime.diff(aggregate.calculated_at, &1.checked_at, :second) in 0..(@sold_out_window_days *
                                                                                       @day))
           ),
         :ok <- sold_out_counts_match?(filtered, aggregate) do
      {:ok, Enum.sort_by(filtered, & &1.retailer_id)}
    end
  end

  defp evidence_before_calculated(values, calculated_at) do
    if Enum.any?(values, &(DateTime.compare(&1.checked_at, calculated_at) == :gt)),
      do: {:error, :future_evidence},
      else: :ok
  end

  defp latest_sold_out_rows(values) do
    Enum.reduce_while(Enum.group_by(values, & &1.retailer_id), {:ok, []}, fn {_retailer, entries},
                                                                             {:ok, acc} ->
      latest_at = Enum.max_by(entries, & &1.checked_at, DateTime).checked_at
      latest = Enum.filter(entries, &(DateTime.compare(&1.checked_at, latest_at) == :eq))
      prices = latest |> Enum.map(& &1.price_pln) |> Enum.reject(&is_nil/1) |> unique_decimals()

      case choose_latest_sold_row(latest, prices) do
        {:error, reason} -> {:halt, {:error, reason}}
        {:ok, chosen} -> {:cont, {:ok, [chosen | acc]}}
      end
    end)
  end

  defp choose_latest_sold_row(_, prices) when length(prices) > 1,
    do: {:error, :ambiguous_sold_out_evidence}

  defp choose_latest_sold_row([first | _], []), do: {:ok, first}

  defp choose_latest_sold_row(latest, [price]),
    do:
      {:ok,
       Enum.find(latest, &(not is_nil(&1.price_pln) and Decimal.equal?(&1.price_pln, price)))}

  defp unique_decimals(values) do
    Enum.reduce(values, [], fn value, unique ->
      if Enum.any?(unique, &Decimal.equal?(&1, value)), do: unique, else: [value | unique]
    end)
  end

  defp sold_out_counts_match?(values, aggregate) do
    recent =
      Enum.count(
        values,
        &(DateTime.diff(aggregate.calculated_at, &1.checked_at, :second) in 0..(@recent_sold_out_days *
                                                                                  @day))
      )

    older =
      Enum.count(
        values,
        &(DateTime.diff(aggregate.calculated_at, &1.checked_at, :second) in (@recent_sold_out_days *
                                                                               @day + 1)..(@sold_out_window_days *
                                                                                             @day))
      )

    if recent == aggregate.recent_sold_out_0_14_day_count and
         older == aggregate.sold_out_15_30_day_count,
       do: :ok,
       else: {:error, :sold_out_count_mismatch}
  end

  defp validate_mapping(true), do: {:ok, true}
  defp validate_mapping(false), do: {:ok, false}
  defp validate_mapping(_), do: {:error, :malformed_input}

  defp eligible_points(current, history, as_of) do
    date = Map.get(current, :aggregate_date)

    (history ++ [current])
    |> Enum.filter(fn item ->
      Map.get(item, :status) == "ready" and
        Date.diff(date, Map.get(item, :aggregate_date)) in 0..@history_window_days
    end)
    |> Enum.reduce(%{}, fn item, acc -> Map.put(acc, Map.get(item, :aggregate_date), item) end)
    |> maybe_put_current(date, current)
    |> Map.values()
    |> Enum.sort_by(&Map.get(&1, :aggregate_date))
    |> Enum.filter(&(Date.compare(Map.get(&1, :aggregate_date), DateTime.to_date(as_of)) != :gt))
  end

  defp maybe_put_current(points, date, %{status: "ready"} = current),
    do: Map.put(points, date, current)

  defp maybe_put_current(points, _, _), do: points

  defp history_span([], _), do: 0

  defp history_span(points, current),
    do: Date.diff(Map.get(current, :aggregate_date), points |> hd() |> Map.get(:aggregate_date))

  defp hard_reason(false, _, _, _, _, _), do: :uncertain_mapping
  defp hard_reason(_, %{status: "limited"}, _, _, _, _), do: :limited_market_aggregate
  defp hard_reason(_, _, false, _, _, _), do: :stale_market_evidence

  defp hard_reason(_, _, _, points, span, _)
       when length(points) < @history_target or span < @span_target, do: :insufficient_history

  defp hard_reason(_, _, _, _, _, confidence),
    do:
      if(Decimal.compare(confidence, @confidence_threshold) == :lt,
        do: :low_confidence,
        else: nil
      )

  defp fresh?(%DateTime{} = timestamp, as_of),
    do: DateTime.diff(as_of, timestamp, :second) in 0..(@freshness_days * @day)

  defp fresh?(_, _), do: false

  defp trend(points, %{status: "ready"} = current, span)
       when length(points) >= @history_target and span >= @span_target do
    change = trend_change(points, current, span)

    cond do
      Decimal.compare(change, @trend_threshold) != :lt -> "rising"
      Decimal.compare(change, Decimal.negate(@trend_threshold)) != :gt -> "falling"
      true -> "stable"
    end
  end

  defp trend(_, _, _), do: "insufficient_history"

  defp trend_change(points, %{status: "ready"} = current, span)
       when length(points) >= @history_target and span >= @span_target do
    first = hd(points)

    Decimal.div(
      Decimal.sub(Map.get(current, :benchmark_pln), Map.get(first, :benchmark_pln)),
      Map.get(first, :benchmark_pln)
    )
  end

  defp trend_change(_, _, _), do: nil

  defp availability(aggregate) do
    regular = Map.get(aggregate, :fresh_regular_retailer_count)
    sold_out = Map.get(aggregate, :recent_sold_out_0_14_day_count)
    coverage = regular + Map.get(aggregate, :fresh_lgs_count)

    cond do
      regular >= @availability_thresholds.abundant_regular_minimum and
          sold_out <= @availability_thresholds.abundant_recent_sold_out_maximum ->
        "abundant"

      (regular <= @availability_thresholds.scarce_regular_maximum and
         sold_out >= @availability_thresholds.scarce_recent_sold_out_minimum) or
          sold_out * @sold_out_majority_multiplier > coverage ->
        "scarce"

      true ->
        "balanced"
    end
  end

  defp availability_trend(points, %{status: "ready"} = current, span)
       when length(points) >= @history_target and span >= @span_target do
    earliest = hd(points)
    coverage_change = coverage(current) - coverage(earliest)

    sold_out_change =
      current.recent_sold_out_0_14_day_count - earliest.recent_sold_out_0_14_day_count

    cond do
      coverage_change <= -@availability_change_threshold or
          sold_out_change >= @availability_change_threshold ->
        "tightening"

      coverage_change >= @availability_change_threshold or
          sold_out_change <= -@availability_change_threshold ->
        "improving"

      true ->
        "stable"
    end
  end

  defp availability_trend(_, _, _), do: "insufficient_history"
  defp coverage(aggregate), do: aggregate.fresh_regular_retailer_count + aggregate.fresh_lgs_count

  defp confidence(aggregate, points, span, fresh?, msrp, lgs, sold_out) do
    scores = %{
      regular_coverage: ratio(Map.get(aggregate, :fresh_regular_retailer_count), @regular_target),
      history: Decimal.mult(ratio(length(points), @history_target), ratio(span, @span_target)),
      evidence_freshness: if(fresh?, do: Decimal.new(1), else: Decimal.new(0)),
      msrp_presence: if(is_nil(msrp), do: Decimal.new(0), else: Decimal.new(1)),
      lgs_support: ratio(length(lgs), @lgs_target),
      sold_out_support: ratio(Enum.count(sold_out, &(not is_nil(&1.price_pln))), @sold_out_target)
    }

    Enum.reduce(@confidence_weights, Decimal.new(0), fn {key, weight}, total ->
      Decimal.add(total, Decimal.mult(weight, Map.fetch!(scores, key)))
    end)
  end

  defp ratio(value, target),
    do: Decimal.min(Decimal.new(1), Decimal.div(Decimal.new(value), Decimal.new(target)))

  defp centers(current, msrp, lgs, sold_out, _as_of) do
    %{}
    |> put_if(:regular_benchmark, Map.get(current, :benchmark_pln))
    |> put_if(:msrp, msrp)
    |> put_if(:lgs_median, median(Enum.map(lgs, & &1.price_pln)))
    |> put_if(:sold_out_center, sold_out_center(sold_out, current.calculated_at))
  end

  defp put_if(map, _, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values, &(Decimal.compare(&1, &2) != :gt))
    left = Enum.at(sorted, div(length(sorted) - 1, 2))
    right = Enum.at(sorted, div(length(sorted), 2))
    Decimal.div(Decimal.add(left, right), Decimal.new(2))
  end

  defp sold_out_center(values, as_of) do
    values
    |> Enum.reduce({Decimal.new(0), Decimal.new(0)}, fn value, totals ->
      accumulate_sold_out(value, totals, as_of)
    end)
    |> case do
      {_, weight} when weight == %Decimal{coef: 0} -> nil
      {total, weight} -> round2(Decimal.div(total, weight))
    end
  end

  defp accumulate_sold_out(%{price_pln: nil}, totals, _as_of), do: totals

  defp accumulate_sold_out(%{price_pln: price, checked_at: checked}, {total, weight}, as_of) do
    recency_weight = recency_weight(checked, as_of)
    {Decimal.add(total, Decimal.mult(price, recency_weight)), Decimal.add(weight, recency_weight)}
  end

  defp recency_weight(checked, as_of) do
    if DateTime.diff(as_of, checked, :second) <= @recent_sold_out_days * @day,
      do: @sold_out_recency_weights.days_0_to_14_inclusive,
      else: @sold_out_recency_weights.days_15_to_30_inclusive
  end

  defp blended_reference(centers) do
    {total, weight} =
      Enum.reduce(@component_order, {Decimal.new(0), Decimal.new(0)}, fn key, totals ->
        blend_component(centers, key, totals)
      end)

    if Decimal.compare(weight, Decimal.new(0)) == :gt,
      do: round2(Decimal.div(total, weight)),
      else: nil
  end

  defp blend_component(centers, key, {total, weight} = totals) do
    case Map.fetch(centers, key) do
      {:ok, value} ->
        component_weight = Map.fetch!(@component_weights, key)

        {Decimal.add(total, Decimal.mult(value, component_weight)),
         Decimal.add(weight, component_weight)}

      :error ->
        totals
    end
  end

  defp calculate_bands(reference, current, trend, availability, availability_trend) do
    adjustment =
      Map.fetch!(@trend_adjustments, String.to_existing_atom(trend))
      |> Decimal.add(
        Map.fetch!(@availability_adjustments, String.to_existing_atom(availability))
        |> Decimal.add(
          Map.fetch!(@availability_trend_adjustments, String.to_existing_atom(availability_trend))
        )
      )

    multipliers = @band_multipliers
    great = Decimal.mult(reference, Decimal.add(multipliers.great, adjustment))
    fair = Decimal.mult(reference, Decimal.add(multipliers.fair, adjustment))
    expensive = Decimal.mult(reference, Decimal.add(multipliers.expensive, adjustment))
    great = Decimal.min(great, Map.get(current, :typical_low_pln))
    fair = Decimal.max(fair, Map.get(current, :benchmark_pln))

    expensive =
      Decimal.max(
        expensive,
        Decimal.mult(Map.get(current, :typical_high_pln), @expensive_minimum_high_multiplier)
      )

    values = Enum.map([great, fair, expensive], &round2/1)

    if Enum.all?(values, &valid_price?/1) and ascending?(values),
      do:
        {:ok,
         %{
           great_price_max_pln: Enum.at(values, 0),
           fair_price_max_pln: Enum.at(values, 1),
           expensive_price_max_pln: Enum.at(values, 2),
           buying_bands: [
             %{
               key: :great,
               min_price_pln: nil,
               max_price_pln: Enum.at(values, 0),
               min_inclusive?: false,
               max_inclusive?: true
             },
             %{
               key: :fair,
               min_price_pln: Enum.at(values, 0),
               max_price_pln: Enum.at(values, 1),
               min_inclusive?: false,
               max_inclusive?: true
             },
             %{
               key: :expensive,
               min_price_pln: Enum.at(values, 1),
               max_price_pln: Enum.at(values, 2),
               min_inclusive?: false,
               max_inclusive?: true
             },
             %{
               key: :avoid,
               min_price_pln: Enum.at(values, 2),
               max_price_pln: nil,
               min_inclusive?: false,
               max_inclusive?: false
             }
           ]
         }},
      else: {:limited, :invalid_band_boundaries}
  end

  defp ascending?([first, second, third]),
    do: Decimal.compare(first, second) == :lt and Decimal.compare(second, third) == :lt

  defp explanation_factors(centers, trend, availability, availability_trend) do
    factors =
      if Map.has_key?(centers, :regular_benchmark),
        do: ["market_benchmark"],
        else: ["market_data_limited"]

    factors
    |> append_factor(Map.has_key?(centers, :msrp), "msrp")
    |> append_factor(Map.has_key?(centers, :lgs_median), "lgs")
    |> append_factor(Map.has_key?(centers, :sold_out_center), "sold_out")
    |> Kernel.++([
      "trend_" <> trend,
      "availability_" <> availability,
      "availability_trend_" <> availability_trend
    ])
  end

  defp append_factor(factors, true, factor), do: factors ++ [factor]
  defp append_factor(factors, false, _), do: factors

  defp valid_price?(%Decimal{} = value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt

  defp valid_price?(_), do: false

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error
  defp round2(value), do: Decimal.round(value, 2, :half_up)
end
