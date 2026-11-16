defmodule TcgCheap.Pricing.ExchangeRateWorker do
  @moduledoc """
  Oban acquisition job for one currency's NBP rate to PLN, from the table NBP
  publishes it in (`TcgCheap.Pricing.ExchangeRate.table/1`). The daily job
  without args queues one for every currency the guide needs
  (`TcgCheap.Sealed.Market.currencies/0`).
  """
  use Oban.Worker,
    queue: :exchange_rates,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:source, :table, :base_currency, :quote_currency],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Pricing
  alias TcgCheap.Pricing.ExchangeRate
  alias TcgCheap.Pricing.NbpExchangeRate
  alias TcgCheap.Sealed.Market

  @doc "Queues the acquisition of one currency's latest NBP rate to PLN."
  def enqueue(currency) do
    %{
      source: "nbp",
      table: ExchangeRate.table(currency),
      base_currency: currency,
      quote_currency: "PLN"
    }
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    Enum.each(Market.currencies(), fn currency -> {:ok, _job} = enqueue(currency) end)
  end

  def perform(%Oban.Job{args: args}) do
    with {:ok, table, currency} <- validate_args(args),
         {:ok, observation} <- fetch(table, currency),
         {:ok, _rate} <- persist(observation) do
      :ok
    end
  end

  defp validate_args(
         %{
           "source" => "nbp",
           "table" => table,
           "base_currency" => currency,
           "quote_currency" => "PLN"
         } = args
       )
       when map_size(args) == 4 do
    if currency in Market.currencies() and table == ExchangeRate.table(currency),
      do: {:ok, table, currency},
      else: {:cancel, :malformed_job_args}
  end

  defp validate_args(_args), do: {:cancel, :malformed_job_args}

  defp fetch(table, currency) do
    with {:error, reason} <- NbpExchangeRate.fetch(table, currency), do: classify(reason)
  end

  defp persist(observation) do
    case Pricing.record_exchange_rate(observation) do
      {:ok, rate} -> {:ok, rate}
      {:error, %Ash.Error.Invalid{}} -> {:cancel, :persistence_invalid}
      {:error, _} -> {:error, :persistence_failed}
    end
  end

  # Oban retries `{:error, _}` and discards `{:cancel, _}`.
  defp classify({:rate_limited, details}), do: {:error, {:rate_limited, details}}

  defp classify({:http_error, %{status: status}})
       when status in [408, 429] or status in 500..599,
       do: {:error, {:http_error, status}}

  defp classify({:transport_error, _}), do: {:error, :transport_error}
  defp classify({:http_error, _}), do: {:cancel, :http_error}
  defp classify(reason), do: {:cancel, reason}
end
