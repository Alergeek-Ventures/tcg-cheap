defmodule TcgCheap.Operations.ImportIssues do
  @moduledoc "The sole normalization boundary for retained catalogue import issues."

  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionTracker

  @providers ["tcgdex_catalogue"]
  @operations ["card_catalogue_sync", "card_catalogue_enrichment"]
  @stages [
    "catalogue_fetch",
    "catalogue_validation",
    "set_fetch",
    "set_validation",
    "set_import",
    "card_fetch",
    "card_import"
  ]
  @targets ["catalogue", "set", "card"]

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
         {:ok, kind, code} <- normalized_issue(reason),
         true <-
           provider_key in @providers and operation in @operations and stage in @stages and
             target_type in @targets and valid_target_key?(target_type, target_key),
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

  defp normalized_issue({:malformed_response, _}), do: {:ok, "malformed", "malformed_response"}
  defp normalized_issue(:unmatched_external_mapping), do: {:ok, "unmatched", "provider_response"}
  defp normalized_issue(:ambiguous_external_mapping), do: {:ok, "ambiguous", "provider_response"}
  defp normalized_issue({:provider_callback_error, _}), do: {:ok, "failed", "provider_response"}

  defp normalized_issue({:provider_callback_error, _, _}),
    do: {:ok, "failed", "provider_response"}

  defp normalized_issue(:invalid_clock), do: {:ok, "failed", "local_input"}

  defp normalized_issue(reason) do
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

  defp valid_target_key?(target_type, value) when target_type in ["set", "card"] do
    valid_text?(value, 128) and Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, value)
  end

  defp valid_target_key?(_, _), do: false
end
