defmodule TcgCheapWeb.PublicAcquisitionLimiter do
  @moduledoc "Single-node fixed-window limiter for public acquisition requests."

  use GenServer

  @type address :: :inet.ip_address()
  @type server :: GenServer.server()
  @default_limit 30
  @default_window_ms :timer.hours(1)

  def start_link(opts) do
    case Keyword.pop(opts, :name, __MODULE__) do
      {nil, opts} -> GenServer.start_link(__MODULE__, opts)
      {name, opts} -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec reserve(address()) :: :ok | {:error, term()}
  def reserve(address), do: reserve(__MODULE__, address)

  @spec reserve(server(), address()) :: :ok | {:error, term()}
  def reserve(server, address), do: GenServer.call(server, {:reserve, address})

  @spec admitter(address()) :: (-> :ok | {:error, term()})
  def admitter(address), do: fn -> reserve(address) end

  @impl true
  def init(opts) do
    limit = positive_integer(Keyword.get(opts, :limit), @default_limit)
    window_ms = positive_integer(Keyword.get(opts, :window_ms), @default_window_ms)
    max_entries = positive_integer(Keyword.get(opts, :max_entries), 10_000)
    prune_interval_ms = positive_integer(Keyword.get(opts, :prune_interval_ms), :timer.minutes(1))
    schedule_prune(prune_interval_ms)

    {:ok,
     %{
       entries: %{},
       limit: limit,
       window_ms: window_ms,
       max_entries: max_entries,
       prune_interval_ms: prune_interval_ms
     }}
  end

  @impl true
  def handle_call({:reserve, address}, _from, state) do
    now = System.monotonic_time(:millisecond)

    if valid_address?(address) do
      entries = expire_address(address, state.entries, now, state.window_ms)

      case Map.get(entries, address) do
        {started_at, count} when count >= state.limit ->
          {:reply,
           {:error,
            {:public_acquisition_rate_limited, retry_after(started_at, now, state.window_ms)}},
           %{state | entries: entries}}

        nil when map_size(entries) >= state.max_entries ->
          reclaim_or_reject(entries, address, now, state)

        nil ->
          {:reply, :ok, %{state | entries: Map.put(entries, address, {now, 1})}}

        {started_at, count} ->
          {:reply, :ok, %{state | entries: Map.put(entries, address, {started_at, count + 1})}}
      end
    else
      {:reply, {:error, :invalid_address}, state}
    end
  end

  @impl true
  def handle_info(:prune, state) do
    now = System.monotonic_time(:millisecond)
    schedule_prune(state.prune_interval_ms)

    entries =
      Map.reject(state.entries, fn {_address, {started_at, _count}} ->
        now - started_at >= state.window_ms
      end)

    {:noreply, %{state | entries: entries}}
  end

  defp valid_address?(address), do: :inet.is_ip_address(address)

  defp expire_address(address, entries, now, window_ms) do
    case Map.get(entries, address) do
      {started_at, _count} when now - started_at >= window_ms -> Map.delete(entries, address)
      _ -> entries
    end
  end

  defp prune_expired(entries, now, window_ms) do
    Map.reject(entries, fn {_address, {started_at, _count}} ->
      now - started_at >= window_ms
    end)
  end

  defp reclaim_or_reject(entries, address, now, state) do
    entries = prune_expired(entries, now, state.window_ms)

    if map_size(entries) < state.max_entries do
      {:reply, :ok, %{state | entries: Map.put(entries, address, {now, 1})}}
    else
      {:reply,
       {:error, {:public_acquisition_rate_limited, Integer.ceil_div(state.window_ms, 1_000)}},
       %{state | entries: entries}}
    end
  end

  defp retry_after(started_at, now, window_ms),
    do: max(Integer.ceil_div(window_ms - (now - started_at), 1_000), 1)

  defp schedule_prune(interval_ms), do: Process.send_after(self(), :prune, interval_ms)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
