defmodule TcgCheap.Pricing.Singles.EmbeddedValuation do
  @moduledoc "Records valid pricing embedded in a detailed catalogue card."

  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{TcgdexCardmarket, ValuationAcquisition, ValuationWorker}

  @mapping_race_message "active-policy valuation must match the currently matched positive Cardmarket product"

  @doc "Records embedded pricing, or enqueues background valuation for a valid mapping."
  @spec record_or_enqueue(map(), map(), DateTime.t()) :: :ok | {:error, term()}
  def record_or_enqueue(card, provider_card, fetched_at) do
    case TcgdexCardmarket.parse_embedded(card.tcgdex_id, provider_card, fetched_at) do
      {:ok, result} -> persist_embedded_if_current(card.tcgdex_id, result)
      {:error, _reason} -> enqueue_current(card.tcgdex_id)
    end
  end

  defp enqueue_current(tcgdex_id) do
    case Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, %{mapping_status: "matched", cardmarket_product_id: product_id} = card}
      when is_integer(product_id) and product_id > 0 ->
        enqueue_valuation(card)

      {:ok, _card} ->
        :ok

      {:error, _} ->
        {:error, :persistence_failed}
    end
  end

  defp persist_embedded_if_current(tcgdex_id, result) do
    case Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, %{mapping_status: "matched", cardmarket_product_id: product_id} = card}
      when is_integer(product_id) and product_id > 0 ->
        case ValuationWorker.validate_result(result, %{tcgdex_id: tcgdex_id}, card) do
          {:ok, attrs} -> record_embedded(attrs, tcgdex_id)
          {:error, _} -> enqueue_valuation(card)
        end

      {:ok, _card} ->
        :ok

      {:error, _} ->
        {:error, :persistence_failed}
    end
  end

  defp enqueue_valuation(card) do
    case ValuationAcquisition.enqueue_if_stale_background(card) do
      {:fresh, _} -> :ok
      {:enqueued, _} -> :ok
      {:error, :unpriced_mapping} -> :ok
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp record_embedded(attrs, tcgdex_id) do
    case Core.record_single_valuation(attrs, authorize?: false) do
      {:ok, _snapshot} ->
        :ok

      {:error, %Ash.Error.Invalid{} = error} ->
        if mapping_race_error?(error),
          do: refetch_after_mapping_race(tcgdex_id),
          else: {:error, :persistence_failed}

      {:error, _error} ->
        {:error, :persistence_failed}
    end
  end

  defp mapping_race_error?(%Ash.Error.Invalid{errors: [error]}),
    do: error_message(error) == @mapping_race_message

  defp mapping_race_error?(_error), do: false
  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(message) when is_binary(message), do: message
  defp error_message(_error), do: nil

  defp refetch_after_mapping_race(tcgdex_id), do: enqueue_current(tcgdex_id)
end
