defmodule TcgCheap.Pricing.Singles.EmbeddedValuation do
  @moduledoc "Legacy no-op retained for resumable catalogue enrichment compatibility."

  @doc "Records embedded pricing, or enqueues background valuation for a valid mapping."
  @spec record_or_enqueue(map(), map(), DateTime.t()) :: :ok | {:error, term()}
  def record_or_enqueue(card, provider_card, fetched_at) do
    _ = {card, provider_card, fetched_at}
    :ok
  end
end
