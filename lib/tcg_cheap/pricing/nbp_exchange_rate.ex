defmodule TcgCheap.Pricing.NbpExchangeRate do
  @moduledoc "Fetches and validates the NBP table A EUR exchange rate."
  @behaviour TcgCheap.Pricing.ExchangeRateProvider
  alias TcgCheap.Pricing.ExchangeRateProvider.Result
  @url "https://api.nbp.pl/api/exchangerates/rates/a/eur/"
  @allowed [:plug, :retry, :max_retries, :clock, :request_admitter]

  @impl true
  def fetch(
        %{
          "source" => "nbp",
          "table" => "A",
          "base_currency" => "EUR",
          "quote_currency" => "PLN"
        } = request,
        options
      )
      when is_list(options) and map_size(request) == 4 do
    with :ok <- valid_options(options),
         {:ok, fetched_at} <- clock(options),
         {:ok, response} <- request(options),
         {:ok, payload} <- decode(response.body) do
      normalize(payload, fetched_at)
    end
  end

  def fetch(request, _options) when not is_map(request), do: {:error, :invalid_request}
  def fetch(_request, _options), do: {:error, :invalid_request}

  defp valid_options(options) do
    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in @allowed)) and
         length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
       do: validate_request_values(options),
       else: {:error, :invalid_options}
  end

  defp validate_request_values(options) do
    retry = Keyword.get(options, :retry, :safe_transient)
    max_retries = Keyword.get(options, :max_retries, 2)
    plug = Keyword.get(options, :plug)

    if valid_plug?(plug) and retry in [false, :safe_transient] and is_integer(max_retries) and
         max_retries in 0..2 and
         is_function(Keyword.get(options, :request_admitter, fn -> :ok end), 0),
       do: :ok,
       else: {:error, :invalid_options}
  end

  defp valid_plug?(nil), do: true
  defp valid_plug?(plug) when is_atom(plug), do: true
  defp valid_plug?({module, _name}) when is_atom(module), do: true
  defp valid_plug?(_), do: false

  defp clock(options) do
    clock = Keyword.get(options, :clock, &DateTime.utc_now/0)

    if is_function(clock, 0) do
      try do
        case clock.() do
          %DateTime{} = value -> {:ok, value}
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

  defp request(options) do
    budgeted? = Keyword.has_key?(options, :request_admitter)

    req_options =
      [
        url: @url,
        decode_body: false,
        receive_timeout: 10_000
      ]
      |> Keyword.merge(request_attempt_options(options, budgeted?))
      |> maybe_put(:plug, Keyword.get(options, :plug))

    with :ok <- admit_request(options) do
      case Req.request(req_options) do
        {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, %{body: body}}
        {:ok, %{status: 200}} -> {:error, :malformed_response}
        {:ok, %{status: 404}} -> {:error, :no_published_rate}
        {:ok, %{status: 429}} -> {:error, {:rate_limited, %{status: 429}}}
        {:ok, %{status: status}} -> {:error, {:http_error, %{status: status}}}
        {:error, reason} -> {:error, {:transport_error, reason}}
      end
    end
  rescue
    exception -> {:error, {:transport_error, exception}}
  end

  defp admit_request(options) do
    case Keyword.get(options, :request_admitter, fn -> :ok end).() do
      :ok -> :ok
      {:error, :budget_persistence_failed} = error -> error
      {:error, {:acquisition_budget_rejected, _reason}} = error -> error
      _ -> {:error, :invalid_admission_result}
    end
  rescue
    _ -> {:error, :budget_persistence_failed}
  catch
    _, _ -> {:error, :budget_persistence_failed}
  end

  defp request_attempt_options(_options, true),
    do: [retry: false, max_retries: 0, redirect: false]

  defp request_attempt_options(options, false),
    do: [
      retry: Keyword.get(options, :retry, :safe_transient),
      max_retries: Keyword.get(options, :max_retries, 2)
    ]

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp decode(body) do
    case Jason.decode(body, floats: :decimals) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :malformed_json}
    end
  end

  defp normalize(%{"table" => "A", "code" => "EUR", "rates" => [rate]}, fetched_at),
    do: normalize_rate(rate, fetched_at)

  defp normalize(_payload, _fetched_at), do: {:error, :malformed_shape}

  defp normalize_rate(
         %{"mid" => value, "effectiveDate" => date, "no" => no},
         fetched_at
       )
       when is_binary(date) and is_binary(no) do
    with {:ok, value} <- decimal_value(value),
         true <- String.trim(no) != "",
         {:ok, effective_date} <- Date.from_iso8601(date),
         true <- Date.compare(effective_date, DateTime.to_date(fetched_at)) != :gt,
         true <- finite_decimal?(value),
         true <- Decimal.compare(value, Decimal.new(0)) == :gt do
      {:ok,
       %Result{
         rate: value,
         effective_date: effective_date,
         publication_number: String.trim(no),
         fetched_at: fetched_at,
         source: "nbp",
         table: "A",
         base_currency: "EUR",
         quote_currency: "PLN"
       }}
    else
      _ -> {:error, :invalid_rate}
    end
  end

  defp normalize_rate(_, _), do: {:error, :malformed_rate}

  defp decimal_value(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp decimal_value(%Decimal{} = value), do: {:ok, value}
  defp decimal_value(_), do: {:error, :invalid_rate}

  defp finite_decimal?(value), do: not Decimal.nan?(value) and not Decimal.inf?(value)
end
