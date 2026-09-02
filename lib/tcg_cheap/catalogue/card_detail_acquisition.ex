defmodule TcgCheap.Catalogue.CardDetailAcquisition do
  @moduledoc "Public entry point for detail enrichment requests."
  alias TcgCheap.Catalogue.CardDetailEnrichmentWorker
  alias TcgCheap.Core
  alias TcgCheapWeb.PublicAcquisitionLimiter

  def subscribe_and_request(input, opts \\ []) do
    with {:ok, card} <- canonical(input),
         :ok <- CardDetailEnrichmentWorker.subscribe(card),
         {:ok, fresh} <- canonical(card),
         result <- request(fresh, opts) do
      {:ok, fresh, result}
    end
  end

  def subscribe(card),
    do: Phoenix.PubSub.subscribe(TcgCheap.PubSub, CardDetailEnrichmentWorker.topic(card))

  defp request(%{pricing_checked_at: nil} = card, opts) do
    case PublicAcquisitionLimiter.admitter(Keyword.get(opts, :public_address)).() do
      :ok -> CardDetailEnrichmentWorker.enqueue(card, false, priority: 0) |> result()
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(card, _opts), do: {:fresh, card}
  defp result({:ok, job}), do: {:enqueued, job}
  defp result({:error, reason}), do: {:error, reason}

  defp canonical(%{id: id, tcgdex_id: tcgdex_id}), do: canonical(tcgdex_id, id)
  defp canonical(%{"id" => id, "tcgdex_id" => tcgdex_id}), do: canonical(tcgdex_id, id)
  defp canonical(id) when is_binary(id), do: canonical(id, nil)
  defp canonical(tcgdex_id, nil), do: Core.get_public_card_printing_by_tcgdex_id(tcgdex_id)

  defp canonical(tcgdex_id, id) do
    case Core.get_public_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, %{id: ^id} = card} -> {:ok, card}
      _ -> {:error, :invalid_local_card}
    end
  end
end
