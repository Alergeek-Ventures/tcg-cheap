defmodule TcgCheap.Operations.ImportIssues do
  @moduledoc "The sole normalization boundary for retained catalogue and sealed-retailer import issues."

  alias TcgCheap.Operations
  alias TcgCheap.Operations.{AcquisitionTracker, ImportIssue}

  @providers ["tcgdex_catalogue"]
  @operations ["card_catalogue_sync", "card_catalogue_enrichment"]
  @catalogue_set_lock_prefix "tcgdex-catalogue-set-import-issue:"
  @catalogue_set_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
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
           persist_record(
             provider_key,
             operation,
             stage,
             target_type,
             target_key,
             kind,
             code,
             now
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

  defp persist_record(
         "tcgdex_catalogue",
         "card_catalogue_sync",
         stage,
         "set",
         target_key,
         kind,
         code,
         now
       )
       when kind in ["partial", "malformed", "failed"] do
    case Ash.transact(ImportIssue, fn ->
           lock_catalogue_set(target_key)
           resolved_at = inherited_resolution(target_key, kind, now)

           Operations.record_import_issue(
             "tcgdex_catalogue",
             "card_catalogue_sync",
             stage,
             "set",
             target_key,
             kind,
             code,
             now,
             resolved_at,
             authorize?: false
           )
         end) do
      {:ok, {:ok, issue}} -> {:ok, issue}
      _ -> {:error, :import_issue_persistence_failed}
    end
  end

  defp persist_record(provider_key, operation, stage, target_type, target_key, kind, code, now) do
    Operations.record_import_issue(
      provider_key,
      operation,
      stage,
      target_type,
      target_key,
      kind,
      code,
      now,
      nil,
      authorize?: false
    )
  end

  defp inherited_resolution(target_key, kind, occurred_at) do
    mode = if kind in ["malformed", "failed"], do: "hard", else: "all"

    case Operations.get_catalogue_set_issue_resolution(target_key, mode, authorize?: false) do
      {:ok, %{resolved_at: watermark}} when is_struct(watermark, DateTime) ->
        before? = DateTime.compare(occurred_at, watermark) == :lt
        equal? = DateTime.compare(occurred_at, watermark) == :eq

        if (kind in ["malformed", "failed"] and (before? or equal?)) or
             (kind == "partial" and before?),
           do: watermark

      _ ->
        nil
    end
  end

  defp lock_catalogue_set(set_id) do
    TcgCheap.Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      [@catalogue_set_lock_prefix <> set_id]
    )
  end

  @doc "Returns sorted unresolved TCGdex catalogue set IDs, failing closed on overflow."
  @spec unresolved_catalogue_set_ids() ::
          {:ok, [String.t()]} | {:error, :import_issue_read_failed}
  def unresolved_catalogue_set_ids do
    case Operations.list_unresolved_catalogue_sets(authorize?: false) do
      {:ok, issues} when length(issues) <= 1000 ->
        {:ok, issues |> Enum.map(& &1.target_key) |> Enum.uniq() |> Enum.sort()}

      _ ->
        {:error, :import_issue_read_failed}
    end
  rescue
    _ -> {:error, :import_issue_read_failed}
  catch
    _, _ -> {:error, :import_issue_read_failed}
  end

  @doc "Resolves every unresolved partial or hard issue for one canonical catalogue set."
  def resolve_catalogue_set(set_id, resolved_at) do
    resolve_catalogue_set(set_id, resolved_at, :all)
  end

  @doc "Resolves only malformed and failed issues for one catalogue set."
  def resolve_hard_catalogue_set(set_id, resolved_at) do
    resolve_catalogue_set(set_id, resolved_at, :hard)
  end

  defp resolve_catalogue_set(set_id, resolved_at, mode) do
    with true <- valid_catalogue_set_id?(set_id),
         {:ok, timestamp} <- clock(resolved_at),
         {:ok, _} <- resolve_transaction(set_id, timestamp, mode) do
      :ok
    else
      _ -> {:error, :import_issue_resolution_failed}
    end
  rescue
    _ -> {:error, :import_issue_resolution_failed}
  catch
    _, _ -> {:error, :import_issue_resolution_failed}
  end

  defp resolve_transaction(set_id, timestamp, mode) do
    Ash.transact(ImportIssue, fn ->
      lock_catalogue_set(set_id)

      with {:ok, issues} <- list_resolution_issues(set_id, mode),
           true <- length(issues) <= 1000,
           :ok <- resolve_issues(issues, timestamp),
           :ok <- persist_resolution_watermark(set_id, timestamp, mode) do
        :ok
      else
        _ -> {:error, :resolve_failed}
      end
    end)
  end

  defp list_resolution_issues(set_id, :all),
    do: Operations.list_unresolved_catalogue_set(set_id, authorize?: false)

  defp list_resolution_issues(set_id, :hard),
    do: Operations.list_unresolved_hard_catalogue_set(set_id, authorize?: false)

  defp resolve_issues([], _timestamp), do: :ok

  defp resolve_issues([issue | rest], timestamp) do
    case resolution_decision(issue, timestamp) do
      :resolve ->
        case Operations.resolve_import_issue(issue, timestamp, authorize?: false) do
          {:ok, _} -> resolve_issues(rest, timestamp)
          _ -> {:error, :resolve_failed}
        end

      :skip ->
        resolve_issues(rest, timestamp)

      :reject ->
        {:error, :resolve_failed}
    end
  end

  defp resolution_decision(%{issue_kind: "partial", last_seen_at: last_seen_at}, timestamp) do
    case DateTime.compare(last_seen_at, timestamp) do
      :lt -> :resolve
      :eq -> :skip
      :gt -> :reject
    end
  end

  defp resolution_decision(
         %{issue_kind: kind, last_seen_at: last_seen_at},
         timestamp
       )
       when kind in ["malformed", "failed"] do
    case DateTime.compare(last_seen_at, timestamp) do
      :lt -> :resolve
      :eq -> :resolve
      :gt -> :reject
    end
  end

  defp resolution_decision(_, _), do: :skip

  defp persist_resolution_watermark(set_id, timestamp, :hard) do
    case Operations.record_catalogue_set_issue_resolution(
           set_id,
           "hard",
           timestamp,
           authorize?: false
         ) do
      {:ok, _} -> :ok
      _ -> {:error, :resolve_failed}
    end
  end

  defp persist_resolution_watermark(set_id, timestamp, :all) do
    with {:ok, _} <-
           Operations.record_catalogue_set_issue_resolution(
             set_id,
             "hard",
             timestamp,
             authorize?: false
           ),
         {:ok, _} <-
           Operations.record_catalogue_set_issue_resolution(
             set_id,
             "all",
             timestamp,
             authorize?: false
           ) do
      :ok
    else
      _ -> {:error, :resolve_failed}
    end
  end

  defp valid_catalogue_set_id?(value),
    do:
      is_binary(value) and Regex.match?(@catalogue_set_pattern, value) and
        String.trim(value) == value

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

  defp normalized_issue(_provider, {:partial_coverage, _}),
    do: {:ok, "partial", "partial_coverage"}

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
