defmodule TcgCheap.Pricing.ExchangeRateAcquisition do
  @moduledoc "Coordinates daily local exchange-rate acquisition without HTTP."
  alias TcgCheap.Core
  alias TcgCheap.Pricing.ExchangeRateWorker

  @canonical %{
    "source" => "nbp",
    "table" => "A",
    "base_currency" => "EUR",
    "quote_currency" => "PLN"
  }

  @spec topic() :: String.t()
  def topic, do: "exchange_rates"

  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: @canonical |> ExchangeRateWorker.new() |> Oban.insert()

  @spec latest(Date.t()) :: {:ok, term()} | {:error, :invalid_date}
  def latest(as_of) do
    with {:ok, date} <- valid_date(as_of), do: Core.get_latest_exchange_rate(date)
  end

  def subscribe_and_request_latest(opts \\ [])

  def subscribe_and_request_latest(opts) when is_list(opts) do
    with true <- valid_options?(opts),
         :ok <- Phoenix.PubSub.subscribe(TcgCheap.PubSub, topic()),
         {:ok, now} <- clock_now(opts),
         {:ok, latest} <- latest(DateTime.to_date(now)) do
      if fresh_today?(latest, now), do: {:fresh, latest}, else: enqueue_result(opts)
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def subscribe_and_request_latest(_), do: {:error, :invalid_options}

  defp unique_keys?(opts), do: length(opts) == length(Enum.uniq(Keyword.keys(opts)))

  defp valid_options?(opts) do
    Keyword.keyword?(opts) and unique_keys?(opts) and
      Enum.all?(Keyword.keys(opts), &(&1 in [:clock, :request_admitter])) and
      valid_function_option?(opts, :request_admitter, 0)
  end

  defp valid_function_option?(opts, key, arity) do
    case Keyword.fetch(opts, key) do
      :error -> true
      {:ok, value} -> is_function(value, arity)
    end
  end

  defp enqueue_result(opts) do
    case admit(opts) do
      :ok -> enqueue_job()
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_job do
    case enqueue() do
      {:ok, job} -> {:enqueued, job}
      error -> error
    end
  end

  defp admit(opts) do
    case Keyword.get(opts, :request_admitter) do
      nil ->
        {:error, :request_admitter_required}

      callback ->
        try do
          case callback.() do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
            _ -> {:error, :invalid_request_admission}
          end
        rescue
          _ -> {:error, :request_admission_failed}
        catch
          _, _ -> {:error, :request_admission_failed}
        end
    end
  end

  defp fresh_today?(%{fetched_at: %DateTime{} = fetched}, %DateTime{} = now),
    do: DateTime.to_date(fetched) == DateTime.to_date(now)

  defp fresh_today?(_, _), do: false
  defp valid_date(%Date{} = date), do: {:ok, date}
  defp valid_date(_), do: {:error, :invalid_date}

  defp clock_now(opts) do
    clock =
      Keyword.get(
        opts,
        :clock,
        Application.get_env(:tcg_cheap, :exchange_rate_clock, &DateTime.utc_now/0)
      )

    if is_function(clock, 0) do
      try do
        case clock.() do
          %DateTime{} = now -> {:ok, now}
          _ -> {:error, :invalid_clock}
        end
      rescue
        _ -> {:error, :invalid_clock}
      catch
        _, _ -> {:error, :invalid_clock}
      end
    else
      {:error, :invalid_clock}
    end
  end
end
