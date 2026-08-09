defmodule TcgCheap.Pricing.Validations.SealedBuyingGuideSnapshot do
  @moduledoc false
  use Ash.Resource.Validation

  @reasons TcgCheap.Pricing.SealedBuyingModel.limited_reasons() |> Enum.map(&Atom.to_string/1)
  @trends ["rising", "stable", "falling", "insufficient_history"]
  @availability ["abundant", "balanced", "scarce"]
  @availability_trends ["improving", "stable", "tightening", "insufficient_history"]
  @factor ~r/^(market_benchmark|market_data_limited|msrp|lgs|sold_out|trend_(rising|stable|falling|insufficient_history)|availability_(abundant|balanced|scarce)|availability_trend_(improving|stable|tightening|insufficient_history))$/

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  # The ordered branches intentionally mirror the persisted database decision table.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)
    status = get.(:status)
    reason = get.(:limited_reason)

    ceilings =
      Enum.map([:great_price_max_pln, :fair_price_max_pln, :expensive_price_max_pln], get)

    components =
      Enum.map([:regular_benchmark_pln, :msrp_pln, :lgs_median_pln, :sold_out_center_pln], get)

    date = get.(:guide_date)
    calculated = get.(:calculated_at)
    source_calculated = get.(:source_aggregate_calculated_at)

    cond do
      not Regex.match?(~r/^sealed_buying_model_v[0-9]+$/, get.(:model_version) || "") ->
        {:error, "unsupported model version"}

      get.(:currency) != "PLN" ->
        {:error, "currency must be PLN"}

      not valid_fingerprint?(get.(:source_aggregate_fingerprint)) ->
        {:error, "invalid source aggregate fingerprint"}

      not valid_fingerprint?(get.(:source_history_fingerprint)) ->
        {:error, "invalid source history fingerprint"}

      status not in ["ready", "limited"] ->
        {:error, "invalid status"}

      status == "ready" and
          (not is_nil(reason) or invalid_price?(get.(:reference_price_pln)) or
             Enum.any?(ceilings, &invalid_price?/1) or not strictly_ascending?(ceilings)) ->
        {:error,
         "ready snapshot requires reference and strictly ascending ceilings with no reason"}

      status == "limited" and (reason not in @reasons or Enum.any?(ceilings, &(not is_nil(&1)))) ->
        {:error, "limited snapshot requires a canonical reason and no ceilings"}

      not is_nil(get.(:reference_price_pln)) and invalid_price?(get.(:reference_price_pln)) ->
        {:error, "reference price must be finite and positive"}

      Enum.any?(components, fn value -> not is_nil(value) and invalid_price?(value) end) ->
        {:error, "component centers must be finite and positive"}

      not finite_unit?(get.(:confidence)) ->
        {:error, "confidence must be finite and between zero and one"}

      get.(:trend) not in @trends ->
        {:error, "invalid trend"}

      get.(:availability) not in @availability ->
        {:error, "invalid availability"}

      get.(:availability_trend) not in @availability_trends ->
        {:error, "invalid availability trend"}

      (get.(:trend) == "insufficient_history" and not is_nil(get.(:trend_change))) or
          (get.(:trend) != "insufficient_history" and
             not finite_above_minus_one?(get.(:trend_change))) ->
        {:error, "trend change is incoherent"}

      not valid_factors?(get.(:explanation_factors)) ->
        {:error, "invalid explanation factors"}

      not (match?(%Date{}, date) and match?(%DateTime{}, calculated) and
               (is_nil(source_calculated) or match?(%DateTime{}, source_calculated))) ->
        {:error, "invalid snapshot time"}

      not is_nil(source_calculated) and
          Date.compare(date, DateTime.to_date(source_calculated)) == :gt ->
        {:error, "guide date cannot be after the source aggregate calculation date"}

      not is_nil(source_calculated) and DateTime.compare(source_calculated, calculated) == :gt ->
        {:error, "source aggregate cannot be calculated after snapshot"}

      true ->
        :ok
    end
  end

  defp invalid_price?(%Decimal{} = value),
    do: Decimal.nan?(value) or Decimal.inf?(value) or Decimal.compare(value, 0) != :gt

  defp invalid_price?(_), do: true

  defp strictly_ascending?([a, b, c]),
    do: Decimal.compare(a, b) == :lt and Decimal.compare(b, c) == :lt

  defp strictly_ascending?(_), do: false

  defp finite_unit?(%Decimal{} = value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and Decimal.compare(value, 0) != :lt and
        Decimal.compare(value, 1) != :gt

  defp finite_unit?(_), do: false

  defp finite_above_minus_one?(%Decimal{} = value),
    do: not Decimal.nan?(value) and not Decimal.inf?(value) and Decimal.compare(value, -1) == :gt

  defp finite_above_minus_one?(_), do: false

  defp valid_factors?(factors) when is_list(factors) and length(factors) in 1..8,
    do:
      Enum.uniq(factors) == factors and
        Enum.all?(factors, &(is_binary(&1) and byte_size(&1) > 0 and Regex.match?(@factor, &1)))

  defp valid_factors?(_), do: false

  defp valid_fingerprint?(value) when is_binary(value),
    do: Regex.match?(~r/^[0-9a-f]{64}$/, value)

  defp valid_fingerprint?(_), do: false
end
