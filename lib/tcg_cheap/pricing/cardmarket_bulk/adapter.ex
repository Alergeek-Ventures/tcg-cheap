defmodule TcgCheap.Pricing.CardmarketBulk.Adapter do
  @moduledoc "A bounded, read-only adapter for Cardmarket's Pokémon bulk files."

  @products_url "https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_6.json"
  @prices_url "https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_6.json"
  @max_response_bytes 32 * 1024 * 1024
  @max_source_rows 100_000
  @metrics ~w(avg low trend avg1 avg7 avg30 avg-holo low-holo trend-holo avg1-holo avg7-holo avg30-holo)
  @malformed_provider_response {:error, {:malformed, :invalid_content_type}}

  defstruct [
    :raw_body,
    :sha256,
    :byte_size,
    :fetched_at,
    :created_at,
    :total_rows,
    :source_rows,
    :priceable_count,
    :rows
  ]

  defmodule Product do
    @moduledoc "A validated Cardmarket product row."

    defstruct [
      :id_product,
      :name,
      :category,
      :category_id,
      :id_expansion,
      :id_metacard,
      :date_added
    ]
  end

  defmodule Price do
    @moduledoc "A validated Cardmarket price row and its selected metric."

    defstruct [
      :id_product,
      :category_id,
      :selected_metric,
      :selected_value,
      avg: nil,
      low: nil,
      trend: nil,
      avg1: nil,
      avg7: nil,
      avg30: nil,
      avg_holo: nil,
      low_holo: nil,
      trend_holo: nil,
      avg1_holo: nil,
      avg7_holo: nil,
      avg30_holo: nil
    ]
  end

  @doc "Fetch and parse the allowlisted Cardmarket product file."
  def fetch_products(opts \\ []), do: fetch(@products_url, :products, opts)

  @doc "Fetch and parse the allowlisted Cardmarket price guide."
  def fetch_prices(opts \\ []), do: fetch(@prices_url, :prices, opts)

  def parse_products(body, opts \\ []), do: parse(body, :products, opts)
  def parse_prices(body, opts \\ []), do: parse(body, :prices, opts)

  defp fetch(url, kind, opts) when is_list(opts) and is_map(opts) == false do
    if Keyword.keyword?(opts) and valid_options?(opts) do
      with :ok <- admit(opts),
           {:ok, response} <- request(url, opts),
           {:ok, body} <- response_body(response) do
        parse(body, kind, opts)
      end
    else
      {:error, :invalid_options}
    end
  end

  defp fetch(_, _, _), do: {:error, :invalid_options}

  defp request(url, opts) do
    request_options = Keyword.get(opts, :request_options, [])

    options =
      request_options
      |> Keyword.put(:decode_body, false)
      |> Keyword.put(:into, &bounded_into/2)
      |> Keyword.put(:redirect, false)
      |> Keyword.put(:retry, false)
      |> Keyword.put(:max_retries, 0)
      |> Keyword.put_new(:connect_options, timeout: 5_000)
      |> Keyword.put_new(:receive_timeout, 15_000)
      |> Keyword.put_new(:request_timeout, 15_000)

    case Req.get(url, options) do
      {:ok, %{status: 200} = response} -> {:ok, response}
      {:ok, %{status: status}} when status == 404 -> {:error, {:http_error, :not_found}}
      {:ok, %{status: status}} when status == 429 -> {:error, {:http_error, :rate_limited}}
      {:ok, %{status: status}} -> {:error, {:http_error, {:unexpected_status, status}}}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, {:timeout, :request}}
      {:error, %Req.TransportError{} = error} -> {:error, {:transport_error, error.reason}}
      {:error, error} -> {:error, {:transport_error, error}}
    end
  end

  defp response_body(%{body: :too_large}), do: {:error, {:oversized, @max_response_bytes}}

  defp response_body(%{body: body} = response) when is_binary(body) do
    if valid_json_content_type?(response), do: {:ok, body}, else: @malformed_provider_response
  end

  defp response_body(%{body: {size, chunks}} = response)
       when is_integer(size) and is_list(chunks) do
    if valid_json_content_type?(response) do
      {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
    else
      @malformed_provider_response
    end
  end

  defp response_body(_), do: {:error, {:malformed, :invalid_body}}

  defp valid_json_content_type?(response) do
    case Req.Response.get_header(response, "content-type") do
      [value] when is_binary(value) -> Regex.match?(json_content_type_regex(), value)
      _ -> false
    end
  end

  defp json_content_type_regex do
    ~r/\Aapplication\/json(?:\s*;\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+\s*=\s*(?:"(?:[^"\\]|\\.)*"|[!#$%&'*+\-.^_`|~0-9A-Za-z]+))*\z/i
  end

  defp parse(body, kind, opts) when is_binary(body) do
    cond do
      byte_size(body) > @max_response_bytes -> {:error, {:oversized, @max_response_bytes}}
      not valid_options?(opts) -> {:error, :invalid_options}
      true -> parse_decoded(body, kind, opts)
    end
  end

  defp parse(_, _, _), do: {:error, {:malformed, :expected_binary}}

  defp parse_decoded(body, kind, opts) do
    case decode_json(body) do
      {:error, reason} ->
        {:error, reason}

      {:ok, decoded} ->
        parse_decoded_rows(body, kind, opts, decoded)
    end
  rescue
    _ -> {:error, {:malformed, :invalid_body}}
  end

  defp parse_decoded_rows(body, kind, opts, decoded) do
    with {:ok, created_at} <- created_at(decoded),
         {:ok, source} <- source_rows(decoded, kind),
         {:ok, rows} <- validate_rows(source, kind),
         {:ok, now} <- clock(opts) do
      priceable = priceable_count(rows, kind)

      {:ok,
       %__MODULE__{
         raw_body: body,
         sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower),
         byte_size: byte_size(body),
         fetched_at: now,
         created_at: created_at,
         total_rows: length(source),
         source_rows: length(rows),
         priceable_count: priceable,
         rows: rows
       }}
    else
      {:error, :invalid_clock} -> {:error, :invalid_clock}
      {:error, reason} -> {:error, {:malformed, reason}}
    end
  end

  defp priceable_count(_rows, :products), do: 0

  defp priceable_count(rows, :prices),
    do: Enum.count(rows, &(!is_nil(&1.selected_value)))

  defp created_at(%{"version" => 1, "createdAt" => value}) when is_binary(value) do
    normalized = Regex.replace(~r/([+-]\d{2})(\d{2})\z/, value, "\\1:\\2")

    case DateTime.from_iso8601(normalized) do
      {:ok, date, _} -> {:ok, date}
      _ -> {:error, :invalid_created_at}
    end
  end

  defp created_at(%{"version" => version}) when version != 1,
    do: {:error, {:invalid_version, version}}

  defp created_at(_), do: {:error, :invalid_shape}

  defp source_rows(%{"products" => rows}, :products) when is_list(rows), do: bounded_rows(rows)
  defp source_rows(%{"priceGuides" => rows}, :prices) when is_list(rows), do: bounded_rows(rows)
  defp source_rows(_, _), do: {:error, :expected_rows_array}

  defp bounded_rows(rows) do
    case length(rows) do
      count when count <= @max_source_rows -> {:ok, rows}
      count -> {:error, {:too_many_rows, count}}
    end
  end

  defp validate_rows(rows, kind), do: validate_rows(rows, kind, %{}, [])
  defp validate_rows([], _, _, acc), do: {:ok, Enum.reverse(acc)}

  defp validate_rows([row | rest], kind, ids, acc) when is_map(row) do
    with {:ok, id} <- positive_integer(row, "idProduct"),
         false <- Map.has_key?(ids, id),
         {:ok, parsed} <- validate_row(row, kind) do
      next_acc = if is_nil(parsed), do: acc, else: [parsed | acc]
      validate_rows(rest, kind, Map.put(ids, id, true), next_acc)
    else
      true -> {:error, {:duplicate_id_product, Map.get(row, "idProduct")}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_rows(_, _, _, _), do: {:error, :row_not_object}

  defp validate_row(row, :products) do
    with {:ok, category_id} <- category_id(row),
         true <- category_id == 51,
         {:ok, name} <- nonblank(row, "name"),
         {:ok, expansion} <- positive_integer(row, "idExpansion"),
         {:ok, metacard} <- nonnegative_integer(row, "idMetacard"),
         {:ok, category} <- category(row),
         {:ok, date_added} <- nonblank(row, "dateAdded") do
      {:ok,
       %Product{
         id_product: row["idProduct"],
         name: name,
         category: category,
         category_id: category_id,
         id_expansion: expansion,
         id_metacard: metacard,
         date_added: date_added
       }}
    else
      false -> {:error, :wrong_category}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_row(row, :prices) do
    with {:ok, category_id} <- category_id(row),
         true <- category_id == 51,
         {:ok, values} <- metrics(row) do
      {metric, value} = selected_metric(values)

      {:ok,
       struct(
         Price,
         Map.merge(values, %{
           id_product: row["idProduct"],
           category_id: category_id,
           selected_metric: metric,
           selected_value: value
         })
       )}
    else
      false -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp selected_metric(values) do
    Enum.find_value([:avg7, :avg30, :trend, :avg, :low], {nil, nil}, fn key ->
      value = Map.get(values, key)
      value && {key, value}
    end)
  end

  defp decode_json(body) do
    case Jason.decode(body, floats: :decimals) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp metrics(row) do
    Enum.reduce_while(@metrics, {:ok, %{}}, &metric_step(row, &1, &2))
  end

  defp metric_step(row, key, {:ok, acc}) do
    field = key |> String.replace("-", "_") |> String.to_existing_atom()

    case Map.get(row, key) do
      nil -> {:cont, {:ok, Map.put(acc, field, nil)}}
      value -> put_metric(acc, field, value)
    end
  end

  defp put_metric(acc, field, value) do
    case decimal(value) do
      {:ok, parsed} -> {:cont, {:ok, Map.put(acc, field, parsed)}}
      error -> {:halt, error}
    end
  end

  defp decimal(%Decimal{} = value) do
    cond do
      Decimal.nan?(value) or Decimal.inf?(value) -> {:error, {:invalid_number, value}}
      Decimal.compare(value, Decimal.new(0)) == :eq -> {:ok, nil}
      Decimal.compare(value, Decimal.new(0)) == :gt -> {:ok, value}
      true -> {:error, {:invalid_number, value}}
    end
  end

  defp decimal(value) when is_integer(value) and value >= 0, do: decimal(Decimal.new(value))

  defp decimal(value) when is_binary(value) do
    if String.match?(value, ~r/\A\d+(?:\.\d+)?\z/),
      do: decimal(Decimal.new(value)),
      else: {:error, {:invalid_number, value}}
  end

  defp decimal(value), do: {:error, {:invalid_number, value}}

  defp positive_integer(row, key), do: integer(row, key, &(&1 > 0))
  defp nonnegative_integer(row, key), do: integer(row, key, &(&1 >= 0))

  defp integer(row, key, predicate) do
    case Map.get(row, key) do
      value when is_integer(value) ->
        if predicate.(value), do: {:ok, value}, else: {:error, {:invalid_integer, key}}

      _ ->
        {:error, {:invalid_integer, key}}
    end
  end

  defp nonblank(row, key) do
    case Map.get(row, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:blank, key}}, else: {:ok, value}

      _ ->
        {:error, {:blank, key}}
    end
  end

  defp category(row) do
    value = Map.get(row, "categoryName") || Map.get(row, "category")

    case value do
      "Pokémon Single" = value -> {:ok, value}
      _ -> {:error, :wrong_category_name}
    end
  end

  defp category_id(row) do
    case Map.get(row, "idCategory") do
      nil -> positive_integer(row, "categoryId")
      _ -> positive_integer(row, "idCategory")
    end
  end

  defp admit(opts) do
    case Keyword.get(opts, :request_admitter, fn -> :ok end).() do
      :ok -> :ok
      {:error, _} = error -> error
      _ -> {:error, :invalid_admission_result}
    end
  rescue
    _ -> {:error, :admission_failed}
  catch
    _, _ -> {:error, :admission_failed}
  end

  defp clock(opts) do
    case Keyword.get(opts, :clock, &DateTime.utc_now/0).() do
      %DateTime{} = value -> {:ok, value}
      _ -> {:error, :invalid_clock}
    end
  catch
    _, _ -> {:error, :invalid_clock}
  end

  defp valid_options?(opts) do
    Keyword.keyword?(opts) and
      Enum.all?(Keyword.keys(opts), &(&1 in [:request_options, :request_admitter, :clock])) and
      valid_request_options?(Keyword.get(opts, :request_options, [])) and
      is_function(Keyword.get(opts, :clock, &DateTime.utc_now/0), 0) and
      is_function(Keyword.get(opts, :request_admitter, fn -> :ok end), 0)
  end

  defp valid_request_options?(options) when is_list(options) do
    Keyword.keyword?(options) and
      length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) and
      Enum.all?(
        Keyword.keys(options),
        &(&1 in [:plug, :headers, :connect_options, :receive_timeout, :request_timeout])
      )
  end

  defp valid_request_options?(_), do: false

  defp bounded_into({:data, data}, {request, response}) when is_binary(data) do
    {size, chunks} =
      case response.body do
        {n, c} -> {n, c}
        _ -> {0, []}
      end

    if size + byte_size(data) > @max_response_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: {size + byte_size(data), [data | chunks]}}}}
  end
end
