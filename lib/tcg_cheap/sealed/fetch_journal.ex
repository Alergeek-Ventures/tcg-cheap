defmodule TcgCheap.Sealed.FetchJournal do
  @moduledoc """
  Keeps the progress of one shop fetch across restarts and across the short
  steps `TcgCheap.Sealed.FetchWorker` runs it in.

  A fetch is a fixed sequence of requests: every `TcgCheap.Sealed.ShopFeed.get/5`
  of a fetch passes `through/4`, which stores each response it reads
  (`TcgCheap.Sealed.FetchResponse`) and answers a request an earlier step of the
  same job already read from the store, without asking the shop or pausing
  again. A step that has been reading for its time budget stops before the next
  request it has to make (`catch_pause/1`); the job runs again at once and
  replays what is stored. A restart therefore costs the request that was in
  flight, and the shop sees the same pace as in one long run.

  A request that is only an extra (`optional: true`) keeps its failure as well:
  the fetch goes on without it, so a later step must not ask for it again, and
  a shop that answers errors slowly cannot hold the fetch back.

  Nothing but the requests is kept: the fetch is parsed, and its offers
  stored, only by the step that reads the last response, so a fetch that has
  not read the whole shop changes nothing.

  A request is named by its place in the fetch (a fetch asks for the same
  page more than once) and its path and query, so a response is replayed only
  to the request that read it, even if a deploy changed what the fetch asks
  for.
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.FetchResponse

  @budget_ms :timer.minutes(2)
  # A stored response older than this is read again: a job that waits long
  # (a rate-limited shop is asked again after minutes) must not mix hours-old
  # prices into a fresh read.
  @max_age_hours 3
  @paused {__MODULE__, :paused}
  @max_query_bytes 512

  @enforce_keys [:run_id, :shop, :deadline, :counters, :responses]
  defstruct [:run_id, :shop, :deadline, :counters, :responses]

  @typedoc "What one step of a fetch knows: the stored responses and its time budget."
  @type t :: %__MODULE__{
          run_id: integer(),
          shop: String.t(),
          deadline: integer(),
          counters: :counters.counters_ref(),
          responses: %{String.t() => binary()}
        }

  @doc """
  Opens the journal of fetch job `run_id` for one step: forgets the responses
  of the shop's other runs and the stale ones, and loads those the job has
  stored. The step reads for `:budget_ms` (default 2 minutes) before it pauses.
  """
  @spec open(integer(), String.t(), keyword()) :: t()
  def open(run_id, shop, opts \\ []) when is_integer(run_id) and is_binary(shop) do
    now = DateTime.utc_now()

    FetchResponse
    |> Ash.Query.for_read(:left_over, %{
      shop: shop,
      run_id: run_id,
      before: DateTime.add(now, -@max_age_hours, :hour)
    })
    |> discard()

    %__MODULE__{
      run_id: run_id,
      shop: shop,
      deadline: System.monotonic_time(:millisecond) + Keyword.get(opts, :budget_ms, @budget_ms),
      # 1: requests asked so far, 2: requests that went to the shop.
      counters: :counters.new(2, []),
      responses: Map.new(Sealed.list_fetch_responses!(run_id), &{&1.request, &1.body})
    }
  end

  @doc "Forgets everything the job stored; the fetch is over."
  @spec close(t()) :: :ok
  def close(%__MODULE__{run_id: run_id}) do
    FetchResponse
    |> Ash.Query.for_read(:for_run, %{run_id: run_id})
    |> discard()
  end

  @doc """
  Answers the request for `path` and `params` from the journal when its
  response is stored. Otherwise calls `live`, which asks the shop (after its
  pause) and returns `{:ok, response}` or an error, and stores a successful
  response. Without a journal (`nil`) it is just `live`. With `optional: true`
  a failure is stored too and answered as `{:error, :failed_earlier}` to the
  replays of the request.

  Throws to `catch_pause/1` instead of calling `live` once the step has used
  its time budget, but not before the step has made one request of its own, so
  every step moves the fetch on.
  """
  @spec through(
          t() | nil,
          String.t(),
          keyword(),
          (-> {:ok, Req.Response.t()} | {:error, term()}),
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def through(journal, path, params, live, opts \\ [])

  def through(nil, _path, _params, live, _opts), do: ask(live)

  def through(%__MODULE__{} = journal, path, params, live, opts) do
    :counters.add(journal.counters, 1, 1)
    request = "#{:counters.get(journal.counters, 1)} #{request_name(path, params)}"

    case journal.responses do
      %{^request => stored} ->
        decode(stored)

      _unread ->
        pause_when_over_budget(journal)

        live |> ask() |> remember(journal, request, Keyword.get(opts, :optional, false))
    end
  end

  # The name is part of the table's primary key, which Postgres limits to
  # about 2.7 kB per row: a long query (a Storefront request names 250
  # variants) is named by its sha256 instead, so the name stays short and
  # still tells two different requests apart.
  defp request_name(path, params) do
    query = URI.encode_query(params)

    if byte_size(query) <= @max_query_bytes do
      "#{path}?#{query}"
    else
      "#{path}?sha256:" <> Base.encode16(:crypto.hash(:sha256, query), case: :lower)
    end
  end

  defp remember({:ok, response} = read, journal, request, _optional) do
    store(journal, request, {response.headers, response.body})
    read
  end

  defp remember({:error, _reason} = error, journal, request, optional) do
    if optional, do: store(journal, request, :failed)
    error
  end

  # Names what `live` may answer, so callers keep knowing they get a response.
  defp ask(live) do
    case live.() do
      {:ok, %Req.Response{}} = read -> read
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Runs `fun`, a whole fetch, and answers `:paused` when a step stopped it
  at a request it has still to make; any result of `fun` is returned as it is.
  """
  @spec catch_pause((-> result)) :: result | :paused when result: term()
  def catch_pause(fun) do
    fun.()
  catch
    :throw, @paused -> :paused
  end

  # Non-local on purpose: the feed clients are written as one pass over a
  # shop, and an error return would make them store what they had read as
  # the whole shop (singles read apart, for one, answer `{:partial, ...}`).
  defp pause_when_over_budget(journal) do
    if :counters.get(journal.counters, 2) > 0 and
         System.monotonic_time(:millisecond) >= journal.deadline,
       do: throw(@paused)

    :counters.add(journal.counters, 2, 1)
  end

  defp store(journal, request, entry) do
    Sealed.record_fetch_response!(%{
      run_id: journal.run_id,
      shop: journal.shop,
      request: request,
      body: :erlang.term_to_binary(entry, [:compressed])
    })
  end

  defp decode(stored) do
    case :erlang.binary_to_term(stored, [:safe]) do
      :failed -> {:error, :failed_earlier}
      {headers, body} -> {:ok, %Req.Response{status: 200, headers: headers, body: body}}
    end
  end

  defp discard(query) do
    %Ash.BulkResult{status: :success} =
      Ash.bulk_destroy!(query, :discard, %{}, domain: Sealed, return_errors?: true)

    :ok
  end
end
