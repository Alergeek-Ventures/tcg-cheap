defmodule TcgCheap.Catalogue.Enrichment do
  @moduledoc "Bounded, set-level enrichment of detailed TCGdex cards."

  alias TcgCheap.Catalogue.{Importer, Tcgdex}
  alias TcgCheap.Operations.AcquisitionBudget

  @default_concurrency 4
  @default_timeout 30_000
  @max_concurrency 16
  @max_timeout 120_000
  @max_cards 1_000

  def enrich_set(set_id, opts \\ [])

  def enrich_set(set_id, opts) when is_binary(set_id) and is_list(opts) do
    with {:ok, set_id} <- canonical_id(set_id),
         {:ok, config} <- validate_options(opts),
         {:ok, set} <-
           provider_call_with_timeout(
             config.provider,
             :fetch_set,
             [set_id, config.provider_options],
             config.fetch_timeout
           ),
         :ok <- validate_set_identity(set, set_id) do
      if pocket?(set) do
        {:ok,
         %{
           status: :excluded,
           reason: :tcg_pocket,
           set_id: set_id,
           cards_seen: 0,
           cards_enriched: 0,
           cards_preserved: 0,
           cards_failed: 0,
           failures: []
         }}
      else
        enrich_validated_cards(set, set_id, config)
      end
    end
  end

  def enrich_set(_, _), do: {:error, :invalid_options}

  defp enrich_validated_cards(set, set_id, config) do
    case validate_cards(set) do
      {:ok, card_ids} -> enrich_cards(set, set_id, card_ids, config)
      error -> error
    end
  end

  defp enrich_cards(set, set_id, card_ids, config) do
    fetched =
      Task.async_stream(
        card_ids,
        fn card_id ->
          case safe_provider_call(config.provider, :fetch_card, [card_id, config.provider_options]) do
            {:ok, card} -> {:ok, card}
            {:error, reason} -> {:error, reason}
          end
        end,
        ordered: true,
        max_concurrency: config.max_concurrency,
        timeout: config.fetch_timeout,
        on_timeout: :kill_task
      )
      |> Enum.zip(card_ids)

    results =
      Enum.map(fetched, fn {result, card_id} ->
        case result do
          {:ok, {:ok, card}} -> {:ok, card_id, card}
          {:ok, {:error, reason}} -> {:error, card_id, :fetch, reason}
          {:exit, reason} -> {:error, card_id, :fetch, {:task_exit, reason}}
        end
      end)

    with {:ok, synced_at} <- clock_datetime(config.clock) do
      {enriched, preserved, failures} =
        Enum.reduce(results, {0, 0, []}, fn
          {:error, card_id, stage, reason}, {count, preserved, failures} ->
            {count, preserved, [{card_id, stage, reason} | failures]}

          {:ok, card_id, card}, {count, preserved, failures} ->
            import_result(card, set, set_id, card_id, synced_at, count, preserved, failures)
        end)

      {:ok,
       %{
         status: :completed,
         set_id: set_id,
         cards_seen: length(card_ids),
         cards_enriched: enriched,
         cards_preserved: preserved,
         cards_failed: length(failures),
         failures:
           Enum.reverse(
             Enum.map(failures, fn {card_id, stage, reason} ->
               %{card_id: card_id, stage: stage, reason: reason}
             end)
           )
       }}
    end
  end

  defp import_result(card, set, set_id, card_id, synced_at, count, preserved, failures) do
    case Importer.import_fetched_card(card, set, card_id,
           synced_at: synced_at,
           expected_set_id: set_id
         ) do
      {:ok, %{outcome: :imported}} ->
        {count + 1, preserved, failures}

      {:ok, %{outcome: :stale}} ->
        {count, preserved + 1, failures}

      {:error, reason} ->
        {count, preserved, [{card_id, :import, reason} | failures]}
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp validate_options(opts) do
    allowed = [:provider, :provider_options, :clock, :max_concurrency, :fetch_timeout]

    cond do
      not Keyword.keyword?(opts) or duplicate?(opts) or
          Enum.any?(Keyword.keys(opts), &(&1 not in allowed)) ->
        {:error, :invalid_options}

      not valid_provider_options?(Keyword.get(opts, :provider_options, [])) ->
        {:error, :invalid_provider_options}

      not valid_provider?(Keyword.get(opts, :provider, Tcgdex)) ->
        {:error, :invalid_provider}

      not is_function(Keyword.get(opts, :clock, &DateTime.utc_now/0), 0) ->
        {:error, :invalid_clock}

      not valid_bound?(
        Keyword.get(opts, :max_concurrency, @default_concurrency),
        @max_concurrency
      ) ->
        {:error, :invalid_max_concurrency}

      not valid_bound?(Keyword.get(opts, :fetch_timeout, @default_timeout), @max_timeout) ->
        {:error, :invalid_fetch_timeout}

      true ->
        {:ok,
         %{
           provider: Keyword.get(opts, :provider, Tcgdex),
           provider_options: budgeted_options(Keyword.get(opts, :provider_options, [])),
           clock: Keyword.get(opts, :clock, &DateTime.utc_now/0),
           max_concurrency: Keyword.get(opts, :max_concurrency, @default_concurrency),
           fetch_timeout: Keyword.get(opts, :fetch_timeout, @default_timeout)
         }}
    end
  end

  defp valid_bound?(value, max), do: is_integer(value) and value > 0 and value <= max

  defp valid_provider_options?(value),
    do: is_list(value) and Keyword.keyword?(value) and not duplicate?(value)

  defp valid_provider?(provider) when is_atom(provider),
    do:
      Code.ensure_loaded?(provider) and function_exported?(provider, :fetch_set, 2) and
        function_exported?(provider, :fetch_card, 2)

  defp valid_provider?(_), do: false
  defp duplicate?(list), do: length(list) != length(Enum.uniq(Keyword.keys(list)))

  defp budgeted_options(options),
    do:
      Keyword.put(options, :request_admitter, fn ->
        AcquisitionBudget.admit_request("tcgdex_catalogue")
      end)

  defp safe_provider_call(provider, function, args) do
    case apply(provider, function, args) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:provider_callback_error, function, {:unexpected_return, other}}}
    end
  rescue
    exception -> {:error, {:provider_callback_error, function, {:raised, exception}}}
  catch
    kind, reason -> {:error, {:provider_callback_error, function, {kind, reason}}}
  end

  defp provider_call_with_timeout(provider, function, args, timeout) do
    task = Task.async(fn -> safe_provider_call(provider, function, args) end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error, {:provider_callback_error, function, {:exit, reason}}}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:provider_timeout, function}}
    end
  end

  defp canonical_id(id) do
    id = String.trim(id)

    if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, id),
      do: {:ok, id},
      else: {:error, :invalid_id}
  end

  defp validate_set_identity(%{"id" => id, "name" => name}, expected)
       when is_binary(id) and is_binary(name) do
    cond do
      id != expected ->
        {:error, {:malformed_response, {:set_id_mismatch, expected, id}}}

      String.trim(name) == "" ->
        {:error, {:malformed_response, {:set, :missing_identity}}}

      true ->
        :ok
    end
  end

  defp validate_set_identity(_, _), do: {:error, {:malformed_response, {:set, :missing_identity}}}

  defp validate_cards(%{"cards" => cards, "cardCount" => %{"total" => total}})
       when is_list(cards) and is_integer(total) and total >= 0 do
    if total != length(cards),
      do: {:error, {:malformed_response, {:set, {:truncated_cards, total, length(cards)}}}},
      else:
        if(total > @max_cards,
          do: {:error, {:malformed_response, {:set, :too_many_cards}}},
          else: validate_card_ids(cards)
        )
  end

  defp validate_cards(_), do: {:error, {:malformed_response, {:set, :invalid_card_count_total}}}

  defp validate_card_ids(cards) do
    Enum.reduce_while(cards, {[], MapSet.new()}, fn card, {ids, seen} ->
      with {:ok, id} <- card_id(card), false <- MapSet.member?(seen, id) do
        {:cont, {[id | ids], MapSet.put(seen, id)}}
      else
        true ->
          {:halt, {:error, {:malformed_response, {:duplicate_card_id, Map.get(card, "id")}}}}

        _ ->
          {:halt, {:error, {:malformed_response, {:card, :missing_identity}}}}
      end
    end)
    |> case do
      {ids, _} when is_list(ids) -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp card_id(%{"id" => id}) when is_binary(id), do: canonical_id(id)
  defp card_id(_), do: {:error, :invalid_id}
  defp pocket?(%{"serie" => %{"id" => "tcgp"}}), do: true
  defp pocket?(%{"series" => %{"id" => "tcgp"}}), do: true
  defp pocket?(_), do: false

  defp clock_datetime(clock) do
    case clock.() do
      %DateTime{} = value ->
        {:ok, value |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:microsecond)}

      _ ->
        {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end
end
