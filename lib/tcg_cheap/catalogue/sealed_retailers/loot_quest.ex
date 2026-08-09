defmodule TcgCheap.Catalogue.SealedRetailers.LootQuest do
  @moduledoc """
  Normalizes LootQuest's public WooCommerce Store API into sealed listing values.

  Live use is intentionally unconfigured until recurring collection and republication are approved.
  """

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailerAdapter

  @endpoint "https://lootquest.pl/wp-json/wc/store/v1/products"
  @category 55
  @max_listings 1_000
  @max_response_bytes 2_000_000
  @allowed [:plug, :clock, :per_page, :max_pages, :request_admitter]
  @fields "id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder"
  @excluded ~r/(japan|japoń|japons|korea|koreań|koreans|china|chiń|chins|import|single|pojedyncz|accessor|akcesori|sleeve|preorder|pre-order|backorder|przedsprzeda|przedpremier)/iu

  @impl true
  def source_key, do: "lootquest"

  @impl true
  def fetch_listings(%{source_key: "lootquest", status: "active"}, options)
      when is_list(options) do
    with :ok <- valid_options(options),
         {:ok, products} <- fetch_pages(options),
         {:ok, now} <- clock(options) do
      normalize(products, now)
    end
  end

  def fetch_listings(%{source_key: "lootquest"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}

  defp valid_options(options) do
    if Keyword.keyword?(options) and unique_keys?(options) and
         Enum.all?(Keyword.keys(options), &(&1 in @allowed)) and valid_values?(options),
       do: :ok,
       else: {:error, :invalid_options}
  end

  defp valid_values?(options) do
    per_page = Keyword.get(options, :per_page, 100)
    max_pages = Keyword.get(options, :max_pages, 10)

    valid_plug?(Keyword.get(options, :plug)) and
      valid_pagination_values?(per_page, max_pages) and
      is_function(Keyword.get(options, :clock, &DateTime.utc_now/0), 0) and
      is_function(Keyword.get(options, :request_admitter, fn -> :ok end), 0)
  end

  defp valid_pagination_values?(per_page, max_pages)
       when is_integer(per_page) and is_integer(max_pages),
       do: per_page in 1..100 and max_pages in 1..20 and per_page * max_pages <= @max_listings

  defp valid_pagination_values?(_per_page, _max_pages), do: false

  defp unique_keys?(options),
    do: length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options)))

  defp valid_plug?(nil), do: true
  defp valid_plug?(plug) when is_atom(plug), do: true
  defp valid_plug?({module, _name}) when is_atom(module), do: true
  defp valid_plug?(_), do: false

  defp clock(options) do
    case Keyword.get(options, :clock, &DateTime.utc_now/0).() do
      %DateTime{} = value -> {:ok, value}
      _ -> {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp fetch_pages(options), do: fetch_page(options, 1, nil, [])

  defp fetch_page(_options, page, total_pages, chunks)
       when is_integer(total_pages) and page > total_pages do
    {:ok, chunks |> Enum.reverse() |> Enum.flat_map(& &1)}
  end

  defp fetch_page(options, page, total_pages, chunks) do
    max_pages = Keyword.get(options, :max_pages, 10)

    with :ok <- validate_requested_page(page, max_pages),
         {:ok, products, response_pages} <- request(options, page),
         {:ok, next_pages} <- validate_pagination(total_pages, response_pages, max_pages),
         :ok <- validate_page_products(products, Keyword.get(options, :per_page, 100)) do
      fetch_page(options, page + 1, next_pages, [products | chunks])
    end
  end

  defp validate_requested_page(page, max_pages) when page <= max_pages, do: :ok
  defp validate_requested_page(_page, _max_pages), do: {:error, :max_pages_exceeded}

  defp validate_pagination(total_pages, response_pages, max_pages)
       when is_integer(response_pages) do
    if is_nil(total_pages) do
      if response_pages in 1..max_pages,
        do: {:ok, response_pages},
        else: {:error, :invalid_pagination}
    else
      if response_pages == total_pages,
        do: {:ok, total_pages},
        else: {:error, :pagination_changed}
    end
  end

  defp validate_page_products(products, per_page)
       when is_list(products) and products != [] and length(products) <= per_page,
       do: :ok

  defp validate_page_products([], _per_page), do: {:error, :malformed_pagination}

  defp validate_page_products(products, per_page)
       when is_list(products) and length(products) > per_page,
       do: {:error, :malformed_pagination}

  defp validate_page_products(_products, _per_page), do: {:error, :malformed_shape}

  defp request(options, page) do
    req = [
      url: @endpoint,
      params: [
        category: @category,
        page: page,
        per_page: Keyword.get(options, :per_page, 100),
        _fields: @fields
      ],
      decode_body: false,
      into: &bounded_into/2,
      connect_options: [timeout: 5_000],
      receive_timeout: 10_000,
      request_timeout: 15_000,
      redirect: false,
      retry: false
    ]

    req = if options[:plug], do: Keyword.put(req, :plug, options[:plug]), else: req

    with :ok <- admit_request(options) do
      case Req.request(req) do
        {:ok, response} -> handle_response(response)
        {:error, reason} -> {:error, {:transport_error, reason}}
      end
    end
  end

  defp admit_request(options) do
    case Keyword.get(options, :request_admitter, fn -> :ok end).() do
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

  defp bounded_into({:data, data}, {request, response}) when is_binary(data) do
    {size, chunks} = body_chunks(response.body)

    if size + byte_size(data) > @max_response_bytes do
      {:halt, {request, %{response | body: :too_large}}}
    else
      {:cont, {request, %{response | body: {size + byte_size(data), [data | chunks]}}}}
    end
  end

  defp body_chunks({size, chunks}) when is_integer(size) and is_list(chunks), do: {size, chunks}
  defp body_chunks(_initial_body), do: {0, []}

  defp handle_response(%{status: 200, body: :too_large}), do: {:error, :response_too_large}

  defp handle_response(%{status: 200, body: body, headers: headers}) do
    with {:ok, body} <- response_body(body),
         {:ok, payload} <- decode(body),
         {:ok, total_pages} <- wp_total_pages(headers) do
      {:ok, payload, total_pages}
    end
  end

  defp handle_response(%{status: 429, headers: headers}) do
    {:error, {:rate_limited, %{status: 429, retry_after_seconds: retry_after_seconds(headers)}}}
  end

  defp handle_response(%{status: status}) when is_integer(status),
    do: {:error, {:http_error, %{status: status}}}

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, payload} -> {:ok, payload}
      {:error, _error} -> {:error, :malformed_json}
    end
  end

  defp response_body({size, chunks}) when is_integer(size) and is_list(chunks),
    do: {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

  defp response_body(body) when is_binary(body), do: {:ok, body}
  defp response_body(_body), do: {:error, :malformed_shape}

  defp wp_total_pages(headers) when is_map(headers) do
    value = headers["x-wp-totalpages"] || headers["X-WP-TotalPages"]

    case value do
      [value | _] -> parse_total_pages(value)
      value when is_binary(value) -> parse_total_pages(value)
      _ -> {:error, :malformed_pagination}
    end
  end

  defp retry_after_seconds(headers) when is_map(headers) do
    case headers["retry-after"] do
      [value | _] -> bounded_seconds(value)
      value when is_binary(value) -> bounded_seconds(value)
      _ -> nil
    end
  end

  defp bounded_seconds(value) do
    case Integer.parse(String.trim(value)) do
      {seconds, ""} when seconds in 1..3_600 -> seconds
      _ -> nil
    end
  end

  defp parse_total_pages(value) do
    case Integer.parse(String.trim(value)) do
      {pages, ""} when pages > 0 -> {:ok, pages}
      _ -> {:error, :malformed_pagination}
    end
  end

  defp normalize(products, now) do
    products
    |> Enum.reduce_while({:ok, []}, fn product, {:ok, acc} ->
      case normalize_product(product, now) do
        :skip -> {:cont, {:ok, acc}}
        {:ok, listing} -> {:cont, {:ok, [listing | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, listings} -> {:ok, Enum.reverse(listings)}
      error -> error
    end
  end

  defp normalize_product(%{"is_on_backorder" => true}, _now), do: :skip

  defp normalize_product(%{"is_on_backorder" => false} = product, now) do
    with {:ok, id} <- positive_id(product["id"]),
         {:ok, title} <- product_name(product["name"]),
         {:ok, url} <- canonical_url(product["permalink"]),
         {:ok, true} <- eligibility(title, product["categories"], product["tags"]),
         {:ok, price} <- price(product["prices"]),
         {:ok, stock} <- stock(product) do
      attrs = %SealedRetailerAdapter.Listing{
        source_listing_id: Integer.to_string(id),
        source_title: title,
        direct_url: url,
        current_price_pln: price,
        currency: "PLN",
        stock_status: stock,
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now,
        source_payload:
          Map.take(product, [
            "id",
            "name",
            "permalink",
            "prices",
            "categories",
            "tags",
            "is_purchasable",
            "is_in_stock",
            "is_on_backorder"
          ])
      }

      SealedRetailerAdapter.new(Map.from_struct(attrs))
    else
      {:ok, false} -> :skip
      _ -> {:error, :malformed_shape}
    end
  end

  defp normalize_product(_, _), do: {:error, :malformed_shape}
  defp positive_id(id) when is_integer(id) and id > 0, do: {:ok, id}
  defp positive_id(_), do: {:error, :malformed_shape}

  defp product_name(name) when is_binary(name) do
    value = name |> html_decode() |> String.trim()
    if value == "", do: {:error, :malformed_shape}, else: {:ok, value}
  end

  defp product_name(_), do: {:error, :malformed_shape}

  defp html_decode(value) do
    value =
      Regex.replace(~r/&#x([0-9a-f]+);/i, value, fn entity, digits ->
        codepoint(entity, digits, 16)
      end)

    value =
      Regex.replace(~r/&#([0-9]+);/, value, fn entity, digits -> codepoint(entity, digits, 10) end)

    value = String.replace(value, "&amp;", "&")
    value = String.replace(value, "&quot;", "\"")
    value = String.replace(value, "&apos;", "'")
    value = String.replace(value, "&#039;", "'")
    value = String.replace(value, "&lt;", "<")
    value = String.replace(value, "&gt;", ">")
    String.replace(value, "&nbsp;", " ")
  end

  defp codepoint(entity, digits, base) do
    case Integer.parse(digits, base) do
      {value, ""} when value in 0x20..0xD7FF -> <<value::utf8>>
      {value, ""} when value in 0xE000..0x10FFFF -> <<value::utf8>>
      _ -> entity
    end
  end

  defp canonical_url(url) when is_binary(url) do
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host == "lootquest.pl" and uri.authority == uri.host and
         is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
         is_binary(uri.path) and
         Regex.match?(~r|^/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/$|, uri.path),
       do: {:ok, url},
       else: {:error, :invalid_url}
  end

  defp canonical_url(_), do: {:error, :invalid_url}

  defp eligibility(title, categories, tags) do
    with {:ok, category_slugs} <- slugs(categories),
         {:ok, tag_slugs} <- slugs(tags) do
      sealed_category? =
        Enum.any?(
          category_slugs,
          &(&1 in [
              "pokemon-boostery",
              "pokemon-blistry",
              "pokemon-zestawy",
              "pokemon-talie"
            ])
        )

      excluded? =
        Regex.match?(@excluded, title <> " " <> Enum.join(category_slugs ++ tag_slugs, " "))

      {:ok, sealed_category? and not excluded?}
    end
  end

  defp slugs(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn
      %{"slug" => slug}, {:ok, acc} when is_binary(slug) and slug != "" ->
        {:cont, {:ok, [String.downcase(slug) | acc]}}

      _, _acc ->
        {:halt, {:error, :malformed_shape}}
    end)
  end

  defp slugs(_values), do: {:error, :malformed_shape}

  defp price(%{"price" => value, "currency_code" => "PLN", "currency_minor_unit" => unit})
       when is_binary(value) and is_integer(unit) and unit in 0..4 do
    case Integer.parse(value) do
      {minor, ""} when minor > 0 ->
        {:ok, Decimal.div(Decimal.new(minor), scale(unit))}

      _ ->
        {:error, :malformed_price}
    end
  end

  defp price(_), do: {:error, :malformed_price}

  defp scale(unit),
    do:
      Enum.reduce(List.duplicate(:ten, unit), Decimal.new(1), fn _, acc ->
        Decimal.mult(acc, Decimal.new(10))
      end)

  defp stock(%{"is_purchasable" => true, "is_in_stock" => true, "is_on_backorder" => false}),
    do: {:ok, "in_stock"}

  defp stock(%{"is_in_stock" => false}), do: {:ok, "sold_out"}
  defp stock(_), do: {:ok, "unknown"}
end
