defmodule TcgCheap.Pricing.ExchangeRateWorker do
  @moduledoc "Oban acquisition job for the NBP EUR/PLN rate."
  use Oban.Worker,
    queue: :exchange_rates,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:source, :table, :base_currency, :quote_currency],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Core
  alias TcgCheap.Operations.AcquisitionTracker
  alias TcgCheap.Pricing.ExchangeRateAcquisition

  @canonical %{
    "source" => "nbp",
    "table" => "A",
    "base_currency" => "EUR",
    "quote_currency" => "PLN"
  }

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    with {:ok, args} <- validate_args(args),
         result <-
           AcquisitionTracker.run(
             job,
             tracker_options(),
             &execute(args, &1, job)
           ) do
      result
    else
      {:cancel, reason} ->
        broadcast_failure(reason)
        {:cancel, reason}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp validate_args(@canonical), do: {:ok, @canonical}
  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp execute(args, request_admitter, job) do
    with {:ok, result} <- acquire(args, request_admitter),
         {:ok, rate} <- persist(result) do
      Phoenix.PubSub.broadcast(
        TcgCheap.PubSub,
        ExchangeRateAcquisition.topic(),
        {:exchange_rate_completed, %{exchange_rate: rate}}
      )

      :ok
    else
      {:retry, reason} ->
        retry_or_fail(job, reason)

      {:cancel, reason} ->
        broadcast_failure(reason)
        {:cancel, reason}
    end
  end

  defp acquire(args, request_admitter) do
    case provider_config() do
      {:ok, adapter, options} -> admitted_fetch(adapter, args, options, request_admitter)
      _ -> {:cancel, :invalid_provider_configuration}
    end
  end

  defp admitted_fetch(adapter, args, options, request_admitter) do
    options = Keyword.put(options, :request_admitter, request_admitter)
    classify_fetch(safely_fetch(adapter, args, options))
  end

  defp tracker_options,
    do: [
      provider_key: "nbp",
      operation: "exchange_rate",
      target_key: "EUR/PLN"
    ]

  defp classify_fetch({:ok, {:ok, result}}), do: validate_result(result)
  defp classify_fetch({:ok, {:error, reason}}), do: classify(reason)
  defp classify_fetch({:ok, _other}), do: {:cancel, :malformed_provider_result}
  defp classify_fetch({:error, reason}), do: classify(reason)

  defp provider_config do
    config = Application.get_env(:tcg_cheap, :exchange_rate_provider, [])

    with true <- is_list(config) and Keyword.keyword?(config) and unique_keys?(config),
         [:adapter, :options] <- Enum.sort(Keyword.keys(config)),
         adapter when is_atom(adapter) <- Keyword.fetch!(config, :adapter),
         true <- Code.ensure_loaded?(adapter) and function_exported?(adapter, :fetch, 2),
         options when is_list(options) <- Keyword.fetch!(config, :options),
         true <- Keyword.keyword?(options) and unique_keys?(options),
         true <- valid_options?(options) do
      {:ok, adapter, options}
    else
      _ -> {:error, :invalid_provider_configuration}
    end
  end

  defp unique_keys?(keyword), do: length(keyword) == length(Enum.uniq(Keyword.keys(keyword)))

  defp valid_options?(options) do
    Enum.all?(Keyword.keys(options), &(&1 in [:plug, :retry, :max_retries, :clock])) and
      valid_plug?(Keyword.get(options, :plug)) and
      Keyword.get(options, :retry, :safe_transient) in [false, :safe_transient] and
      match?(
        retries when is_integer(retries) and retries in 0..2,
        Keyword.get(options, :max_retries, 2)
      ) and
      match?(
        clock when is_function(clock, 0),
        Keyword.get(options, :clock, &DateTime.utc_now/0)
      )
  end

  defp valid_plug?(nil), do: true
  defp valid_plug?(plug) when is_atom(plug), do: true
  defp valid_plug?({module, _name}) when is_atom(module), do: true
  defp valid_plug?(_), do: false

  defp safely_fetch(adapter, args, options) do
    {:ok, adapter.fetch(args, options)}
  rescue
    _ -> {:error, :transport_error}
  catch
    _, _ -> {:error, :transport_error}
  end

  defp validate_result(
         %{
           rate: %Decimal{} = rate,
           effective_date: %Date{} = effective_date,
           publication_number: no,
           fetched_at: %DateTime{} = fetched_at,
           source: "nbp",
           table: "A",
           base_currency: "EUR",
           quote_currency: "PLN"
         } = result
       )
       when is_binary(no) and no != "" do
    if String.trim(no) == "" do
      {:cancel, :malformed_provider_result}
    else
      if finite_decimal?(rate) and Decimal.compare(rate, Decimal.new(0)) == :gt and
           Date.compare(effective_date, DateTime.to_date(fetched_at)) != :gt,
         do:
           {:ok,
            Map.take(result, [
              :rate,
              :effective_date,
              :publication_number,
              :fetched_at,
              :source,
              :table,
              :base_currency,
              :quote_currency
            ])},
         else: {:cancel, :malformed_provider_result}
    end
  end

  defp validate_result(_), do: {:cancel, :malformed_provider_result}

  defp persist(result) do
    case Core.record_exchange_rate(result) do
      {:ok, rate} -> {:ok, rate}
      {:error, %Ash.Error.Invalid{}} -> {:cancel, :persistence_invalid}
      {:error, _} -> {:retry, :persistence_failed}
    end
  end

  defp classify({:rate_limited, details}), do: {:retry, {:rate_limited, details}}

  defp classify({:http_error, %{status: status}})
       when is_integer(status) and (status in [408, 429] or status in 500..599),
       do: {:retry, {:http_error, status}}

  defp classify({:transport_error, _}), do: {:retry, :transport_error}
  defp classify(:transport_error), do: {:retry, :transport_error}
  defp classify(:budget_persistence_failed), do: {:retry, :budget_persistence_failed}
  defp classify(:no_published_rate), do: {:cancel, :no_published_rate}
  defp classify({:http_error, _}), do: {:cancel, :http_error}
  defp classify(reason), do: {:cancel, reason}

  defp finite_decimal?(value), do: not Decimal.nan?(value) and not Decimal.inf?(value)

  defp retry_or_fail(%Oban.Job{attempt: attempt, max_attempts: max} = _job, reason)
       when attempt >= max do
    broadcast_failure(reason)
    {:error, reason}
  end

  defp retry_or_fail(_job, reason), do: {:error, reason}

  defp broadcast_failure(reason) do
    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      ExchangeRateAcquisition.topic(),
      {:exchange_rate_failed, %{reason: reason}}
    )
  end
end
