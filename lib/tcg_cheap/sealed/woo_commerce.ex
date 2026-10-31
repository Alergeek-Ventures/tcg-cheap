defmodule TcgCheap.Sealed.WooCommerce do
  @moduledoc """
  Reads the public WooCommerce Store API of a shop
  (`/wp-json/wc/store/v1/products`), limited to the shop's Pokémon `category`
  ids and at most `max_pages` pages of 100 products.

  A product counts as sealed when it is in one of the shop's
  `sealed_categories`, or, for a shop without curated sealed categories, when
  its title names a sealed product (`TcgCheap.Sealed.Matcher.sealed_title?/1`).
  Its permalink must be on the shop's host and match `product_path`, and its
  price must be in PLN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Matcher, Shop, ShopFeed}

  @per_page 100
  @fields "id,name,permalink,prices,categories,images,sku,is_purchasable,is_in_stock,is_on_backorder"

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- fetch_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(_shop, _req_options, page, total, acc)
       when is_integer(total) and page > total,
       do: {:ok, acc |> Enum.reverse() |> List.flatten()}

  defp fetch_pages(shop, req_options, page, total, acc) do
    with {:ok, products, page_total} <- request(shop, req_options, page),
         :ok <- check_total(shop, total, page_total) do
      fetch_pages(shop, req_options, page + 1, page_total, [products | acc])
    end
  end

  defp check_total(%Shop{max_pages: max}, _total, page_total) when page_total > max,
    do: {:error, :too_many_pages}

  defp check_total(_shop, nil, _page_total), do: :ok
  defp check_total(_shop, total, total), do: :ok
  defp check_total(_shop, _total, _page_total), do: {:error, :pagination_changed}

  defp request(shop, req_options, page) do
    params = [category: shop.category, page: page, per_page: @per_page, _fields: @fields]

    with {:ok, response} <-
           ShopFeed.get(shop, "/wp-json/wc/store/v1/products", params, req_options),
         {:ok, products} when is_list(products) <- ShopFeed.decode(response),
         {:ok, total} <- total_pages(response) do
      {:ok, products, total}
    else
      {:ok, _not_a_list} -> {:error, :malformed_response}
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

  defp normalize(shop, %{} = product) do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         true <- sealed?(shop, product["categories"], title) || :ignore,
         {:ok, id} <- product_id(product["id"]),
         {:ok, url} <- product_url(shop, product["permalink"]),
         {:ok, price} <- price(product["prices"]) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product["images"]),
           ean: Ean.normalize(product["sku"]),
           price: price,
           in_stock: in_stock?(product)
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  defp sealed?(%Shop{sealed_categories: nil}, _categories, title),
    do: Matcher.sealed_title?(title)

  defp sealed?(shop, categories, _title) when is_list(categories) do
    Enum.any?(categories, fn
      %{"slug" => slug} when is_binary(slug) -> String.downcase(slug) in shop.sealed_categories
      _ -> false
    end)
  end

  defp sealed?(_shop, _categories, _title), do: false

  defp product_id(id) when is_integer(id) and id > 0, do: {:ok, Integer.to_string(id)}
  defp product_id(_id), do: :error

  defp product_url(shop, url) do
    with {:ok, uri} <- ShopFeed.https_url(url, [shop.host]),
         true <- is_nil(uri.query) and Regex.match?(shop.product_path, uri.path) do
      {:ok, url}
    else
      _ -> :error
    end
  end

  defp image_url(shop, [%{"src" => src} | _]), do: ShopFeed.image_url(src, image_hosts(shop))
  defp image_url(_shop, _images), do: nil

  defp price(%{"price" => value, "currency_code" => "PLN", "currency_minor_unit" => unit})
       when is_binary(value) and is_integer(unit) and unit in 0..4 do
    case Integer.parse(value) do
      {minor, ""} when minor > 0 ->
        ShopFeed.price(Decimal.div(Decimal.new(minor), Decimal.new(Integer.pow(10, unit))))

      _ ->
        :error
    end
  end

  defp price(_prices), do: :error

  defp in_stock?(product) do
    product["is_in_stock"] == true and product["is_purchasable"] == true and
      product["is_on_backorder"] == false
  end
end
