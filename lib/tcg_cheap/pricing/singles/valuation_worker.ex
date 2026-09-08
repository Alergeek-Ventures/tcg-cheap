defmodule TcgCheap.Pricing.Singles.ValuationWorker do
  @moduledoc "Rollout-safe no-op for retired TCGdex per-card valuation jobs."

  use Oban.Worker, queue: :valuations, max_attempts: 1

  def timeout(_), do: :timer.seconds(60)
  def perform(%Oban.Job{}), do: {:cancel, :legacy_tcgdex_valuation_disabled}
  def perform(_), do: {:cancel, :malformed_job_args}
  def perform_for_policy(%Oban.Job{}, _policy), do: {:cancel, :legacy_tcgdex_valuation_disabled}
  def perform_for_policy(_, _), do: {:cancel, :malformed_job_args}
end
