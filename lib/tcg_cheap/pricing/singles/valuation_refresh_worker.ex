defmodule TcgCheap.Pricing.Singles.ValuationRefreshWorker do
  @moduledoc "Rollout-safe no-op for retired TCGdex valuation sweep jobs."

  use Oban.Worker, queue: :valuations, max_attempts: 1

  def enqueue, do: %{} |> new() |> Oban.insert()
  def perform(%Oban.Job{}), do: {:cancel, :legacy_tcgdex_valuation_disabled}
  def perform(_), do: {:cancel, :malformed_job_args}
  def perform_for_policy(%Oban.Job{}, _policy), do: {:cancel, :legacy_tcgdex_valuation_disabled}
  def perform_for_policy(_, _), do: {:cancel, :malformed_job_args}
end
