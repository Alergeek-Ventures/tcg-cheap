defmodule TcgCheap.Pricing.Singles.ValuationRefreshWorker do
  @moduledoc "Refreshes valuations for currently scoped, matched Singles cards."
  use Oban.Worker,
    queue: :valuations,
    max_attempts: 3,
    unique: [
      period: 86_400,
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Catalogue.Tcgdex
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.ValuationAcquisition
  def timeout(_), do: :timer.seconds(120)

  def enqueue, do: %{} |> new() |> Oban.insert()

  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    perform_page(nil, page_size())
  end

  def perform(%Oban.Job{args: %{"cursor" => cursor, "limit" => limit} = args})
      when map_size(args) == 2 and is_binary(cursor) and is_integer(limit) and limit in 1..1_000 do
    if Tcgdex.valid_card_id?(cursor) do
      perform_page(cursor, limit)
    else
      {:cancel, :malformed_job_args}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp perform_page(cursor, limit) do
    case Core.list_singles_valuation_candidates(cursor, limit, authorize?: false) do
      {:ok, cards} when is_list(cards) ->
        case Enum.reduce_while(cards, :ok, &refresh_card/2) do
          :ok -> enqueue_next(cards, limit)
          error -> error
        end

      {:error, _} ->
        {:error, :persistence_failed}
    end
  end

  defp page_size do
    case Application.get_env(:tcg_cheap, :valuation_refresh_page_size, 1_000) do
      size when is_integer(size) and size in 1..1_000 -> size
      _ -> 1_000
    end
  end

  defp enqueue_next([], _limit), do: :ok

  defp enqueue_next(cards, limit) do
    cursor = List.last(cards).tcgdex_id

    case new(%{"cursor" => cursor, "limit" => limit}) |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  defp refresh_card(card, :ok) do
    case ValuationAcquisition.enqueue_if_stale_background(card) do
      {:fresh, _} -> {:cont, :ok}
      {:enqueued, _} -> {:cont, :ok}
      {:error, :unpriced_mapping} -> {:cont, :ok}
      {:error, _} -> {:halt, {:error, :persistence_failed}}
    end
  end
end
