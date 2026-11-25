defmodule TcgCheap.Bot.Hosts do
  @moduledoc """
  What the bot remembers about the hosts it reads, in memory: the robots.txt
  rules last fetched from each host (and when to try a refresh again), the time
  before which a host asked not to be asked again (`Retry-After`), the hosts
  that refused an image, and the turns of requests to a host, which every
  reader (shop fetches, REBEL, images) takes so that the host sees them no
  closer together than its pause.

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

  @doc "The system time (ms) before which the rules of `host` are not fetched again, or nil."
  @spec robots_retry_at(String.t()) :: integer() | nil
  def robots_retry_at(host), do: lookup({:robots_retry_at, host})

  @spec put_robots_retry_at(String.t(), integer()) :: :ok
  def put_robots_retry_at(host, at), do: store({:robots_retry_at, host}, at)

  @doc "The reason robots.txt of `host` could not be read and the time (ms) until which that stands, or nil."
  @spec robots_unreadable(String.t()) :: {term(), integer()} | nil
  def robots_unreadable(host), do: lookup({:robots_unreadable, host})

  @spec put_robots_unreadable(String.t(), term(), integer()) :: :ok
  def put_robots_unreadable(host, reason, until),
    do: store({:robots_unreadable, host}, {reason, until})

  @doc "The system time (ms) before which `host` is not to be asked, or nil."
  @spec not_before(String.t()) :: integer() | nil
  def not_before(host), do: lookup({:not_before, host})

  @spec put_not_before(String.t(), integer()) :: :ok
  def put_not_before(host, at), do: store({:not_before, host}, at)

  @doc "The status (or `:challenge`) with which `host` refused an image until the time (ms) given, or nil."
  @spec image_refusal(String.t()) :: {term(), integer()} | nil
  def image_refusal(host), do: lookup({:image_refusal, host})

  @spec put_image_refusal(String.t(), term(), integer()) :: :ok
  def put_image_refusal(host, refusal, until), do: store({:image_refusal, host}, {refusal, until})

  @doc """
  Takes the next turn at `host`: no sooner than `gap_ms` after the turn before
  it, and no sooner than the gap that turn asked for. Answers `{:ok, wait_ms}`,
  the time to wait for it, or `{:wait, wait_ms}` without taking the turn when
  that wait is longer than `max_wait_ms`.
  """
  @spec reserve(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:wait, pos_integer()}
  def reserve(host, gap_ms, max_wait_ms),
    do: GenServer.call(__MODULE__, {:reserve, host, gap_ms, max_wait_ms})

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

  # A host's state is the time of its last turn and the time its next one is
  # free (that turn's own gap after it).
  @impl true
  def handle_call({:reserve, host, gap_ms, max_wait_ms}, _from, turns) do
    now = System.monotonic_time(:millisecond)
    {last, free} = Map.get(turns, host, {now - gap_ms, now})
    turn = Enum.max([now, last + gap_ms, free])

    if turn - now > max_wait_ms,
      do: {:reply, {:wait, turn - now}, turns},
      else: {:reply, {:ok, turn - now}, Map.put(turns, host, {turn, turn + gap_ms})}
  end
end
