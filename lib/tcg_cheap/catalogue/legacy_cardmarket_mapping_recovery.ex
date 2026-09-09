defmodule TcgCheap.Catalogue.LegacyCardmarketMappingRecovery do
  @moduledoc "Repairs only importer material-review rows proven by immutable history."

  alias TcgCheap.Catalogue.{CardmarketMapping, CardPrinting, CardSet, Importer, Tcgdex}
  alias TcgCheap.Core
  require Ash.Query
  import Ash.Expr

  @page_size 500
  @max_scan 100_000
  @legacy_reasons [
    "firstEdition variant",
    "wPromo variant",
    "jumbo variant",
    "preRelease variant"
  ]

  def run(opts \\ []) do
    with {:ok, options} <- validate_options(opts),
         {:ok, candidates} <- snapshot_candidates(options) do
      process_snapshot(candidates, initial_counts(), options)
    end
  end

  defp initial_counts do
    %{
      scanned: 0,
      recovered: 0,
      unchanged: 0,
      categories: %{
        unsupported_reason: 0,
        unverified_history: 0,
        missing_payload: 0,
        malformed_payload: 0,
        still_ambiguous: 0,
        no_change: 0
      }
    }
  end

  defp validate_options(opts) when is_list(opts) do
    max_scan = Keyword.get(opts, :max_scan, @max_scan)
    page_size = Keyword.get(opts, :page_size, @page_size)

    valid? =
      Keyword.keyword?(opts) and Keyword.keys(opts) |> Enum.uniq() == Keyword.keys(opts) and
        Enum.all?(Keyword.keys(opts), &(&1 in [:max_scan, :page_size])) and
        valid_bound?(max_scan, 1, 100_000) and valid_bound?(page_size, 1, 10_000)

    if valid?,
      do: {:ok, %{max_scan: max_scan, page_size: page_size}},
      else: {:error, :invalid_options}
  end

  defp validate_options(_), do: {:error, :invalid_options}

  defp valid_bound?(value, min, max), do: is_integer(value) and value in min..max

  defp snapshot_candidates(options), do: snapshot_candidates(nil, [], options)

  defp snapshot_candidates(cursor, candidates, options) do
    remaining = options.max_scan + 1 - length(candidates)
    query = candidate_query(min(options.page_size, remaining)) |> after_cursor(cursor)

    case Ash.read(query, authorize?: false) do
      {:ok, []} ->
        {:ok, Enum.reverse(candidates)}

      {:ok, rows} when is_list(rows) ->
        process_candidate_page(cursor, candidates, options, rows)

      {:error, reason} ->
        {:error, {:persistence, reason}}

      other ->
        {:error, {:persistence, {:malformed_page, other}}}
    end
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, {tcgdex_id, id}) do
    Ash.Query.filter(
      query,
      expr(tcgdex_id > ^tcgdex_id or (tcgdex_id == ^tcgdex_id and id > ^id))
    )
  end

  defp process_candidate_page(cursor, candidates, options, rows) do
    last_row = List.last(rows)

    if advancing_cursor?(cursor, last_row) do
      frozen = Enum.map(rows, &freeze_candidate/1)
      accumulated = Enum.reverse(frozen, candidates)
      continue_snapshot(accumulated, options, last_row)
    else
      {:error, {:persistence, :non_advancing_recovery_cursor}}
    end
  end

  defp continue_snapshot(candidates, options, last_row) do
    if length(candidates) > options.max_scan do
      {:error, {:persistence, {:scan_cap_exceeded, options.max_scan}}}
    else
      snapshot_candidates({last_row.tcgdex_id, last_row.id}, candidates, options)
    end
  end

  defp process_snapshot(candidates, counts, options) do
    Enum.reduce_while(
      Enum.chunk_every(candidates, options.page_size),
      {:ok, counts},
      &process_snapshot_chunk/2
    )
  end

  defp process_snapshot_chunk(chunk, {:ok, acc}) do
    case reload_rows(chunk) do
      {:ok, rows} -> process_reloaded_chunk(chunk, rows, acc)
      {:error, reason} -> {:halt, {:error, {:persistence, reason}}}
    end
  end

  defp process_reloaded_chunk(chunk, rows, acc) do
    by_id = Map.new(rows, &{&1.id, &1})
    current = Enum.zip(chunk, Enum.map(chunk, &Map.get(by_id, &1.id)))

    case process_rows(current, %{acc | scanned: acc.scanned + length(chunk)}) do
      {:ok, updated} -> {:cont, {:ok, updated}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp candidate_query(limit) do
    query =
      Ash.Query.for_read(CardPrinting, :read, %{})
      |> Ash.Query.filter(expr(mapping_status == "review" and mapping_authority == "provider"))
      |> Ash.Query.select([
        :id,
        :tcgdex_id,
        :card_set_id,
        :mapping_status,
        :mapping_authority,
        :mapping_review_reason,
        :mapping_updated_at,
        :updated_at
      ])
      |> Ash.Query.sort(tcgdex_id: :asc, id: :asc)

    if is_integer(limit), do: Ash.Query.limit(query, limit), else: query
  end

  defp freeze_candidate(row) do
    Map.take(row, [
      :id,
      :tcgdex_id,
      :card_set_id,
      :mapping_status,
      :mapping_authority,
      :mapping_review_reason,
      :mapping_updated_at,
      :updated_at
    ])
  end

  defp reload_rows(candidates) do
    ids = Enum.map(candidates, & &1.id)

    CardPrinting
    |> Ash.Query.for_read(:read, %{})
    |> Ash.Query.filter(expr(id in ^ids))
    |> Ash.Query.select([
      :id,
      :tcgdex_id,
      :card_set_id,
      :mapping_status,
      :mapping_authority,
      :mapping_review_reason,
      :mapping_updated_at,
      :updated_at,
      :last_synced_at,
      :details_synced_at,
      :source_payload
    ])
    |> Ash.read(authorize?: false)
  end

  defp process_rows(rows, counts) do
    Enum.reduce_while(rows, {:ok, counts}, fn row, {:ok, acc} ->
      case repair(row) do
        :recovered ->
          {:cont, {:ok, %{acc | recovered: acc.recovered + 1}}}

        {:unchanged, category} ->
          {:cont,
           {:ok,
            %{
              acc
              | unchanged: acc.unchanged + 1,
                categories: increment_category(acc.categories, category)
            }}}

        {:error, reason} ->
          {:halt, {:error, {:persistence, reason}}}
      end
    end)
  end

  defp repair({_reference, nil}), do: {:unchanged, :no_change}

  defp repair({reference, card}) do
    if current_snapshot_matches?(reference, card),
      do: repair_current(card),
      else: {:unchanged, :no_change}
  end

  defp repair_current(card) do
    with :ok <- valid_persisted_ids(card),
         :ok <- legacy_reason(card.mapping_review_reason),
         :ok <- qualifying_history(card),
         {:ok, payload, set_payload} <- persisted_payloads(card),
         {:ok, expected_set_id} <- valid_set_payload(set_payload),
         classification <- CardmarketMapping.classify(payload),
         %{status: "matched", cardmarket_product_id: product_id} <- classification,
         synced_at when is_struct(synced_at, DateTime) <-
           card.details_synced_at || card.last_synced_at,
         {:ok, result} <-
           Importer.import_fetched_card(payload, set_payload, card.tcgdex_id,
             synced_at: synced_at,
             expected_set_id: expected_set_id,
             expected_updated_at: card.updated_at,
             notify?: false
           ),
         :ok <- recovery_result(result, product_id) do
      :recovered
    else
      {:error, :unsupported_reason} -> {:unchanged, :unsupported_reason}
      :unchanged -> {:unchanged, :no_change}
      {:error, :ineligible} -> {:unchanged, :unverified_history}
      {:error, :malformed_payload} -> {:unchanged, :malformed_payload}
      {:error, :still_ambiguous} -> {:unchanged, :still_ambiguous}
      {:error, :no_change} -> {:unchanged, :no_change}
      {:error, :missing_payload} -> {:unchanged, :missing_payload}
      {:error, {:malformed_response, _}} -> {:unchanged, :malformed_payload}
      {:error, reason} -> {:error, reason}
      %{} -> {:unchanged, :still_ambiguous}
      _ -> {:unchanged, :still_ambiguous}
    end
  end

  defp current_snapshot_matches?(reference, card) do
    Enum.all?(
      [
        :tcgdex_id,
        :card_set_id,
        :mapping_status,
        :mapping_authority,
        :mapping_review_reason,
        :mapping_updated_at,
        :updated_at
      ],
      fn field ->
        Map.get(reference, field) == Map.get(card, field)
      end
    )
  end

  defp valid_persisted_ids(card) do
    if Tcgdex.valid_card_id?(card.tcgdex_id), do: :ok, else: {:error, :malformed_payload}
  end

  # The strict immutable-history predicate is kept together to make every safety condition explicit.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp qualifying_history(card) do
    case Core.list_card_printing_mapping_decision_history(card.id, authorize?: false) do
      {:ok, history} ->
        # All immutable-history checks are intentionally conjunctive and fail closed.
        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        if valid_current_timestamps?(card) and
             Enum.any?(history, &qualifying_decision?(&1, card)),
           do: :ok,
           else: {:error, :ineligible}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_current_timestamps?(card) do
    valid_datetime?(card.mapping_updated_at) and valid_datetime?(card.updated_at)
  end

  # Baseline is retained for old backfills where it may be the only immutable
  # record.  It is safe only under the same exact-current checks as imported.
  defp qualifying_decision?(decision, card) do
    decision_shape?(decision) and qualifying_decision_identity?(decision, card) and
      qualifying_decision_timestamps?(decision)
  end

  defp qualifying_decision_identity?(decision, card) do
    decision.to_status == "review" and
      is_nil(decision.cardmarket_product_id) and
      decision.mapping_authority == "provider" and
      decision.actor_type == "system" and
      is_nil(decision.actor_id) and
      is_nil(decision.actor_email) and
      decision.reason == card.mapping_review_reason and
      decision.source_mapping_evidence_at == card.mapping_updated_at and
      decision.printing_version_at == card.updated_at
  end

  defp qualifying_decision_timestamps?(decision) do
    valid_datetime?(decision.source_mapping_evidence_at) and
      valid_datetime?(decision.printing_version_at)
  end

  defp decision_shape?(%{event: event} = decision) when event in ["baseline", "imported"] do
    is_nil(decision.from_status) and is_nil(decision.from_cardmarket_product_id)
  end

  defp decision_shape?(%{event: "provider_updated", from_status: from_status} = decision)
       when from_status in ["pending", "unmatched", "review"] do
    is_nil(decision.from_cardmarket_product_id)
  end

  defp decision_shape?(%{event: "provider_updated", from_status: "matched"} = decision) do
    is_integer(decision.from_cardmarket_product_id) and decision.from_cardmarket_product_id > 0
  end

  defp decision_shape?(_), do: false

  defp valid_datetime?(%DateTime{} = timestamp) do
    DateTime.to_unix(timestamp, :microsecond)
    true
  rescue
    ArgumentError -> false
  end

  defp valid_datetime?(_), do: false

  defp persisted_payloads(%{source_payload: payload, card_set_id: set_id}) when is_map(payload) do
    with :ok <- valid_payload_card_id(payload),
         {:ok, payload_set_id} <- payload_set_id(payload),
         {:ok, set} <- load_set(payload_set_id),
         true <- set.id == set_id,
         set_payload when is_map(set_payload) <- set.source_payload do
      {:ok, payload, set_payload}
    else
      false -> {:error, :malformed_payload}
      nil -> {:error, :missing_payload}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_payload}
    end
  end

  defp persisted_payloads(_), do: {:error, :missing_payload}

  defp valid_payload_card_id(%{"id" => id}) when is_binary(id) and id != "" do
    if Tcgdex.valid_card_id?(id), do: :ok, else: {:error, :malformed_payload}
  end

  defp valid_payload_card_id(_), do: {:error, :malformed_payload}

  defp load_set(id) do
    query =
      Ash.Query.for_read(CardSet, :by_tcgdex_id, %{tcgdex_id: id})
      |> Ash.Query.select([:id, :source_payload])

    case Ash.read_one(query, authorize?: false) do
      {:ok, nil} -> {:error, :missing_payload}
      {:ok, set} -> {:ok, set}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recovered_result?(
         %{
           card: %{
             mapping_status: "matched",
             mapping_authority: "provider",
             cardmarket_product_id: id
           }
         },
         id
       ),
       do: true

  defp recovered_result?(_, _), do: false

  defp recovery_result(result, product_id) do
    cond do
      recovered_result?(result, product_id) -> :ok
      match?(%{outcome: :stale}, result) -> {:error, :no_change}
      true -> {:error, :still_ambiguous}
    end
  end

  defp legacy_reason(reason) do
    if reason in @legacy_reasons or String.starts_with?(reason || "", "stamped variant:") or
         String.starts_with?(reason || "", "material descriptor:") do
      :ok
    else
      {:error, :unsupported_reason}
    end
  end

  defp payload_set_id(%{"set" => %{"id" => id}}) when is_binary(id) and id != "" do
    if Tcgdex.valid_set_id?(id), do: {:ok, id}, else: {:error, :malformed_payload}
  end

  defp payload_set_id(%{"set" => id}) when is_binary(id) and id != "" do
    if Tcgdex.valid_set_id?(id), do: {:ok, id}, else: {:error, :malformed_payload}
  end

  defp payload_set_id(_), do: {:error, :malformed_payload}

  defp valid_set_payload(%{"id" => id, "name" => name})
       when is_binary(id) and is_binary(name) do
    if Tcgdex.valid_set_id?(id) and String.trim(name) != "",
      do: {:ok, id},
      else: {:error, :malformed_payload}
  end

  defp valid_set_payload(_), do: {:error, :malformed_payload}

  defp increment_category(categories, category), do: Map.update!(categories, category, &(&1 + 1))

  defp advancing_cursor?(nil, %{tcgdex_id: tcgdex_id, id: id})
       when is_binary(tcgdex_id) and not is_nil(id),
       do: true

  defp advancing_cursor?({previous_tcgdex_id, previous_id}, %{tcgdex_id: tcgdex_id, id: id}) do
    {tcgdex_id, id} > {previous_tcgdex_id, previous_id}
  end

  defp advancing_cursor?(_, _), do: false
end
