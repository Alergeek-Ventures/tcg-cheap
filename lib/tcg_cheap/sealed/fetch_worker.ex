defmodule TcgCheap.Sealed.FetchWorker do
  @moduledoc """
  Oban job that refreshes one shop's offers. The daily cron runs it without a
  shop, which queues one job per configured shop; the `sealed` queue then
  fetches them one after another.

  A fetch the shop rate-limited (HTTP 429) is retried 20 and then 40 minutes
  later, plus up to 5 minutes of jitter so rate-limited shops do not return
  together; Oban's default backoff (seconds) would ask again while the shop
  still refuses us. Other failures keep the default backoff.
  """

  use Oban.Worker,
    queue: :sealed,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:shop],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias TcgCheap.Sealed.{Refresh, Shops}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def backoff(%Oban.Job{
        attempt: attempt,
        unsaved_error: %{reason: %Oban.PerformError{reason: {:error, {:http_status, 429}}}}
      }),
      do: attempt * 20 * 60 + :rand.uniform(5 * 60)

  def backoff(job), do: super(job)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"shop" => key}}) do
    case Shops.fetch(key) do
      {:ok, shop} -> refresh(shop)
      :error -> {:cancel, :unknown_shop}
    end
  end

  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    Enum.each(Shops.keys(), fn key -> {:ok, _job} = enqueue(key) end)
  end

  def perform(_job), do: {:cancel, :malformed_args}

  @doc "Queues a refresh of one shop."
  @spec enqueue(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(key), do: %{"shop" => key} |> new() |> Oban.insert()

  defp refresh(shop) do
    options = Application.get_env(:tcg_cheap, __MODULE__, [])

    case Refresh.run(shop, req_options: Keyword.get(options, :req_options, [])) do
      {:ok, %{offers: count}} ->
        Logger.info("sealed fetch #{shop.key}: #{count} offers")
        :ok

      {:error, reason} ->
        Logger.warning("sealed fetch #{shop.key} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
