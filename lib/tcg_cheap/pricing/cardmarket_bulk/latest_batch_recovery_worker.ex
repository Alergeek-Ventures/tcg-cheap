defmodule TcgCheap.Pricing.CardmarketBulk.LatestBatchRecoveryWorker do
  @moduledoc "Operator-triggered replay of the latest successful Cardmarket batch."

  use Oban.Worker,
    queue: :cardmarket_bulk,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias TcgCheap.Catalogue.LegacyCardmarketMappingRecovery
  alias TcgCheap.Core
  alias TcgCheap.Pricing.CardmarketBulk.{Batch, MappingReplayWorker}

  @revision "cardmarket_mapping_recovery_v1"

  @doc "Enqueues the revisioned operator recovery job."
  def enqueue, do: new(%{"revision" => @revision}) |> Oban.insert()

  def perform(%Oban.Job{args: %{"revision" => @revision} = args}) when map_size(args) == 1 do
    with {:ok, %Batch{} = batch} <-
           Core.get_latest_successful_cardmarket_bulk_batch(authorize?: false),
         {:ok, _} <- LegacyCardmarketMappingRecovery.run(),
         result <- MappingReplayWorker.replay_succeeded_batch(batch),
         :ok <- result do
      :ok
    else
      {:ok, nil} -> {:discard, :no_succeeded_batch}
      {:error, reason} -> {:error, reason}
      other -> {:discard, other}
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :malformed_job_args}
  def perform(_), do: {:discard, :malformed_job_args}
end
