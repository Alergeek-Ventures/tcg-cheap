defmodule TcgCheap.Pricing.CardmarketBulk.Adapter do
  @moduledoc """
  Downloads and validates Cardmarket's public Pokémon files: the singles
  product list, the sealed (non-singles) product list and the price guide.

  Every download has a body size limit, short timeouts and no redirects or
  retries. A file is accepted only when its JSON, version, creation time and
  every row are valid and no product id repeats; otherwise the result is an
  `{:error, reason}` tuple. An accepted file is a `t:t/0`: its creation time
  and its rows (`Product` or `Price` structs).

  The only option is `:request_options`, a keyword list limited to the `Req`
  options `:plug`, `:headers`, `:connect_options`, `:receive_timeout` and
  `:request_timeout`.
  """

  @products_url "https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_6.json"
  @sealed_products_url "https://downloads.s3.cardmarket.com/productCatalog/productList/products_nonsingles_6.json"
  @prices_url "https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_6.json"
  @max_response_bytes 32 * 1024 * 1024
  @max_source_rows 100_000
  # Cardmarket's category id of Pokémon single cards.
  @singles_category 51
  @metrics ~w(avg low trend avg1 avg7 avg30 avg-holo low-holo trend-holo avg1-holo avg7-holo avg30-holo)
  @malformed_provider_response {:error, {:malformed, :invalid_content_type}}
  @json_content_type ~r/\Aapplication\/json(?:\s*;\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+\s*=\s*(?:"(?:[^"\\]|\\.)*"|[!#$%&'*+\-.^_`|~0-9A-Za-z]+))*\z/i
  @compact_utc_offset ~r/([+-]\d{2})(\d{2})\z/
  @decimal_string ~r/\A\d+(?:\.\d+)?\z/

  defstruct [:created_at, :rows]

  @type t :: %__MODULE__{
          created_at: DateTime.t(),
          rows: [__MODULE__.Product.t()] | [__MODULE__.Price.t()]
        }

  defmodule Product do
    @moduledoc "A validated Cardmarket product row."
    @type t :: %__MODULE__{}

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
    @moduledoc "A validated Cardmarket price guide row; a metric Cardmarket lists as 0 is nil."
    @type t :: %__MODULE__{}

    defstruct [
      :id_product,
      :category_id,
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

  @doc "The category id of Pokémon single cards in Cardmarket's files."
  def singles_category, do: @singles_category

  @doc "Fetch and parse the Cardmarket singles product file."
  def fetch_products(opts \\ []), do: fetch(@products_url, :products, opts)

  @doc "Fetch and parse the Cardmarket sealed (non-singles) product file."
  def fetch_sealed_products(opts \\ []), do: fetch(@sealed_products_url, :sealed_products, opts)

  @doc "Fetch and parse the Cardmarket price guide with every row, singles and sealed products alike."
  def fetch_all_prices(opts \\ []), do: fetch(@prices_url, :prices, opts)

  defp fetch(url, kind, opts) when is_list(opts) do
    if valid_options?(opts) do
      with {:ok, response} <- request(url, opts),
           {:ok, body} <- response_body(response) do
        parse(body, kind)
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
      [value] when is_binary(value) -> Regex.match?(@json_content_type, value)
      _ -> false
    end
  end

  defp parse(body, _kind) when byte_size(body) > @max_response_bytes,
    do: {:error, {:oversized, @max_response_bytes}}

  defp parse(body, kind) do
    case decode_json(body) do
      {:error, reason} -> {:error, reason}
      {:ok, decoded} -> parse_decoded(decoded, kind)
    end
  rescue
    _ -> {:error, {:malformed, :invalid_body}}
  end

  defp parse_decoded(decoded, kind) do
    with {:ok, created_at} <- created_at(decoded),
         {:ok, source} <- source_rows(decoded, kind),
         {:ok, rows} <- validate_rows(source, kind) do
      {:ok, %__MODULE__{created_at: created_at, rows: rows}}
    else
      {:error, reason} -> {:error, {:malformed, reason}}
    end
  end

  defp created_at(%{"version" => 1, "createdAt" => value}) when is_binary(value) do
    normalized = Regex.replace(@compact_utc_offset, value, "\\1:\\2")

    case DateTime.from_iso8601(normalized) do
      {:ok, date, _} -> {:ok, date}
      _ -> {:error, :invalid_created_at}
    end
  end

  defp created_at(%{"version" => version}) when version != 1,
    do: {:error, {:invalid_version, version}}

  defp created_at(_), do: {:error, :invalid_shape}

  defp source_rows(%{"products" => rows}, kind)
       when is_list(rows) and kind in [:products, :sealed_products],
       do: bounded_rows(rows)

  defp source_rows(%{"priceGuides" => rows}, kind)
       when is_list(rows) and kind == :prices,
       do: bounded_rows(rows)

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
      validate_rows(rest, kind, Map.put(ids, id, true), [parsed | acc])
    else
      true -> {:error, {:duplicate_id_product, Map.get(row, "idProduct")}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_rows(_, _, _, _), do: {:error, :row_not_object}

  defp validate_row(row, :products) do
    with {:ok, category_id} <- category_id(row),
         true <- category_id == @singles_category,
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

  defp validate_row(row, :sealed_products) do
    with {:ok, category_id} <- category_id(row),
         true <- category_id != @singles_category,
         {:ok, name} <- nonblank(row, "name"),
         {:ok, expansion} <- nonnegative_integer(row, "idExpansion"),
         {:ok, metacard} <- nonnegative_integer(row, "idMetacard"),
         {:ok, category} <- nonblank(row, "categoryName"),
         {:ok, date_added} <- nonblank(row, "dateAdded") do
      {:ok,
       %Product{
         id_product: row["idProduct"],
         name: unescape_quotes(name),
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
         {:ok, values} <- metrics(row) do
      {:ok,
       struct(Price, Map.merge(values, %{id_product: row["idProduct"], category_id: category_id}))}
    end
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
    if String.match?(value, @decimal_string),
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

  # The sealed catalogue keeps CSV quote escaping in its JSON names:
  # `WCD 2025: Liao Fu Guan ""Joltdengo""`.
  defp unescape_quotes(name), do: String.replace(name, ~s(""), ~s("))

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

  defp valid_options?(opts) do
    Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 == :request_options)) and
      valid_request_options?(Keyword.get(opts, :request_options, []))
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
