defmodule TcgCheap.Pricing.Validations.SealedDailyAggregate do
  @moduledoc false
  use Ash.Resource.Validation

  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @reasons ["no_fresh_current_offers", "too_few_regular_retailers", "insufficient_inliers"]

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  # The database invariant is intentionally represented as one ordered decision table.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, _opts, _context) do
    status = Ash.Changeset.get_attribute(changeset, :status)
    reason = Ash.Changeset.get_attribute(changeset, :limited_reason)

    prices =
      Enum.map(
        [:typical_low_pln, :benchmark_pln, :typical_high_pln],
        &Ash.Changeset.get_attribute(changeset, &1)
      )

    date = Ash.Changeset.get_attribute(changeset, :aggregate_date)
    calculated = Ash.Changeset.get_attribute(changeset, :calculated_at)
    latest_checked = Ash.Changeset.get_attribute(changeset, :latest_nonfuture_checked_at)

    counts = [
      :fresh_regular_retailer_count,
      :fresh_lgs_count,
      :recent_sold_out_0_14_day_count,
      :sold_out_15_30_day_count,
      :stale_or_future_current_offer_count,
      :unique_source_retailer_count
    ]

    cond do
      not Regex.match?(
        ~r/^sealed_market_daily_v[0-9]+$/,
        Ash.Changeset.get_attribute(changeset, :calculation_version) || ""
      ) ->
        {:error, "unsupported calculation version"}

      Ash.Changeset.get_attribute(changeset, :currency) != "PLN" ->
        {:error, "currency must be PLN"}

      status not in ["ready", "limited"] ->
        {:error, "invalid status"}

      Enum.any?(
        counts,
        &(not (is_integer(Ash.Changeset.get_attribute(changeset, &1)) and
                   Ash.Changeset.get_attribute(changeset, &1) >= 0))
      ) ->
        {:error, "counts must be nonnegative"}

      Ash.Changeset.get_attribute(changeset, :unique_source_retailer_count) <
          Ash.Changeset.get_attribute(changeset, :fresh_regular_retailer_count) +
            Ash.Changeset.get_attribute(changeset, :fresh_lgs_count) ->
        {:error, "unique source coverage cannot be lower than fresh retailer coverage"}

      Enum.any?(prices, &invalid_price?/1) ->
        {:error, "prices must be finite and positive"}

      invalid_price?(Ash.Changeset.get_attribute(changeset, :source_msrp_pln)) ->
        {:error, "source MSRP must be finite and positive"}

      present_prices?(prices) and not ordered_prices?(prices) ->
        {:error, "price range is invalid"}

      status == "ready" and (Enum.any?(prices, &is_nil/1) or not is_nil(reason)) ->
        {:error, "ready aggregate must have all prices and no reason"}

      status == "ready" and
          Ash.Changeset.get_attribute(changeset, :fresh_regular_retailer_count) <
            SealedDailyAggregateCalculator.minimum_fresh_regular_retailers() ->
        {:error,
         "ready aggregate must have at least #{SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()} fresh regular retailers"}

      status == "ready" and is_nil(latest_checked) ->
        {:error, "ready aggregate must have latest nonfuture checked time"}

      status == "limited" and
          (Enum.any?(prices, fn price -> not is_nil(price) end) or reason not in @reasons) ->
        {:error, "limited aggregate must have a canonical reason and no prices"}

      status == "limited" and
          not limited_reason_matches_counts?(
            reason,
            Ash.Changeset.get_attribute(changeset, :fresh_regular_retailer_count),
            Ash.Changeset.get_attribute(changeset, :fresh_lgs_count)
          ) ->
        {:error, "limited reason does not match fresh retailer counts"}

      not (match?(%Date{}, date) and match?(%DateTime{}, calculated)) ->
        {:error, "invalid aggregate time"}

      Date.compare(date, DateTime.to_date(calculated)) == :gt ->
        {:error, "aggregate date cannot be in the future"}

      not is_nil(latest_checked) and
          (not match?(%DateTime{}, calculated) or
             DateTime.compare(latest_checked, calculated) == :gt) ->
        {:error, "latest nonfuture checked time cannot be after calculated time"}

      true ->
        :ok
    end
  end

  defp invalid_price?(nil), do: false

  defp invalid_price?(%Decimal{} = value),
    do:
      Decimal.nan?(value) or Decimal.inf?(value) or Decimal.compare(value, Decimal.new(0)) != :gt

  defp invalid_price?(_), do: true
  defp present_prices?(prices), do: Enum.all?(prices, &(not is_nil(&1)))

  defp ordered_prices?([low, benchmark, high]),
    do: Decimal.compare(low, benchmark) != :gt and Decimal.compare(benchmark, high) != :gt

  defp limited_reason_matches_counts?("no_fresh_current_offers", 0, 0), do: true

  defp limited_reason_matches_counts?("too_few_regular_retailers", regular, lgs),
    do:
      regular < SealedDailyAggregateCalculator.minimum_fresh_regular_retailers() and
        regular + lgs > 0

  defp limited_reason_matches_counts?("insufficient_inliers", regular, _lgs),
    do: regular >= SealedDailyAggregateCalculator.minimum_fresh_regular_retailers()

  defp limited_reason_matches_counts?(_, _, _), do: false
end
