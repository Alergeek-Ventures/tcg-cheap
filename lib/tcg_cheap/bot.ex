defmodule TcgCheap.Bot do
  @moduledoc """
  The one identity and access policy of every request the bot ("TcgCheap")
  makes to a shop, to REBEL and for remote product and card images.

  - Identity: `new/1` builds the request with the bot's User-Agent and signs
    it with Web Bot Auth (`TcgCheap.WebBotAuth`). Nothing else sets that
    User-Agent. The requests of other tools (NBP rates, Cardmarket files,
    TCGdex) are no crawling and do not carry it.
  - robots.txt: `permit/4` fetches `https://<host>/robots.txt` (signed, same
    identity; up to five redirects are followed) before the host is read and decides whether a path may be
    requested (`TcgCheap.Bot.Robots`). Rules fetched are used for an hour
    without asking again. A host whose robots.txt answers 404 or 410 allows
    everything; one that refuses us (401, 403, a challenge) allows nothing;
    when it cannot be read (5xx, 429, timeout, network failure, any other
    status) the rules fetched before are used for up to 24 hours after they
    were fetched, and without them the host is not read.
  - Refusals and waits: a 401, a 403 or a challenge response (`cf-mitigated:
    challenge`, a Cloudflare challenge page) is never retried, and nothing is
    asked of the host again through another way. A `Retry-After` on 429 or 503
    is honoured: a short one is waited out in the request (`retry_step/1`), a
    longer one is remembered (`TcgCheap.Bot.Hosts`) so that the host is not
    asked before it has passed (`classify/2`, `permit/4`).

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
  # A Crawl-delay longer than this would hold a job far beyond its time.
  @max_crawl_delay_ms :timer.minutes(5)
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
  Decides whether `target` (a path with its query) may be requested from
  `host`: `{:ok, pause_ms}`, the `Crawl-delay` the host asks between
  requests, or `{:error, reason}` (see the moduledoc). Fetches robots.txt when
  its rules are not at hand; `req_options` are merged into that request, and
  `opts` take `:pause_ms` (before it), `:protocols` and `:max_retry_after_ms`.
  """
  @spec permit(String.t(), String.t(), keyword(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, reason()}
  def permit(host, target, req_options, opts \\ []) do
    host = String.downcase(host)

    with :ok <- cooled_down(host),
         {:ok, rules} <- rules(host, req_options, opts) do
      verdict(rules, target)
    end
  end

  defp verdict(%Robots{refused: status}, _target) when is_integer(status),
    do: {:error, {:robots_refused, status}}

  defp verdict(%Robots{delay_ms: delay}, _target) when delay > @max_crawl_delay_ms,
    do: {:error, {:robots_crawl_delay, div(delay, 1000)}}

  defp verdict(%Robots{} = rules, target) do
    case Robots.check(rules, target) do
      :allowed -> {:ok, rules.delay_ms}
      {:disallowed, _rule} -> {:error, {:robots_disallowed, path(target)}}
    end
  end

  defp path(target), do: target |> String.split("?", parts: 2) |> hd()

  defp cooled_down(host) do
    case Hosts.not_before(host) do
      at when is_integer(at) and at > 0 ->
        remaining = at - Hosts.now()
        if remaining > 0, do: {:error, {:retry_after, seconds(remaining)}}, else: :ok

      _none ->
        :ok
    end
  end

  defp rules(host, req_options, opts) do
    stored = Hosts.robots(host)

    case stored do
      {rules, fetched_at} when is_struct(rules, Robots) ->
        if Hosts.now() - fetched_at < @fresh_ms,
          do: {:ok, rules},
          else: fetch_rules(host, req_options, opts, stored)

      nil ->
        fetch_rules(host, req_options, opts, stored)
    end
  end

  defp fetch_rules(host, req_options, opts, stored) do
    max_retry_after_ms = Keyword.get(opts, :max_retry_after_ms, @default_max_retry_after_ms)
    Process.sleep(Keyword.get(opts, :pause_ms, 0))

    request =
      [
        url: "https://#{host}/robots.txt",
        decode_body: false,
        connect_options: [timeout: 5_000, protocols: Keyword.get(opts, :protocols, [:http1])],
        receive_timeout: 15_000,
        # RFC 9309: a crawler follows at least five redirects to robots.txt.
        redirect: true,
        max_redirects: 5,
        retry: retry_step(max_retry_after_ms),
        max_retries: 1
      ]
      |> new()
      |> Req.merge(req_options)

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: body} = response} when is_binary(body) ->
        if refused?(response),
          do: remember_refusal(host, 200),
          else: remember(host, Robots.parse(body, @token))

      {:ok, %Req.Response{status: status}} when status in [404, 410] ->
        remember(host, Robots.allow_all())

      {:ok, response} ->
        unreadable(host, response, stored)

      {:error, exception} ->
        fall_back(host, {:transport, exception.__struct__}, stored)
    end
  end

  defp remember(host, rules) do
    Hosts.put_robots(host, rules)
    {:ok, rules}
  end

  defp remember_refusal(host, status) do
    Hosts.put_robots(host, Robots.refused(status))
    {:error, {:robots_refused, status}}
  end

  defp unreadable(host, response, stored) do
    case classify(host, response) do
      {:stop, {:refused, status}} -> remember_refusal(host, status)
      {:stop, {:retry_after, _seconds} = reason} -> {:error, reason}
      :ok -> fall_back(host, {:http_status, response.status}, stored)
    end
  end

  # The rules fetched before stay valid for a day after they were fetched.
  defp fall_back(host, reason, {rules, fetched_at}) do
    if Hosts.now() - fetched_at <= @valid_ms do
      Logger.info(
        "robots.txt of #{host} unreadable (#{inspect(reason)}): using the earlier rules"
      )

      {:ok, rules}
    else
      {:error, {:robots_unreadable, reason}}
    end
  end

  defp fall_back(_host, reason, nil), do: {:error, {:robots_unreadable, reason}}

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

  defp challenge?(%Req.Response{status: status, body: body} = response) do
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
  repeat (robots.txt, a refusal). A `Retry-After` is not: it is waited out.
  """
  @spec final?(term()) :: boolean()
  def final?({tag, _detail})
      when tag in [
             :robots_disallowed,
             :robots_refused,
             :robots_unreadable,
             :robots_crawl_delay,
             :refused
           ],
      do: true

  def final?(_reason), do: false

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
