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
    with true <- valid_options?(opts),
         {:ok, card} <- resolve_card(input),
         {:ok, now} <- clock_now(opts),
         {:ok, current} <- TcgCheap.Core.get_current_single_valuation(card.id, @policy_version) do
      enqueue_for_status(card, current, Freshness.status(current, now), opts)
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def enqueue_if_stale(_input, _opts), do: {:error, :invalid_options}

  @doc "Subscribe before requesting freshness, so callers can reconcile the result."
  def subscribe_and_request(input, opts \\ [])

  def subscribe_and_request(input, opts) when is_list(opts) do
    with true <- valid_options?(opts),
         {:ok, card} <- resolve_card(input),
         :ok <- subscribe(card) do
      {:ok, card, enqueue_if_stale(card, opts)}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def subscribe_and_request(_input, _opts), do: {:error, :invalid_options}

  @doc "Subscribes to and requests freshness for up to 100 canonical cards in one read."
  @spec subscribe_and_request_many([map()], keyword()) ::
          {:ok, %{String.t() => {:fresh, map()} | {:enqueued, Oban.Job.t()} | {:error, term()}}}
          | {:error, term()}
  def subscribe_and_request_many(inputs, opts \\ [])

  def subscribe_and_request_many(inputs, opts) when is_list(inputs) and is_list(opts) do
    with true <- valid_options?(opts),
         {:ok, requested} <- extract_many_ids(inputs),
         {:ok, cards} <- read_many(requested),
         :ok <- validate_many(inputs, requested, cards),
         {:ok, now} <- clock_now(opts),
         :ok <- subscribe_many(cards) do
      {:ok, build_many_results(requested, cards, now, opts)}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def subscribe_and_request_many(_inputs, opts) when not is_list(opts),
    do: {:error, :invalid_options}

  def subscribe_and_request_many(_inputs, _opts), do: {:error, :invalid_input}

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

  defp extract_many_ids(inputs) when length(inputs) <= 100 do
    ids = Enum.map(inputs, &extract_many_id/1)

    if Enum.any?(ids, &(&1 == :invalid_local_card)),
      do: {:error, :invalid_local_card},
      else: {:ok, Enum.uniq(ids)}
  end

  defp extract_many_ids(_inputs), do: {:error, :too_many_cards}

  defp extract_many_id(input) when is_map(input) do
    id = Map.get(input, "tcgdex_id") || Map.get(input, :tcgdex_id)
    local_id = Map.get(input, "id") || Map.get(input, :id)

    if is_binary(id) and id != "" and is_binary(local_id) and local_id != "",
      do: id,
      else: :invalid_local_card
  end

  defp extract_many_id(_), do: :invalid_local_card

  defp read_many([]), do: {:ok, []}

  defp read_many(ids) do
    case TcgCheap.Core.list_card_printings_by_tcgdex_ids(ids) do
      {:ok, cards} when is_list(cards) -> {:ok, cards}
      _ -> {:error, :invalid_local_card}
    end
  end

  defp validate_many(inputs, ids, cards) do
    by_id = Map.new(cards, &{&1.tcgdex_id, &1})

    valid? =
      MapSet.size(MapSet.new(Map.keys(by_id))) == length(ids) and
        Enum.all?(ids, &Map.has_key?(by_id, &1)) and
        Enum.all?(inputs, &matches_canonical?(&1, by_id))

    if valid? do
      :ok
    else
      {:error, :invalid_local_card}
    end
  end

  defp matches_canonical?(input, by_id) do
    tcgdex_id = Map.get(input, "tcgdex_id", Map.get(input, :tcgdex_id))
    local_id = Map.get(input, "id", Map.get(input, :id))
    local_id == Map.get(by_id, tcgdex_id).id
  end

  defp subscribe_many(cards) do
    Enum.reduce_while(cards, :ok, fn card, :ok ->
      case subscribe(card) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_many_results(requested, cards, now, opts) do
    cards_by_id = Map.new(cards, &{&1.tcgdex_id, &1})

    Map.new(requested, fn id ->
      card = Map.fetch!(cards_by_id, id)
      current = Map.get(card, :tcgdex_cardmarket_v1_current_valuation)
      {id, enqueue_for_status(card, current, Freshness.status(current, now), opts)}
    end)
  end

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

  defp enqueue_for_status(_card, current, :fresh, _opts), do: {:fresh, current}

  defp enqueue_for_status(card, _current, status, opts) when status in [:missing, :stale] do
    case admit(opts) do
      :ok -> insert_result(card)
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_result(card) do
    case insert(card) do
      {:ok, job} -> {:enqueued, job}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_options?(opts) do
    Keyword.keyword?(opts) and length(opts) == length(Enum.uniq(Keyword.keys(opts))) and
      Enum.all?(Keyword.keys(opts), &(&1 in [:clock, :request_admitter])) and
      valid_function_option?(opts, :request_admitter, 0)
  end

  defp valid_function_option?(opts, key, arity) do
    case Keyword.fetch(opts, key) do
      :error -> true
      {:ok, value} -> is_function(value, arity)
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
