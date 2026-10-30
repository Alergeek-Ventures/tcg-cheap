defmodule TcgCheap.Sealed.WooCommerce do
  @moduledoc """
  A small client for the public WooCommerce Store API of a configured shop.

  Requests go only to the shop's fixed HTTPS host, follow no redirects, read at
  most `max_pages` pages and at most 2 MB per page. Every product field is
  untrusted: products with an invalid id, title, permalink or price are
  skipped, and only products in the shop's sealed categories are returned.
  Any transport, status, pagination or shape problem fails the whole fetch so
  that a partial catalogue is never mistaken for a complete one.
  """

  require Logger

  alias TcgCheap.Sealed.Shop

  @per_page 100
  @max_body_bytes 2_000_000
  @max_title_length 300
  @max_url_length 2_000
  @max_price_minor 100_000_000
  @fields "id,name,permalink,prices,categories,images,sku,is_purchasable,is_in_stock,is_on_backorder"

  @type offer :: %{
          shop_product_id: String.t(),
          title: String.t(),
          url: String.t(),
          image_url: String.t() | nil,
          ean: String.t() | nil,
          price: Decimal.t(),
          in_stock: boolean()
        }

  @doc """
  Fetches every sealed product currently listed by `shop`.

  Options: `:plug` (a `Req.Test` stub in tests) and `:per_page`.
  """
  @spec fetch(Shop.t(), keyword()) :: {:ok, [offer()]} | {:error, term()}
  def fetch(%Shop{} = shop, opts \\ []) do
    with {:ok, products} <- fetch_pages(shop, opts, 1, nil, []) do
      {offers, skipped} = normalize(shop, products)

      if skipped > 0,
        do: Logger.warning("sealed fetch #{shop.key}: skipped #{skipped} invalid products")

      {:ok, offers}
    end
  end

  defp fetch_pages(_shop, _opts, page, total, acc) when is_integer(total) and page > total,
    do: {:ok, acc |> Enum.reverse() |> List.flatten()}

  defp fetch_pages(shop, opts, page, total, acc) do
    with {:ok, products, page_total} <- request(shop, opts, page),
         :ok <- check_total(shop, total, page_total) do
      fetch_pages(shop, opts, page + 1, page_total, [products | acc])
    end
  end

  defp check_total(%Shop{max_pages: max}, _total, page_total) when page_total > max,
    do: {:error, :too_many_pages}

  defp check_total(_shop, nil, _page_total), do: :ok
  defp check_total(_shop, total, total), do: :ok
  defp check_total(_shop, _total, _page_total), do: {:error, :pagination_changed}

  defp request(shop, opts, page) do
    request =
      Req.new(
        url: "https://#{shop.host}/wp-json/wc/store/v1/products",
        params: [
          category: shop.category,
          page: page,
          per_page: Keyword.get(opts, :per_page, @per_page),
          _fields: @fields
        ],
        headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}],
        decode_body: false,
        into: &bounded_body/2,
        connect_options: [timeout: 5_000],
        receive_timeout: 15_000,
        redirect: false,
        retry: false
      )
      |> maybe_plug(opts[:plug])

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: :too_large}} -> {:error, :response_too_large}
      {:ok, %Req.Response{status: 200} = response} -> decode(response)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:transport, exception.__struct__}}
    end
  end

  defp maybe_plug(request, nil), do: request
  defp maybe_plug(request, plug), do: Req.merge(request, plug: plug)

  defp bounded_body({:data, data}, {request, response}) do
    body = if is_binary(response.body), do: response.body, else: ""

    if byte_size(body) + byte_size(data) > @max_body_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body <> data}}}
  end

  defp decode(%Req.Response{body: body} = response) do
    with {:ok, products} when is_list(products) <- Jason.decode(body),
         {:ok, total} <- total_pages(response) do
      {:ok, products, total}
    else
      {:ok, _not_a_list} -> {:error, :malformed_response}
      {:error, %Jason.DecodeError{}} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp total_pages(response) do
    with [value | _] <- Req.Response.get_header(response, "x-wp-totalpages"),
         {pages, ""} when pages >= 1 <- Integer.parse(String.trim(value)) do
      {:ok, pages}
    else
      _ -> {:error, :malformed_pagination}
    end
  end

  defp normalize(shop, products) do
    Enum.reduce(products, {[], 0}, fn product, {offers, skipped} ->
      case normalize_product(shop, product) do
        {:ok, offer} -> {[offer | offers], skipped}
        :ignore -> {offers, skipped}
        :invalid -> {offers, skipped + 1}
      end
    end)
    |> then(fn {offers, skipped} -> {offers |> Enum.reverse() |> unique_ids(), skipped} end)
  end

  defp unique_ids(offers), do: Enum.uniq_by(offers, & &1.shop_product_id)

  defp normalize_product(shop, %{} = product) do
    with true <- sealed_category?(shop, product["categories"]) || :ignore,
         {:ok, id} <- product_id(product["id"]),
         {:ok, title} <- title(product["name"]),
         {:ok, url} <- shop_url(shop, product["permalink"], :product),
         {:ok, price} <- price(product["prices"]) do
      {:ok,
       %{
         shop_product_id: id,
         title: title,
         url: url,
         image_url: image_url(shop, product["images"]),
         ean: ean(product["sku"]),
         price: price,
         in_stock: in_stock?(product)
       }}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize_product(_shop, _product), do: :invalid

  defp sealed_category?(shop, categories) when is_list(categories) do
    Enum.any?(categories, fn
      %{"slug" => slug} when is_binary(slug) -> String.downcase(slug) in shop.sealed_categories
      _ -> false
    end)
  end

  defp sealed_category?(_shop, _categories), do: false

  defp product_id(id) when is_integer(id) and id > 0, do: {:ok, Integer.to_string(id)}
  defp product_id(_id), do: :error

  defp title(name) when is_binary(name) do
    title = name |> html_decode() |> String.replace(~r/\s+/u, " ") |> String.trim()

    if String.valid?(title) and String.length(title) in 1..@max_title_length,
      do: {:ok, title},
      else: :error
  end

  defp title(_name), do: :error

  @entities %{
    "amp" => "&",
    "quot" => "\"",
    "apos" => "'",
    "lt" => "<",
    "gt" => ">",
    "nbsp" => " ",
    "ndash" => "–",
    "mdash" => "—",
    "rsquo" => "’",
    "lsquo" => "‘",
    "rdquo" => "”",
    "ldquo" => "“",
    "bdquo" => "„",
    "hellip" => "…"
  }

  defp html_decode(value) do
    Regex.replace(~r/&(#x[0-9a-f]{1,6}|#[0-9]{1,7}|[a-z]{2,8});/i, value, fn entity, code ->
      decode_entity(entity, code)
    end)
  end

  defp decode_entity(entity, "#x" <> hex), do: codepoint(entity, Integer.parse(hex, 16))
  defp decode_entity(entity, "#X" <> hex), do: codepoint(entity, Integer.parse(hex, 16))
  defp decode_entity(entity, "#" <> dec), do: codepoint(entity, Integer.parse(dec))
  defp decode_entity(entity, name), do: Map.get(@entities, String.downcase(name), entity)

  defp codepoint(_entity, {value, ""}) when value in 0x20..0xD7FF or value in 0xE000..0x10FFFF,
    do: <<value::utf8>>

  defp codepoint(entity, _parsed), do: entity

  defp shop_url(shop, url, kind) when is_binary(url) and byte_size(url) <= @max_url_length do
    uri = URI.parse(url)

    if on_shop_host?(shop, uri, url) and path_allowed?(shop, uri, kind),
      do: {:ok, url},
      else: :error
  end

  defp shop_url(_shop, _url, _kind), do: :error

  defp on_shop_host?(shop, uri, url) do
    uri.scheme == "https" and uri.host == shop.host and uri.port == 443 and
      is_nil(uri.userinfo) and is_nil(uri.fragment) and is_binary(uri.path) and
      String.match?(url, ~r/\Ahttps:\/\/[^\s]+\z/)
  end

  defp path_allowed?(shop, uri, :product),
    do: is_nil(uri.query) and Regex.match?(shop.product_path, uri.path)

  defp path_allowed?(_shop, _uri, :image), do: true

  defp image_url(shop, [%{"src" => src} | _]) do
    case shop_url(shop, src, :image) do
      {:ok, url} -> url
      :error -> nil
    end
  end

  defp image_url(_shop, _images), do: nil

  defp price(%{"price" => value, "currency_code" => "PLN", "currency_minor_unit" => unit})
       when is_binary(value) and is_integer(unit) and unit in 0..4 do
    case Integer.parse(value) do
      {minor, ""} when minor > 0 and minor <= @max_price_minor ->
        {:ok, Decimal.div(Decimal.new(minor), Decimal.new(Integer.pow(10, unit)))}

      _ ->
        :error
    end
  end

  defp price(_prices), do: :error

  # A 12- or 13-digit SKU counts as an EAN only when its GS1 check digit is right.
  defp ean(sku) when is_binary(sku) do
    code =
      case String.trim(sku) do
        <<_::binary-size(12)>> = code -> "0" <> code
        code -> code
      end

    if String.match?(code, ~r/\A[0-9]{13}\z/) and check_digit_valid?(code), do: code
  end

  defp ean(_sku), do: nil

  defp check_digit_valid?(code) do
    digits = code |> String.graphemes() |> Enum.map(&String.to_integer/1)

    sum =
      digits
      |> Enum.with_index()
      |> Enum.map(fn {digit, index} -> if rem(index, 2) == 1, do: digit * 3, else: digit end)
      |> Enum.sum()

    rem(sum, 10) == 0
  end

  defp in_stock?(product) do
    product["is_in_stock"] == true and product["is_purchasable"] == true and
      product["is_on_backorder"] == false
  end
end
