defmodule TcgCheap.Pricing.ExchangeRateWorker do
  @moduledoc "Oban acquisition job for one currency's NBP rate to PLN."
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
  alias TcgCheap.Pricing.ExchangeRate

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, args} <- validate_args(args),
         {:ok, result} <- acquire(args),
         {:ok, _rate} <- persist(result) do
      :ok
    else
      {:retry, reason} -> {:error, reason}
      {:cancel, reason} -> {:cancel, reason}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp validate_args(
         %{
           "source" => "nbp",
           "table" => "A",
           "base_currency" => currency,
           "quote_currency" => "PLN"
         } = args
       )
       when map_size(args) == 4 do
    if currency in ExchangeRate.currencies(),
      do: {:ok, args},
      else: {:cancel, :malformed_job_args}
  end

  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp acquire(args) do
    case provider_config() do
      {:ok, adapter, options} -> adapter |> safely_fetch(args, options) |> classify_fetch(args)
      _ -> {:cancel, :invalid_provider_configuration}
    end
  end

  defp classify_fetch({:ok, {:ok, result}}, args), do: validate_result(result, args)
  defp classify_fetch({:ok, {:error, reason}}, _args), do: classify(reason)
  defp classify_fetch({:ok, _other}, _args), do: {:cancel, :malformed_provider_result}
  defp classify_fetch({:error, reason}, _args), do: classify(reason)

  @doc false
  def provider_config do
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
           base_currency: currency,
           quote_currency: "PLN"
         } = result,
         %{"base_currency" => currency}
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

  defp validate_result(_result, _args), do: {:cancel, :malformed_provider_result}

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
  defp classify(:no_published_rate), do: {:cancel, :no_published_rate}
  defp classify({:http_error, _}), do: {:cancel, :http_error}
  defp classify(reason), do: {:cancel, reason}

  defp finite_decimal?(value), do: not Decimal.nan?(value) and not Decimal.inf?(value)
end
