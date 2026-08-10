defmodule TcgCheap.Catalogue.Sync do
  @moduledoc """
  Enumerates TCGdex sets and safely seeds their card briefs.

  `cards_seeded` counts successful inserts and safe pending-row refreshes;
  `cards_preserved` counts authoritative upserts skipped by the safety condition.
  TCG Pocket sets are reported as exclusions rather than failures.
  """

  alias TcgCheap.Catalogue.{CardPrinting, CardSet, Normalizer, Tcgdex}
  alias TcgCheap.{Core, Repo}
  alias TcgCheap.Operations.AcquisitionBudget
  alias TcgCheap.Operations.ImportIssues

  @type result :: %{
          set_id: String.t(),
          cards_seen: non_neg_integer(),
          cards_seeded: non_neg_integer(),
          cards_preserved: non_neg_integer()
        }

  def sync_set(set_id, opts \\ [])

  def sync_set(set_id, opts) when is_binary(set_id) and is_list(opts) do
    with {:ok, set_id} <- canonical_id(set_id),
         {:ok, provider, provider_options, clock, request_admitter} <-
           validate_options(opts, :set) do
      provider
      |> safe_provider_call(:fetch_set, [
        set_id,
        budgeted_options(provider_options, request_admitter)
      ])
      |> handle_set_fetch(set_id, clock)
    end
  end

  def sync_set(_, _), do: {:error, :invalid_options}

  defp handle_set_fetch({:error, reason} = error, set_id, _clock) do
    _ = record_issue("set_fetch", "set", set_id, reason)
    error
  end

  defp handle_set_fetch({:ok, set}, set_id, clock) do
    set
    |> validate_set_identity(set_id)
    |> handle_set_validation(set, set_id, clock)
  end

  defp handle_set_validation({:error, reason} = error, _set, set_id, _clock) do
    _ = record_issue("set_validation", "set", set_id, reason)
    error
  end

  defp handle_set_validation(:ok, set, set_id, clock) do
    if tcg_pocket?(set),
      do: {:ok, excluded_result(set_id)},
      else: sync_supported_set(set, set_id, clock)
  end

  defp sync_supported_set(set, set_id, clock) do
    case validate_set(set, set_id) do
      {:ok, cards} ->
        sync_cards(set, set_id, cards, clock)

      {:error, reason} = error ->
        _ = record_issue("set_validation", "set", set_id, reason)
        error
    end
  end

  defp sync_cards(set, set_id, cards, clock) do
    case clock_datetime(clock) do
      {:ok, synced_at} ->
        set
        |> Map.merge(%{"id" => set_id, "name" => String.trim(set["name"])})
        |> persist(cards, synced_at)
        |> handle_persist_result(set_id, synced_at)

      {:error, :invalid_clock} = error ->
        _ = record_issue("set_import", "set", set_id, :invalid_clock)
        error
    end
  end

  defp handle_persist_result({:error, reason} = error, set_id, synced_at) do
    _ =
      ImportIssues.record(
        "tcgdex_catalogue",
        "card_catalogue_sync",
        "set_import",
        "set",
        set_id,
        reason,
        synced_at
      )

    error
  end

  defp handle_persist_result(result, _set_id, _synced_at), do: result

  def sync_all_sets(opts \\ [])

  def sync_all_sets(opts) when is_list(opts) do
    case validate_options(opts, :list) do
      {:ok, provider, provider_options, clock, request_admitter} ->
        provider
        |> safe_provider_call(:list_sets, [budgeted_options(provider_options, request_admitter)])
        |> handle_catalogue_fetch(provider, provider_options, clock, request_admitter)

      error ->
        error
    end
  end

  def sync_all_sets(_), do: {:error, :invalid_options}

  def discover_set_ids(opts \\ [])

  def discover_set_ids(opts) when is_list(opts) do
    case validate_options(opts, :list) do
      {:ok, provider, provider_options, _clock, request_admitter} ->
        provider
        |> safe_provider_call(:list_sets, [budgeted_options(provider_options, request_admitter)])
        |> handle_discovery_fetch()

      error ->
        error
    end
  end

  def discover_set_ids(_), do: {:error, :invalid_options}

  defp handle_catalogue_fetch(
         {:error, reason} = error,
         _provider,
         _options,
         _clock,
         _request_admitter
       ) do
    _ = record_issue("catalogue_fetch", "catalogue", "tcgdex", reason)
    error
  end

  defp handle_catalogue_fetch({:ok, sets}, provider, provider_options, clock, request_admitter) do
    sets
    |> validate_briefs()
    |> handle_catalogue_validation(provider, provider_options, clock, request_admitter)
  end

  defp handle_discovery_fetch({:error, reason} = error) do
    _ = record_issue("catalogue_fetch", "catalogue", "tcgdex", reason)
    error
  end

  defp handle_discovery_fetch({:ok, sets}) do
    case validate_briefs(sets) do
      {:ok, briefs} ->
        {:ok, briefs |> Enum.map(& &1["id"]) |> Enum.sort()}

      {:error, reason} = error ->
        _ = record_issue("catalogue_validation", "catalogue", "tcgdex", reason)
        error
    end
  end

  defp handle_catalogue_validation(
         {:error, reason} = error,
         _provider,
         _provider_options,
         _clock,
         _request_admitter
       ) do
    _ = record_issue("catalogue_validation", "catalogue", "tcgdex", reason)
    error
  end

  defp handle_catalogue_validation(
         {:ok, sets},
         provider,
         provider_options,
         clock,
         request_admitter
       ) do
    initial = %{report() | discovered_sets: length(sets)}

    sets
    |> Enum.reduce(initial, fn %{"id" => id}, report ->
      sync_one(id, report, provider, provider_options, clock, request_admitter)
    end)
    |> Map.update!(:failures, &Enum.reverse/1)
    |> Map.update!(:exclusions, &Enum.reverse/1)
    |> then(&{:ok, &1})
  end

  defp report,
    do: %{
      discovered_sets: 0,
      synced_sets: 0,
      failed_sets: 0,
      excluded_sets: 0,
      cards_seen: 0,
      cards_seeded: 0,
      cards_preserved: 0,
      failures: [],
      exclusions: []
    }

  defp validate_options(opts, mode) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: validate_keyword_options(opts, mode),
      else: {:error, :invalid_options}
  end

  defp validate_keyword_options(opts, mode) do
    with :ok <- validate_keys(opts),
         :ok <- validate_provider_options(Keyword.get(opts, :provider_options, [])),
         {:ok, provider} <- validate_provider(Keyword.get(opts, :provider, Tcgdex), mode),
         {:ok, clock} <- validate_clock(Keyword.get(opts, :clock, &DateTime.utc_now/0)),
         {:ok, request_admitter} <-
           validate_request_admitter(
             Keyword.get(opts, :request_admitter, &default_request_admitter/0)
           ) do
      {:ok, provider, Keyword.get(opts, :provider_options, []), clock, request_admitter}
    end
  end

  defp validate_keys(opts) do
    if duplicate?(opts) or
         Enum.any?(
           Keyword.keys(opts),
           &(&1 in [:provider, :provider_options, :clock, :request_admitter] == false)
         ),
       do: {:error, :invalid_options},
       else: :ok
  end

  defp validate_provider_options(options) when is_list(options) do
    if Keyword.keyword?(options) and not duplicate?(options) and
         not Keyword.has_key?(options, :request_admitter),
       do: :ok,
       else: {:error, :invalid_provider_options}
  end

  defp validate_provider_options(_), do: {:error, :invalid_provider_options}

  defp validate_provider(provider, mode) when is_atom(provider) do
    required = if mode == :set, do: [:fetch_set], else: [:list_sets, :fetch_set]

    if Code.ensure_loaded?(provider) and
         Enum.all?(
           required,
           &function_exported?(provider, &1, if(&1 == :list_sets, do: 1, else: 2))
         ), do: {:ok, provider}, else: {:error, :invalid_provider}
  end

  defp validate_provider(_, _), do: {:error, :invalid_provider}

  defp validate_clock(clock) when is_function(clock, 0), do: {:ok, clock}
  defp validate_clock(_), do: {:error, :invalid_clock}

  defp validate_request_admitter(admitter) when is_function(admitter, 0), do: {:ok, admitter}
  defp validate_request_admitter(_), do: {:error, :invalid_request_admitter}

  defp duplicate?(list), do: length(list) != length(Enum.uniq(Keyword.keys(list)))

  defp budgeted_options(options, request_admitter),
    do: Keyword.put(options, :request_admitter, request_admitter)

  defp default_request_admitter,
    do: AcquisitionBudget.admit_request("tcgdex_catalogue")

  defp canonical_id(id) when is_binary(id) do
    id = String.trim(id)

    if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, id),
      do: {:ok, id},
      else: {:error, :invalid_id}
  end

  defp canonical_id(_), do: {:error, :invalid_id}

  defp clock_datetime(clock) do
    case clock.() do
      %DateTime{} = value -> {:ok, value}
      _ -> {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp safe_provider_call(provider, function, args) do
    case apply(provider, function, args) do
      {:ok, value}
      when (function == :fetch_set and is_map(value)) or
             (function == :list_sets and is_list(value)) ->
        {:ok, value}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:provider_callback_error, function, {:unexpected_return, other}}}
    end
  rescue
    exception -> {:error, {:provider_callback_error, function, {:raised, exception}}}
  catch
    kind, reason -> {:error, {:provider_callback_error, function, {kind, reason}}}
  end

  defp validate_set(%{"id" => id, "name" => name, "cards" => cards} = set, _expected)
       when is_binary(id) and is_binary(name) and is_list(cards) do
    total = get_in(set, ["cardCount", "total"])

    cond do
      not is_integer(total) or total < 0 ->
        {:error, {:malformed_response, {:set, :invalid_card_count_total}}}

      total != length(cards) ->
        {:error, {:malformed_response, {:set, {:truncated_cards, total, length(cards)}}}}

      true ->
        validate_cards(cards, String.trim(name))
    end
  end

  defp validate_set(_, _), do: {:error, {:malformed_response, {:set, :missing_identity}}}

  defp validate_set_identity(%{"id" => id, "name" => name}, expected)
       when is_binary(id) and is_binary(name) do
    cond do
      String.trim(id) != expected ->
        {:error, {:malformed_response, {:set_id_mismatch, expected, id}}}

      String.trim(name) == "" ->
        {:error, {:malformed_response, {:set, :missing_identity}}}

      true ->
        :ok
    end
  end

  defp validate_set_identity(_, _), do: {:error, {:malformed_response, {:set, :missing_identity}}}

  defp validate_cards(cards, set_name) do
    Enum.reduce_while(cards, {[], MapSet.new()}, fn card, {result, ids} ->
      with {:ok, brief} <- validate_card(card, set_name),
           false <- MapSet.member?(ids, brief.tcgdex_id) do
        {:cont, {[brief | result], MapSet.put(ids, brief.tcgdex_id)}}
      else
        true ->
          {:halt, {:error, {:malformed_response, {:duplicate_card_id, Map.get(card, "id")}}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {cards, _} when is_list(cards) ->
        {:ok, cards |> Enum.reverse() |> Enum.sort_by(& &1.tcgdex_id)}

      error ->
        error
    end
  end

  defp validate_card(%{"id" => id, "name" => name, "localId" => local_id} = card, set_name)
       when is_binary(id) and is_binary(name) and (is_binary(local_id) or is_integer(local_id)) do
    id = String.trim(id)
    name = String.trim(name)
    local_id = Normalizer.canonical_local_id(local_id)

    with :ok <- valid_card_identity(id, name, local_id),
         {:ok, image} <- valid_card_image(Map.get(card, "image")) do
      {:ok,
       %{
         tcgdex_id: id,
         name: name,
         set_name: set_name,
         collector_number: local_id,
         image_url: Normalizer.asset_url(image, :card)
       }}
    end
  end

  defp validate_card(_, _), do: {:error, {:malformed_response, {:card, :missing_identity}}}

  defp valid_card_identity(id, name, local_id) do
    if id != "" and name != "" and local_id != "" and
         Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, id),
       do: :ok,
       else: {:error, {:malformed_response, {:card, :missing_identity}}}
  end

  defp valid_card_image(image) when is_binary(image) or is_nil(image), do: {:ok, image}
  defp valid_card_image(_), do: {:error, {:malformed_response, {:card, :invalid_image}}}

  defp validate_briefs(sets) when is_list(sets) do
    Enum.reduce_while(sets, {[], MapSet.new()}, fn brief, {result, ids} ->
      with true <- is_map(brief),
           {:ok, id} <- canonical_id(Map.get(brief, "id")),
           name when is_binary(name) <- nonblank(Map.get(brief, "name")),
           false <- MapSet.member?(ids, id) do
        {:cont, {[Map.merge(brief, %{"id" => id, "name" => name}) | result], MapSet.put(ids, id)}}
      else
        false -> {:halt, {:error, {:malformed_response, :invalid_set_briefs}}}
        {:error, _} -> {:halt, {:error, {:malformed_response, :invalid_set_briefs}}}
        nil -> {:halt, {:error, {:malformed_response, :invalid_set_briefs}}}
        true -> {:halt, {:error, {:malformed_response, :duplicate_id}}}
      end
    end)
    |> case do
      {result, _} when is_list(result) -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end

  defp validate_briefs(_), do: {:error, {:malformed_response, :expected_array}}

  defp nonblank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp nonblank(_), do: nil

  defp persist(set, cards, synced_at) do
    case Ash.transact([CardSet, CardPrinting], fn ->
           persist_transaction(set, cards, synced_at)
         end) do
      {:ok, {:ok, seeded, preserved}} ->
        {:ok,
         %{
           set_id: set["id"],
           cards_seen: length(cards),
           cards_seeded: seeded,
           cards_preserved: preserved
         }}

      {:ok, other} ->
        other

      {:error, reason} ->
        {:error, unwrap_transaction_error(reason)}
    end
  rescue
    exception -> {:error, exception}
  end

  defp unwrap_transaction_error(%{__struct__: Ash.Error.Unknown, value: [{tag, detail}]})
       when tag in [:card_set_conflict],
       do: {tag, detail}

  defp unwrap_transaction_error(%{
         __struct__: Ash.Error.Unknown.UnknownError,
         value: [{tag, detail}]
       })
       when tag in [:card_set_conflict],
       do: {tag, detail}

  defp unwrap_transaction_error(reason), do: reason

  defp persist_transaction(set, cards, synced_at) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "tcgdex-set:" <> set["id"]
    ])

    with {:ok, imported_set} <- Core.import_card_set(Normalizer.set_attributes(set, synced_at)) do
      seed_cards(cards, imported_set.id, synced_at)
    end
  end

  defp seed_cards(cards, set_id, synced_at) do
    Enum.reduce_while(cards, {:ok, 0, 0}, fn brief, {:ok, seeded, preserved} ->
      lock_card(brief.tcgdex_id)
      attrs = brief |> Map.put(:card_set_id, set_id) |> Map.put(:last_synced_at, synced_at)

      upsert_fields =
        if is_nil(brief.image_url),
          do: [:name, :set_name, :collector_number, :card_set_id, :last_synced_at],
          else: [:name, :set_name, :collector_number, :image_url, :card_set_id, :last_synced_at]

      case Core.seed_card_printing_brief(attrs, upsert_fields: upsert_fields) do
        {:ok, card} ->
          skipped = Ash.Resource.get_metadata(card, :upsert_skipped) == true
          handle_seed_result(brief, card, set_id, skipped, seeded, preserved)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp lock_card(tcgdex_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "tcgdex-card:" <> tcgdex_id
    ])

    :ok
  end

  defp handle_seed_result(brief, card, set_id, true, _seeded, _preserved)
       when not is_nil(card.card_set_id) and card.card_set_id != set_id,
       do:
         {:halt,
          {:error,
           {:card_set_conflict,
            %{
              tcgdex_id: brief.tcgdex_id,
              existing_card_set_id: card.card_set_id,
              expected_card_set_id: set_id
            }}}}

  defp handle_seed_result(_brief, _card, _set_id, skipped, seeded, preserved),
    do: {:cont, {:ok, seeded + bool_int(!skipped), preserved + bool_int(skipped)}}

  defp bool_int(true), do: 1
  defp bool_int(false), do: 0

  defp sync_one(id, report, provider, provider_options, clock, request_admitter) do
    case sync_set(id,
           provider: provider,
           provider_options: provider_options,
           clock: clock,
           request_admitter: request_admitter
         ) do
      {:ok, result} ->
        if Map.get(result, :status) == :excluded do
          %{
            report
            | excluded_sets: report.excluded_sets + 1,
              exclusions: [%{set_id: id, reason: :tcg_pocket} | report.exclusions]
          }
        else
          %{
            report
            | synced_sets: report.synced_sets + 1,
              cards_seen: report.cards_seen + result.cards_seen,
              cards_seeded: report.cards_seeded + result.cards_seeded,
              cards_preserved: report.cards_preserved + result.cards_preserved
          }
        end

      {:error, reason} ->
        %{
          report
          | failed_sets: report.failed_sets + 1,
            failures: [%{set_id: id, stage: :sync, reason: reason} | report.failures]
        }
    end
  end

  defp record_issue(stage, target_type, target_key, reason) do
    ImportIssues.record(
      "tcgdex_catalogue",
      "card_catalogue_sync",
      stage,
      target_type,
      target_key,
      reason
    )
  end

  defp excluded_result(set_id),
    do: %{set_id: set_id, status: :excluded, cards_seen: 0, cards_seeded: 0, cards_preserved: 0}

  defp tcg_pocket?(%{"serie" => %{"id" => "tcgp"}}), do: true
  defp tcg_pocket?(%{"series" => %{"id" => "tcgp"}}), do: true
  defp tcg_pocket?(_), do: false
end
