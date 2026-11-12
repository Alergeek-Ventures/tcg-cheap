defmodule TcgCheap.Sealed.CardSyncWorker do
  @moduledoc """
  Daily Oban job that copies the cards of TCGdex sets and their Cardmarket
  product ids (`TcgCheap.Sealed.CardSync`).
  """

  use Oban.Worker,
    queue: :sealed,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TcgCheap.Sealed.CardSync

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, counts} = CardSync.run()

    Logger.info(
      "TCGdex set cards: #{counts.synced} sets copied, #{counts.failed} failed; " <>
        "Cardmarket ids: #{counts.looked_up} cards looked up, #{counts.lookups_failed} failed, " <>
        "#{counts.checked} set from the checked list, #{counts.unlinked} unlinked as shared"
    )

    :ok
  end

  @doc "Queues a run now, unless one is already waiting or running."
  def enqueue, do: %{} |> new() |> Oban.insert()
end
