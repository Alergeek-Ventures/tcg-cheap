defmodule TcgCheap.Sealed.FetchWorker do
  @moduledoc """
  Oban job that refreshes one shop's offers. The daily cron runs it without a
  shop, which queues one job per configured shop; the `sealed` queue then
  fetches them one after another. Shopify shops have the `shopify` queue,
  also one at a time: their requests wait far longer (`TcgCheap.Sealed.Shopify`)
  and would hold up every other shop, and one at a time keeps a single pace
  towards Shopify, which may count the bot across all its shops.

  A fetch the shop rate-limited (HTTP 429), or a Shopify fetch that ran out
  of time (most likely waiting out `Retry-After`s), is retried 20 and then 40
  minutes later, plus up to 5 minutes of jitter so rate-limited shops do not
  return together; Oban's default backoff (seconds) would ask again while the
  shop still refuses us. Other failures keep the default backoff.
  """

  use Oban.Worker,
    queue: :sealed,
    max_attempts: 3,
    unique: [
      period: :infinity,
      # Not the queue: one job per shop, whichever queue it was put in.
      fields: [:args, :worker],
      keys: [:shop],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias TcgCheap.Sealed.{FetchFailure, Refresh, Shopify, Shops}

  # Within the Lifeline's 30 minutes (config.exs), after which a job still
  # executing counts as orphaned and is run again.
  @impl Oban.Worker
  def timeout(%Oban.Job{queue: "shopify"}), do: :timer.minutes(25)
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def backoff(%Oban.Job{
        attempt: attempt,
        unsaved_error: %{reason: %Oban.PerformError{reason: {:error, {:http_status, 429}}}}
      }),
      do: rate_limited_backoff(attempt)

  def backoff(%Oban.Job{
        attempt: attempt,
        queue: "shopify",
        unsaved_error: %{reason: %Oban.TimeoutError{}}
      }),
      do: rate_limited_backoff(attempt)

  def backoff(job), do: super(job)

  defp rate_limited_backoff(attempt), do: attempt * 20 * 60 + :rand.uniform(5 * 60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"shop" => key}} = job) do
    case Shops.fetch(key) do
      {:ok, shop} -> refresh(shop, job)
      :error -> {:cancel, :unknown_shop}
    end
  end

  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    Enum.each(Shops.keys(), fn key -> {:ok, _job} = enqueue(key) end)
  end

  def perform(_job), do: {:cancel, :malformed_args}

  @doc "Queues a refresh of one shop."
  @spec enqueue(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(key), do: %{"shop" => key} |> new(queue: queue(key)) |> Oban.insert()

  defp queue(key) do
    case Shops.fetch(key) do
      {:ok, %{source: Shopify}} -> :shopify
      _other -> :sealed
    end
  end

  defp refresh(shop, job) do
    options = Application.get_env(:tcg_cheap, __MODULE__, [])

    case Refresh.run(shop, req_options: Keyword.get(options, :req_options, [])) do
      {:ok, %{offers: count}} ->
        Logger.info("sealed fetch #{shop.key}: #{count} offers")
        :ok

      # Only the last attempt is a failed fetch: an earlier one is retried and
      # may still read the shop the same night.
      {:error, reason} when job.attempt < job.max_attempts ->
        Logger.warning(
          "sealed fetch #{shop.key} failed (attempt #{job.attempt} of #{job.max_attempts}), " <>
            "retrying: #{inspect(reason)}"
        )

        {:error, reason}

      {:error, reason} ->
        FetchFailure.report(:sealed, shop.key, reason)
        {:error, reason}
    end
  end
end
