defmodule TcgCheap.Sealed.CatalogueImportWorker do
  @moduledoc "Daily Oban job that imports the Cardmarket sealed catalogue and prices."

  use Oban.Worker,
    queue: :sealed,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TcgCheap.Sealed.CatalogueImport

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    options = Application.get_env(:tcg_cheap, __MODULE__, [])

    case CatalogueImport.run(request_options: Keyword.get(options, :request_options, [])) do
      {:ok, %{products: count}} ->
        Logger.info("sealed catalogue import: #{count} products")
        :ok

      {:error, reason} ->
        Logger.warning("sealed catalogue import failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Queues an import."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> new() |> Oban.insert()
end
