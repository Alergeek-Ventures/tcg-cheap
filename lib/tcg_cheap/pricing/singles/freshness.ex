defmodule TcgCheap.Pricing.Singles.Freshness do
  @moduledoc """
  24-hour freshness classification for locally stored singles valuations.
  """

  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot

  @ttl_seconds :timer.hours(24) |> div(1_000)

  @spec status(SingleValuationSnapshot.t() | nil, DateTime.t()) :: :fresh | :stale | :missing
  def status(nil, _now), do: :missing

  def status(%SingleValuationSnapshot{fetched_at: fetched_at}, now)
      when is_struct(fetched_at, DateTime) and is_struct(now, DateTime) do
    status_at(fetched_at, now)
  end

  @doc "Classifies a persisted valuation timestamp without requiring its resource record."
  @spec status_at(DateTime.t(), DateTime.t()) :: :fresh | :stale
  def status_at(fetched_at, now)
      when is_struct(fetched_at, DateTime) and is_struct(now, DateTime) do
    if fresh_at?(fetched_at, now), do: :fresh, else: :stale
  end

  @spec fresh?(SingleValuationSnapshot.t(), DateTime.t()) :: boolean()
  def fresh?(%SingleValuationSnapshot{fetched_at: fetched_at}, now)
      when is_struct(fetched_at, DateTime) and is_struct(now, DateTime) do
    fresh_at?(fetched_at, now)
  end

  defp fresh_at?(fetched_at, now), do: DateTime.diff(now, fetched_at, :second) < @ttl_seconds
end
