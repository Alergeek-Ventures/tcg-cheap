defmodule TcgCheap.Sealed.FetchWorker do
  @moduledoc """
  Oban job that refreshes one shop's offers. The daily cron runs it without a
  shop, which queues one job per configured shop; the `sealed` queue then
  fetches them one after another. Shopify shops have the `shopify` queue,
  also one at a time: their requests wait far longer (`TcgCheap.Sealed.ShopFeed.Shopify`)
  and would hold up every other shop, and one at a time keeps a single pace
  towards Shopify, which may count the bot across all its shops.

  A shop is read in steps, so that a restart (every deploy) costs at most the
  request in flight: a step reads for two minutes, and when the shop is not
  yet read to its end the job snoozes and runs again at once. The responses
  already read are kept for the job (`TcgCheap.Sealed.FetchJournal`), and a
  step replays them without asking the shop. A job a restart interrupted
  returns to the queue when the application stops
  (`TcgCheap.JobShutdown`), or else by the Lifeline (config.exs). The offers
  are stored by the step that reads the last response, never before.

  A fetch the shop rate-limited (HTTP 429) is retried 20 and then 40
  minutes later, plus up to 5 minutes of jitter so rate-limited shops do not
  return together; Oban's default backoff (seconds) would ask again while the
  shop still refuses us. The retry goes on from the responses already read.
  A robots.txt that cannot be read is remembered for five minutes
  (`TcgCheap.Bot`), so the next attempt comes after those five minutes (plus up
  to 30 s of jitter) and asks the host afresh; the other failures keep the
  default backoff.

  The bot's policy (`TcgCheap.Bot`) ends a fetch at once, with no further
  attempt that night: a path the shop's robots.txt disallows, a robots.txt
  that refuses us, a 401, a 403 or a challenge response end the job as
  cancelled (after the failure report below). A robots.txt that cannot be read
  (a timeout, a 5xx) is a failure of the moment: the job's attempts retry it. A `Retry-After` the
  fetch does not wait out in place (longer than 10 s, a minute on Shopify) is
  not slept in the queue: the attempt ends, and the next one comes no sooner
  than the shop said and no sooner than the spacing above, so a shop that
  keeps limiting us is asked three times a night, not every minute. A
  `Crawl-delay` that puts the shop's next turn more than five minutes away is
  waited out by snoozing until that turn (plus up to 30 s of jitter), which
  uses up no attempt. Either wait must end an hour before the nightly run that
  follows the job's insertion (02:30 UTC), or the job fails with one report,
  `{:retry_after, seconds}` or `{:robots_crawl_delay, seconds}`, and is
  cancelled. The shop is not asked before the time it named, by any job, and
  the next attempt goes on from the responses already read.

  A failure on the last attempt is reported with `TcgCheap.Sealed.FetchFailure`:
  an error the fetch returns by `perform/1`, and a raise, crash or Oban timeout,
  which never returns there, by the Oban telemetry handler that
  `attach_failure_reports/0` attaches at app start. A job the Lifeline discards
  as orphaned is not reported: its telemetry carries no worker or arguments.
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

  alias TcgCheap.Bot
  alias TcgCheap.Sealed.{FetchFailure, FetchJournal, Refresh, Shops}

  alias TcgCheap.Sealed.ShopFeed.Shopify

  # Seconds. The shop's own pause comes before each request anyway.
  @next_step_in 1

  # The nightly cron entry of this worker (config.exs), UTC.
  @nightly_at ~T[02:30:00]

  @worker inspect(__MODULE__)
  @failure_handler "sealed-fetch-failures"

  @doc """
  Attaches the handler that reports a last attempt that raised, crashed or
  timed out; called at app start. Attaching again replaces the handler.
  """
  @spec attach_failure_reports() :: :ok
  def attach_failure_reports do
    _detached = :telemetry.detach(@failure_handler)

    case :telemetry.attach(
           @failure_handler,
           [:oban, :job, :exception],
           &__MODULE__.handle_failure_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("sealed fetch failures not reported: #{inspect(reason)}")
    end
  end

  # :telemetry detaches a handler that raises, which would silently end these
  # reports, so a failing report is only logged.
  @doc false
  def handle_failure_event(_event, _measurements, metadata, _config) do
    report_failure(metadata)
  catch
    kind, reason ->
      Logger.warning(
        "sealed fetch failure not reported: #{Exception.format(kind, reason, __STACKTRACE__)}"
      )
  end

  # An `{:error, reason}` from `perform/1` (`Oban.PerformError`) is already
  # reported by `refresh/2`, with the fetch's own reason.
  defp report_failure(%{
         job: %Oban.Job{worker: @worker, args: %{"shop" => key}} = job,
         reason: reason
       })
       when is_binary(key) and job.attempt >= job.max_attempts and
              not is_struct(reason, Oban.PerformError),
       do: FetchFailure.report(:sealed, key, failure_reason(reason))

  defp report_failure(_metadata), do: :ok

  defp failure_reason(%Oban.TimeoutError{}), do: :timeout
  defp failure_reason(exception), do: exception

  # One step: its two minutes of reading, a request that was still to finish
  # (a pause, a wait out of a `Retry-After`), and, in the last step, the two
  # transactions that store sealed offers and singles, 5 minutes each
  # (`Refresh.transaction_timeout/0`, `TcgCheap.Cards.Refresh`). Within the
  # Lifeline's time (config.exs), after which a job still executing counts as
  # orphaned and is run again.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)

  @impl Oban.Worker
  def backoff(job), do: Bot.rate_limit_backoff(job) || super(job)

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
    journal = FetchJournal.open(job.id, shop.key, Keyword.take(options, [:budget_ms]))
    req_options = [journal: journal] ++ Keyword.get(options, :req_options, [])

    case Refresh.run(shop, req_options: req_options) do
      # Read as far as the step's time allowed; the next step goes on.
      :paused -> {:snooze, @next_step_in}
      result -> finish(result, shop, job, journal)
    end
  end

  defp finish({:ok, %{offers: count}}, shop, _job, journal) do
    FetchJournal.close(journal)
    Logger.info("sealed fetch #{shop.key}: #{count} offers")
    :ok
  end

  defp finish({:error, reason}, shop, job, journal) do
    case Bot.wait_seconds(reason) do
      seconds when is_integer(seconds) -> wait(reason, seconds, shop, job, journal)
      nil -> fail_or_retry(reason, shop, job, journal)
    end
  end

  # A shop that rate-limits us with a `Retry-After` is asked again no sooner
  # than it said, and that counts as an attempt: a shop that keeps limiting us
  # would otherwise be asked every minute for a day. The attempts are spaced
  # like those after a 429 without a `Retry-After` (`backoff/1`), and the
  # responses already read are kept.
  #
  # A `Crawl-delay` of its robots.txt that leaves the shop's next turn too far
  # away to wait for in place is waited out by snoozing. Snoozes do not count as attempts, so the
  # wait ends with the failure when it would reach the next nightly run, which
  # then reads the shop afresh; a job snoozing past it would keep that run from
  # being queued (the job is unique per shop).
  defp wait({:retry_after, _seconds} = reason, seconds, shop, job, journal) do
    next_in = Bot.rate_limit_wait(job.attempt, seconds)

    cond do
      job.attempt >= job.max_attempts ->
        fail(reason, shop, journal, :error)

      Bot.snooze_before(job, next_in, @nightly_at) == :expired ->
        fail(reason, shop, journal, :cancel)

      true ->
        retry(reason, shop, job, journal)
    end
  end

  defp wait(reason, seconds, shop, job, journal) do
    case Bot.snooze_before(job, seconds, @nightly_at) do
      {:snooze, _seconds} = snooze ->
        Logger.info("sealed fetch #{shop.key}: asked to wait #{seconds} s, snoozing")
        snooze

      :expired ->
        fail(reason, shop, journal, :cancel)
    end
  end

  # Another attempt would only ask a shop that refused us, or one whose
  # robots.txt closes it to us, again.
  defp fail_or_retry(reason, shop, job, journal) do
    cond do
      Bot.final?(reason) -> fail(reason, shop, journal, :cancel)
      # Only the last attempt is a failed fetch: an earlier one is retried and
      # may still read the shop the same night.
      job.attempt < job.max_attempts -> retry(reason, shop, job, journal)
      true -> fail(reason, shop, journal, :error)
    end
  end

  defp retry(reason, shop, job, journal) do
    if not transient?(reason), do: FetchJournal.close(journal)

    Logger.warning(
      "sealed fetch #{shop.key} failed (attempt #{job.attempt} of #{job.max_attempts}), " <>
        "retrying: #{inspect(reason)}"
    )

    {:error, reason}
  end

  defp fail(reason, shop, journal, :cancel) do
    fail(reason, shop, journal, :error)
    {:cancel, reason}
  end

  defp fail(reason, shop, journal, :error) do
    FetchJournal.close(journal)
    FetchFailure.report(:sealed, shop.key, reason)
    {:error, reason}
  end

  # A shop that refused or dropped us once is asked again where it stopped;
  # after any other failure the retry reads the shop afresh, since a response
  # that did not parse may have been a bad one.
  defp transient?({:http_status, 429}), do: true
  defp transient?({:retry_after, _seconds}), do: true
  defp transient?({:transport, _exception}), do: true
  defp transient?(_reason), do: false
end
