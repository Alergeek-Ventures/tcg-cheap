defmodule TcgCheap.Sealed.Cache do
  @moduledoc """
  Reads that every render shares: whole-site lists, banners and names change
  with the shop fetches and catalogue syncs, not with a search or a page.

  An entry lives in `:persistent_term` for 10 minutes. Once it
  expires, its readers get the expired value at once and a task under
  `TcgCheap.Sealed.Cache.Refreshes` reads it again, one at a time under a
  `:global` lock: on a quiet site the first visitor after a pause would
  otherwise wait seconds for every read its page makes. Only an entry not read
  yet (after a start, see `TcgCheap.Sealed.CacheWarmup`) makes its readers wait,
  one of them reading it and the others waiting for its result.
  """

  @cached_for_ms :timer.minutes(10)
  @refreshes __MODULE__.Refreshes

  @doc """
  The value read by `read` for `key`, shared by every caller until it expires.
  """
  @spec fetch(term(), (-> value)) :: value when value: term()
  def fetch(key, read) do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, nil) do
      {expires_at, value} when expires_at > now ->
        value

      nil ->
        :global.trans(refresh_lock(key), fn -> refresh(key, read) end, [node()])

      {_expired_at, stale} ->
        refresh_in_background(key, read)
        stale
    end
  end

  @doc """
  Like `fetch/2`, for a value that a change outside the cache can make
  incomplete before it expires: when `covers?` says the cached value lacks
  something, one reader reads it again and the others keep the value they
  have. It is read again at most once per `refresh_gap_ms`, so lookups that can
  never be covered (an id from a URL that does not exist) do not read it on
  every call: each replaced entry makes the VM scan every process.
  """
  @spec fetch_covering(term(), (-> value), (value -> boolean()), non_neg_integer()) :: value
        when value: term()
  def fetch_covering(key, read, covers?, refresh_gap_ms) do
    value = fetch(key, read)

    if covers?.(value) or read_within?(key, refresh_gap_ms),
      do: value,
      else: reread_or_keep(key, read, refresh_gap_ms, value)
  end

  # Retries 0: a reader that finds the lock taken does not wait.
  defp reread_or_keep(key, read, refresh_gap_ms, value) do
    case :global.trans(
           refresh_lock(key),
           fn -> reread(key, read, refresh_gap_ms) end,
           [node()],
           0
         ) do
      :aborted -> value
      reread -> reread
    end
  end

  # Retries 0: a task that finds the lock taken ends, another one is reading.
  # A read that fails keeps the expired value; the next reader starts another.
  defp refresh_in_background(key, read) do
    {:ok, _pid} =
      Task.Supervisor.start_child(@refreshes, fn ->
        :global.trans(refresh_lock(key), fn -> refresh(key, read) end, [node()], 0)
      end)

    :ok
  end

  defp refresh_lock(key), do: {{__MODULE__, key}, self()}

  # Under the lock: the reader that held it before may have read it already.
  defp refresh(key, read) do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, nil) do
      {expires_at, value} when expires_at > now ->
        value

      _missing_or_expired ->
        value = read.()
        store(key, value, now)
        value
    end
  end

  # Under the lock: the reader that held it before may have read it already.
  defp reread(key, read, refresh_gap_ms) do
    if read_within?(key, refresh_gap_ms) do
      fetch(key, read)
    else
      value = read.()
      store(key, value, System.monotonic_time(:millisecond))
      value
    end
  end

  defp store(key, value, now),
    do: :persistent_term.put({__MODULE__, key}, {now + @cached_for_ms, value})

  # Whether the entry was read less than `ms` milliseconds ago.
  defp read_within?(key, ms) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      {expires_at, _value} ->
        expires_at - System.monotonic_time(:millisecond) > @cached_for_ms - ms

      nil ->
        false
    end
  end
end
