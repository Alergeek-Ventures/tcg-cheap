defmodule TcgCheap.Bot do
  @moduledoc """
  The one identity and access policy of every request the bot ("TcgCheap")
  makes to a shop, to REBEL and for remote product and card images.

  - Identity: `new/1` builds the request with the bot's User-Agent and signs
    it with Web Bot Auth (`TcgCheap.WebBotAuth`). Nothing else sets that
    User-Agent. The requests of other tools (NBP rates, Cardmarket files,
    TCGdex) are no crawling and do not carry it.
  - robots.txt: `permit/4` fetches `https://<host>/robots.txt` (signed, same
    identity; up to five redirects are followed, at most 512 KiB are read,
    one request at a time per host) before the host is read and decides
    whether a path may be requested (`TcgCheap.Bot.Robots`). Rules fetched are
    used for an hour without asking again. The status of robots.txt itself
    follows RFC 9309: a 2xx is parsed; any 4xx but 429 (404, 410, and 401 or
    403 too) means there are no rules and everything is allowed; 429, 5xx, a
    timeout and network failures mean it cannot be read, and then the rules
    fetched before are used for up to 24 hours after they were fetched (a
    refresh is tried again after the `Retry-After`, or an hour), and without
    them the host is not read. A challenge response in place of robots.txt
    (`cf-mitigated: challenge`, a Cloudflare challenge page) is a refusal:
    nothing is read.
  - Pace: every request to a host takes a turn (`TcgCheap.Bot.Hosts`), the
    larger of the reader's own pause and the host's `Crawl-delay` after the
    one before, whichever reader made it. A turn up to five minutes away is
    waited for in place; a later one ends the step with
    `{:robots_crawl_delay, seconds}` (`wait_seconds/1`), so that a worker can
    do it later instead of holding its queue slot.
  - Refusals and waits: a 401, a 403 or a challenge response to a request
    itself is never retried, and nothing is asked of the host again through
    another way. A `Retry-After` on 429 or 503 is honoured: a short one is
    waited out in the request (`retry_step/1`), a longer one is remembered
    (`TcgCheap.Bot.Hosts`) so that the host is not asked before it has passed
    (`classify/2`, `permit/4`), and the worker snoozes until then
    (`snooze_before/3`).

  A policy decision that ends the reading of a host is a reason such as
  `{:robots_disallowed, path}`; `stop/1` throws it to `catch_stop/1`, so that
  a client written as one pass over a shop (and its optional requests) ends at
  once.
  """

  require Logger

  alias TcgCheap.Bot.{Hosts, Robots}
  alias TcgCheap.WebBotAuth

  @user_agent "TcgCheap/1.0 (buying guide)"
  @token "TcgCheap"
  # Rules fetched less than an hour ago are not fetched again; a robots.txt
  # that cannot be read is replaced by older rules for up to a day.
  @fresh_ms :timer.hours(1)
  @valid_ms :timer.hours(24)
  @rate_limit_delay_ms 10_000
  @default_max_retry_after_ms 10_000
  # What a request waits for its turn in place: within a job's timeout, and
  # not longer than a queue slot should be held.
  @max_wait_ms :timer.minutes(5)
  @challenge_page ~r/<title>\s*(?:Just a moment|Attention Required|Checking your browser)|cf-chl-|challenge-platform|\/cdn-cgi\/challenge/i
  @stop {__MODULE__, :stop}

  @type reason ::
          {:robots_disallowed, String.t()}
          | {:robots_refused, pos_integer()}
          | {:robots_unreadable, term()}
          | {:robots_crawl_delay, pos_integer()}
          | {:refused, pos_integer()}
          | {:retry_after, pos_integer()}

  @doc "The bot's User-Agent."
  @spec user_agent() :: String.t()
  def user_agent, do: @user_agent

  @doc """
  A request with the bot's User-Agent, signed (a step, so a retry or a
  redirect is signed afresh). `options` are `Req.new/1` options.
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(options) do
    options
    |> Req.new()
    |> Req.Request.put_header("user-agent", @user_agent)
    |> Req.Request.append_request_steps(web_bot_auth: &WebBotAuth.sign/1)
  end

  @doc """
  The URL to request for `path` and `params` on `host`, and the target (path
  and query) that robots.txt rules are matched against. Both come from the one
  URL, with the query of `path` and `params` merged once and a fragment, which
  is never sent, dropped, so that what is checked is what is requested.
  """
  @spec request_url(String.t(), String.t(), keyword()) :: {String.t(), String.t()}
  def request_url(host, path, params) do
    uri = URI.parse("https://" <> host <> path)

    query =
      [uri.query, if(params == [], do: nil, else: URI.encode_query(params))]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("&")

    uri = %{uri | fragment: nil, query: if(query == "", do: nil, else: query)}
    {URI.to_string(uri), target(uri)}
  end

  @doc "The path and query of `uri`, which robots.txt rules are matched against."
  @spec target(URI.t()) :: String.t()
  def target(%URI{path: path, query: nil}), do: path || "/"
  def target(%URI{path: path, query: query}), do: (path || "/") <> "?" <> query

  @doc """
  Decides whether `target` (a path with its query) may be requested from
  `host` and takes the turn for it: `:ok` once it is the request's turn (the
  pause has been waited), or `{:error, reason}` (see the moduledoc). Fetches
  robots.txt when its rules are not at hand; `req_options` are merged into
  that request, and `opts` take `:pause_ms` (the reader's own pause, default
  0), `:protocols`, `:max_retry_after_ms` and `:max_wait_ms` (how long to wait
  for the turn in place).
  """
  @spec permit(String.t(), String.t(), keyword(), keyword()) :: :ok | {:error, reason()}
  def permit(host, target, req_options, opts \\ []) do
    host = String.downcase(host)

    with :ok <- cooled_down(host),
         {:ok, rules} <- rules(host, req_options, opts),
         :ok <- verdict(rules, target) do
      pace(host, max(Keyword.get(opts, :pause_ms, 0), rules.delay_ms), opts)
    end
  end

  defp verdict(%Robots{refused: status}, _target) when is_integer(status),
    do: {:error, {:robots_refused, status}}

  defp verdict(%Robots{} = rules, target) do
    case Robots.check(rules, target) do
      :allowed -> :ok
      {:disallowed, _rule} -> {:error, {:robots_disallowed, target |> String.split("?") |> hd()}}
    end
  end

  # The turn at the host, whoever reads it: a pause, or a longer `Crawl-delay`,
  # after the request before.
  defp pace(host, gap_ms, opts) do
    case Hosts.reserve(host, gap_ms, Keyword.get(opts, :max_wait_ms, @max_wait_ms)) do
      {:ok, wait_ms} -> Process.sleep(wait_ms)
      {:wait, wait_ms} -> {:error, {:robots_crawl_delay, seconds(wait_ms)}}
    end
  end

  defp cooled_down(host) do
    case Hosts.not_before(host) do
      at when is_integer(at) and at > 0 ->
        remaining = at - Hosts.now()
        if remaining > 0, do: {:error, {:retry_after, seconds(remaining)}}, else: :ok

      _none ->
        :ok
    end
  end

  # Rules at hand are used; otherwise one process at a time fetches them, and
  # the others find them when it is done.
  defp rules(host, req_options, opts) do
    case at_hand(host) do
      {:ok, rules} ->
        {:ok, rules}

      {:stale, _stored} ->
        :global.trans(
          {{__MODULE__, :robots, host}, self()},
          fn -> fetch_if_stale(host, req_options, opts) end,
          [node()]
        )
    end
  end

  defp fetch_if_stale(host, req_options, opts) do
    case at_hand(host) do
      {:ok, rules} -> {:ok, rules}
      {:stale, stored} -> fetch_rules(host, req_options, opts, stored)
    end
  end

  # Rules fetched within the hour, or while a refresh that was throttled waits
  # for its time, stand.
  defp at_hand(host) do
    case Hosts.robots(host) do
      {rules, fetched_at} = stored ->
        now = Hosts.now()

        if now - fetched_at < @fresh_ms or
             (now - fetched_at <= @valid_ms and now < (Hosts.robots_retry_at(host) || 0)),
           do: {:ok, rules},
           else: {:stale, stored}

      nil ->
        {:stale, nil}
    end
  end

  defp fetch_rules(host, req_options, opts, stored) do
    max_retry_after_ms = Keyword.get(opts, :max_retry_after_ms, @default_max_retry_after_ms)

    with :ok <- pace(host, Keyword.get(opts, :pause_ms, 0), opts) do
      request =
        [
          url: "https://#{host}/robots.txt",
          decode_body: false,
          into: &bounded_body/2,
          connect_options: [timeout: 5_000, protocols: Keyword.get(opts, :protocols, [:http1])],
          receive_timeout: 15_000,
          # RFC 9309: a crawler follows at least five redirects to robots.txt.
          redirect: true,
          max_redirects: 5,
          retry: retry_step(max_retry_after_ms),
          max_retries: 1
        ]
        |> new()
        # Nothing of the shop's own requests (a token header) goes to robots.txt.
        |> Req.merge(Keyword.drop(req_options, [:headers, :params, :url]))

      case Req.request(request) do
        {:ok, response} -> robots_answer(host, response, stored)
        {:error, exception} -> unreadable(host, {:transport, exception.__struct__}, nil, stored)
      end
    end
  end

  # RFC 9309 says a crawler parses at least 500 KiB and may ignore the rest, so
  # the download stops there.
  @doc false
  def bounded_body({:data, data}, {request, response}) do
    body = if is_binary(response.body), do: response.body, else: ""
    room = Robots.max_bytes() - byte_size(body)

    if byte_size(data) < room,
      do: {:cont, {request, %{response | body: body <> data}}},
      else: {:halt, {request, %{response | body: body <> binary_part(data, 0, room)}}}
  end

  defp robots_answer(host, %Req.Response{status: status} = response, stored) do
    cond do
      challenge?(response) -> remember_refusal(host, status)
      status in 200..299 -> remember(host, Robots.parse(body(response), @token))
      status in 400..499 and status != 429 -> remember(host, Robots.allow_all())
      true -> unreadable(host, {:http_status, status}, response, stored)
    end
  end

  defp body(%Req.Response{body: body}) when is_binary(body), do: body
  defp body(_response), do: ""

  defp remember(host, rules) do
    Hosts.put_robots(host, rules)
    {:ok, rules}
  end

  defp remember_refusal(host, status) do
    Hosts.put_robots(host, Robots.refused(status))
    {:error, {:robots_refused, status}}
  end

  # The rules fetched before stay valid for a day after they were fetched, and
  # win over a refresh the host throttles (the refresh waits for the
  # `Retry-After`, or an hour).
  defp unreadable(host, reason, response, {rules, fetched_at}) do
    now = Hosts.now()

    if now - fetched_at <= @valid_ms do
      Logger.info(
        "robots.txt of #{host} unreadable (#{inspect(reason)}): using the earlier rules"
      )

      retry_ms = (response && retry_after_ms(response)) || @fresh_ms
      Hosts.put_robots_retry_at(host, now + retry_ms)
      {:ok, rules}
    else
      unreadable(host, reason, response, nil)
    end
  end

  # No usable rules: a `Retry-After` is waited out by the job, else the host is
  # not read.
  defp unreadable(host, reason, response, nil) do
    case response && classify(host, response) do
      {:stop, {:retry_after, _seconds} = retry} -> {:error, retry}
      _none -> {:error, {:robots_unreadable, reason}}
    end
  end

  @doc """
  What a response means for the policy: `{:stop, {:refused, status}}` for a
  refusal, `{:stop, {:retry_after, seconds}}` for a 429 or 503 with a
  `Retry-After` (remembered, so that `permit/4` keeps the host from being
  asked before it has passed), otherwise `:ok`: the caller reads the status.
  """
  @spec classify(String.t(), Req.Response.t()) :: :ok | {:stop, reason()}
  def classify(host, %Req.Response{status: status} = response) do
    cond do
      refused?(response) ->
        {:stop, {:refused, status}}

      status in [429, 503] and is_integer(retry_after_ms(response)) ->
        ms = retry_after_ms(response)
        Hosts.put_not_before(String.downcase(host), Hosts.now() + ms)
        {:stop, {:retry_after, seconds(ms)}}

      true ->
        :ok
    end
  end

  @doc "Whether the host refused us: a 401, a 403 or a challenge response."
  @spec refused?(Req.Response.t()) :: boolean()
  def refused?(%Req.Response{status: status} = response),
    do: status in [401, 403] or challenge?(response)

  @doc "Whether the response is a challenge page or carries a challenge header."
  @spec challenge?(Req.Response.t()) :: boolean()
  def challenge?(%Req.Response{status: status, body: body} = response) do
    Enum.any?(
      Req.Response.get_header(response, "cf-mitigated"),
      &String.contains?(String.downcase(&1), "challenge")
    ) or
      (status in [403, 503] and is_binary(body) and Regex.match?(@challenge_page, body))
  end

  @doc """
  The `retry:` option of a request: a 429 or 503 is repeated once after its
  `Retry-After` when that is at most `max_retry_after_ms` (a 429 without one
  after 10 s); a refusal and every other answer are not repeated.
  """
  @spec retry_step(non_neg_integer()) :: (Req.Request.t(), term() -> false | {:delay, integer()})
  def retry_step(max_retry_after_ms) do
    fn _request, response_or_exception ->
      retry(response_or_exception, max_retry_after_ms)
    end
  end

  defp retry(%Req.Response{status: status} = response, max_retry_after_ms)
       when status in [429, 503] do
    case {refused?(response), retry_after_ms(response)} do
      {true, _} -> false
      {false, nil} when status == 429 -> {:delay, @rate_limit_delay_ms}
      {false, delay} when is_integer(delay) and delay <= max_retry_after_ms -> {:delay, delay}
      _long_or_none -> false
    end
  end

  defp retry(_response_or_exception, _max_retry_after_ms), do: false

  @doc "The milliseconds a response's `Retry-After` asks for, or nil."
  @spec retry_after_ms(Req.Response.t()) :: non_neg_integer() | nil
  def retry_after_ms(response) do
    Req.Response.get_retry_after(response)
  rescue
    # An unparsable HTTP date; the header is the host's, not ours.
    ArgumentError -> nil
  end

  @doc """
  Whether `reason` is a policy decision that another attempt would only
  repeat (robots.txt, a refusal). A wait (`wait_seconds/1`) is not: it is
  waited out.
  """
  @spec final?(term()) :: boolean()
  def final?({tag, _detail})
      when tag in [:robots_disallowed, :robots_refused, :robots_unreadable, :refused],
      do: true

  def final?(_reason), do: false

  @doc """
  The seconds a reason asks to wait before the host is asked again (a
  `Retry-After`, or the turn a `Crawl-delay` leaves), or nil.
  """
  @spec wait_seconds(term()) :: pos_integer() | nil
  def wait_seconds({tag, seconds}) when tag in [:retry_after, :robots_crawl_delay], do: seconds
  def wait_seconds(_reason), do: nil

  @doc """
  What a job does with a wait of `seconds`: `{:snooze, seconds}` (plus up to
  30 s of jitter) when it ends before the job's next nightly run at `run_at`
  (UTC), counted from the job's insertion, else `:expired`: the job must end
  with its failure then, or its snoozing would keep the next night's job from
  being queued.
  """
  @spec snooze_before(Oban.Job.t(), pos_integer(), Time.t()) ::
          {:snooze, pos_integer()} | :expired
  def snooze_before(%Oban.Job{inserted_at: inserted_at}, seconds, %Time{} = run_at) do
    deadline = next_run(inserted_at, run_at)
    wake_at = DateTime.add(DateTime.utc_now(), seconds, :second)

    if DateTime.compare(wake_at, deadline) == :lt,
      do: {:snooze, seconds + :rand.uniform(30)},
      else: :expired
  end

  defp next_run(after_time, run_at) do
    same_day = DateTime.new!(DateTime.to_date(after_time), run_at, "Etc/UTC")

    if DateTime.compare(after_time, same_day) == :lt,
      do: same_day,
      else: DateTime.add(same_day, 1, :day)
  end

  @doc "Ends the reading of a host at once, from anywhere in a client; see `catch_stop/1`."
  @spec stop(reason()) :: no_return()
  def stop(reason), do: throw({@stop, reason})

  @doc "Runs `fun`, a whole fetch, and answers `{:error, reason}` when `stop/1` ended it."
  @spec catch_stop((-> result)) :: result | {:error, reason()} when result: term()
  def catch_stop(fun) do
    fun.()
  catch
    :throw, {@stop, reason} -> {:error, reason}
  end

  defp seconds(ms), do: max(1, ceil(ms / 1000))
end
