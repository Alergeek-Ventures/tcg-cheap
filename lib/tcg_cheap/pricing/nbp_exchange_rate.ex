defmodule TcgCheap.Pricing.NbpExchangeRate do
  @moduledoc """
  Client for the National Bank of Poland's API: the latest mid rate of one
  currency to PLN, from the table (A or B) NBP publishes it in.
  """

  @url "https://api.nbp.pl/api/exchangerates/rates/"

  @doc """
  Fetches the latest published rate of `currency` from `table` and returns it
  as the attributes `TcgCheap.Pricing.ExchangeRate`'s `:record` action takes.

  A rate dated after the moment of the request, or one that is not positive, is
  rejected as `:invalid_rate`.
  """
  @spec fetch(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(table, currency) do
    fetched_at = DateTime.utc_now()

    with {:ok, body} <- request(table, currency),
         {:ok, payload} <- decode(body) do
      normalize(payload, table, currency, fetched_at)
    end
  end

  defp request(table, currency) do
    options = [
      url: @url <> String.downcase(table) <> "/" <> String.downcase(currency) <> "/",
      decode_body: false,
      receive_timeout: 10_000,
      retry: :safe_transient,
      max_retries: 2
    ]

    case Req.request(options) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, :malformed_response}
      {:ok, %{status: 404}} -> {:error, :no_published_rate}
      {:ok, %{status: 429}} -> {:error, {:rate_limited, %{status: 429}}}
      {:ok, %{status: status}} -> {:error, {:http_error, %{status: status}}}
      {:error, reason} -> {:error, {:transport_error, reason}}
    end
  rescue
    exception -> {:error, {:transport_error, exception}}
  end

  defp decode(body) do
    case Jason.decode(body, floats: :decimals) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :malformed_json}
    end
  end

  defp normalize(
         %{"table" => table, "code" => currency, "rates" => [rate]},
         table,
         currency,
         fetched_at
       ),
       do: normalize_rate(rate, table, currency, fetched_at)

  defp normalize(_payload, _table, _currency, _fetched_at), do: {:error, :malformed_shape}

  defp normalize_rate(
         %{"mid" => value, "effectiveDate" => date, "no" => no},
         table,
         currency,
         fetched_at
       )
       when is_binary(date) and is_binary(no) do
    with {:ok, rate} <- decimal_value(value),
         publication_number when publication_number != "" <- String.trim(no),
         {:ok, effective_date} <- Date.from_iso8601(date),
         true <- Date.compare(effective_date, DateTime.to_date(fetched_at)) != :gt,
         true <- Decimal.compare(rate, 0) == :gt do
      {:ok,
       %{
         rate: rate,
         effective_date: effective_date,
         publication_number: publication_number,
         fetched_at: fetched_at,
         source: "nbp",
         table: table,
         base_currency: currency,
         quote_currency: "PLN"
       }}
    else
      _ -> {:error, :invalid_rate}
    end
  end

  defp normalize_rate(_rate, _table, _currency, _fetched_at), do: {:error, :malformed_rate}

  defp decimal_value(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp decimal_value(%Decimal{} = value), do: {:ok, value}
  defp decimal_value(_value), do: {:error, :invalid_rate}
end
