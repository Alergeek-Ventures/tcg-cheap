defmodule TcgCheap.Sealed.Tcgdex do
  @moduledoc "Strict, read-only adapter for the official TCGdex API."

  @base "https://api.tcgdex.net/v2/en"
  @max_response_bytes 2 * 1024 * 1024
  @request_options [
    decode_body: false,
    into: &__MODULE__.bounded_into/2,
    connect_options: [timeout: 5_000],
    receive_timeout: 15_000,
    request_timeout: 15_000,
    redirect: false,
    retry: :safe_transient,
    max_retries: 2
  ]
  @card_id ~r/\A[A-Za-z0-9](?:[A-Za-z0-9._!-]|%[0-9A-Fa-f]{2})*\z/

  @doc false
  def valid_card_id?(id) when is_binary(id) do
    byte_size(id) in 1..128 and
      Regex.match?(@card_id, id)
  end

  def valid_card_id?(_), do: false

  def fetch_card(id) do
    if valid_card_id?(id),
      do: execute_request("#{@base}/cards/#{URI.encode(id)}", @request_options, "cards", id),
      else: {:error, :invalid_id}
  end

  defp execute_request(path, options, kind, id) do
    case Req.get(path, options) do
      {:ok, %{status: 200, body: :too_large}} ->
        {:error, {:malformed_response, :response_too_large}}

      {:ok, %{status: 200, body: body}} ->
        with {:ok, body} <- response_body(body), do: decode(body, kind, id)

      {:ok, %{status: status}} ->
        {:error, {:http_error, %{status: status, kind: kind, id: id}}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, {:provider_timeout, :request}}

      {:error, reason} ->
        {:error, {:transport_error, reason}}
    end
  end

  defp decode(body, kind, id) when is_binary(body) do
    case decode_json(body, kind) do
      {:ok, value} -> normalize(value, kind, id)
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp decode_json(body, "cards"), do: Jason.decode(body, floats: :decimals)
  defp decode_json(body, _kind), do: Jason.decode(body)

  defp response_body({size, chunks}) when is_integer(size) and is_list(chunks),
    do: {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

  defp response_body(body) when is_binary(body), do: {:ok, body}
  defp response_body(_), do: {:error, {:malformed_response, :invalid_body}}

  defp normalize(%{} = value, _kind, id) do
    case Map.get(value, "id") do
      ^id -> {:ok, value}
      nil -> {:error, {:malformed_response, :missing_id}}
      actual -> {:error, {:malformed_response, {:id_mismatch, id, actual}}}
    end
  end

  defp normalize(_, _, _), do: {:error, {:malformed_response, :expected_object}}

  @doc false
  def bounded_into({:data, data}, {request, response}) when is_binary(data) do
    {size, chunks} = body_chunks(response.body)

    if size + byte_size(data) > @max_response_bytes do
      {:halt, {request, %{response | body: :too_large}}}
    else
      {:cont, {request, %{response | body: {size + byte_size(data), [data | chunks]}}}}
    end
  end

  defp body_chunks({size, chunks}) when is_integer(size) and is_list(chunks), do: {size, chunks}
  defp body_chunks(_), do: {0, []}
end
