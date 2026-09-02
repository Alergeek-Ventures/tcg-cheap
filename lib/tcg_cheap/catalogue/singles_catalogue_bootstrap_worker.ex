defmodule TcgCheap.Catalogue.SinglesCatalogueBootstrapWorker do
  @moduledoc "Weekly canonical bootstrap for the complete catalogue and detail chain."
  use Oban.Worker,
    queue: :catalogue_sync,
    max_attempts: 5,
    unique: [
      period: 7 * 24 * 60 * 60,
      keys: [:policy_version],
      states: [:available, :scheduled, :executing, :retryable, :suspended, :completed],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.{CatalogueSyncWorker, SinglesEnrichmentBootstrapWorker}
  @policy_version 1
  def timeout(_), do: :timer.seconds(120)
  def enqueue, do: new(%{"policy_version" => @policy_version}) |> Oban.insert()

  def perform(%Oban.Job{args: %{"policy_version" => @policy_version}}) do
    with {:ok, _} <- CatalogueSyncWorker.enqueue(),
         {:ok, _} <- SinglesEnrichmentBootstrapWorker.enqueue() do
      :ok
    else
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}
end
