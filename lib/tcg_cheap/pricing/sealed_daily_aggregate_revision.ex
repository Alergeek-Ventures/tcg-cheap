defmodule TcgCheap.Pricing.SealedDailyAggregateRevision do
  @moduledoc "Deterministic identity for one persisted daily-aggregate revision."

  @aggregate_fields [
    :id,
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
    :source_mapping_confident,
    :latest_nonfuture_checked_at,
    :calculated_at,
    :source_msrp_pln
  ]

  @evidence_fields [
    :mapping_id,
    :confidence,
    :approved_at,
    :listing_id,
    :retailer_id,
    :retailer_category,
    :stock_status,
    :price_pln,
    :checked_at
  ]

  @spec fingerprint(map()) :: {:ok, String.t()} | {:error, :malformed_aggregate_revision}
  def fingerprint(aggregate) when is_map(aggregate) do
    aggregate = Map.put_new(aggregate, :source_mapping_confident, false)

    with true <- aggregate_fields_present?(aggregate),
         evidence when is_list(evidence) <- Map.get(aggregate, :source_evidence),
         {:ok, evidence} <- evidence_projection(evidence),
         {:ok, aggregate_values} <- scalar_projection(@aggregate_fields, aggregate),
         {:ok, evidence_values} <- scalar_rows(evidence) do
      digest =
        [aggregate_values, Enum.sort(evidence_values)]
        |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {:ok, digest}
    else
      _ -> {:error, :malformed_aggregate_revision}
    end
  end

  def fingerprint(_), do: {:error, :malformed_aggregate_revision}

  @spec history_fingerprint(list()) :: {:ok, String.t()} | {:error, :malformed_aggregate_revision}
  def history_fingerprint(history) when is_list(history) do
    with {:ok, fingerprints} <- history_projection(history) do
      digest =
        ["sealed_daily_aggregate_history_v1", Enum.sort(fingerprints)]
        |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {:ok, digest}
    end
  end

  def history_fingerprint(_), do: {:error, :malformed_aggregate_revision}

  defp aggregate_fields_present?(aggregate),
    do: Enum.all?(@aggregate_fields, &Map.has_key?(aggregate, &1))

  defp history_projection(history) do
    Enum.reduce_while(history, {:ok, []}, fn aggregate, {:ok, rows} ->
      case fingerprint(aggregate) do
        {:ok, fingerprint} -> {:cont, {:ok, [fingerprint | rows]}}
        {:error, :malformed_aggregate_revision} = error -> {:halt, error}
      end
    end)
  end

  defp evidence_projection(evidence) do
    Enum.reduce_while(evidence, {:ok, []}, fn row, {:ok, rows} ->
      if is_map(row) and Enum.all?(@evidence_fields, &Map.has_key?(row, &1)) do
        projected = Enum.map(@evidence_fields, &{&1, Map.get(row, &1)})
        {:cont, {:ok, [projected | rows]}}
      else
        {:halt, {:error, :malformed_aggregate_revision}}
      end
    end)
  end

  defp scalar_rows(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case scalar_projection(@evidence_fields, Map.new(row)) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp scalar_projection(fields, map) do
    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, acc} ->
      case scalar(Map.get(map, field)) do
        {:ok, value} ->
          {:cont, {:ok, [value | acc]}}

        :error ->
          {:halt, {:error, :malformed_aggregate_revision}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp scalar(nil), do: {:ok, ["nil"]}
  defp scalar(value) when is_boolean(value), do: {:ok, ["bool", value]}
  defp scalar(value) when is_integer(value), do: {:ok, ["int", Integer.to_string(value)]}

  defp scalar(value) when is_binary(value) do
    if String.valid?(value), do: {:ok, ["string", value]}, else: :error
  end

  defp scalar(%Decimal{} = value) do
    if Decimal.nan?(value) or Decimal.inf?(value),
      do: :error,
      else: {:ok, ["decimal", Decimal.to_string(Decimal.normalize(value))]}
  end

  defp scalar(%Date{} = value), do: {:ok, ["date", Date.to_iso8601(value)]}

  defp scalar(%DateTime{} = value),
    do: {:ok, ["datetime_us", Integer.to_string(DateTime.to_unix(value, :microsecond))]}

  defp scalar(_), do: :error
end
