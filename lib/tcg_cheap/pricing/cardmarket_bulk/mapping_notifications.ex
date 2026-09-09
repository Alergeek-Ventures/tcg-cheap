defmodule TcgCheap.Pricing.CardmarketBulk.MappingNotifications do
  @moduledoc "Publishes valuation invalidations for Cardmarket mapping evidence."

  alias TcgCheap.Catalogue.CardmarketCardMappingEvidence
  alias TcgCheap.Pricing.Singles.ValuationNotifications

  @page_size 500

  @doc "Publishes card mapping events and one collection invalidation per successful batch."
  @spec notify_batch(String.t()) :: :ok | {:error, term()}
  def notify_batch(batch_id) when is_binary(batch_id) do
    with {:ok, ids} <- evidence_ids(batch_id),
         :ok <- notify_ids(ids),
         :ok <- notify_collection() do
      :ok
    else
      {:error, reason} -> {:error, {:mapping_notification_failed, reason}}
    end
  rescue
    error -> {:error, {:mapping_notification_failed, error}}
  end

  defp notify_collection do
    case ValuationNotifications.notify_collection_changed() do
      :ok -> :ok
      {:error, reason} -> {:error, {:collection_notification_failed, reason}}
    end
  end

  defp evidence_ids(batch_id), do: read_pages(batch_id, 0, MapSet.new())

  defp read_pages(batch_id, offset, ids) do
    query =
      CardmarketCardMappingEvidence
      |> Ash.Query.for_read(:by_batch, %{source_batch_id: batch_id})
      |> Ash.Query.select([:card_printing_id, :id])
      |> Ash.Query.sort(card_printing_id: :asc, id: :asc)
      |> Ash.Query.limit(@page_size)
      |> Ash.Query.offset(offset)

    case Ash.read(query, authorize?: false) do
      {:ok, records} when is_list(records) ->
        ids = Enum.reduce(records, ids, &MapSet.put(&2, &1.card_printing_id))

        if length(records) < @page_size do
          {:ok, ids |> MapSet.to_list() |> Enum.sort()}
        else
          read_pages(batch_id, offset + @page_size, ids)
        end

      {:error, reason} ->
        {:error, {:evidence_read_failed, reason}}

      other ->
        {:error, {:evidence_read_failed, other}}
    end
  end

  defp notify_ids(ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case ValuationNotifications.notify_mapping_changed(id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:notification_failed, reason}}}
      end
    end)
  end
end
