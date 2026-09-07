defmodule TcgCheap.Pricing.CardmarketBulk.MappingNotifications do
  @moduledoc "Publishes valuation invalidations for Cardmarket mapping evidence."

  alias TcgCheap.Catalogue.CardmarketCardMappingEvidence
  alias TcgCheap.Pricing.Singles.ValuationAcquisition

  @page_size 500

  @doc "Publishes one mapping-change event per distinct printing in a batch."
  @spec notify_batch(String.t()) :: :ok | {:error, term()}
  def notify_batch(batch_id) when is_binary(batch_id) do
    case evidence_ids(batch_id) do
      {:ok, ids} ->
        case notify_ids(ids) do
          :ok -> :ok
          {:error, reason} -> {:error, {:mapping_notification_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:mapping_notification_failed, reason}}
    end
  rescue
    error -> {:error, {:mapping_notification_failed, error}}
  end

  defp evidence_ids(batch_id), do: read_pages(batch_id, 0, MapSet.new())

  defp read_pages(batch_id, offset, ids) do
    query =
      CardmarketCardMappingEvidence
      |> Ash.Query.for_read(:by_batch, %{source_batch_id: batch_id})
      |> Ash.Query.select([:card_printing_id])
      |> Ash.Query.sort(card_printing_id: :asc)
      |> Ash.Query.limit(@page_size)
      |> Ash.Query.offset(offset)

    case Ash.read(query, authorize?: false) do
      {:ok, records} when is_list(records) ->
        ids = Enum.reduce(records, ids, &MapSet.put(&2, &1.card_printing_id))

        if length(records) < @page_size do
          {:ok, MapSet.to_list(ids)}
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
      case ValuationAcquisition.notify_mapping_changed(id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:notification_failed, reason}}}
      end
    end)
  end
end
