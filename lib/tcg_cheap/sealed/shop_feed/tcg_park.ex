defmodule TcgCheap.Sealed.ShopFeed.TcgPark do
  @moduledoc """
  Reads TCG Park's server-rendered Next.js category (`feed_path`), whose
  `__NEXT_DATA__` holds twelve products and an `offsetPagination` block.
  Consecutive `?page=N` pages must make up the stated total of unique products
  and agree with the first one about that total. A partial listing fails.

  The shop's categories include accessories and repacks, so a title must name
  sealed Pokémon (`ShopFeed.sealed_pokemon?/2`). A product marked as a pre-order
  never counts as in stock. Prices are in euro; links are relative to the shop
  and images come from its separate WordPress API host. The listing has no EAN.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}

  @page_size 12
  @image_host "api.tcgpark.com"

  @impl true
  def image_hosts(_shop), do: [@image_host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- read_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp read_pages(shop, req_options, number, stated_total, acc) do
    with {:ok, page} <- request(shop, req_options, number),
         :ok <- check_page(shop.max_pages, number, stated_total, page) do
      products = [page.products | acc]
      total = page.total

      if page.has_more do
        read_pages(shop, req_options, number + 1, total, products)
      else
        complete(Enum.reverse(products) |> List.flatten(), total)
      end
    end
  end

  defp check_page(max_pages, number, total, page) do
    cond do
      number > max_pages ->
        {:error, :too_many_pages}

      total != nil and total != page.total ->
        {:error, :pagination_changed}

      page.products not in [[], nil] ->
        :ok

      page.total > 0 and number <= div(page.total + @page_size - 1, @page_size) ->
        {:error, :malformed_listing}

      true ->
        :ok
    end
  end

  defp complete(products, total) do
    if length(Enum.uniq_by(products, & &1["databaseId"])) == total,
      do: {:ok, products},
      else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: number], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, data} <- next_data(document) do
      page(data)
    end
  end

  defp page(%{
         "products" => %{
           "nodes" => nodes,
           "pageInfo" => %{"offsetPagination" => %{"total" => total, "hasMore" => has_more}}
         }
       })
       when is_list(nodes) and is_integer(total) and total >= 0 and is_boolean(has_more),
       do: {:ok, %{products: nodes, total: total, has_more: has_more}}

  defp page(_data), do: {:error, :malformed_pagination}

  defp next_data(document) do
    document
    |> Floki.find("script#__NEXT_DATA__")
    |> Enum.map(&Floki.text(&1, js: true))
    |> Enum.find_value({:error, :malformed_response}, fn json ->
      case Jason.decode(json) do
        {:ok, %{"props" => %{"pageProps" => %{"initialData" => %{} = initial}}}} ->
          {:ok, initial}

        _ ->
          nil
      end
    end)
  end

  defp normalize(shop, %{} = product) do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         true <- ShopFeed.sealed_pokemon?(title, "Pokemon") || :ignore,
         {:ok, id} <- product_id(product["databaseId"]),
         {:ok, url} <- product_url(shop, product["uri"]),
         {:ok, price} <- ShopFeed.decimal_price(product["price"]),
         {:ok, in_stock} <- stock(product) do
      preorder = Matcher.preorder_title?(title) or pre_order?(product)

      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(product),
           ean: nil,
           price: price,
           in_stock: in_stock and not preorder,
           preorder: preorder
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp product_id(id) when is_integer(id) and id > 0,
    do: ShopFeed.product_id(Integer.to_string(id))

  defp product_id(_id), do: :error

  defp product_url(shop, "/" <> _rest = path) do
    with {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}#{path}", [shop.host]),
         true <- Regex.match?(~r|\A/izdelek/[a-z0-9-]+/\z|, uri.path) and is_nil(uri.query) do
      {:ok, "https://#{shop.host}/si#{String.trim_trailing(uri.path, "/")}"}
    else
      _ -> :error
    end
  end

  defp product_url(_shop, _path), do: :error

  defp image_url(%{"featuredImage" => %{"node" => %{"sourceUrl" => url}}}),
    do: ShopFeed.image_url(url, [@image_host])

  defp image_url(_product), do: nil

  defp stock(%{"stockStatus" => "IN_STOCK", "stockQuantity" => quantity})
       when is_integer(quantity) and quantity > 0,
       do: {:ok, true}

  defp stock(%{"stockStatus" => status})
       when status in ["OUT_OF_STOCK", "ON_BACKORDER"],
       do: {:ok, false}

  defp stock(_product), do: :error

  defp pre_order?(%{"preOrderDetails" => details}) when is_map(details), do: true
  defp pre_order?(_product), do: false
end
