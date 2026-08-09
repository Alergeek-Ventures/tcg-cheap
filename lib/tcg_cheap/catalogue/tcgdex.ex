defmodule TcgCheap.Catalogue.Tcgdex do
  @moduledoc "Strict, read-only adapter for the official TCGdex API."
  @behaviour TcgCheap.Catalogue.Provider

  @base "https://api.tcgdex.net/v2/en"

  @impl true
  def fetch_card(id, opts \\ []), do: fetch("cards", id, opts)

  @impl true
  def fetch_set(id, opts \\ []), do: fetch("sets", id, opts)

  @impl true
  def list_sets(opts \\ []) do
    if valid_top_options?(opts), do: request("sets", nil, opts), else: {:error, :invalid_options}
  end

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
    is_list(options) and Keyword.keyword?(options) and
      Enum.all?(Keyword.keys(options), &(&1 in [:request_options, :request_admitter])) and
      length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) and
      is_function(Keyword.get(options, :request_admitter, fn -> :ok end), 0)
  end

  defp canonical_id?(id), do: Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/, id)

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
        receive_timeout: 10_000,
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
      {:ok, %{status: 200, body: body}} ->
        decode(body, kind, id)

      {:ok, %{status: status}} ->
        {:error, {:http_error, %{status: status, kind: kind, id: id}}}

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
    do: options |> Keyword.put(:retry, false) |> Keyword.put(:max_retries, 0)

  defp force_single_attempt(options, false), do: options

  defp admit_request(opts) do
    case Keyword.get(opts, :request_admitter, fn -> :ok end).() do
      :ok -> :ok
      {:error, :budget_persistence_failed} = error -> error
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

  defp decode(body, kind, id), do: normalize(body, kind, id)

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

  defp validate_set_brief(brief, ids) do
    with {:ok, id} <- brief_field(brief, "id"),
         {:ok, name} <- brief_field(brief, "name") do
      cond do
        not canonical_id?(id) -> {:error, {:set, {:invalid_id, id}}}
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

  defp brief_field(_, _), do: {:error, :expected_object}
end
