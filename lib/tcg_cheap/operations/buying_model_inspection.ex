defmodule TcgCheap.Operations.BuyingModelInspection do
  @moduledoc "Authenticated, read-only projection of the current sealed buying policy."

  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Accounts.AdminActor
  alias TcgCheap.Pricing.SealedBuyingModel

  @model_version "sealed_buying_model_v1"
  @aggregate_version "sealed_market_daily_v1"
  @v1_policy_fingerprint "4eeae686286a9ac8d6cf7831275980b7bd4e7a00cae5d755c79800221f54470a"
  @reasons [
    :uncertain_mapping,
    :limited_market_aggregate,
    :stale_market_evidence,
    :insufficient_history,
    :low_confidence,
    :invalid_band_boundaries
  ]

  @spec load(Admin.t()) :: {:ok, map()} | {:error, :invalid_actor | :invalid_model_policy}
  def load(%Admin{} = actor) do
    with :ok <- AdminActor.validate(actor),
         {:ok, projection} <-
           project(SealedBuyingModel.policy(), SealedBuyingModel.limited_reasons()) do
      {:ok, projection}
    else
      {:error, :invalid_actor} -> {:error, :invalid_actor}
      _ -> {:error, :invalid_model_policy}
    end
  end

  def load(_), do: {:error, :invalid_actor}

  @spec project(term(), term()) :: {:ok, map()} | {:error, :invalid_model_policy}
  def project(policy, limited_reasons) do
    with :ok <- validate_policy(policy),
         :ok <- validate_reasons(limited_reasons) do
      {:ok, projection(policy, limited_reasons)}
    else
      _ -> {:error, :invalid_model_policy}
    end
  rescue
    _ -> {:error, :invalid_model_policy}
  end

  defp projection(policy, reasons) do
    confidence = policy.confidence
    hard = confidence.hard_requirements
    history = policy.history

    %{
      model_version: policy.version,
      aggregate_version: policy.aggregate_delegation.source_version,
      model_status: "Provisional",
      validation_basis: "Synthetic policy cases only",
      component_weights:
        decimal_rows(
          policy.component_weights,
          [
            {:regular_benchmark, "Regular retailer benchmark"},
            {:msrp, "MSRP"},
            {:lgs_median, "LGS median"},
            {:sold_out_center, "Sold-out center"}
          ],
          &percentage/1
        ),
      confidence: %{
        weights:
          decimal_rows(
            confidence.weights,
            [
              {:regular_coverage, "Regular coverage"},
              {:history, "History"},
              {:evidence_freshness, "Evidence freshness"},
              {:msrp_presence, "MSRP presence"},
              {:lgs_support, "LGS support"},
              {:sold_out_support, "Sold-out support"}
            ],
            &percentage/1
          ),
        ready_threshold: percentage(confidence.ready_threshold),
        targets:
          rows([
            {"Regular coverage target", integer(confidence.regular_coverage_target)},
            {"History points target", integer(confidence.history_points_target)},
            {"History span target", days(confidence.history_span_days_target)},
            {"LGS support target", integer(confidence.lgs_support_target)},
            {"Sold-out support target", integer(confidence.sold_out_support_target)}
          ]),
        hard_requirements:
          rows([
            {"Mapping confident", boolean(hard.mapping_confident?)},
            {"Market status", hard.market_status},
            {"Minimum regular shops (hard)", integer(hard.minimum_regular_coverage)},
            {"Minimum unique ready points", integer(hard.minimum_unique_ready_points)},
            {"Minimum history span", days(hard.minimum_history_span_days)}
          ])
      },
      freshness_and_history:
        rows([
          {"Aggregate freshness", inclusive_days(policy.aggregate_freshness.max_age_days)},
          {"Future checked-at allowed", boolean(policy.aggregate_freshness.future_checked_at?)},
          {"History window", days(history.window_days)},
          {"Minimum unique ready points", integer(history.minimum_unique_ready_points)},
          {"Minimum history span", days(history.minimum_span_days)},
          {"Trend threshold", percentage(history.trend_threshold)}
        ]),
      sold_out_recency:
        rows([
          {"0–14 days (inclusive)",
           multiplier(policy.sold_out_recency_weights.days_0_to_14_inclusive)},
          {"15–30 days (inclusive)",
           multiplier(policy.sold_out_recency_weights.days_15_to_30_inclusive)}
        ]),
      availability:
        rows([
          {"Abundant: regular shops at least",
           integer(policy.availability.abundant_regular_minimum)},
          {"Abundant: recent sold-outs at most",
           integer(policy.availability.abundant_recent_sold_out_maximum)},
          {"Scarce: regular shops at most", integer(policy.availability.scarce_regular_maximum)},
          {"Scarce: recent sold-outs at least",
           integer(policy.availability.scarce_recent_sold_out_minimum)},
          {"Scarce: recent sold-out majority",
           "sold outs × #{integer(policy.availability.scarce_recent_sold_out_majority_multiplier)} > fresh regular + LGS coverage"},
          {"Coverage trend change threshold",
           integer(policy.availability_trend.coverage_change_threshold)},
          {"Sold-out trend change threshold",
           integer(policy.availability_trend.sold_out_change_threshold)}
        ]),
      bands: %{
        base_multipliers:
          decimal_rows(
            policy.bands.base_multipliers,
            [
              {:great, "Great"},
              {:fair, "Fair"},
              {:expensive, "Expensive"}
            ],
            &multiplier/1
          ),
        trend_adjustments:
          decimal_rows(
            policy.bands.trend_adjustments,
            [
              {:rising, "Rising"},
              {:stable, "Stable"},
              {:falling, "Falling"},
              {:insufficient_history, "Insufficient history"}
            ],
            &adjustment/1
          ),
        availability_adjustments:
          decimal_rows(
            policy.bands.availability_adjustments,
            [
              {:abundant, "Abundant"},
              {:balanced, "Balanced"},
              {:scarce, "Scarce"}
            ],
            &adjustment/1
          ),
        availability_trend_adjustments:
          decimal_rows(
            policy.bands.availability_trend_adjustments,
            [
              {:improving, "Improving"},
              {:stable, "Stable"},
              {:tightening, "Tightening"},
              {:insufficient_history, "Insufficient history"}
            ],
            &adjustment/1
          ),
        guardrail:
          rows([
            {"Great ceiling guardrail", "At most aggregate typical low"},
            {"Fair ceiling guardrail", "At least aggregate benchmark"},
            {"Expensive ceiling guardrail",
             "At least aggregate typical high × #{decimal(policy.bands.expensive_minimum_high_multiplier)}"}
          ])
      },
      aggregate:
        rows([
          {"Center", "Median"},
          {"Outlier method", "Tukey IQR"},
          {"IQR multiplier",
           multiplier(policy.aggregate_delegation.outlier_policy.iqr_multiplier)}
        ]),
      rounding:
        rows([
          {"Scale", integer(policy.rounding.scale)},
          {"Mode", atom_text(policy.rounding.mode)}
        ]),
      decimal_arithmetic:
        rows([
          {"Precision", integer(policy.arithmetic_context.precision)},
          {"Rounding", atom_text(policy.arithmetic_context.rounding)},
          {"Maximum exponent", integer(policy.arithmetic_context.emax)},
          {"Minimum exponent", integer(policy.arithmetic_context.emin)},
          {"Traps", Enum.map_join(policy.arithmetic_context.traps, ", ", &atom_text/1)}
        ]),
      limited_reason_precedence:
        reasons
        |> Enum.with_index(1)
        |> Enum.map(fn {reason, position} ->
          %{position: position, label: humanized_atom(reason)}
        end)
    }
  end

  defp validate_policy(
         %{
           version: version,
           aggregate_delegation: %{source_version: aggregate_version},
           arithmetic_context: %Decimal.Context{}
         } = policy
       ) do
    if valid_version?(version, @model_version) and
         valid_version?(aggregate_version, @aggregate_version) and exact_v1_policy?(policy),
       do: :ok,
       else: {:error, :invalid_model_policy}
  end

  defp validate_policy(_), do: {:error, :invalid_model_policy}

  defp valid_version?(version, expected) when is_binary(version),
    do: version == expected and byte_size(version) <= 64

  defp valid_version?(_, _), do: false

  defp exact_v1_policy?(policy) do
    policy
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> Kernel.==(@v1_policy_fingerprint)
  rescue
    _ -> false
  end

  defp validate_reasons(@reasons), do: :ok
  defp validate_reasons(_), do: {:error, :invalid_model_policy}

  defp decimal_rows(map, labels, formatter),
    do:
      Enum.map(labels, fn {key, label} ->
        %{label: label, value: formatter.(Map.fetch!(map, key))}
      end)

  defp rows(values), do: Enum.map(values, fn {label, value} -> %{label: label, value: value} end)

  defp percentage(value),
    do: (Decimal.mult(value, Decimal.new(100)) |> Decimal.to_string(:normal)) <> "%"

  defp multiplier(value), do: Decimal.to_string(value, :normal) <> "×"
  defp decimal(value), do: Decimal.to_string(value, :normal)

  defp adjustment(value) do
    case Decimal.compare(value, Decimal.new(0)) do
      :lt -> "−" <> percentage(Decimal.abs(value))
      :gt -> "+" <> percentage(value)
      :eq -> percentage(value)
    end
  end

  defp integer(value), do: Integer.to_string(value)
  defp days(value), do: integer(value) <> " days"
  defp inclusive_days(value), do: days(value) <> " (inclusive)"
  defp boolean(true), do: "yes"
  defp boolean(false), do: "no"

  defp atom_text(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ")

  defp humanized_atom(value),
    do: value |> atom_text() |> String.capitalize()
end
