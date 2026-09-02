defmodule TcgCheap.Catalogue.SinglesEnrichmentBootstrapWorker do
  @moduledoc "Starts the serial background detail-enrichment chain."
  use Oban.Worker,
    queue: :catalogue_sync,
    priority: 5,
    max_attempts: 5,
    unique: [
      period: 15 * 60,
      keys: [:policy_version],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.CardDetailEnrichmentWorker
  alias TcgCheap.Core

  @policy_version 1
  def timeout(_), do: :timer.seconds(60)

  def enqueue do
    new(%{"policy_version" => @policy_version}) |> Oban.insert()
  end

  def perform(%Oban.Job{args: %{"policy_version" => @policy_version}} = _job) do
    case Core.list_detail_enrichment_candidates(nil, 1, authorize?: false) do
      {:ok, [card | _]} ->
        case CardDetailEnrichmentWorker.enqueue(card, true, priority: 5) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :persistence_failed}
        end

      {:ok, []} ->
        :ok

      _ ->
        {:error, :persistence_failed}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}
end
