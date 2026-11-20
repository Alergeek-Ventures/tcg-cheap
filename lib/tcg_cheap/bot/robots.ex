defmodule TcgCheap.Bot.Robots do
  @moduledoc """
  A host's robots.txt as it applies to the bot (RFC 9309): the rules of the
  group whose user-agent token is the bot's (compared case-insensitively),
  and only when there is none, of the `*` group; groups of the same token
  are merged. Within the rules, the longest matching path pattern wins
  (`Allow` wins a tie), `*` in a pattern matches any characters and a final
  `$` anchors the end. A path no rule matches is allowed. `Crawl-delay` is
  not part of the RFC; the bot honours it as a minimum pause between requests.
  """

  # RFC 9309 asks a crawler to parse at least 500 KiB; the rest is ignored.
  @max_bytes 512 * 1024

  @doc "How much of a robots.txt is read; `TcgCheap.Bot` does not download more."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes
  @max_pattern_bytes 1_024

  @enforce_keys [:rules, :delay_ms]
  defstruct [:rules, :delay_ms, :refused]

  @typedoc """
  `rules` are `{:allow | :disallow, pattern}` pairs. `refused` is the status
  of a robots.txt the host refused to give us (401 or 403): everything is
  disallowed.
  """
  @type t :: %__MODULE__{
          rules: [{:allow | :disallow, String.t()}],
          delay_ms: non_neg_integer(),
          refused: pos_integer() | nil
        }

  @doc "No robots.txt (404, 410): everything is allowed."
  @spec allow_all() :: t()
  def allow_all, do: %__MODULE__{rules: [], delay_ms: 0}

  @doc "A robots.txt the host refused (HTTP `status`): everything is disallowed."
  @spec refused(pos_integer()) :: t()
  def refused(status),
    do: %__MODULE__{rules: [{:disallow, "/"}], delay_ms: 0, refused: status}

  @doc "Parses a robots.txt body for the user-agent `token`."
  @spec parse(binary(), String.t()) :: t()
  def parse(body, token) when is_binary(body) do
    token = String.downcase(token)
    # The cut may fall inside a character; the line splitting below works on
    # bytes and does not mind.
    groups = body |> binary_part(0, min(byte_size(body), @max_bytes)) |> groups()

    named = Enum.filter(groups, &(token in &1.agents))
    chosen = if named == [], do: Enum.filter(groups, &("*" in &1.agents)), else: named

    %__MODULE__{
      rules: Enum.flat_map(chosen, & &1.rules),
      delay_ms: chosen |> Enum.map(& &1.delay_ms) |> Enum.max(fn -> 0 end)
    }
  end

  @doc """
  Whether `target` (a path with its query, starting with `/`) may be read:
  `:allowed`, or `{:disallowed, rule}` naming the rule that forbids it.
  """
  @spec check(t(), String.t()) :: :allowed | {:disallowed, String.t()}
  def check(%__MODULE__{rules: rules}, target) do
    target = normalize(target)

    best =
      rules
      |> Enum.filter(fn {_kind, pattern} -> matches?(pattern, target) end)
      |> Enum.max_by(
        fn {kind, pattern} -> {byte_size(pattern), kind == :allow} end,
        fn -> nil end
      )

    case best do
      {:disallow, pattern} -> {:disallowed, "Disallow: #{pattern}"}
      _allowed_or_none -> :allowed
    end
  end

  # Consecutive user-agent lines name one group; the first other line after
  # them starts its rules, and a user-agent line after rules starts a new group.
  defp groups(body) do
    body
    |> String.replace_prefix("﻿", "")
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.flat_map(&line/1)
    |> Enum.reduce({[], :agents}, &add_line/2)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.map(fn group -> %{group | rules: Enum.reverse(group.rules)} end)
  end

  defp line(text) do
    [content | _comment] = String.split(text, "#", parts: 2)

    with [field, value] <- String.split(content, ":", parts: 2),
         field when field in ["user-agent", "allow", "disallow", "crawl-delay"] <-
           field |> String.trim() |> String.downcase() do
      [{field, String.trim(value)}]
    else
      _ignored -> []
    end
  end

  defp add_line({"user-agent", agent}, {[group | rest], :agents}),
    do: {[%{group | agents: [String.downcase(agent) | group.agents]} | rest], :agents}

  defp add_line({"user-agent", agent}, {groups, _state}),
    do: {[%{agents: [String.downcase(agent)], rules: [], delay_ms: 0} | groups], :agents}

  # Rules before any user-agent line belong to no group.
  defp add_line(_line, {[], _state}), do: {[], :agents}

  defp add_line({"crawl-delay", value}, {[group | rest], _state}),
    do: {[%{group | delay_ms: max(group.delay_ms, delay_ms(value))} | rest], :rules}

  defp add_line({kind, pattern}, {[group | rest], _state}) do
    kind = String.to_existing_atom(kind)

    # An empty Disallow allows everything, an empty Allow is no rule.
    if pattern == "" or byte_size(pattern) > @max_pattern_bytes,
      do: {[group | rest], :rules},
      else: {[%{group | rules: [{kind, normalize(pattern)} | group.rules]} | rest], :rules}
  end

  defp delay_ms(value) do
    case Float.parse(value) do
      {seconds, _rest} when seconds > 0 -> round(seconds * 1000)
      _no_delay -> 0
    end
  end

  # RFC 9309: a pattern and a path compare after the same normalisation: bytes
  # outside ASCII as escapes, escapes in upper case, and escapes of unreserved
  # characters (letters, digits, `-._~`) decoded. An escaped reserved character
  # (`%2F`) stays distinct from the character itself.
  defp normalize(text), do: text |> normalize([]) |> IO.iodata_to_binary()

  defguardp hex?(char) when char in ?0..?9 or char in ?a..?f or char in ?A..?F

  defguardp unreserved?(byte)
            when byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in [?-, ?., ?_, ?~]

  defp normalize(<<?%, high, low, rest::binary>>, acc) when hex?(high) and hex?(low) do
    byte = String.to_integer(<<high, low>>, 16)
    escape = if unreserved?(byte), do: <<byte>>, else: <<?%, high, low>> |> String.upcase()
    normalize(rest, [acc, escape])
  end

  defp normalize(<<byte, rest::binary>>, acc) when byte > 127,
    do: normalize(rest, [acc, "%", Base.encode16(<<byte>>)])

  defp normalize(<<byte, rest::binary>>, acc), do: normalize(rest, [acc, byte])
  defp normalize(<<>>, acc), do: acc

  defp matches?("$", target), do: target == ""
  defp matches?("", _target), do: true
  defp matches?("*" <> pattern, target), do: skip(pattern, target)

  defp matches?(<<char, pattern::binary>>, <<char, target::binary>>),
    do: matches?(pattern, target)

  defp matches?(_pattern, _target), do: false

  # `*` matches any run of characters, also none.
  defp skip(pattern, target) do
    matches?(pattern, target) or
      case target do
        <<_char, rest::binary>> -> skip(pattern, rest)
        "" -> false
      end
  end
end
