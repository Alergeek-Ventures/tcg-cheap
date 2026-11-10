defmodule TcgCheap.Sealed.FetchFailure do
  @moduledoc """
  Reports a failed shop fetch as an error: a log line and a Sentry event, so
  it becomes an Issue the owner is alerted about rather than only a line in
  Sentry Logs (Sentry's logger handler turns crashes alone into Issues).

  Events group per fetch kind, shop and failure reason, so a shop failing
  every night stays one Issue, and a new reason or another shop opens its own.
  The key keeps an HTTP status and a transport error's module, and drops the
  details that vary between nights (response snippets, dates).
  """

  require Logger

  @type kind :: :sealed | :singles

  @spec report(kind(), String.t(), term()) :: :ok
  def report(kind, shop_key, reason) when kind in [:sealed, :singles] do
    message = "#{kind} fetch #{shop_key} failed: #{describe(reason)}"
    reason_key = reason_key(reason)

    Logger.error(message)

    Sentry.capture_message(message,
      level: :error,
      fingerprint: ["shop-fetch", Atom.to_string(kind), shop_key, reason_key],
      tags: %{shop: shop_key, fetch: kind, fetch_reason: reason_key},
      extra: %{reason: inspect(reason)}
    )

    :ok
  end

  defp describe(reason) when is_exception(reason),
    do: "#{inspect(reason.__struct__)}: #{Exception.message(reason)}"

  defp describe(reason), do: inspect(reason)

  defp reason_key(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_key({:http_status, status}), do: "http_status_#{status}"
  defp reason_key({:transport, module}) when is_atom(module), do: "transport_#{inspect(module)}"

  defp reason_key(reason) when is_tuple(reason) and is_atom(elem(reason, 0)),
    do: Atom.to_string(elem(reason, 0))

  defp reason_key(%module{}), do: inspect(module)
  defp reason_key(_reason), do: "other"
end
