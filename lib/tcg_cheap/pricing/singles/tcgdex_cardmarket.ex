defmodule TcgCheap.Pricing.Singles.TcgdexCardmarket do
  @moduledoc """
  Aggregate Cardmarket pricing from TCGdex.

  This adapter does not represent seller-level offers. Calls belong in background
  acquisition jobs, not in normal page rendering.
  """

  @endpoint "https://api.tcgdex.net/v2/en/cards/:card_id"
  @policy_version :tcgdex_cardmarket_v1
  @source :tcgdex_cardmarket
  @metrics [:avg7, :avg30, :trend, :avg, :low]

  defmodule Result do
    @moduledoc "Aggregate TCGdex Cardmarket pricing result."

    @enforce_keys [
      :card_id,
      :value_eur,
      :currency,
      :policy_version,
      :source,
      :source_metric,
      :fetched_at
    ]
    defstruct [
      :card_id,
      :value_eur,
      :currency,
      :policy_version,
      :source,
      :source_metric,
      :fetched_at,
      :provider_updated_at,
      :cardmarket_product_id
    ]

    @type t :: %__MODULE__{
            card_id: String.t(),
            value_eur: Decimal.t(),
            currency: :eur,
            policy_version: :tcgdex_cardmarket_v1,
            source: :tcgdex_cardmarket,
            source_metric: :avg7 | :avg30 | :trend | :avg | :low,
            fetched_at: DateTime.t(),
            provider_updated_at: DateTime.t() | nil,
            cardmarket_product_id: pos_integer() | nil
          }
  end

  @type result :: Result.t()
  @type error ::
          :invalid_card_id
          | {:not_found, map()}
          | {:rate_limited, map()}
          | {:http_error, map()}
          | {:transport_error, term()}
          | {:decode_error, term()}
          | {:malformed_response, term()}
          | {:unsupported_currency, term()}
          | :unavailable_pricing
          | :invalid_options

  @spec fetch(term(), term()) :: {:ok, result()} | {:error, error()}
  def fetch(card_id, opts \\ [])

  def fetch(card_id, opts) when is_binary(card_id) and is_list(opts) do
    if valid_options?(opts) do
      fetch_card(card_id, opts)
    else
      {:error, :invalid_options}
    end
  end

  def fetch(card_id, _opts) when is_binary(card_id), do: {:error, :invalid_options}

  def fetch(_card_id, _opts), do: {:error, :invalid_card_id}

  defp fetch_card(card_id, opts) do
    requested_id = String.trim(card_id)

    if requested_id == "" do
      {:error, :invalid_card_id}
    else
      request(requested_id, opts)
    end
  end

  defp request(card_id, opts) do
    budgeted? = Keyword.has_key?(opts, :request_admitter)

    defaults = [
      decode_body: false,
      receive_timeout: 10_000,
      retry: if(budgeted?, do: false, else: :safe_transient),
      max_retries: if(budgeted?, do: 0, else: 2)
    ]

    request_options = Keyword.get(opts, :request_options, [])

    with :ok <- validate_request_options(request_options),
         :ok <- validate_clock(opts),
         :ok <- admit_request(opts) do
      options =
        defaults
        |> Keyword.merge(request_options)
        |> force_single_attempt(budgeted?)
        |> Keyword.put(:path_params, card_id: card_id)

      case Req.get(@endpoint, options) do
        {:ok, %{status: 200, body: body}} -> parse_body(body, card_id, opts)
        {:ok, %{status: 404}} -> {:error, {:not_found, %{status: 404, card_id: card_id}}}
        {:ok, %{status: 429}} -> {:error, {:rate_limited, %{status: 429, card_id: card_id}}}
        {:ok, %{status: status}} -> {:error, {:http_error, %{status: status, card_id: card_id}}}
        {:error, reason} -> classify_request_error(reason)
      end
    else
      {:error, :invalid_options} -> {:error, :invalid_options}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_body(body, card_id, opts) when is_binary(body) do
    case decode_json(body) do
      {:ok, decoded} -> parse_body(decoded, card_id, opts)
      {:error, %Jason.DecodeError{} = reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp parse_body(body, card_id, opts) when is_map(body) do
    case Map.get(body, "id") do
      ^card_id -> parse_pricing(body, card_id, opts)
      actual -> {:error, {:malformed_response, {:card_id_mismatch, card_id, actual}}}
    end
  end

  defp parse_body(_body, _card_id, _opts), do: {:error, {:malformed_response, :expected_object}}

  defp parse_pricing(%{"pricing" => pricing}, card_id, opts) when is_map(pricing) do
    case Map.get(pricing, "cardmarket") do
      nil -> {:error, :unavailable_pricing}
      cardmarket when is_map(cardmarket) -> parse_cardmarket(cardmarket, card_id, opts)
      _cardmarket -> {:error, {:malformed_response, :invalid_cardmarket}}
    end
  end

  defp parse_pricing(%{"pricing" => _}, _card_id, _opts),
    do: {:error, {:malformed_response, :invalid_pricing}}

  defp parse_pricing(_body, _card_id, _opts), do: {:error, :unavailable_pricing}

  defp parse_cardmarket(cardmarket, card_id, opts) do
    with :ok <- validate_currency(cardmarket),
         {:ok, metric, value} <- select_value(cardmarket) do
      with {:ok, fetched_at} <- clock_datetime(opts) do
        {:ok,
         %Result{
           card_id: card_id,
           value_eur: value,
           currency: :eur,
           policy_version: @policy_version,
           source: @source,
           source_metric: metric,
           fetched_at: fetched_at,
           provider_updated_at: parse_updated(Map.get(cardmarket, "updated")),
           cardmarket_product_id: positive_integer(Map.get(cardmarket, "idProduct"))
         }}
      end
    else
      {:unsupported_currency, unit} -> {:error, {:unsupported_currency, unit}}
      :unavailable_pricing -> {:error, :unavailable_pricing}
    end
  end

  defp validate_currency(%{"unit" => "EUR"}), do: :ok
  defp validate_currency(%{"unit" => unit}), do: {:unsupported_currency, unit}
  defp validate_currency(_), do: {:unsupported_currency, nil}

  defp select_value(cardmarket) do
    Enum.reduce_while(@metrics, :unavailable_pricing, fn metric, _acc ->
      case decimal_value(Map.get(cardmarket, Atom.to_string(metric))) do
        {:ok, value} -> {:halt, {:ok, metric, value}}
        :skip -> {:cont, :unavailable_pricing}
      end
    end)
  end

  defp decimal_value(value) when is_integer(value) do
    decimal_value(Decimal.new(value))
  end

  defp decimal_value(%Decimal{} = value) do
    if finite_positive?(value) do
      try do
        {:ok, Decimal.round(value, 2, :half_up)}
      rescue
        exception in [ArgumentError, ArithmeticError, Decimal.Error] ->
          _ = exception
          :skip
      end
    else
      :skip
    end
  end

  defp decimal_value(_value), do: :skip

  defp finite_positive?(%Decimal{sign: 1, coef: coef, exp: exp})
       when is_integer(coef) and coef > 0 and is_integer(exp),
       do: true

  defp finite_positive?(_value), do: false

  defp parse_updated(updated) when is_binary(updated) do
    case DateTime.from_iso8601(updated) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_updated(_updated), do: nil

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp decode_json(body), do: Jason.decode(body, floats: :decimals)

  defp valid_options?(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)

      length(keys) == length(Enum.uniq(keys)) and
        Enum.all?(keys, &(&1 in [:request_options, :clock, :request_admitter])) and
        is_function(Keyword.get(opts, :request_admitter, fn -> :ok end), 0)
    else
      false
    end
  end

  defp force_single_attempt(options, true),
    do: options |> Keyword.put(:retry, false) |> Keyword.put(:max_retries, 0)

  defp force_single_attempt(options, false), do: options

  defp admit_request(opts) do
    case Keyword.get(opts, :request_admitter, fn -> :ok end).() do
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

  defp validate_request_options(request_options) when is_list(request_options) do
    if Keyword.keyword?(request_options) do
      allowed = [:plug, :retry, :max_retries]
      keys = Keyword.keys(request_options)

      if Enum.all?(keys, &(&1 in allowed)) and
           length(keys) == length(Enum.uniq(keys)) and
           valid_retry_option?(request_options) and
           valid_max_retries?(request_options) do
        :ok
      else
        {:error, :invalid_options}
      end
    else
      {:error, :invalid_options}
    end
  end

  defp validate_request_options(_request_options), do: {:error, :invalid_options}

  defp valid_retry_option?(options) do
    case Keyword.get(options, :retry, :safe_transient) do
      false -> true
      :safe_transient -> true
      _other -> false
    end
  end

  defp valid_max_retries?(options) do
    case Keyword.get(options, :max_retries, 2) do
      retries when is_integer(retries) and retries in 0..2 -> true
      _other -> false
    end
  end

  defp validate_clock(opts) do
    case Keyword.get(opts, :clock, &DateTime.utc_now/0) do
      clock when is_function(clock, 0) -> :ok
      _clock -> {:error, :invalid_options}
    end
  end

  defp clock_datetime(opts) do
    clock = Keyword.get(opts, :clock, &DateTime.utc_now/0)

    try do
      case clock.() do
        %DateTime{} = datetime -> {:ok, datetime}
        _other -> {:error, :invalid_options}
      end
    rescue
      _exception -> {:error, :invalid_options}
    end
  end

  defp classify_request_error(reason), do: {:error, {:transport_error, reason}}
end
