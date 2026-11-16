defmodule TcgCheap.JobShutdown do
  @moduledoc """
  Puts the jobs still running when the application stops back in the queue.

  Oban waits `shutdown_grace_period` (config.exs) for running jobs, then stops
  their processes and leaves them `executing`: nothing but the Lifeline brings
  such a job back, an hour or minutes later, and it counts as an attempt the
  job did not get. The deploy that stopped the application is no failure of
  the job, so the job goes back to `available` at once, with the attempt
  returned, for the next start to run. Every job that is stopped like this
  runs again from its beginning, so its worker must be safe to repeat; the
  long ones keep their progress (`TcgCheap.Sealed.FetchJournal`).
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  @handler "tcg-cheap-job-shutdown"

  @doc "Attaches the handler of Oban's queue shutdown; called at app start."
  @spec attach() :: :ok
  def attach do
    _detached = :telemetry.detach(@handler)

    case :telemetry.attach(
           @handler,
           [:oban, :queue, :shutdown],
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("stopped jobs not returned: #{inspect(reason)}")
    end
  end

  # :telemetry detaches a handler that raises, which would silently end this
  # for every later shutdown of the node, so a failure is only logged.
  @doc false
  def handle_event(_event, _measurements, %{orphaned: [_ | _] = ids, conf: conf}, _config) do
    # Still `executing`: one that finished meanwhile stays finished.
    query = from(job in Oban.Job, where: job.id in ^ids and job.state == "executing")

    {count, _jobs} =
      Oban.Repo.update_all(conf, query, set: [state: "available"], inc: [attempt: -1])

    Logger.info("stopped jobs returned to the queue: #{count}")
  catch
    kind, reason ->
      Logger.warning(
        "stopped jobs not returned: #{Exception.format(kind, reason, __STACKTRACE__)}"
      )
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
