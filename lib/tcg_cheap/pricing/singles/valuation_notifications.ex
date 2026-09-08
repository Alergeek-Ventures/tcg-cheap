defmodule TcgCheap.Pricing.Singles.ValuationNotifications do
  @moduledoc "Neutral PubSub notifications for public bulk valuation and mapping changes."

  @spec topic(String.t() | map()) :: String.t()
  def topic(%{id: id}), do: topic(id)
  def topic(%{"id" => id}), do: topic(id)
  def topic(id) when is_binary(id), do: "valuations:#{id}"

  def subscribe(card), do: Phoenix.PubSub.subscribe(TcgCheap.PubSub, topic(card))

  def notify_mapping_changed(%{id: id}), do: notify_mapping_changed(id)

  def notify_mapping_changed(id) when is_binary(id) do
    event = {:card_mapping_changed, %{card_printing_id: id}}
    Phoenix.PubSub.broadcast(TcgCheap.PubSub, topic(id), event)
  end
end
