defmodule TcgCheap.Pricing.Singles.ValuationNotifications do
  @moduledoc "Neutral PubSub notifications for public bulk valuation and mapping changes."

  @collection_topic "valuations:singles_collection"

  @spec topic(String.t() | map()) :: String.t()
  def topic(%{id: id}), do: topic(id)
  def topic(%{"id" => id}), do: topic(id)
  def topic(id) when is_binary(id), do: "valuations:#{id}"

  @spec collection_topic() :: String.t()
  def collection_topic, do: @collection_topic

  def subscribe(card), do: Phoenix.PubSub.subscribe(TcgCheap.PubSub, topic(card))

  def subscribe_collection,
    do: Phoenix.PubSub.subscribe(TcgCheap.PubSub, collection_topic())

  def notify_mapping_changed(%{id: id}), do: notify_mapping_changed(id)

  def notify_mapping_changed(id) when is_binary(id) do
    event = {:card_mapping_changed, %{card_printing_id: id}}
    Phoenix.PubSub.broadcast(TcgCheap.PubSub, topic(id), event)
  end

  @spec notify_collection_changed() :: :ok | {:error, term()}
  def notify_collection_changed do
    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      collection_topic(),
      {:singles_collection_invalidated, %{}}
    )
  end
end
