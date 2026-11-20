defmodule TcgCheap.Bot.Hosts do
  @moduledoc """
  What the bot remembers about the hosts it reads, in memory: the robots.txt
  rules last fetched from each host, the time before which a host asked not
  to be asked again (`Retry-After`), and the turns of requests to a host with
  a `Crawl-delay` that several processes read at once (images).

  A restart forgets all of it: the rules are fetched again and a cooldown is
  left to the job that waits it out (`TcgCheap.Sealed.FetchWorker` snoozes
  until the time the host named).
  """

  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The rules last fetched from `host` and the system time (ms) they were fetched at."
  @spec robots(String.t()) :: {TcgCheap.Bot.Robots.t(), integer()} | nil
  def robots(host), do: lookup({:robots, host})

  @spec put_robots(String.t(), TcgCheap.Bot.Robots.t()) :: :ok
  def put_robots(host, rules), do: store({:robots, host}, {rules, now()})

  @doc "The system time (ms) before which `host` is not to be asked, or nil."
  @spec not_before(String.t()) :: integer() | nil
  def not_before(host), do: lookup({:not_before, host})

  @spec put_not_before(String.t(), integer()) :: :ok
  def put_not_before(host, at), do: store({:not_before, host}, at)

  @doc """
  Takes the next turn at `host`, `gap_ms` after the one before it, and answers
  how long to wait for it.
  """
  @spec reserve(String.t(), non_neg_integer()) :: non_neg_integer()
  def reserve(host, gap_ms), do: GenServer.call(__MODULE__, {:reserve, host, gap_ms})

  @doc false
  def now, do: System.system_time(:millisecond)

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  defp store(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:reserve, host, gap_ms}, _from, turns) do
    now = System.monotonic_time(:millisecond)
    turn = max(now, Map.get(turns, host, now - gap_ms) + gap_ms)
    {:reply, turn - now, Map.put(turns, host, turn)}
  end
end
