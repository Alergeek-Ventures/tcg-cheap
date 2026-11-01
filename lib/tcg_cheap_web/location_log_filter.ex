defmodule TcgCheapWeb.LocationLogFilter do
  @moduledoc """
  A primary `:logger` filter that keeps the visitor's location out of crash
  reports. A crashing LiveView logs its last message and state (Elixir's
  translator prints them at :error), and those hold the location under a
  `"location"` event parameter or the `:location` assign; Phoenix's
  `:filter_parameters` covers only its own parameter logs.

  Only structured events (`{:report, _}` and `{format, args}`) are searched,
  to a bounded depth; ordinary string log messages pass untouched.
  """

  @max_depth 40
  @filtered "[FILTERED]"

  @doc """
  Installs the filter as the first primary filter; called at application
  start. It must run before Elixir's `logger_translator` primary filter,
  which turns reports into strings (`add_primary_filter/2` would append it
  after).
  """
  @spec install() :: :ok | {:error, term()}
  def install do
    %{filters: filters} = :logger.get_primary_config()
    own = {__MODULE__, {&__MODULE__.filter/2, []}}
    :logger.set_primary_config(:filters, [own | List.keydelete(filters, __MODULE__, 0)])
  end

  @doc false
  def filter(%{msg: {:string, _chardata}} = event, _opts), do: event

  def filter(%{msg: {:report, report}} = event, _opts),
    do: redacted(event, fn -> {:report, redact(report, @max_depth)} end)

  def filter(%{msg: {format, args}} = event, _opts) when is_list(args),
    do: redacted(event, fn -> {format, redact(args, @max_depth)} end)

  def filter(event, _opts), do: event

  # :logger removes a filter that raises, which would end the redaction for
  # good; a report that cannot be searched is hidden instead.
  defp redacted(event, redact_msg) do
    %{event | msg: redact_msg.()}
  rescue
    _error -> %{event | msg: {:string, "[report hidden: location filter failed]"}}
  end

  defp redact(term, 0), do: term

  # :maps.map/2 also walks structs, keeping them structs.
  defp redact(%{} = map, depth) do
    :maps.map(
      fn
        key, _value when key in ["location", :location] -> @filtered
        _key, value -> redact(value, depth - 1)
      end,
      map
    )
  end

  defp redact([head | tail], depth), do: [redact(head, depth - 1) | redact(tail, depth)]

  defp redact(tuple, depth) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> redact(depth - 1) |> List.to_tuple()

  defp redact(term, _depth), do: term
end
