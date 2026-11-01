defmodule TcgCheap.Sealed.SuggestedPriceWorker do
  @moduledoc "Daily Oban job that collects REBEL's suggested retail prices (`TcgCheap.Sealed.Rebel`)."

  use Oban.Worker,
    queue: :sealed,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TcgCheap.Sealed.Rebel

  @impl Oban.Worker
  # The first run reads every product page, 5 seconds apart.
  def timeout(_job), do: :timer.minutes(15)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    options = Application.get_env(:tcg_cheap, __MODULE__, [])

    case Rebel.run(req_options: Keyword.get(options, :req_options, [])) do
      {:ok, %{items: items, matched: matched}} ->
        Logger.info("REBEL suggested prices: #{items} listed, #{matched} matched")
        :ok

      {:error, reason} ->
        Logger.warning("REBEL suggested prices failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Queues a collection."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> new() |> Oban.insert()
end
