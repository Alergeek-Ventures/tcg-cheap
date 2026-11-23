defmodule TcgCheap.Sealed.SuggestedPriceWorker do
  @moduledoc "Daily Oban job that collects REBEL's suggested retail prices (`TcgCheap.Sealed.Rebel`)."

  use Oban.Worker,
    queue: :sealed,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TcgCheap.Bot
  alias TcgCheap.Sealed.Rebel

  # The daily cron entry of this worker (config.exs), UTC.
  @daily_at ~T[03:15:00]

  @impl Oban.Worker
  # The first run reads every product page, 5 seconds apart.
  def timeout(_job), do: :timer.minutes(15)

  @impl Oban.Worker
  def backoff(job), do: Bot.rate_limit_backoff(job) || super(job)

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    options = Application.get_env(:tcg_cheap, __MODULE__, [])

    case Rebel.run(req_options: Keyword.get(options, :req_options, [])) do
      {:ok, %{items: items, matched: matched}} ->
        Logger.info("REBEL suggested prices: #{items} listed, #{matched} matched")
        :ok

      {:error, reason} ->
        Logger.warning("REBEL suggested prices failed: #{inspect(reason)}")
        stop_or_retry(reason, job)
    end
  end

  # The bot's policy (`TcgCheap.Bot`): another attempt would ask a host that
  # refused us, or that robots.txt closes to us, again. A `Retry-After` ends
  # the attempt, and the next one comes no sooner than the host said and no
  # sooner than `Bot.rate_limit_wait/2` (see `backoff/1`), so a host that keeps
  # limiting us is asked three times a night, not every minute; the job ends
  # with the failure when that wait would reach the next daily run (the job is
  # unique, so a retrying one would block that run). A `Crawl-delay` is snoozed.
  defp stop_or_retry({:retry_after, seconds} = reason, job) do
    case Bot.snooze_before(job, Bot.rate_limit_wait(job.attempt, seconds), @daily_at) do
      {:snooze, _seconds} -> {:error, reason}
      :expired -> {:cancel, reason}
    end
  end

  defp stop_or_retry(reason, job) do
    with seconds when is_integer(seconds) <- Bot.wait_seconds(reason),
         {:snooze, _seconds} = snooze <- Bot.snooze_before(job, seconds, @daily_at) do
      snooze
    else
      nil -> if Bot.final?(reason), do: {:cancel, reason}, else: {:error, reason}
      :expired -> {:cancel, reason}
    end
  end

  @doc "Queues a collection."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> new() |> Oban.insert()
end
