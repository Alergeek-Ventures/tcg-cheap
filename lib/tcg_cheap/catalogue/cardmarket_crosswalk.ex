defmodule TcgCheap.Catalogue.CardmarketCrosswalk do
  @moduledoc "Conservative, exact-batch Cardmarket expansion and card crosswalk."

  alias TcgCheap.Catalogue.{
    CardmarketCardMappingEvidence,
    CardmarketExpansionMapping,
    CardPrinting,
    MaterialVariant,
    SearchText
  }

  alias TcgCheap.Core
  alias TcgCheap.Pricing.CardmarketBulk.{Batch, Product}
  require Ash.Query
  import Ash.Expr

  @chunk 1_000
  @canonical_set_limit 10_000
  @prefix "cardmarket_bulk_v1:"

  def run(%Batch{} = batch) do
    with {:ok, anchors} <- load_anchors(),
         {:ok, anchor_products} <- load_products(anchors, batch.id),
         {:ok, pairs} <- observed_pairs(anchors, anchor_products),
         {:ok, mappings} <- persist_expansion_pairs(batch, pairs),
         {:ok, existing} <- existing_evidence(batch.id),
         {:ok, canonical_sets} <- canonical_sets() do
      process_pairs(batch, mappings, anchors, pairs, existing, canonical_sets)
    end
  end

  def run(_), do: {:error, :invalid_batch}

  defp load_anchors do
    load_anchor_page(nil, [])
  end

  defp load_anchor_page(cursor, acc) do
    case Core.list_cardmarket_anchors(cursor, @chunk, authorize?: false) do
      {:ok, []} ->
        {:ok, Enum.reverse(acc)}

      {:ok, rows} when is_list(rows) ->
        case anchor_page_cursor(rows, cursor) do
          {:ok, next_cursor} ->
            # Keep pages in the accumulator in reverse order and reverse once at
            # the end, rather than repeatedly appending pages to a growing list.
            load_anchor_page(next_cursor, Enum.reverse(rows, acc))

          :error ->
            {:error, {:persistence, :malformed_cardmarket_anchors_page}}
        end

      {:error, reason} ->
        {:error, {:persistence, reason}}

      other ->
        {:error, {:persistence, {:malformed_cardmarket_anchors_response, other}}}
    end
  end

  defp anchor_page_cursor(rows, cursor) do
    result =
      Enum.reduce_while(rows, cursor, fn
        %CardPrinting{tcgdex_id: tcgdex_id}, previous
        when is_binary(tcgdex_id) and byte_size(tcgdex_id) > 0 ->
          if is_nil(previous) or tcgdex_id > previous do
            {:cont, tcgdex_id}
          else
            {:halt, :error}
          end

        _row, _previous ->
          {:halt, :error}
      end)

    case result do
      :error -> :error
      next_cursor when is_binary(next_cursor) -> {:ok, next_cursor}
    end
  end

  defp load_products(anchors, batch_id) do
    anchors
    |> Enum.map(& &1.cardmarket_product_id)
    |> Enum.uniq()
    |> Enum.chunk_every(@chunk)
    |> Enum.reduce_while({:ok, []}, fn ids, {:ok, acc} ->
      query = Product |> Ash.Query.for_read(:by_product_ids, %{cardmarket_product_ids: ids})
      query = Ash.Query.filter(query, expr(last_batch_id == ^batch_id))

      case Ash.read(query, domain: TcgCheap.Core, authorize?: false) do
        {:ok, rows} -> {:cont, {:ok, Enum.reverse(rows, acc)}}
        {:error, reason} -> {:halt, {:error, {:persistence, reason}}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp observed_pairs(anchors, products) do
    by_product = Map.new(products, &{&1.cardmarket_product_id, &1.expansion_id})

    {observed, missing} =
      Enum.reduce(anchors, {%{}, 0}, fn anchor, {pairs, missing} ->
        case Map.get(by_product, anchor.cardmarket_product_id) do
          nil ->
            {pairs, missing + 1}

          expansion ->
            {Map.update(pairs, {anchor.card_set_id, expansion}, [anchor], &[anchor | &1]),
             missing}
        end
      end)

    {:ok, %{pairs: observed, missing_anchor_products: missing}}
  end

  defp persist_expansion_pairs(batch, %{pairs: pairs}) do
    sets_by_expansion = pairs |> Map.keys() |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    expansions_by_set = pairs |> Map.keys() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    pairs
    |> Enum.sort_by(fn {{set_id, expansion_id}, _} -> {set_id, expansion_id} end)
    |> Enum.reduce_while({:ok, []}, fn {{set_id, expansion_id}, anchors}, {:ok, acc} ->
      set_degree = length(Map.get(expansions_by_set, set_id, []))
      expansion_degree = length(Map.get(sets_by_expansion, expansion_id, []))
      approved? = set_degree == 1 and expansion_degree == 1
      reason = if approved?, do: nil, else: review_reason(set_degree, expansion_degree)

      attrs = %{
        source_batch_id: batch.id,
        card_set_id: set_id,
        expansion_id: expansion_id,
        status: if(approved?, do: "approved", else: "review"),
        authority: "system",
        anchor_count: length(anchors),
        review_reason: reason,
        evidence: %{
          "anchor_card_printing_ids" => Enum.map(anchors, & &1.id) |> Enum.sort(),
          "anchor_cardmarket_product_ids" =>
            Enum.map(anchors, & &1.cardmarket_product_id) |> Enum.sort(),
          "set_expansion_degree" => set_degree,
          "expansion_set_degree" => expansion_degree
        }
      }

      case find_or_record_mapping(attrs) do
        {:ok, mapping} -> {:cont, {:ok, [mapping | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, mappings} -> {:ok, Enum.reverse(mappings)}
      error -> error
    end
  end

  defp find_or_record_mapping(attrs) do
    query =
      CardmarketExpansionMapping
      |> Ash.Query.for_read(:by_batch, %{source_batch_id: attrs.source_batch_id})

    query =
      Ash.Query.filter(
        query,
        expr(card_set_id == ^attrs.card_set_id and expansion_id == ^attrs.expansion_id)
      )

    case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, mapping} when not is_nil(mapping) ->
        {:ok, mapping}

      {:ok, nil} ->
        case Core.record_cardmarket_expansion_mapping(attrs, authorize?: false) do
          {:ok, mapping} -> {:ok, mapping}
          {:error, reason} -> {:error, {:persistence, reason}}
          other -> {:error, {:persistence, other}}
        end

      {:error, reason} ->
        {:error, {:persistence, reason}}

      other ->
        {:error, {:persistence, other}}
    end
  end

  defp existing_evidence(batch_id) do
    query =
      CardmarketCardMappingEvidence |> Ash.Query.for_read(:by_batch, %{source_batch_id: batch_id})

    case Ash.read(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, rows} ->
        rows = Enum.sort_by(rows, &{&1.inserted_at, &1.id})

        {:ok,
         Enum.reduce(rows, %{}, fn row, acc ->
           Map.update(
             acc,
             row.card_printing_id,
             %{row.expansion_mapping_id => [row]},
             fn evidence_by_mapping ->
               Map.update(
                 evidence_by_mapping,
                 row.expansion_mapping_id,
                 [row],
                 fn rows -> [row | rows] end
               )
             end
           )
         end)}

      {:error, reason} ->
        {:error, {:persistence, reason}}
    end
  end

  defp process_pairs(batch, mappings, anchors, pairs, existing, canonical_sets) do
    approved =
      mappings
      |> Enum.filter(&effective_approved?(&1, canonical_sets))
      |> Enum.sort_by(&{&1.card_set_id, &1.expansion_id})

    review_expansions = Enum.count(mappings, &(&1.status == "review"))
    missing = pairs.missing_anchor_products
    used_products = global_product_usage(anchors)

    counts = %{
      anchors: length(anchors),
      missing_anchor_products: missing,
      approved_expansions: length(approved),
      review_expansions: review_expansions,
      auto_matched: 0,
      review: 0,
      unmatched: 0,
      preserved: 0,
      already_processed: 0
    }

    Enum.reduce_while(approved, {:ok, counts}, fn mapping, {:ok, counts} ->
      with {:ok, cards} <- cards_for_set(mapping.card_set_id),
           {:ok, staged} <- load_products_for_pair(batch.id, mapping.expansion_id),
           {:ok, next} <-
             process_cards(
               batch,
               mapping,
               cards,
               staged,
               existing,
               used_products,
               counts
             ) do
        {:cont, {:ok, next}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp canonical_sets do
    query = Ash.Query.limit(TcgCheap.Catalogue.CardSet, @canonical_set_limit + 1)

    case Ash.read(query, authorize?: false) do
      {:ok, sets} when length(sets) <= @canonical_set_limit -> {:ok, Map.new(sets, &{&1.id, &1})}
      {:ok, _sets} -> {:error, {:persistence, :canonical_set_scan_exceeded_limit}}
      error -> error
    end
  end

  defp effective_approved?(mapping, sets) do
    case Map.get(sets, mapping.card_set_id) do
      %{cardmarket_mapping_authority: "administrator", cardmarket_expansion_id: id}
      when is_integer(id) ->
        id == mapping.expansion_id

      _ ->
        mapping.status == "approved"
    end
  end

  defp cards_for_set(set_id) do
    case Core.list_cardmarket_cards_by_set(set_id, authorize?: false) do
      {:ok, cards} ->
        {:ok, Enum.sort_by(cards, &{SearchText.normalize_cardmarket_name(&1.name), &1.id})}

      {:error, reason} ->
        {:error, {:persistence, reason}}
    end
  end

  defp load_products_for_pair(batch_id, expansion_id) do
    case Core.list_cardmarket_bulk_products_for_batch_and_expansion(batch_id, expansion_id,
           authorize?: false
         ) do
      {:ok, products} -> {:ok, Enum.sort_by(products, &{&1.cardmarket_product_id, &1.id})}
      {:error, reason} -> {:error, {:persistence, reason}}
    end
  end

  defp process_cards(batch, mapping, cards, products, existing, used_products, counts) do
    card_names = Enum.frequencies_by(cards, &SearchText.normalize_cardmarket_name(&1.name))
    product_names = Enum.frequencies_by(products, &SearchText.normalize_cardmarket_name(&1.name))

    context = %{
      batch: batch,
      mapping: mapping,
      products: products,
      card_names: card_names,
      product_names: product_names,
      used_products: used_products
    }

    Enum.reduce_while(cards, {:ok, counts}, fn card, {:ok, acc} ->
      process_card(card, context, Map.get(existing, card.id, %{}), acc)
    end)
  end

  defp process_card(card, context, card_evidence, counts) do
    evidence = Map.get(card_evidence, context.mapping.id, [])

    case already_processed?(card, evidence, context.products) do
      true ->
        {:cont, {:ok, Map.update!(counts, :already_processed, &(&1 + 1))}}

      false ->
        classify_and_persist(
          Map.merge(context, %{
            card: card,
            candidates:
              Enum.filter(
                context.products,
                &(SearchText.normalize_cardmarket_name(&1.name) ==
                    SearchText.normalize_cardmarket_name(card.name))
              ),
            existing_evidence: evidence,
            superseded_evidence: superseded_auto_match(card, context.mapping, card_evidence),
            counts: counts
          })
        )
    end
  end

  defp classify_and_persist(context) do
    context
    |> classify()
    |> persist_classification(context)
  end

  defp classify(%{card: %{mapping_authority: "administrator"}} = context) do
    if anchor_match?(context) do
      {:preserved_anchor, context.card.cardmarket_product_id}
    else
      {:preserved, @prefix <> " administrator mapping preserved"}
    end
  end

  defp classify(context) do
    cond do
      anchor_match?(context) and is_nil(context.superseded_evidence) ->
        {:preserved_anchor, context.card.cardmarket_product_id}

      context.superseded_evidence != nil ->
        case safe_candidate(context) do
          {:ok, product} ->
            {:superseded_match, product, context.superseded_evidence.id}

          :review ->
            {:superseded_review,
             @prefix <> "superseded auto-match lacks unique detailed candidate",
             context.superseded_evidence.id}
        end

      context.card.mapping_status == "matched" ->
        {:preserved, @prefix <> "existing matched mapping preserved"}

      true ->
        classify_unmatched(context)
    end
  end

  defp classify_unmatched(context) do
    cond do
      administrator_mapping?(context.card) ->
        {:preserved, "cardmarket_bulk_v1: administrator mapping preserved"}

      unrelated_provider_review?(context.card) ->
        {:preserved, "cardmarket_bulk_v1: unrelated provider review preserved"}

      incomplete_details?(context.card) and context.candidates != [] ->
        {:review, @prefix <> "material variant evidence incomplete"}

      unsafe_reason(
        context.card,
        context.candidates,
        context.card_names,
        context.product_names,
        context.used_products
      ) ->
        {:review,
         unsafe_reason(
           context.card,
           context.candidates,
           context.card_names,
           context.product_names,
           context.used_products
         )}

      length(context.candidates) == 1 ->
        {:match, hd(context.candidates)}

      true ->
        :unmatched
    end
  end

  defp incomplete_details?(card), do: is_nil(card.details_synced_at)

  defp superseded_auto_match(card, mapping, evidence_by_mapping) do
    evidence_by_mapping
    |> Enum.reject(fn {mapping_id, _evidence} -> mapping_id == mapping.id end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {_mapping_id, evidence_rows} ->
      Enum.find(evidence_rows, fn evidence ->
        evidence.decision == "auto_matched" and
          evidence.cardmarket_product_id == card.cardmarket_product_id
      end)
    end)
  end

  defp safe_candidate(context) do
    candidate =
      if incomplete_details?(context.card), do: [], else: context.candidates

    case candidate do
      [product] ->
        if is_nil(
             unsafe_reason(
               context.card,
               candidate,
               context.card_names,
               context.product_names,
               context.used_products
             )
           ), do: {:ok, product}, else: :review

      _ ->
        :review
    end
  end

  defp persist_classification({:preserved_anchor, product_id}, context) do
    evidence =
      Map.merge(candidate_evidence(context.candidates), %{
        "anchor_card_printing_id" => context.card.id,
        "anchor_cardmarket_product_id" => product_id
      })

    persist_evidence(
      context.batch,
      context.mapping,
      context.card,
      "anchor",
      product_id,
      nil,
      evidence_authority(context.card.mapping_authority),
      evidence
    )
    |> increment(context.counts, :preserved)
  end

  defp persist_classification({:preserved, reason}, context),
    do:
      review_without_mutation(
        context.batch,
        context.mapping,
        context.card,
        reason,
        evidence(context),
        context.counts,
        context.existing_evidence
      )

  defp persist_classification({:review, reason}, context),
    do:
      transition_review(
        context.batch,
        context.mapping,
        context.card,
        reason,
        evidence(context),
        context.counts,
        nil,
        context.existing_evidence
      )

  defp persist_classification({:superseded_review, reason, evidence_id}, context),
    do:
      transition_review(
        context.batch,
        context.mapping,
        context.card,
        reason,
        evidence(context),
        context.counts,
        evidence_id,
        context.existing_evidence
      )

  defp persist_classification({:match, product}, context),
    do:
      transition_match(
        context.batch,
        context.mapping,
        context.card,
        product,
        evidence(context),
        context.counts,
        nil,
        context.existing_evidence
      )

  defp persist_classification({:superseded_match, product, evidence_id}, context),
    do:
      transition_match(
        context.batch,
        context.mapping,
        context.card,
        product,
        evidence(context),
        context.counts,
        evidence_id,
        context.existing_evidence
      )

  defp persist_classification(:unmatched, context) do
    persist_evidence(
      context.batch,
      context.mapping,
      context.card,
      "unmatched",
      nil,
      nil,
      evidence_authority(context.card.mapping_authority),
      evidence(context)
    )
    |> increment(context.counts, :unmatched)
  end

  defp evidence(context), do: candidate_evidence(context.candidates)

  defp anchor_match?(%{card: card, products: products}),
    do:
      card.mapping_status == "matched" and
        card.cardmarket_product_id in Enum.map(products, & &1.cardmarket_product_id)

  defp already_processed?(card, evidence_rows, products) when is_list(evidence_rows) do
    matched_anchor? = anchor_match?(%{card: card, products: products})

    Enum.any?(evidence_rows, fn
      %{decision: "review"} ->
        card.mapping_status == "review" or
          (card.mapping_status == "matched" and not matched_anchor?)

      %{decision: "unmatched"} ->
        card.mapping_status == "unmatched" or
          (card.mapping_status == "matched" and not matched_anchor?)

      %{decision: decision, cardmarket_product_id: product_id}
      when decision in ["anchor", "auto_matched"] ->
        card.mapping_status == "matched" and product_id == card.cardmarket_product_id

      _ ->
        false
    end)
  end

  defp already_processed?(_card, _evidence, _products), do: false

  defp administrator_mapping?(card),
    do: card.mapping_authority == "administrator"

  defp unrelated_provider_review?(card),
    do:
      card.mapping_status == "review" and card.mapping_authority == "provider" and
        not String.starts_with?(card.mapping_review_reason || "", @prefix)

  defp unsafe_reason(card, candidates, card_names, product_names, used_products) do
    cond do
      Map.get(card_names, SearchText.normalize_cardmarket_name(card.name), 0) > 1 ->
        @prefix <> "duplicate canonical name"

      MaterialVariant.conflict?(card.variant_data) ->
        @prefix <> "material variant conflict"

      candidates == [] ->
        nil

      Map.get(product_names, SearchText.normalize_cardmarket_name(card.name), 0) > 1 ->
        @prefix <> "duplicate staged product name"

      Enum.any?(candidates, &MaterialVariant.obvious_cardmarket_marker?(&1.name)) ->
        @prefix <> "obvious Cardmarket marker"

      Enum.any?(candidates, &MapSet.member?(used_products, &1.cardmarket_product_id)) ->
        @prefix <> "product already mapped globally"

      true ->
        nil
    end
  end

  defp global_product_usage(anchors) do
    anchors
    |> Enum.map(& &1.cardmarket_product_id)
    |> MapSet.new()
  end

  defp transition_match(
         batch,
         mapping,
         card,
         product,
         evidence,
         counts,
         evidence_id,
         existing_evidence
       ) do
    args = %{
      expected_updated_at: card.updated_at,
      evidence_timestamp: batch.fetched_at,
      cardmarket_product_id: product.cardmarket_product_id,
      superseded_evidence_id: evidence_id
    }

    transact_card(%{
      batch: batch,
      mapping: mapping,
      card: card,
      decision: "auto_matched",
      product_id: product.cardmarket_product_id,
      reason: nil,
      args: args,
      action: :cardmarket_bulk_auto_match,
      authority: evidence_authority(card.mapping_authority),
      counts: counts,
      evidence: evidence,
      existing_evidence: existing_evidence,
      key: :auto_matched
    })
  end

  defp transition_review(
         batch,
         mapping,
         card,
         reason,
         evidence,
         counts,
         evidence_id,
         existing_evidence
       ) do
    args = %{
      expected_updated_at: card.updated_at,
      evidence_timestamp: batch.fetched_at,
      reason: reason,
      superseded_evidence_id: evidence_id
    }

    transact_card(%{
      batch: batch,
      mapping: mapping,
      card: card,
      decision: "review",
      product_id: nil,
      reason: reason,
      args: args,
      action: :cardmarket_bulk_review,
      authority: evidence_authority(card.mapping_authority),
      counts: counts,
      evidence: evidence,
      existing_evidence: existing_evidence,
      key: :review
    })
  end

  defp transact_card(context) do
    case Ash.transact(
           [
             CardPrinting,
             TcgCheap.Catalogue.CardPrintingMappingDecision,
             CardmarketCardMappingEvidence
           ],
           fn -> transact_card_update(context) end
         ) do
      {:ok, {:ok, _}} -> {:cont, {:ok, Map.update!(context.counts, context.key, &(&1 + 1))}}
      {:ok, {:error, reason}} -> {:halt, {:error, {:persistence, reason}}}
      {:error, reason} -> {:halt, {:error, {:persistence, reason}}}
    end
  end

  defp transact_card_update(context) do
    with {:ok, updated} <-
           Ash.update(context.card, context.args, action: context.action, authorize?: false),
         {:ok, _evidence} <- transition_evidence(context, updated) do
      {:ok, updated}
    end
  end

  defp transition_evidence(context, updated) do
    if Enum.any?(context.existing_evidence, fn
         %{decision: decision, cardmarket_product_id: product_id} ->
           decision == context.decision and product_id == context.product_id

         _ ->
           false
       end) do
      {:ok, :existing}
    else
      record_transition_evidence(context, updated)
    end
  end

  defp record_transition_evidence(context, updated) do
    record_evidence(
      context.batch,
      context.mapping,
      updated,
      context.decision,
      context.product_id,
      context.reason,
      context.authority,
      Map.merge(context.evidence, %{"candidate_product_id" => context.product_id})
    )
  end

  defp review_without_mutation(batch, mapping, card, reason, evidence, counts, existing_evidence) do
    if Enum.any?(existing_evidence, &(&1.decision == "review")) do
      {:cont, {:ok, Map.update!(counts, :preserved, &(&1 + 1))}}
    else
      persist_evidence(
        batch,
        mapping,
        card,
        "review",
        nil,
        reason,
        evidence_authority(card.mapping_authority),
        Map.merge(evidence, %{"preserved" => true})
      )
      |> increment(counts, :preserved)
    end
  end

  defp persist_evidence(batch, mapping, card, decision, product, reason, authority, evidence),
    do: record_evidence(batch, mapping, card, decision, product, reason, authority, evidence)

  defp record_evidence(batch, mapping, card, decision, product, reason, authority, evidence) do
    Core.record_cardmarket_card_mapping_evidence(
      %{
        source_batch_id: batch.id,
        expansion_mapping_id: mapping.id,
        card_printing_id: card.id,
        decision: decision,
        cardmarket_product_id: product,
        normalized_card_name: SearchText.normalize_cardmarket_name(card.name),
        review_reason: reason,
        authority: authority,
        evidence: evidence
      },
      authorize?: false
    )
  end

  defp increment({:ok, _}, counts, key), do: {:cont, {:ok, Map.update!(counts, key, &(&1 + 1))}}
  defp increment({:error, reason}, _counts, _key), do: {:halt, {:error, {:persistence, reason}}}
  defp evidence_authority("administrator"), do: "administrator"
  defp evidence_authority(_), do: "system"

  defp candidate_evidence(candidates) do
    candidates = Enum.sort_by(candidates, &{&1.cardmarket_product_id, &1.name})

    %{
      "candidate_count" => length(candidates),
      "candidate_product_ids" => Enum.map(candidates, & &1.cardmarket_product_id),
      "candidate_names" => Enum.map(candidates, & &1.name)
    }
  end

  defp review_reason(set_degree, expansion_degree),
    do:
      @prefix <>
        "non-unique expansion pair: set_degree=#{set_degree}, expansion_degree=#{expansion_degree}"
end
