defmodule TcgCheapWeb.AdminLoginLimiter do
  @moduledoc """
  A small single-node fixed-window limiter for the administrator sign-in endpoint.

  TCG Cheap targets one VPS. Reserving an attempt before password verification
  keeps concurrent guesses within the configured bound; a successful sign-in
  clears both limiter keys immediately.
  """

  use GenServer

  @type address :: :inet.ip_address()
  @type server :: GenServer.server()
  @max_identity_bytes 320

  def start_link(opts) do
    case Keyword.pop(opts, :name, __MODULE__) do
      {nil, opts} -> GenServer.start_link(__MODULE__, opts)
      {name, opts} -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec reserve(address(), String.t()) :: :ok | {:error, pos_integer()}
  def reserve(address, email) do
    reserve(__MODULE__, address, email)
  end

  @spec reserve(server(), address(), String.t()) :: :ok | {:error, pos_integer()}
  def reserve(server, address, email) do
    GenServer.call(server, {:reserve, address, email})
  end

  @spec clear(address(), String.t()) :: :ok
  def clear(address, email) do
    clear(__MODULE__, address, email)
  end

  @spec clear(server(), address(), String.t()) :: :ok
  def clear(server, address, email) do
    GenServer.call(server, {:clear, address, email})
  end

  @impl true
  def init(opts) do
    limit = Keyword.get(opts, :limit, 5)
    window_ms = Keyword.get(opts, :window_ms, :timer.minutes(5))
    max_entries = Keyword.get(opts, :max_entries, 10_000)
    prune_interval_ms = Keyword.get(opts, :prune_interval_ms, min(window_ms, :timer.minutes(1)))
    schedule_prune(prune_interval_ms)

    {:ok,
     %{
       attempts: %{},
       limit: limit,
       max_entries: max_entries,
       prune_interval_ms: prune_interval_ms,
       window_ms: window_ms
     }}
  end

  @impl true
  def handle_call({:reserve, address, email}, _from, state) do
    now = System.monotonic_time(:millisecond)
    keys = keys_for(address, email)
    attempts = expire_keys(state.attempts, keys, now, state.window_ms)
    blocked = Enum.flat_map(keys, fn key -> blocked_retry_after(attempts, key, now, state) end)

    case blocked do
      [] ->
        reserve_keys(attempts, keys, now, state)

      retry_afters ->
        {:reply, {:error, Enum.max(retry_afters)}, %{state | attempts: attempts}}
    end
  end

  def handle_call({:clear, address, email}, _from, state) do
    attempts = Enum.reduce(keys_for(address, email), state.attempts, &Map.delete(&2, &1))
    {:reply, :ok, %{state | attempts: attempts}}
  end

  @impl true
  def handle_info(:prune, state) do
    now = System.monotonic_time(:millisecond)
    schedule_prune(state.prune_interval_ms)
    {:noreply, %{state | attempts: prune_expired(state.attempts, now, state.window_ms)}}
  end

  defp reserve_keys(attempts, keys, now, state) do
    new_entries = Enum.count(keys, &(not Map.has_key?(attempts, &1)))

    if map_size(attempts) + new_entries <= state.max_entries do
      attempts = Enum.reduce(keys, attempts, &increment(&2, &1, now))
      {:reply, :ok, %{state | attempts: attempts}}
    else
      retry_after = Integer.ceil_div(state.window_ms, 1_000)
      {:reply, {:error, max(retry_after, 1)}, %{state | attempts: attempts}}
    end
  end

  defp expire_keys(attempts, keys, now, window_ms) do
    Enum.reduce(keys, attempts, fn key, attempts ->
      case Map.get(attempts, key) do
        {started_at, _count} when now - started_at >= window_ms -> Map.delete(attempts, key)
        _ -> attempts
      end
    end)
  end

  defp prune_expired(attempts, now, window_ms) do
    Map.reject(attempts, fn {_key, {started_at, _count}} ->
      now - started_at >= window_ms
    end)
  end

  defp keys_for(address, email) do
    [{:address, address} | List.wrap(identity_key(email))]
  end

  defp identity_key(email) when is_binary(email) and byte_size(email) <= @max_identity_bytes do
    normalized = email |> String.trim() |> String.downcase()

    if normalized != "" and byte_size(normalized) <= @max_identity_bytes do
      {:email, normalized}
    end
  end

  defp identity_key(_email), do: nil

  defp blocked_retry_after(attempts, key, now, state) do
    case Map.get(attempts, key) do
      {started_at, count} when count >= state.limit ->
        [retry_after_seconds(started_at, now, state.window_ms)]

      _ ->
        []
    end
  end

  defp increment(attempts, key, now) do
    Map.update(attempts, key, {now, 1}, fn {started_at, count} -> {started_at, count + 1} end)
  end

  defp retry_after_seconds(started_at, now, window_ms) do
    window_ms
    |> Kernel.-(now - started_at)
    |> max(1)
    |> Integer.ceil_div(1_000)
  end

  defp schedule_prune(interval_ms), do: Process.send_after(self(), :prune, interval_ms)
end
