defmodule TcgCheap.Operations.ImportIssues do
  @moduledoc "The sole normalization boundary for retained catalogue and sealed-retailer import issues."

  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionTracker

  @providers ["tcgdex_catalogue"]
  @operations ["card_catalogue_sync", "card_catalogue_enrichment"]
  @malformed_reasons [
    :malformed_provider_result,
    :malformed_batch,
    :malformed_listing,
    :duplicate_source_listing_id,
    :malformed_json,
    :malformed_shape,
    :malformed_pagination,
    :malformed_price,
    :invalid_pagination,
    :invalid_url,
    :response_too_large
  ]

  @spec record(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          term(),
          DateTime.t() | (-> term()) | nil
        ) ::
          :ok | {:error, :import_issue_persistence_failed}
  def record(provider_key, operation, stage, target_type, target_key, reason, now \\ nil) do
    with {:ok, now} <- evidence_clock(now),
         {:ok, kind, code} <- normalized_issue(provider_key, reason),
         true <- valid_identity?(provider_key, operation, stage, target_type, target_key),
         {:ok, _issue} <-
           Operations.record_import_issue(
             provider_key,
             operation,
             stage,
             target_type,
             target_key,
             kind,
             code,
             now,
             authorize?: false
           ) do
      :ok
    else
      _ -> {:error, :import_issue_persistence_failed}
    end
  rescue
    _ -> {:error, :import_issue_persistence_failed}
  catch
    _, _ -> {:error, :import_issue_persistence_failed}
  end

  defp evidence_clock(nil), do: clock(DateTime.utc_now())
  defp evidence_clock(clock) when is_function(clock, 0), do: safe_clock(clock)
  defp evidence_clock(value), do: clock(value)

  defp safe_clock(clock) do
    case clock.() do
      value -> clock(value)
    end
  rescue
    _ -> {:error, :invalid_clock}
  catch
    _, _ -> {:error, :invalid_clock}
  end

  defp normalized_issue(_provider, {:malformed_response, _}),
    do: {:ok, "malformed", "malformed_response"}

  defp normalized_issue(provider, reason)
       when provider != "tcgdex_catalogue" and reason in @malformed_reasons,
       do: {:ok, "malformed", "malformed_response"}

  defp normalized_issue(provider, reason)
       when is_tuple(reason) and tuple_size(reason) > 0 and elem(reason, 0) in @malformed_reasons,
       do: normalized_issue(provider, elem(reason, 0))

  defp normalized_issue(_provider, :unmatched_external_mapping),
    do: {:ok, "unmatched", "provider_response"}

  defp normalized_issue(_provider, :ambiguous_external_mapping),
    do: {:ok, "ambiguous", "provider_response"}

  defp normalized_issue(_provider, {:provider_callback_error, _}),
    do: {:ok, "failed", "provider_response"}

  defp normalized_issue(_provider, {:provider_callback_error, _, _}),
    do: {:ok, "failed", "provider_response"}

  defp normalized_issue(_provider, {:http_error, %{status: 408}}),
    do: {:ok, "failed", "timeout"}

  defp normalized_issue(_provider, {:http_error, %{status: 429}}),
    do: {:ok, "failed", "rate_limit"}

  defp normalized_issue(_provider, :invalid_clock), do: {:ok, "failed", "local_input"}

  defp normalized_issue(_provider, reason) do
    {:ok, "failed", AcquisitionTracker.classify(reason) |> Atom.to_string()}
  rescue
    _ -> {:error, :invalid_issue}
  end

  defp clock(%DateTime{} = value) do
    {:ok, value |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:microsecond)}
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp clock(_), do: {:error, :invalid_clock}

  defp valid_text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and value == String.trim(value)

  defp valid_target_key?("catalogue", "tcgdex"), do: true

  defp valid_target_key?("retailer", value) do
    valid_text?(value, 36) and
      Regex.match?(
        ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
        value
      ) and value == String.downcase(value)
  end

  defp valid_target_key?(target_type, value) when target_type in ["set", "card"] do
    valid_text?(value, 128) and
      Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/, value)
  end

  defp valid_target_key?(_, _), do: false

  defp valid_identity?(provider, operation, stage, target_type, target_key) do
    valid_provider?(provider) and valid_operation?(provider, operation) and
      valid_stage?(operation, stage) and valid_target_type?(operation, stage, target_type) and
      valid_target_key?(target_type, target_key)
  end

  defp valid_provider?(provider), do: provider in @providers or sealed_provider?(provider)

  defp sealed_provider?(provider) when is_binary(provider),
    do: Regex.match?(~r/\Asealed_retailer:[A-Za-z0-9][A-Za-z0-9._-]{0,143}\z/, provider)

  defp sealed_provider?(_), do: false

  defp valid_operation?("tcgdex_catalogue", operation), do: operation in @operations
  defp valid_operation?(provider, "sealed_retailer_refresh"), do: sealed_provider?(provider)
  defp valid_operation?(_, _), do: false

  defp valid_stage?("card_catalogue_sync", stage),
    do:
      stage in [
        "catalogue_fetch",
        "catalogue_validation",
        "set_fetch",
        "set_validation",
        "set_import"
      ]

  defp valid_stage?("card_catalogue_enrichment", stage),
    do: stage in ["set_fetch", "set_validation", "set_import", "card_fetch", "card_import"]

  defp valid_stage?("sealed_retailer_refresh", stage),
    do: stage in ["retailer_fetch", "listing_validation", "listing_import"]

  defp valid_stage?(_, _), do: false

  defp valid_target_type?(_, stage, "catalogue"),
    do: stage in ["catalogue_fetch", "catalogue_validation"]

  defp valid_target_type?(_, stage, "set"),
    do: stage in ["set_fetch", "set_validation", "set_import"]

  defp valid_target_type?(_, stage, "card"), do: stage in ["card_fetch", "card_import"]

  defp valid_target_type?("sealed_retailer_refresh", stage, "retailer"),
    do: stage in ["retailer_fetch", "listing_validation", "listing_import"]

  defp valid_target_type?(_, _, _), do: false
end
