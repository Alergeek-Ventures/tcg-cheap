defmodule TcgCheap.Pricing.Singles.FreshnessTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.{Freshness, SingleValuationSnapshot}

  @now ~U[2026-08-07 12:00:00Z]

  test "classifies a valuation as fresh one second inside 24 hours" do
    snapshot = snapshot_at(~U[2026-08-06 12:00:01Z])

    assert Freshness.status(snapshot, @now) == :fresh
    assert Freshness.status_at(snapshot.fetched_at, @now) == :fresh
    assert Freshness.fresh?(snapshot, @now)
  end

  test "classifies a valuation as stale at exactly 24 hours" do
    snapshot = snapshot_at(~U[2026-08-06 12:00:00Z])

    assert Freshness.status(snapshot, @now) == :stale
    assert Freshness.status_at(snapshot.fetched_at, @now) == :stale
    refute Freshness.fresh?(snapshot, @now)
  end

  test "classifies an absent valuation as missing" do
    assert Freshness.status(nil, @now) == :missing
  end

  defp snapshot_at(fetched_at), do: %SingleValuationSnapshot{fetched_at: fetched_at}
end
