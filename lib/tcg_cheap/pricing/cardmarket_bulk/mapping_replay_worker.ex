defmodule TcgCheap.Pricing.CardmarketBulk.MappingReplayWorker do
  @moduledoc "Replays crosswalk and materialization after an administrator mapping approval."
  use Oban.Worker,
    queue: :cardmarket_bulk,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:decision_id], fields: [:worker, :args]]

  alias TcgCheap.Catalogue.CardmarketCrosswalk

  alias TcgCheap.Catalogue.{
    CardmarketCardMappingEvidence,
    CardmarketExpansionMapping,
    CardPrinting
  }

  alias TcgCheap.Catalogue.CardPrintingMappingDecision
  alias TcgCheap.Catalogue.CardSetCardmarketMappingDecision
  alias TcgCheap.Pricing.CardmarketBulk.{Batch, MappingNotifications, Materializer}
  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot
  require Ash.Query
  import Ash.Expr

  def enqueue(batch_id, decision_id),
    do: new(%{"batch_id" => batch_id, "decision_id" => decision_id}) |> Oban.insert()

  @impl true
  def perform(%Oban.Job{args: %{"batch_id" => batch_id, "decision_id" => decision_id}}) do
    case {Ecto.UUID.cast(batch_id), Ecto.UUID.cast(decision_id)} do
      {:error, _} -> {:discard, :malformed_job_args}
      {_, :error} -> {:discard, :malformed_job_args}
      _ -> perform_replay(batch_id, decision_id)
    end
  end

  def perform(_), do: {:discard, :malformed_job_args}

  @doc false
  def materialize(%Batch{} = batch), do: Materializer.run(batch)

  defp perform_replay(batch_id, decision_id) do
    decision_query =
      Ash.Query.for_read(CardSetCardmarketMappingDecision, :read, %{})
      |> Ash.Query.filter(expr(id == ^decision_id and source_batch_id == ^batch_id))

    query =
      Ash.Query.for_read(Batch, :read, %{})
      |> Ash.Query.filter(expr(id == ^batch_id and status == "succeeded"))

    case Ash.read_one(decision_query, authorize?: false) do
      {:ok, nil} ->
        {:discard, :decision_not_found}

      {:ok, %CardSetCardmarketMappingDecision{}} ->
        case Ash.read_one(query, authorize?: false) do
          {:ok, nil} -> {:discard, :batch_not_succeeded}
          {:ok, %Batch{} = batch} -> replay(batch)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Replays the exact materialization sequence for a succeeded batch."
  def replay_succeeded_batch(%Batch{status: "succeeded"} = batch) do
    Ash.transact(
      [
        CardmarketExpansionMapping,
        CardmarketCardMappingEvidence,
        CardPrinting,
        CardPrintingMappingDecision,
        SingleValuationSnapshot
      ],
      fn ->
        with {:ok, _} <- CardmarketCrosswalk.run(batch), do: materialize(batch)
      end
    )
    |> case do
      {:ok, _} ->
        MappingNotifications.notify_batch(batch.id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def replay_succeeded_batch(_), do: {:error, :batch_not_succeeded}

  defp replay(batch), do: replay_succeeded_batch(batch)
end
