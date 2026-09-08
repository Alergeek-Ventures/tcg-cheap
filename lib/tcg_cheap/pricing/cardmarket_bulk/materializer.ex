defmodule TcgCheap.Pricing.CardmarketBulk.Materializer do
  @moduledoc "Materializes approved Cardmarket mappings without changing mappings."

  alias TcgCheap.Catalogue.CardmarketCardMappingEvidence
  alias TcgCheap.Catalogue.CardmarketExpansionMapping
  alias TcgCheap.Core
  alias TcgCheap.Pricing.CardmarketBulk.Batch
  alias TcgCheap.Pricing.CardmarketBulk.Price
  alias TcgCheap.Pricing.CardmarketBulk.Product
  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot
  alias TcgCheap.Repo

  require Ash.Query
  import Ash.Expr

  @limit 1_000
  @policy "cardmarket_bulk_v1"

  def run(%Batch{} = batch),
    do:
      page(batch, nil, %{
        materialized: 0,
        already_materialized: 0,
        missing_price: 0,
        unavailable_value: 0,
        unapproved_mapping: 0
      })

  def run(_), do: {:error, :invalid_batch}

  defp page(batch, cursor, counts) do
    case Core.list_cardmarket_anchors(cursor, @limit, authorize?: false) do
      {:ok, []} ->
        {:ok, counts}

      {:ok, cards} when is_list(cards) ->
        with {:ok, approved_sets} <- approved_sets(batch.id),
             {:ok, prices} <- load_prices(cards, batch.id),
             {:ok, product_expansions} <- load_product_expansions(cards, batch.id),
             {:ok, evidence} <- load_evidence(cards, batch.id),
             {:ok, snapshots} <- load_snapshots(cards),
             {:ok, counts} <-
               process(
                 cards,
                 prices,
                 snapshots,
                 batch,
                 approved_sets,
                 product_expansions,
                 evidence,
                 counts
               ) do
          page(batch, cards |> List.last() |> Map.get(:tcgdex_id), counts)
        end

      {:error, reason} ->
        {:error, {:persistence, reason}}

      other ->
        {:error, {:persistence, other}}
    end
  end

  defp approved_sets(batch_id) do
    query =
      Ash.Query.for_read(CardmarketExpansionMapping, :by_batch, %{source_batch_id: batch_id})

    with {:ok, rows} <- Ash.read(query, domain: TcgCheap.Core, authorize?: false),
         {:ok, sets} <- Ash.read(TcgCheap.Catalogue.CardSet, authorize?: false) do
      admin = Map.new(sets, &{&1.id, administrator_expansion(&1)})

      {:ok,
       rows
       |> Enum.group_by(& &1.card_set_id)
       |> Enum.reduce(%{}, fn {set_id, mappings}, approved ->
         case Enum.filter(mappings, &effective_set?(&1, admin)) do
           [mapping] -> Map.put(approved, {set_id, mapping.expansion_id}, mapping.id)
           _ -> approved
         end
       end)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp effective_set?(row, admin) do
    case Map.get(admin, row.card_set_id) do
      id when is_integer(id) -> id == row.expansion_id
      nil -> row.authority == "system" and row.status == "approved"
    end
  end

  defp administrator_expansion(%{cardmarket_mapping_authority: "administrator"} = set),
    do: set.cardmarket_expansion_id

  defp administrator_expansion(_), do: nil

  defp load_product_expansions(cards, batch_id) do
    ids =
      cards
      |> Enum.map(&Map.get(&1, :cardmarket_product_id))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    query =
      Product
      |> Ash.Query.for_read(:by_product_ids, %{cardmarket_product_ids: ids})
      |> Ash.Query.filter(expr(last_batch_id == ^batch_id))

    case Ash.read(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, rows} -> {:ok, Map.new(rows, &{&1.cardmarket_product_id, &1.expansion_id})}
      other -> {:error, {:persistence, other}}
    end
  end

  defp load_prices(cards, batch_id) do
    ids =
      cards
      |> Enum.map(&Map.get(&1, :cardmarket_product_id))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    query = Ash.Query.for_read(Price, :by_product_ids, %{cardmarket_product_ids: ids})
    query = Ash.Query.filter(query, expr(last_batch_id == ^batch_id))

    case Ash.read(query, authorize?: false) do
      {:ok, rows} -> {:ok, Map.new(rows, &{&1.cardmarket_product_id, &1})}
      other -> {:error, {:persistence, other}}
    end
  end

  defp load_evidence(cards, batch_id) do
    ids = cards |> Enum.map(& &1.id) |> Enum.uniq()

    query =
      CardmarketCardMappingEvidence
      |> Ash.Query.for_read(:by_batch, %{source_batch_id: batch_id})
      |> Ash.Query.filter(expr(card_printing_id in ^ids))

    case Ash.read(query, authorize?: false) do
      {:ok, rows} ->
        {:ok,
         Map.new(rows, fn row ->
           {{row.card_printing_id, row.cardmarket_product_id, row.expansion_mapping_id}, row}
         end)}

      other ->
        {:error, {:persistence, other}}
    end
  end

  defp load_snapshots(cards) do
    ids = cards |> Enum.map(& &1.id) |> Enum.uniq()
    policy = @policy

    query =
      Ash.Query.filter(
        SingleValuationSnapshot,
        expr(card_printing_id in ^ids and policy_version == ^policy and current? == true)
      )

    case Ash.read(query, authorize?: false) do
      {:ok, rows} -> {:ok, Map.new(rows, &{&1.card_printing_id, &1})}
      other -> {:error, {:persistence, other}}
    end
  end

  defp process(
         cards,
         prices,
         snapshots,
         batch,
         approved_sets,
         product_expansions,
         evidence,
         counts
       ) do
    Enum.reduce_while(cards, {:ok, counts}, fn card, {:ok, acc} ->
      case process_card(
             card,
             prices,
             snapshots,
             batch,
             approved_sets,
             product_expansions,
             evidence,
             acc
           ) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp process_card(
         %{card_set_id: set_id, cardmarket_product_id: product_id} = card,
         prices,
         snapshots,
         batch,
         approved_sets,
         product_expansions,
         evidence,
         counts
       ) do
    expansion_id = Map.get(product_expansions, product_id)

    case {set_id, Map.get(approved_sets, {set_id, expansion_id})} do
      {set_id, mapping_id} when not is_nil(set_id) and not is_nil(mapping_id) ->
        process_card_mapping(card, prices, snapshots, batch, evidence, mapping_id, counts)

      _ ->
        {:ok, Map.update!(counts, :unapproved_mapping, &(&1 + 1))}
    end
  end

  defp process_card(
         _card,
         _prices,
         _snapshots,
         _batch,
         _approved_sets,
         _product_expansions,
         _evidence,
         counts
       ),
       do: {:ok, Map.update!(counts, :missing_price, &(&1 + 1))}

  defp process_card_mapping(
         %{cardmarket_product_id: id} = card,
         prices,
         snapshots,
         batch,
         evidence,
         mapping_id,
         counts
       )
       when is_integer(id) do
    case Map.get(evidence, {card.id, id, mapping_id}) do
      %{decision: decision} when decision in ["anchor", "auto_matched"] ->
        process_card_price(card, prices, snapshots, batch, counts, id)

      _ ->
        {:ok, Map.update!(counts, :unapproved_mapping, &(&1 + 1))}
    end
  end

  defp process_card_mapping(_card, _prices, _snapshots, _batch, _evidence, _mapping_id, counts),
    do: {:ok, Map.update!(counts, :unapproved_mapping, &(&1 + 1))}

  defp process_card_price(card, prices, snapshots, batch, counts, id) do
    case Map.get(prices, id) do
      nil ->
        {:ok, Map.update!(counts, :missing_price, &(&1 + 1))}

      %{selected_value_eur: value, selected_metric: metric} = price
      when not is_nil(value) and
             metric in ["avg7", "avg30", "trend", "avg", "low"] ->
        process_valued(card, price, metric, snapshots, batch, counts, id)

      %{selected_value_eur: _} ->
        {:ok, Map.update!(counts, :unavailable_value, &(&1 + 1))}
    end
  end

  defp process_valued(card, price, metric, _snapshots, batch, counts, id) do
    if valid_value?(price.selected_value_eur) do
      record_valued_locked(card, price, metric, batch, counts, id)
    else
      {:ok, Map.update!(counts, :unavailable_value, &(&1 + 1))}
    end
  end

  defp record_valued_locked(card, price, metric, batch, counts, id) do
    case Repo.transaction(fn ->
           record_valued_transaction(card, price, metric, batch, counts, id)
         end) do
      {:ok, {result, notifications}} ->
        Ash.Notifier.notify(notifications)
        result

      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_valued_transaction(card, price, metric, batch, counts, id) do
    with {:ok, _card} <- Core.lock_card_printing_for_update(card.id),
         {:ok, current} <- Core.get_current_single_valuation(card.id, @policy) do
      materialize_locked(current, card, price, metric, batch, counts, id)
    else
      {:error, reason} -> Repo.rollback({:persistence, reason})
    end
  end

  defp materialize_locked(current, card, price, metric, batch, counts, id) do
    case same_batch?(current, batch, id) do
      true -> {{:ok, Map.update!(counts, :already_materialized, &(&1 + 1))}, []}
      false -> record_new_valuation(card, price, metric, batch, counts, id)
    end
  end

  defp record_new_valuation(card, price, metric, batch, counts, id) do
    case record_valued(card, price, metric, batch, counts, id) do
      {:ok, result, notifications} -> {{:ok, result}, notifications}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp record_valued(card, price, metric, batch, counts, id) do
    attrs = %{
      card_printing_id: card.id,
      value_eur: price.selected_value_eur,
      currency: "EUR",
      policy_version: @policy,
      source: "cardmarket_bulk",
      source_metric: metric,
      fetched_at: batch.fetched_at,
      provider_updated_at: batch.price_created_at,
      cardmarket_product_id: id
    }

    case Core.record_single_valuation(attrs, authorize?: false, return_notifications?: true) do
      {:ok, _, notifications} ->
        {:ok, Map.update!(counts, :materialized, &(&1 + 1)), notifications}

      {:ok, _} ->
        {:ok, Map.update!(counts, :materialized, &(&1 + 1)), []}

      {:error, reason} ->
        {:error, {:persistence, reason}}

      other ->
        {:error, {:persistence, other}}
    end
  end

  defp valid_value?(%Decimal{} = value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt

  defp valid_value?(_), do: false

  defp same_batch?(
         %{fetched_at: fetched, provider_updated_at: updated, cardmarket_product_id: id},
         batch,
         id
       ),
       do: fetched == batch.fetched_at and updated == batch.price_created_at

  defp same_batch?(_, _, _), do: false
end
