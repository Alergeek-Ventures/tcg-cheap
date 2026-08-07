defmodule TcgCheap.Pricing.Singles.ValuationAcquisition do
  @moduledoc "Enqueues deduplicated background acquisition for an exact printing."

  alias TcgCheap.Pricing.Singles.Freshness
  alias TcgCheap.Pricing.Singles.ValuationWorker

  @policy_version "tcgdex_cardmarket_v1"
  @currency "EUR"
  @default_clock &DateTime.utc_now/0

  @spec enqueue(map() | String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(input), do: with({:ok, card} <- resolve_card(input), do: insert(card))

  @doc "Enqueue only when the current seven-day valuation is missing or stale."
  @spec enqueue_if_stale(map() | String.t(), keyword()) ::
          {:fresh, TcgCheap.Pricing.Singles.SingleValuationSnapshot.t()}
          | {:enqueued, Oban.Job.t()}
          | {:error, term()}
  def enqueue_if_stale(input, opts \\ [])

  def enqueue_if_stale(input, opts) when is_list(opts) do
    with {:ok, card} <- resolve_card(input),
         {:ok, now} <- clock_now(opts),
         {:ok, current} <- TcgCheap.Core.get_current_single_valuation(card.id, @policy_version) do
      enqueue_for_status(card, current, Freshness.status(current, now))
    end
  end

  def enqueue_if_stale(_input, _opts), do: {:error, :invalid_clock}

  @doc "Subscribe before requesting freshness, so callers can reconcile the result."
  def subscribe_and_request(input, opts \\ [])

  def subscribe_and_request(input, opts) when is_list(opts) do
    with {:ok, card} <- resolve_card(input),
         :ok <- subscribe(card) do
      {:ok, card, enqueue_if_stale(card, opts)}
    end
  end

  def subscribe_and_request(_input, _opts), do: {:error, :invalid_input}

  defp resolve_card(%{id: id, tcgdex_id: tcgdex_id}) when is_binary(id) and is_binary(tcgdex_id),
    do: resolve_card_by_tcgdex_id(id, tcgdex_id)

  defp resolve_card(%{"id" => id, "tcgdex_id" => tcgdex_id})
       when is_binary(id) and is_binary(tcgdex_id),
       do: resolve_card_by_tcgdex_id(id, tcgdex_id)

  defp resolve_card(tcgdex_id) when is_binary(tcgdex_id) do
    case TcgCheap.Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, card} -> {:ok, card}
      _ -> {:error, :invalid_local_card}
    end
  end

  defp resolve_card(_input), do: {:error, :invalid_local_card}

  defp resolve_card_by_tcgdex_id(id, tcgdex_id) do
    case TcgCheap.Core.get_card_printing_by_tcgdex_id(tcgdex_id) do
      {:ok, %{id: ^id, tcgdex_id: ^tcgdex_id} = card} -> {:ok, card}
      _ -> {:error, :invalid_local_card}
    end
  end

  defp insert(%{id: id, tcgdex_id: tcgdex_id}) when is_binary(id) and is_binary(tcgdex_id) do
    %{
      "local_card_id" => id,
      "tcgdex_id" => tcgdex_id,
      "policy_version" => @policy_version,
      "currency" => @currency
    }
    |> ValuationWorker.new()
    |> Oban.insert()
  end

  defp insert(_card), do: {:error, :invalid_local_card}

  defp enqueue_for_status(_card, current, :fresh), do: {:fresh, current}

  defp enqueue_for_status(card, _current, status) when status in [:missing, :stale] do
    case insert(card) do
      {:ok, job} -> {:enqueued, job}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clock_now(opts) do
    clock =
      Keyword.get(opts, :clock, Application.get_env(:tcg_cheap, :valuation_clock, @default_clock))

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

  @spec topic(String.t() | map()) :: String.t()
  def topic(%{id: id}), do: topic(id)
  def topic(%{"id" => id}), do: topic(id)
  def topic(id) when is_binary(id), do: "valuations:#{id}"

  @spec subscribe(String.t() | map()) :: :ok | {:error, term()}
  def subscribe(card), do: Phoenix.PubSub.subscribe(TcgCheap.PubSub, topic(card))

  @doc false
  def policy_version, do: @policy_version

  @doc false
  def currency, do: @currency
end
