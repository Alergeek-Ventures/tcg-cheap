defmodule TcgCheap.Catalogue.Tcgdex do
  @moduledoc "Strict, read-only adapter for the official TCGdex API."
  @behaviour TcgCheap.Catalogue.Provider

  @base "https://api.tcgdex.net/v2/en"
  @max_response_bytes 2 * 1024 * 1024

  @doc false
  def valid_set_id?(id) when is_binary(id),
    do: byte_size(id) in 1..128 and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/, id)

  def valid_set_id?(_), do: false

  @doc false
  def valid_card_id?(id) when is_binary(id) do
    byte_size(id) in 1..128 and
      Regex.match?(~r/\A[A-Za-z0-9](?:[A-Za-z0-9._!-]|%[0-9A-Fa-f]{2})*\z/, id)
  end

  def valid_card_id?(_), do: false

  @impl true
  def fetch_card(id, opts \\ []), do: fetch("cards", id, opts)

  @impl true
  def fetch_set(id, opts \\ []), do: fetch("sets", id, opts)

  @impl true
  def list_sets(opts \\ []) do
    if valid_top_options?(opts), do: request("sets", nil, opts), else: {:error, :invalid_options}
  end

  defp fetch(kind, id, opts) when is_binary(id) do
    cond do
      not valid_id?(kind, id) ->
        {:error, :invalid_id}

      not is_list(opts) or not Keyword.keyword?(opts) or not valid_top_options?(opts) ->
        {:error, :invalid_options}

      true ->
        request(kind, id, opts)
    end
  end

  defp fetch(_, _, _), do: {:error, :invalid_id}

  defp valid_top_options?(options) do
    is_list(options) and Keyword.keyword?(options) and
      Enum.all?(Keyword.keys(options), &(&1 in [:request_options, :request_admitter])) and
      length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) and
      is_function(Keyword.get(options, :request_admitter, fn -> :ok end), 0)
  end

  defp valid_id?("sets", id), do: valid_set_id?(id)
  defp valid_id?("cards", id), do: valid_card_id?(id)

  defp request(kind, id, opts) do
    request_options = Keyword.get(opts, :request_options, [])

    if valid_request_options?(request_options),
      do: request_validated(kind, id, opts, request_options),
      else: {:error, :invalid_options}
  end

  defp request_validated(kind, id, opts, request_options) do
    budgeted? = Keyword.has_key?(opts, :request_admitter)

    options =
      [
        decode_body: false,
        into: &bounded_into/2,
        connect_options: [timeout: 5_000],
        receive_timeout: 15_000,
        request_timeout: 15_000,
        redirect: false,
        retry: if(budgeted?, do: false, else: :safe_transient),
        max_retries: if(budgeted?, do: 0, else: 2)
      ]
      |> Keyword.merge(request_options)
      |> force_single_attempt(budgeted?)

    path = if id, do: "#{@base}/#{kind}/#{URI.encode(id)}", else: "#{@base}/#{kind}"

    with :ok <- admit_request(opts), do: execute_request(path, options, kind, id)
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

  defp valid_request_options?(options) when is_list(options),
    do:
      Keyword.keyword?(options) and
        length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) and
        Enum.all?(Keyword.keys(options), &(&1 in [:plug, :retry, :max_retries])) and
        Keyword.get(options, :retry, :safe_transient) in [false, :safe_transient] and
        valid_max_retries?(Keyword.get(options, :max_retries, 2))

  defp valid_request_options?(_), do: false

  defp valid_max_retries?(value), do: is_integer(value) and value in 0..2

  defp force_single_attempt(options, true),
    do:
      options
      |> Keyword.put(:retry, false)
      |> Keyword.put(:max_retries, 0)
      |> Keyword.put(:redirect, false)

  defp force_single_attempt(options, false), do: options

  defp admit_request(opts) do
    case Keyword.get(opts, :request_admitter, fn -> :ok end).() do
      :ok -> :ok
      {:error, :budget_persistence_failed} = error -> error
      {:error, {:acquisition_budget_rejected, _reason, _reset_at}} = error -> error
      {:error, {:acquisition_budget_rejected, _reason}} = error -> error
      _ -> {:error, :invalid_admission_result}
    end
  rescue
    _ -> {:error, :budget_persistence_failed}
  catch
    _, _ -> {:error, :budget_persistence_failed}
  end

  defp decode(body, kind, id) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, value} -> normalize(value, kind, id)
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp response_body({size, chunks}) when is_integer(size) and is_list(chunks),
    do: {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

  defp response_body(body) when is_binary(body), do: {:ok, body}
  defp response_body(_), do: {:error, {:malformed_response, :invalid_body}}

  defp normalize(value, "sets", nil) when is_list(value), do: validate_set_briefs(value)
  defp normalize(_, "sets", nil), do: {:error, {:malformed_response, :expected_array}}

  defp normalize(%{} = value, _kind, id) do
    case Map.get(value, "id") do
      ^id -> {:ok, value}
      nil -> {:error, {:malformed_response, :missing_id}}
      actual -> {:error, {:malformed_response, {:id_mismatch, id, actual}}}
    end
  end

  defp normalize(_, _, _), do: {:error, {:malformed_response, :expected_object}}

  defp validate_set_briefs(briefs) when length(briefs) > 1_000,
    do: {:error, {:malformed_response, :too_many_set_briefs}}

  defp validate_set_briefs(briefs) do
    Enum.reduce_while(briefs, {[], MapSet.new()}, fn brief, {result, ids} ->
      case validate_set_brief(brief, ids) do
        {:ok, id, name} ->
          {:cont,
           {[Map.merge(brief, %{"id" => id, "name" => name}) | result], MapSet.put(ids, id)}}

        {:error, reason} ->
          {:halt, {:error, {:malformed_response, reason}}}
      end
    end)
    |> case do
      {briefs, _} when is_list(briefs) -> {:ok, Enum.reverse(briefs)}
      error -> error
    end
  end

  defp bounded_into({:data, data}, {request, response}) when is_binary(data) do
    {size, chunks} = body_chunks(response.body)

    if size + byte_size(data) > @max_response_bytes do
      {:halt, {request, %{response | body: :too_large}}}
    else
      {:cont, {request, %{response | body: {size + byte_size(data), [data | chunks]}}}}
    end
  end

  defp body_chunks({size, chunks}) when is_integer(size) and is_list(chunks), do: {size, chunks}
  defp body_chunks(_), do: {0, []}

  defp validate_set_brief(brief, ids) do
    with {:ok, id} <- raw_brief_field(brief, "id"),
         {:ok, name} <- brief_field(brief, "name") do
      cond do
        not valid_set_id?(id) -> {:error, {:set, {:invalid_id, id}}}
        MapSet.member?(ids, id) -> {:error, {:duplicate_id, id}}
        true -> {:ok, id, name}
      end
    else
      {:error, reason} -> {:error, {:set, reason}}
    end
  end

  defp brief_field(value, key) when is_map(value) do
    case Map.get(value, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:missing_or_blank, key}}, else: {:ok, value}

      _ ->
        {:error, {:missing_or_blank, key}}
    end
  end

  defp raw_brief_field(value, key) when is_map(value) do
    case Map.get(value, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_or_blank, key}}
    end
  end

  defp raw_brief_field(_, _), do: {:error, :expected_object}
end
