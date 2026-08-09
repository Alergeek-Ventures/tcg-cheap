defmodule TcgCheap.Pricing.SealedDailyAggregateCalculator do
  @moduledoc "Pure v1 calculator for the daily sealed-market aggregate."
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  @version "sealed_market_daily_v1"
  @minimum_regular_prices 5
  @minimum_inliers 3
  @reasons ["no_fresh_current_offers", "too_few_regular_retailers", "insufficient_inliers"]

  def version, do: @version
  def minimum_fresh_regular_retailers, do: @minimum_regular_prices

  def policy,
    do: %{
      version: @version,
      minimum_regular_prices: @minimum_regular_prices,
      minimum_inliers: @minimum_inliers,
      freshness_days: 7,
      freshness: %{max_age_days: 7, future_checked_at?: false, boundary: :inclusive},
      outlier_policy: %{method: :tukey_iqr, iqr_multiplier: Decimal.new("1.5")},
      center: :median,
      range: :inlier_min_max,
      rounding: %{scale: 2, mode: :half_up}
    }

  def limited_reasons, do: @reasons

  @spec calculate(map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def calculate(%{current: current, sold_out: sold_out}, %DateTime{} = as_of)
      when is_list(current) and is_list(sold_out) do
    with {:ok, current} <- inspect_current(current),
         {:ok, inspected_sold_out} <- inspect_sold_out(sold_out, as_of),
         :ok <- reject_category_conflicts(current ++ Enum.map(inspected_sold_out, &elem(&1, 1))) do
      sold_out =
        inspected_sold_out
        |> Enum.reject(&(elem(&1, 0) == :excluded))
        |> latest_sold_out_per_retailer()

      fresh = current |> Enum.filter(&fresh?(&1, as_of)) |> cheapest_per_retailer()
      regular = Enum.filter(fresh, &(category(&1) == "regular_retailer"))
      lgs = Enum.count(fresh, &(category(&1) == "lgs"))
      prices = Enum.map(regular, &price/1)
      {status, reason, benchmark, low, high} = calculate_prices(prices, length(fresh))

      {:ok,
       %{
         aggregate_date: DateTime.to_date(as_of),
         calculation_version: @version,
         currency: "PLN",
         status: status,
         limited_reason: reason,
         benchmark_pln: benchmark,
         typical_low_pln: low,
         typical_high_pln: high,
         fresh_regular_retailer_count: length(regular),
         fresh_lgs_count: lgs,
         recent_sold_out_0_14_day_count: sold_out |> Enum.count(&(elem(&1, 0) == :recent)),
         sold_out_15_30_day_count: sold_out |> Enum.count(&(elem(&1, 0) == :older)),
         stale_or_future_current_offer_count: Enum.count(current, &(not fresh?(&1, as_of))),
         unique_source_retailer_count:
           unique_retailers(current ++ Enum.map(sold_out, &elem(&1, 1))),
         latest_nonfuture_checked_at:
           latest_checked(current ++ Enum.map(sold_out, &elem(&1, 1)), as_of),
         calculated_at: as_of
       }}
    end
  end

  def calculate(_, _), do: {:error, :malformed_projection}

  defp calculate_prices([], 0), do: {"limited", "no_fresh_current_offers", nil, nil, nil}

  defp calculate_prices([], _fresh_count),
    do: {"limited", "too_few_regular_retailers", nil, nil, nil}

  defp calculate_prices(prices, _fresh_count) when length(prices) < @minimum_regular_prices,
    do: {"limited", "too_few_regular_retailers", nil, nil, nil}

  defp calculate_prices(prices, _fresh_count) do
    sorted = Enum.sort(prices, &(Decimal.compare(&1, &2) != :gt))
    q1 = quantile(sorted, Decimal.new(1), Decimal.new(4))
    q3 = quantile(sorted, Decimal.new(3), Decimal.new(4))
    iqr = Decimal.sub(q3, q1)
    lower = Decimal.sub(q1, Decimal.mult(iqr, Decimal.new("1.5")))
    upper = Decimal.add(q3, Decimal.mult(iqr, Decimal.new("1.5")))

    inliers =
      Enum.filter(
        sorted,
        &(Decimal.compare(&1, lower) != :lt and Decimal.compare(&1, upper) != :gt)
      )

    if length(inliers) < @minimum_inliers do
      {"limited", "insufficient_inliers", nil, nil, nil}
    else
      {"ready", nil, round2(median(inliers)), round2(hd(inliers)), round2(List.last(inliers))}
    end
  end

  defp inspect_current(offers) do
    Enum.reduce_while(offers, {:ok, []}, fn offer, {:ok, acc} ->
      with {:ok, _} <- inspect_offer(offer, "in_stock"),
           {:ok, _checked} <- checked_at(offer),
           {:ok, _price} <- positive_price(offer) do
        {:cont, {:ok, [offer | acc]}}
      else
        _ -> {:halt, {:error, :malformed_current_offer}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
  defp inspect_sold_out(offers, as_of) do
    Enum.reduce_while(offers, {:ok, []}, fn offer, {:ok, acc} ->
      with {:ok, _} <- inspect_offer(offer, "sold_out"),
           {:ok, checked} <- checked_at(offer) do
        age = DateTime.diff(as_of, checked, :second)

        kind =
          cond do
            age >= 0 and age <= 14 * 86_400 -> :recent
            age > 14 * 86_400 and age <= 30 * 86_400 -> :older
            true -> :excluded
          end

        {:cont, {:ok, [{kind, offer} | acc]}}
      else
        _ -> {:halt, {:error, :malformed_sold_out_offer}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  defp inspect_offer(
         %{listing: %{stock_status: status}, retailer: %{id: id, category: category}},
         expected
       )
       when status == expected and is_binary(id) and category in ["regular_retailer", "lgs"],
       do: {:ok, true}

  defp inspect_offer(_, _), do: {:error, :malformed_offer}

  defp fresh?(offer, as_of) do
    case checked_at(offer) do
      {:ok, checked} -> DateTime.diff(as_of, checked, :second) in 0..(7 * 86_400)
      _ -> false
    end
  end

  defp checked_at(%{listing: %{last_checked_at: %DateTime{} = value}}), do: {:ok, value}
  defp checked_at(_), do: {:error, :malformed_checked_at}
  defp price(%{listing: %{current_price_pln: value}}), do: value

  defp positive_price(%{listing: %{current_price_pln: %Decimal{} = value}}),
    do: if(finite_positive?(value), do: {:ok, value}, else: {:error, :invalid_price})

  defp positive_price(_), do: {:error, :invalid_price}
  defp category(%{retailer: %{category: value}}), do: value

  defp cheapest_per_retailer(offers) do
    offers
    |> Enum.group_by(& &1.retailer.id)
    |> Enum.map(fn {_retailer_id, retailer_offers} -> cheapest(retailer_offers) end)
  end

  defp cheapest([first | rest]), do: Enum.reduce(rest, first, &cheaper/2)

  defp cheaper(offer, best) do
    if Decimal.compare(price(offer), price(best)) == :lt, do: offer, else: best
  end

  defp latest_sold_out_per_retailer(inspected_offers) do
    inspected_offers
    |> Enum.group_by(fn {_kind, offer} -> offer.retailer.id end)
    |> Enum.map(fn {_retailer_id, retailer_offers} -> latest_sold_out(retailer_offers) end)
  end

  defp latest_sold_out([first | rest]), do: Enum.reduce(rest, first, &newer_sold_out/2)

  defp newer_sold_out({_kind, offer} = candidate, {_best_kind, best_offer} = best) do
    {:ok, checked_at} = checked_at(offer)
    {:ok, best_checked_at} = checked_at(best_offer)

    if DateTime.compare(checked_at, best_checked_at) == :gt, do: candidate, else: best
  end

  defp reject_category_conflicts(offers) do
    conflicts =
      offers
      |> Enum.group_by(& &1.retailer.id)
      |> Enum.any?(fn {_id, retailer_offers} ->
        retailer_offers |> Enum.map(&category/1) |> Enum.uniq() |> length() > 1
      end)

    if conflicts, do: {:error, :conflicting_retailer_categories}, else: :ok
  end

  defp finite_positive?(value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt

  defp unique_retailers(offers),
    do: offers |> Enum.map(& &1.retailer.id) |> Enum.uniq() |> length()

  defp latest_checked(offers, as_of) do
    offers
    |> Enum.map(&checked_at/1)
    |> Enum.flat_map(fn {:ok, value} ->
      if DateTime.compare(value, as_of) != :gt, do: [value], else: []
    end)
    |> Enum.reduce(nil, fn value, latest ->
      if is_nil(latest) or DateTime.compare(value, latest) == :gt, do: value, else: latest
    end)
  end

  defp quantile(values, numerator, denominator) do
    index = Decimal.mult(Decimal.new(length(values) - 1), Decimal.div(numerator, denominator))
    lower = index |> Decimal.round(0, :down) |> Decimal.to_integer()
    fraction = Decimal.sub(index, Decimal.new(lower))

    case Enum.at(values, lower + 1) do
      nil ->
        Enum.at(values, lower)

      upper ->
        Decimal.add(
          Enum.at(values, lower),
          Decimal.mult(fraction, Decimal.sub(upper, Enum.at(values, lower)))
        )
    end
  end

  defp median(values), do: quantile(values, Decimal.new(1), Decimal.new(2))
  defp round2(value), do: Decimal.round(value, 2, :half_up)
end
