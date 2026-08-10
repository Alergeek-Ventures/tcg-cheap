defmodule TcgCheap.Catalogue.Importer do
  @moduledoc "Imports one TCGdex card and its set atomically and idempotently."
  alias TcgCheap.Catalogue.{CardPrinting, CardSet, Normalizer}
  alias TcgCheap.Core
  alias TcgCheap.Operations.AcquisitionBudget
  alias TcgCheap.Pricing.Singles.ValuationAcquisition
  alias TcgCheap.Repo

  @spec import_card(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def import_card(card_id, opts \\ [])

  def import_card(card_id, opts) when is_binary(card_id) and is_list(opts) do
    if Keyword.keyword?(opts) do
      provider = Keyword.get(opts, :provider, TcgCheap.Catalogue.Tcgdex)
      provider_options = Keyword.get(opts, :provider_options, [])

      with {:ok, clock} <- validate_options(opts, provider, provider_options),
           provider_options = budgeted_options(provider_options),
           {:ok, card} <- safe_provider_call(provider, :fetch_card, [card_id, provider_options]),
           {:ok, set_id} <- set_id(card),
           {:ok, set} <- safe_provider_call(provider, :fetch_set, [set_id, provider_options]),
           {:ok, synced_at} <- clock_datetime(clock) do
        unwrap_import_result(
          import_fetched_card(card, set, card_id,
            synced_at: synced_at,
            expected_set_id: set_id
          )
        )
      end
    else
      {:error, :invalid_options}
    end
  end

  def import_card(_, _), do: {:error, :invalid_options}

  @doc "Imports already-fetched, identity-checked provider payloads without refetching."
  @spec import_fetched_card(map(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def import_fetched_card(card, set, expected_card_id, opts \\ [])

  def import_fetched_card(card, set, expected_card_id, opts)
      when is_map(card) and is_map(set) and is_binary(expected_card_id) and is_list(opts) do
    if Keyword.keyword?(opts) and canonical_id?(expected_card_id) and
         Keyword.keys(opts) |> Enum.uniq() == Keyword.keys(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:synced_at, :expected_set_id])) do
      expected_set_id = Keyword.get(opts, :expected_set_id)

      with :ok <- validate_optional_expected_set_id(expected_set_id),
           {:ok, set_id} <- set_id(card),
           expected_set_id <- expected_set_id || set_id,
           :ok <- validate_expected_id(expected_set_id),
           :ok <- validate_payload(card, set, expected_card_id, expected_set_id),
           {:ok, synced_at} <- valid_synced_at(Keyword.get(opts, :synced_at)) do
        persist(card, set, synced_at)
      end
    else
      {:error, :invalid_options}
    end
  end

  def import_fetched_card(_, _, _, _), do: {:error, :invalid_options}

  defp unwrap_import_result({:ok, %{card: card}}), do: {:ok, card}
  defp unwrap_import_result(error), do: error

  defp validate_options(opts, provider, provider_options) do
    allowed = [:provider, :provider_options, :clock]

    cond do
      duplicate_keys?(opts) or Enum.any?(Keyword.keys(opts), &(&1 not in allowed)) ->
        {:error, :invalid_options}

      not Keyword.keyword?(provider_options) or duplicate_keys?(provider_options) ->
        {:error, :invalid_provider_options}

      not valid_provider?(provider) ->
        {:error, :invalid_provider}

      not is_function(Keyword.get(opts, :clock, &DateTime.utc_now/0), 0) ->
        {:error, :invalid_clock}

      true ->
        {:ok, Keyword.get(opts, :clock, &DateTime.utc_now/0)}
    end
  end

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

  defp valid_provider?(provider) when is_atom(provider) do
    Code.ensure_loaded?(provider) and function_exported?(provider, :fetch_card, 2) and
      function_exported?(provider, :fetch_set, 2)
  end

  defp valid_provider?(_), do: false

  defp clock_datetime(clock) do
    case clock.() do
      %DateTime{} = datetime -> valid_synced_at(datetime)
      _ -> {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp valid_synced_at(%DateTime{} = datetime) do
    {:ok, datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:microsecond)}
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp valid_synced_at(_), do: {:error, :invalid_clock}

  defp duplicate_keys?(options), do: length(options) != length(Enum.uniq(Keyword.keys(options)))

  defp budgeted_options(options),
    do:
      Keyword.put(options, :request_admitter, fn ->
        AcquisitionBudget.admit_request("tcgdex_catalogue")
      end)

  defp persist(card, set, synced_at) do
    Ash.transact(
      [
        CardSet,
        CardPrinting,
        TcgCheap.Catalogue.CardPrintingMappingDecision,
        TcgCheap.Pricing.Singles.SingleValuationSnapshot
      ],
      fn ->
        lock_set(set["id"])
        target_set = existing_set(set["id"])
        lock_card(card)
        {:ok, existing} = Core.lock_card_printing_for_update_by_tcgdex_id(card["id"])
        incoming = card_attributes(card, set, synced_at)
        persist_checked(card, set, incoming, synced_at, existing, target_set)
      end
    )
    |> case do
      {:ok, %{mapping_changed?: true, card: card} = result} ->
        ValuationAcquisition.notify_mapping_changed(card)
        {:ok, Map.delete(result, :mapping_changed?)}

      {:ok, %{mapping_changed?: false} = result} ->
        {:ok, Map.delete(result, :mapping_changed?)}

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, unwrap_conflict(reason)}
    end
  rescue
    exception -> {:error, exception}
  end

  defp persist_checked(card, set, incoming, synced_at, existing, target_set) do
    if cross_set_conflict?(existing, target_set) do
      {:error, {:card_set_conflict, %{tcgdex_id: card["id"]}}}
    else
      persist_if_fresh(
        existing,
        set,
        preserve_administrator_mapping(existing, incoming),
        synced_at,
        target_set
      )
    end
  end

  defp persist_if_fresh(existing, set, incoming, synced_at, target_set) do
    if stale?(existing, incoming),
      do: %{card: existing, outcome: :stale},
      else: persist_nonstale(existing, set, incoming, synced_at, target_set)
  end

  defp persist_nonstale(existing, set, incoming, synced_at, target_set) do
    imported_set = target_set || Core.import_card_set!(Normalizer.set_attributes(set, synced_at))
    mapping_changed? = not is_nil(existing) and mapping_changed?(existing, incoming)

    with :ok <- archive_provider_valuations(existing, incoming),
         card <- import_card_printing!(Map.put(incoming, :card_set_id, imported_set.id)),
         :ok <- record_import_decision(existing, card) do
      %{card: card, outcome: :imported, mapping_changed?: mapping_changed?}
    end
  end

  defp preserve_administrator_mapping(%{mapping_authority: "administrator"} = current, incoming) do
    Map.merge(
      incoming,
      Map.take(current, [
        :cardmarket_product_id,
        :mapping_status,
        :mapping_review_reason,
        :mapping_authority,
        :mapping_updated_at
      ])
    )
  end

  defp preserve_administrator_mapping(_existing, incoming),
    do: Map.put(incoming, :mapping_authority, "provider")

  defp import_card_printing!(attrs) do
    CardPrinting
    |> Ash.Changeset.for_create(:import, attrs)
    |> Ash.create!(authorize?: false)
  end

  defp archive_provider_valuations(nil, _incoming), do: :ok

  defp archive_provider_valuations(%{mapping_authority: "provider"} = existing, incoming) do
    if mapping_changed?(existing, incoming) do
      with {:ok, snapshots} <- Core.list_current_single_valuations(existing.id, authorize?: false),
           do: archive_snapshots(snapshots)
    else
      :ok
    end
  end

  defp archive_provider_valuations(_existing, _incoming), do: :ok

  defp archive_snapshots(snapshots) do
    Enum.reduce_while(snapshots, :ok, fn snapshot, :ok ->
      case Core.archive_single_valuation(snapshot, authorize?: false) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :valuation_archival_failed}}
      end
    end)
  end

  defp record_import_decision(nil, result), do: record_decision(result, "imported", nil)

  defp record_import_decision(existing, result) do
    if existing.mapping_authority == "provider" and mapping_changed?(existing, result) do
      record_decision(result, "provider_updated", existing)
    else
      :ok
    end
  end

  defp record_decision(result, event, previous) do
    attrs = %{
      card_printing_id: result.id,
      event: event,
      from_status: previous && previous.mapping_status,
      to_status: result.mapping_status,
      from_cardmarket_product_id: previous && previous.cardmarket_product_id,
      cardmarket_product_id: result.cardmarket_product_id,
      mapping_authority: result.mapping_authority,
      reason: result.mapping_review_reason,
      source_mapping_evidence_at: result.mapping_updated_at,
      printing_version_at: result.updated_at,
      actor_type: "system",
      actor_id: nil,
      actor_email: nil
    }

    case Core.record_card_printing_mapping_decision(attrs, authorize?: false) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :mapping_history_failed}
    end
  end

  defp mapping_changed?(left, right) do
    left.mapping_status != right.mapping_status or
      left.cardmarket_product_id != right.cardmarket_product_id or
      left.mapping_review_reason != right.mapping_review_reason
  end

  defp cross_set_conflict?(existing, nil), do: existing && existing.card_set_id != nil

  defp cross_set_conflict?(existing, target_set),
    do: existing && existing.card_set_id && existing.card_set_id != target_set.id

  defp existing_set(tcgdex_id) do
    case Core.get_card_set_by_tcgdex_id(tcgdex_id) do
      {:ok, existing} -> existing
      {:error, _} -> nil
    end
  end

  defp unwrap_conflict(%{value: [{:card_set_conflict, detail}]}), do: {:card_set_conflict, detail}
  defp unwrap_conflict(reason), do: reason

  defp lock_card(card) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "tcgdex-card:" <> card["id"]
    ])

    :ok
  end

  defp lock_set(set_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["tcgdex-set:" <> set_id])

    :ok
  end

  defp stale?(nil, _incoming), do: false

  defp stale?(existing, incoming) do
    stale_dimension?(existing.source_updated_at, incoming.source_updated_at) or
      stale_dimension?(existing.mapping_updated_at, incoming.mapping_updated_at)
  end

  defp stale_dimension?(nil, _incoming), do: false
  defp stale_dimension?(_existing, nil), do: true
  defp stale_dimension?(existing, incoming), do: DateTime.compare(incoming, existing) == :lt

  defp set_id(%{"set" => %{"id" => id}}) when is_binary(id) and id != "", do: {:ok, id}
  defp set_id(%{"set" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp set_id(_), do: {:error, {:malformed_response, :missing_set}}

  defp validate_expected_id(id) when is_binary(id) do
    if canonical_id?(id), do: :ok, else: {:error, :invalid_id}
  end

  defp validate_expected_id(_), do: {:error, :invalid_id}
  defp validate_optional_expected_set_id(nil), do: :ok
  defp validate_optional_expected_set_id(id), do: validate_expected_id(id)

  defp canonical_id?(id),
    do:
      Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, String.trim(id)) and
        String.trim(id) == id

  defp validate_payload(card, set, expected_card_id, expected_set_id) do
    case validate_card_identity(card, expected_card_id) do
      :ok ->
        with {:ok, card_set_id} <- set_id(card),
             true <- card_set_id == expected_set_id do
          validate_set_identity(set, expected_set_id)
        else
          false ->
            {:error,
             {:malformed_response, {:card_set_id_mismatch, expected_set_id, set_id_value(card)}}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp set_id_value(%{"set" => %{"id" => id}}), do: id
  defp set_id_value(%{"set" => id}), do: id
  defp set_id_value(_), do: nil

  defp validate_card_identity(%{"id" => id, "name" => name, "localId" => local_id}, expected_id)
       when is_binary(id) and id != "" and id == expected_id and is_binary(name) and name != "" do
    if valid_local_id?(local_id),
      do: :ok,
      else: {:error, {:malformed_response, {:card, :missing_identity}}}
  end

  defp validate_card_identity(%{"id" => actual}, expected_id)
       when is_binary(actual) and actual != "",
       do: {:error, {:malformed_response, {:card_id_mismatch, expected_id, actual}}}

  defp validate_card_identity(_, _),
    do: {:error, {:malformed_response, {:card, :missing_identity}}}

  defp validate_set_identity(%{"id" => set_id, "name" => set_name}, expected_set_id)
       when is_binary(set_id) and set_id != "" and is_binary(set_name) and set_name != "",
       do:
         if(set_id == expected_set_id,
           do: :ok,
           else: {:error, {:malformed_response, {:set_id_mismatch, expected_set_id, set_id}}}
         )

  defp validate_set_identity(_, _), do: {:error, {:malformed_response, {:set, :missing_identity}}}

  defp card_attributes(card, set, synced_at) do
    {status, reason, product_id} = mapping(card)
    legalities = Map.get(card, "legal", %{})

    %{
      tcgdex_id: Map.fetch!(card, "id"),
      name: Map.fetch!(card, "name"),
      set_name: Map.fetch!(set, "name"),
      collector_number: canonical_local_id(Map.fetch!(card, "localId")),
      image_url: asset_url(Map.get(card, "image"), :card),
      rarity: Map.get(card, "rarity"),
      category: Map.get(card, "category"),
      illustrator: Map.get(card, "illustrator"),
      regulation_mark: Map.get(card, "regulationMark"),
      standard_legal: legal?(legalities, "standard"),
      expanded_legal: legal?(legalities, "expanded"),
      variant_data: Map.get(card, "variants", %{}),
      source_updated_at: parse_datetime(Map.get(card, "updated")),
      mapping_updated_at: cardmarket_updated_at(card),
      source_payload: card,
      last_synced_at: synced_at,
      cardmarket_product_id: product_id,
      mapping_status: status,
      mapping_review_reason: reason
    }
  end

  defp canonical_local_id(value), do: Normalizer.canonical_local_id(value)

  defp mapping(card) do
    ids =
      cardmarket_ids(Map.get(card, "pricing", %{})) ++
        detailed_cardmarket_ids(Map.get(card, "variants_detailed", %{}))

    ids = Enum.uniq(ids)
    variants = Map.get(card, "variants", %{})
    detailed = Map.get(card, "variants_detailed", %{})
    material = material_descriptors(variants, detailed)

    mapping_from(material, ids)
  end

  defp mapping_from(material, ids) do
    cond do
      material_review?(material) ->
        {"review", material_reason(material), nil}

      length(material.identities) > 1 ->
        {"review", "multiple material identities", nil}

      material.identities != [] ->
        {"review", "material descriptor: " <> hd(material.identities), nil}

      length(ids) > 1 ->
        {"review", "multiple Cardmarket product IDs", nil}

      ids == [] ->
        {"unmatched", nil, nil}

      true ->
        {"matched", nil, hd(ids)}
    end
  end

  defp material_review?(material) do
    material.first_edition or material.w_promo or material.stamps != [] or material.jumbo or
      material.pre_release
  end

  defp material_descriptors(variants, detailed) do
    detailed_records = records(detailed)

    first_edition =
      Map.get(variants, "firstEdition") == true or
        Enum.any?(detailed_records, &(Map.get(&1, "firstEdition") == true))

    w_promo =
      Map.get(variants, "wPromo") == true or
        Enum.any?(detailed_records, &(Map.get(&1, "wPromo") == true))

    stamps = detailed_records |> Enum.flat_map(&stamp_values/1) |> Enum.uniq() |> Enum.sort()

    jumbo =
      Map.get(variants, "jumbo") == true or
        Enum.any?(detailed_records, &(Map.get(&1, "jumbo") == true))

    pre_release =
      Map.get(variants, "preRelease") == true or
        Enum.any?(detailed_records, &(Map.get(&1, "preRelease") == true))

    identities =
      detailed_records
      |> Enum.map(&material_identity/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      first_edition: first_edition,
      w_promo: w_promo,
      stamps: stamps,
      jumbo: jumbo,
      pre_release: pre_release,
      identities: identities
    }
  end

  defp material_reason(material) do
    cond do
      material.first_edition -> "firstEdition variant"
      material.w_promo -> "wPromo variant"
      material.stamps != [] -> "stamped variant: " <> Enum.join(material.stamps, ",")
      material.jumbo -> "jumbo variant"
      material.pre_release -> "preRelease variant"
    end
  end

  defp records(value) when is_list(value), do: Enum.flat_map(value, &records/1)

  defp records(%{} = value) do
    own =
      if Enum.any?(
           Map.keys(value),
           &(&1 in [
               "type",
               "subtype",
               "stamp",
               "stamps",
               "size",
               "firstEdition",
               "wPromo",
               "jumbo",
               "preRelease",
               "foil"
             ])
         ),
         do: [value],
         else: []

    own ++ Enum.flat_map(Map.values(value), &records/1)
  end

  defp records(_), do: []

  defp stamp_values(record) do
    [Map.get(record, "stamp"), Map.get(record, "stamps")]
    |> List.flatten()
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&String.trim/1)
  end

  defp material_identity(record) do
    subtype = nonblank(Map.get(record, "subtype"))
    size = nonblank(Map.get(record, "size"))
    foil = nonblank(Map.get(record, "foil"))

    values = %{
      "subtype" => if(subtype in [nil, "unlimited"], do: nil, else: subtype),
      "size" => if(size in [nil, "standard"], do: nil, else: size),
      "foil" => foil
    }

    values = Enum.reject(values, fn {_key, value} -> value in [nil, false, "", []] end)
    if values == [], do: nil, else: inspect(values, pretty: false)
  end

  defp nonblank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp nonblank(_), do: nil

  defp asset_url(value, kind), do: Normalizer.asset_url(value, kind)

  defp cardmarket_ids(pricing) when is_map(pricing) or is_list(pricing) do
    pricing
    |> cardmarket_entries()
    |> Enum.flat_map(&ids_from_cardmarket/1)
    |> Enum.uniq()
  end

  defp cardmarket_ids(_), do: []

  defp cardmarket_entries(value) when is_map(value) do
    case Map.get(value, "cardmarket") do
      nil -> []
      cardmarket -> [cardmarket]
    end
  end

  defp cardmarket_entries(value) when is_list(value),
    do: Enum.flat_map(value, &cardmarket_entries/1)

  defp cardmarket_entries(_), do: []

  defp ids_from_cardmarket(value) when is_map(value) do
    [
      positive_int(Map.get(value, "idProduct"))
      | Map.values(value) |> Enum.flat_map(&ids_from_cardmarket/1)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp ids_from_cardmarket(value) when is_list(value),
    do: Enum.flat_map(value, &ids_from_cardmarket/1)

  defp ids_from_cardmarket(_), do: []

  defp detailed_cardmarket_ids(value) when is_map(value) do
    own =
      case Map.get(value, "pricing") do
        pricing when is_map(pricing) or is_list(pricing) -> cardmarket_ids(pricing)
        _ -> []
      end

    own ++ Enum.flat_map(Map.values(value), &detailed_cardmarket_ids/1)
  end

  defp detailed_cardmarket_ids(value) when is_list(value),
    do: Enum.flat_map(value, &detailed_cardmarket_ids/1)

  defp detailed_cardmarket_ids(_), do: []

  defp valid_local_id?(value) when is_integer(value), do: true
  defp valid_local_id?(value) when is_binary(value), do: String.trim(value) != ""
  defp valid_local_id?(_), do: false

  defp cardmarket_updated_at(card) do
    timestamps =
      [Map.get(card, "pricing", %{}), Map.get(card, "variants_detailed", %{})]
      |> Enum.flat_map(&cardmarket_updated_at_values/1)
      |> Enum.reject(&is_nil/1)

    case timestamps do
      [] -> nil
      values -> Enum.max_by(values, &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp cardmarket_updated_at_values(value) when is_map(value) do
    own =
      case Map.get(value, "cardmarket") do
        %{} = cardmarket -> [parse_datetime(Map.get(cardmarket, "updated"))]
        _ -> []
      end

    own ++ Enum.flat_map(Map.values(value), &cardmarket_updated_at_values/1)
  end

  defp cardmarket_updated_at_values(value) when is_list(value),
    do: Enum.flat_map(value, &cardmarket_updated_at_values/1)

  defp cardmarket_updated_at_values(_), do: []

  defp legal?(map, key) do
    case Map.get(map, key) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp positive_int(value) when is_integer(value) and value > 0, do: value
  defp positive_int(_), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> date
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
