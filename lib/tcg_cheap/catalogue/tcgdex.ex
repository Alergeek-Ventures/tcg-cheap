defmodule TcgCheap.Catalogue.Tcgdex do
  @moduledoc "Strict, read-only adapter for the official TCGdex API."
  @behaviour TcgCheap.Catalogue.Provider

  @base "https://api.tcgdex.net/v2/en"

  @impl true
  def fetch_card(id, opts \\ []), do: fetch("cards", id, opts)

  @impl true
  def fetch_set(id, opts \\ []), do: fetch("sets", id, opts)

  defp fetch(kind, id, opts) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" or not canonical_id?(id) ->
        {:error, :invalid_id}

      not is_list(opts) or not Keyword.keyword?(opts) or not valid_top_options?(opts) ->
        {:error, :invalid_options}

      true ->
        request(kind, id, opts)
    end
  end

  defp fetch(_, _, _), do: {:error, :invalid_id}

  defp valid_top_options?(options) do
    keys = Keyword.keys(options)
    keys in [[], [:request_options]] and length(keys) == length(Enum.uniq(keys))
  end

  defp canonical_id?(id), do: Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, id)

  defp request(kind, id, opts) do
    request_options = Keyword.get(opts, :request_options, [])

    if valid_request_options?(request_options) do
      options =
        [decode_body: false, receive_timeout: 10_000, retry: :safe_transient, max_retries: 2]
        |> Keyword.merge(request_options)

      case Req.get("#{@base}/#{kind}/#{URI.encode(id)}", options) do
        {:ok, %{status: 200, body: body}} -> decode(body, kind, id)
        {:ok, %{status: status}} -> {:error, {:http_error, %{status: status, kind: kind, id: id}}}
        {:error, reason} -> {:error, {:transport_error, reason}}
      end
    else
      {:error, :invalid_options}
    end
  end

  defp valid_request_options?(options) when is_list(options),
    do:
      Keyword.keyword?(options) and
        length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) and
        Enum.all?(Keyword.keys(options), &(&1 in [:plug, :retry, :max_retries])) and
        Keyword.get(options, :retry, :safe_transient) in [false, :safe_transient] and
        valid_max_retries?(Keyword.get(options, :max_retries, 2))

  defp valid_request_options?(_), do: false

  defp valid_max_retries?(value), do: is_integer(value) and value in 0..2

  defp decode(body, kind, id) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, value} -> normalize(value, kind, id)
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp decode(body, kind, id), do: normalize(body, kind, id)

  defp normalize(%{} = value, _kind, id) do
    case Map.get(value, "id") do
      ^id -> {:ok, value}
      nil -> {:error, {:malformed_response, :missing_id}}
      actual -> {:error, {:malformed_response, {:id_mismatch, id, actual}}}
    end
  end

  defp normalize(_, _, _), do: {:error, {:malformed_response, :expected_object}}
end
