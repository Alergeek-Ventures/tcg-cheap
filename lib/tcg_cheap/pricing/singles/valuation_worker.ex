defmodule TcgCheap.Pricing.Singles.ValuationWorker do
  @moduledoc "Oban worker that acquires and persists one TCGdex aggregate valuation."

  use Oban.Worker,
    queue: :valuations,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:local_card_id, :tcgdex_id, :policy_version],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.ValuationAcquisition

  @policy_version "tcgdex_cardmarket_v1"
  @currency "EUR"
  @source "tcgdex_cardmarket"
  @transient_tags [:rate_limited, :http_error, :transport_error, :timeout]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) when is_map(args) do
    with {:ok, identity} <- validate_args(args),
         {:ok, card} <- load_card(identity) do
      acquire(job, card)
    else
      {:cancel, reason} -> {:cancel, reason}
    end
  end

  def perform(_job), do: {:cancel, :malformed_job_args}

  defp acquire(job, card) do
    case call_provider(card.tcgdex_id) do
      {:ok, result} ->
        case validate_result(result, %{tcgdex_id: card.tcgdex_id}, card) do
          {:ok, attrs} -> persist_and_finish(job, card, attrs)
          {:error, _reason} -> cancel_with_event(card, :malformed_provider_result)
        end

      {:cancel, reason} ->
        cancel_with_event(card, reason)

      {:retry, reason} ->
        retry_with_event(job, card, reason)
    end
  end

  defp persist_and_finish(job, card, attrs) do
    case persist(attrs) do
      {:ok, snapshot} ->
        broadcast(card.id, snapshot)
        :ok

      {:cancel, reason} ->
        cancel_with_event(card, reason)

      {:retry, reason} ->
        retry_with_event(job, card, reason)
    end
  end

  defp cancel_with_event(card, reason) do
    broadcast_failure(card.id, reason)
    {:cancel, reason}
  end

  defp retry_with_event(%Oban.Job{attempt: attempt, max_attempts: max_attempts}, card, reason)
       when attempt >= max_attempts do
    broadcast_failure(card.id, reason)
    {:error, reason}
  end

  defp retry_with_event(_job, _card, reason), do: {:error, reason}

  defp validate_args(%{
         "local_card_id" => local_card_id,
         "tcgdex_id" => tcgdex_id,
         "policy_version" => @policy_version,
         "currency" => @currency
       })
       when is_binary(local_card_id) and is_binary(tcgdex_id),
       do: {:ok, %{local_card_id: local_card_id, tcgdex_id: tcgdex_id}}

  defp validate_args(_args), do: {:cancel, :malformed_job_args}

  defp load_card(%{local_card_id: id, tcgdex_id: tcgdex_id}) do
    case Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, %{id: ^id, tcgdex_id: ^tcgdex_id} = card} -> {:ok, card}
      {:ok, _card} -> {:cancel, :invalid_local_card}
      {:error, _error} -> {:cancel, :invalid_local_card}
    end
  end

  defp call_provider(tcgdex_id) do
    case provider_config() do
      {:ok, adapter, options} ->
        case safely_fetch(adapter, tcgdex_id, options) do
          {:ok, response} -> classify_response(response)
          {:error, :provider_callback_failed} -> {:retry, :provider_callback_failed}
        end

      {:error, _reason} ->
        {:cancel, :invalid_provider_configuration}
    end
  end

  defp provider_config do
    config = Application.get_env(:tcg_cheap, :valuation_provider, [])

    with true <- is_list(config) and Keyword.keyword?(config),
         config_keys = Keyword.keys(config),
         true <- Enum.sort(config_keys) == [:adapter, :options],
         true <- length(config_keys) == length(Enum.uniq(config_keys)),
         adapter when is_atom(adapter) <- Keyword.get(config, :adapter),
         true <- Code.ensure_loaded?(adapter),
         true <- function_exported?(adapter, :fetch, 2),
         options when is_list(options) <- Keyword.get(config, :options, []),
         true <- Keyword.keyword?(options),
         option_keys = Keyword.keys(options),
         true <- length(option_keys) == length(Enum.uniq(option_keys)) do
      {:ok, adapter, options}
    else
      _ -> {:error, :invalid_provider_configuration}
    end
  end

  defp safely_fetch(adapter, card_id, options) do
    {:ok, adapter.fetch(card_id, options)}
  rescue
    _exception -> {:error, :provider_callback_failed}
  catch
    :throw, _reason -> {:error, :provider_callback_failed}
    :exit, _reason -> {:error, :provider_callback_failed}
  end

  defp classify_response({:ok, result}), do: {:ok, result}

  defp classify_response({:error, reason}) when reason in @transient_tags,
    do: transient_reason(reason, nil)

  defp classify_response({:error, {tag, details}}) when tag in @transient_tags,
    do: transient_reason(tag, details)

  defp classify_response({:error, :not_found}), do: {:cancel, :provider_not_found}
  defp classify_response({:error, {:not_found, _}}), do: {:cancel, :provider_not_found}
  defp classify_response({:error, :unavailable_pricing}), do: {:cancel, :pricing_unavailable}
  defp classify_response({:error, :unsupported_currency}), do: {:cancel, :unsupported_currency}

  defp classify_response({:error, {:unsupported_currency, _}}),
    do: {:cancel, :unsupported_currency}

  defp classify_response({:error, :malformed_response}),
    do: {:cancel, :malformed_provider_response}

  defp classify_response({:error, {:malformed_response, _}}),
    do: {:cancel, :malformed_provider_response}

  defp classify_response({:error, :decode_error}), do: {:cancel, :malformed_provider_response}

  defp classify_response({:error, {:decode_error, _}}),
    do: {:cancel, :malformed_provider_response}

  defp classify_response({:error, :invalid_card_id}), do: {:cancel, :invalid_provider_request}
  defp classify_response({:error, :invalid_options}), do: {:cancel, :invalid_provider_request}
  defp classify_response({:error, _reason}), do: {:cancel, :malformed_provider_result}

  defp classify_response(_response), do: {:cancel, :malformed_provider_result}

  defp validate_result(result, %{tcgdex_id: tcgdex_id}, card) do
    with true <- is_map(result),
         ^tcgdex_id <- Map.get(result, :card_id),
         @policy_version <- normalize_policy(Map.get(result, :policy_version)),
         @currency <- normalize_currency(Map.get(result, :currency)),
         @source <- normalize_string(Map.get(result, :source)),
         source_metric when is_atom(source_metric) <- Map.get(result, :source_metric),
         true <- source_metric in [:avg7, :avg30, :trend, :avg, :low],
         %Decimal{} = value <- Map.get(result, :value_eur),
         true <- positive_decimal?(value),
         %DateTime{} = fetched_at <- Map.get(result, :fetched_at),
         true <-
           is_nil(Map.get(result, :provider_updated_at)) or
             match?(%DateTime{}, Map.get(result, :provider_updated_at)),
         product_id <- Map.get(result, :cardmarket_product_id),
         true <- is_nil(product_id) or (is_integer(product_id) and product_id > 0) do
      {:ok,
       %{
         card_printing_id: card.id,
         value_eur: value,
         currency: @currency,
         policy_version: @policy_version,
         source: @source,
         source_metric: Atom.to_string(source_metric),
         fetched_at: fetched_at,
         provider_updated_at: Map.get(result, :provider_updated_at),
         cardmarket_product_id: product_id
       }}
    else
      _ -> {:error, :malformed_provider_result}
    end
  end

  defp normalize_currency(:eur), do: "EUR"
  defp normalize_currency("EUR"), do: "EUR"
  defp normalize_currency(_), do: nil

  defp normalize_policy(:tcgdex_cardmarket_v1), do: @policy_version
  defp normalize_policy(@policy_version), do: @policy_version
  defp normalize_policy(_), do: nil

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(_), do: nil

  defp positive_decimal?(%Decimal{sign: 1, coef: coef}) when is_integer(coef) and coef > 0,
    do: true

  defp positive_decimal?(_), do: false

  defp persist(attrs) do
    case Core.record_single_valuation(attrs) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, %Ash.Error.Invalid{}} -> {:cancel, :persistence_invalid}
      {:error, _error} -> {:retry, :persistence_failed}
    end
  end

  defp transient_reason(:rate_limited, details),
    do: {:retry, {:provider_rate_limited, status(details)}}

  defp transient_reason(:http_error, details), do: classify_http(status(details))
  defp transient_reason(:transport_error, _details), do: {:retry, :provider_transport_error}
  defp transient_reason(:timeout, _details), do: {:retry, :provider_timeout}

  defp classify_http(status) when status in [408, 429],
    do: {:retry, {:provider_http_error, status}}

  defp classify_http(status) when is_integer(status) and status >= 500 and status <= 599,
    do: {:retry, {:provider_http_error, status}}

  defp classify_http(nil), do: {:retry, {:provider_http_error, nil}}

  defp classify_http(status), do: {:cancel, {:provider_http_error, status}}

  defp status(%{status: status}) when is_integer(status), do: status
  defp status(_details), do: nil

  defp broadcast(card_id, snapshot) do
    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      ValuationAcquisition.topic(card_id),
      {:valuation_completed, %{card_printing_id: card_id, snapshot: snapshot}}
    )
  end

  defp broadcast_failure(card_id, reason) do
    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      ValuationAcquisition.topic(card_id),
      {:valuation_failed, %{card_printing_id: card_id, reason: reason}}
    )
  end
end
