defmodule TcgCheap.Pricing.Singles.ValuationPolicyCache do
  @moduledoc "Short-lived, fail-closed cache for the public valuation policy."

  use GenServer

  @default_ttl_seconds 30
  @name __MODULE__
  @tcgdex "tcgdex_cardmarket_v1"
  @bulk "cardmarket_bulk_v1"
  @pubsub TcgCheap.PubSub
  @topic "pricing:singles:valuation-policy"

  def topic, do: @topic

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, topic())
  end

  def start_link(opts \\ []) do
    name =
      if is_list(opts) and Keyword.keyword?(opts),
        do: Keyword.get(opts, :name, @name),
        else: @name

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def selection(server \\ @name) do
    case GenServer.call(server, :selection, 2_000) do
      policy when policy in [@tcgdex, @bulk] -> policy
      _ -> @tcgdex
    end
  catch
    :exit, _ -> @tcgdex
  end

  def invalidate(server \\ @name) do
    case GenServer.call(server, :invalidate, 2_000) do
      :ok -> :ok
      _ -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(opts) do
    with true <- Keyword.keyword?(opts),
         true <- valid_options?(opts),
         loader <- Keyword.get(opts, :loader, TcgCheap.Operations.CardmarketBulkCoverage),
         ttl_seconds <- Keyword.get(opts, :ttl_seconds, @default_ttl_seconds),
         true <- valid_loader?(loader),
         true <-
           is_integer(ttl_seconds) and ttl_seconds > 0 and ttl_seconds <= @default_ttl_seconds do
      {:ok,
       %{
         loader: loader,
         ttl_ms: ttl_seconds * 1_000,
         policy: nil,
         expires_at: nil,
         timer_ref: nil,
         timer_token: nil
       }}
    else
      _ -> {:stop, :invalid_options}
    end
  end

  defp valid_options?(opts) do
    Enum.all?(Keyword.keys(opts), &(&1 in [:name, :loader, :ttl_seconds])) and
      Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts))
  end

  @impl true
  def handle_call(:selection, _from, %{policy: policy, expires_at: expires_at} = state)
      when is_binary(policy) and is_integer(expires_at) do
    if System.monotonic_time(:millisecond) < expires_at do
      {:reply, policy, state}
    else
      state = load_and_cache(state, :on_demand)
      {:reply, state.policy, state}
    end
  end

  def handle_call(:selection, _from, state) do
    state = load_and_cache(state, :on_demand)
    {:reply, state.policy, state}
  end

  def handle_call(:invalidate, _from, state) do
    cleared_state =
      state
      |> cancel_refresh_timer()
      |> Map.merge(%{policy: nil, expires_at: nil})

    Phoenix.PubSub.broadcast(@pubsub, topic(), :valuation_policy_invalidated)
    {:reply, :ok, cleared_state}
  end

  @impl true
  def handle_info({:refresh, timer_token}, %{timer_token: timer_token} = state) do
    state = %{state | timer_ref: nil, timer_token: nil}
    old_policy = state.policy
    state = load_and_cache(state, :scheduled)

    if old_policy != nil and old_policy != state.policy do
      Phoenix.PubSub.broadcast(@pubsub, topic(), :valuation_policy_invalidated)
    end

    {:noreply, state}
  end

  def handle_info({:refresh, _stale_timer_token}, state), do: {:noreply, state}

  defp load_and_cache(state, :on_demand) do
    state = load_and_cache(state, :scheduled)
    Phoenix.PubSub.broadcast(@pubsub, topic(), :valuation_policy_invalidated)
    state
  end

  defp load_and_cache(%{loader: loader, ttl_ms: ttl_ms} = state, :scheduled) do
    state = cancel_refresh_timer(state)
    policy = safe_policy(loader)
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    schedule_refresh(%{state | policy: policy, expires_at: expires_at})
  end

  defp schedule_refresh(%{ttl_ms: ttl_ms} = state) do
    timer_token = make_ref()
    timer_ref = Process.send_after(self(), {:refresh, timer_token}, ttl_ms)
    %{state | timer_ref: timer_ref, timer_token: timer_token}
  end

  defp cancel_refresh_timer(%{timer_ref: nil} = state), do: state

  defp cancel_refresh_timer(%{timer_ref: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | timer_ref: nil, timer_token: nil}
  end

  defp safe_policy(loader) do
    result = loader.load_system()

    case result do
      {:ok, %{cutover: %{ready?: ready?}}} when is_boolean(ready?) ->
        if ready?, do: @bulk, else: @tcgdex

      _ ->
        @tcgdex
    end
  rescue
    _ -> @tcgdex
  catch
    _, _ -> @tcgdex
  end

  defp valid_loader?(loader) when is_atom(loader),
    do: Code.ensure_loaded?(loader) and function_exported?(loader, :load_system, 0)

  defp valid_loader?(_), do: false
end
