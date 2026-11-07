defmodule TcgCheap.Sealed.WooCommerce do
  @moduledoc """
  Reads the public WooCommerce Store API of a shop
  (`/wp-json/wc/store/v1/products`), limited to the shop's Pokémon `category`
  ids and at most `max_pages` pages of 100 products.

  A product counts as sealed when it is in one of the shop's
  `sealed_categories`, or, for a shop without curated sealed categories, when
  its title names a sealed product (`TcgCheap.Sealed.Matcher.sealed_title?/1`).
  Every product of the shop's `singles_categories` (category ids, requested
  separately, subcategories included, at most 80 pages instead of
  `max_pages`) is a single, priced with a 0.10 minimum; its category is the
  name of its first category. Its permalink must be on the shop's host and
  match `product_path`, and its price must be in the shop's `currency`. Its image is the Store API's `src`, the full upload,
  except where a plugin has swapped in a smaller copy (see `with_originals/3`).
  See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  require Logger

  alias TcgCheap.Sealed.{Ean, Matcher, Shop, ShopFeed}

  @per_page 100
  # Singles categories run far longer than sealed ones (Kolekcjoner Kart: 41
  # pages in November 2026); a page takes 1.5–2.5 s with the pause, so 80
  # stay within the job's 5-minute timeout.
  @max_singles_pages 80
  @fields "id,name,permalink,prices,categories,images,sku,is_purchasable,is_in_stock,is_on_backorder"

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, sealed} <- products(shop, sealed_category(shop), shop.max_pages, req_options),
         {:ok, singles} <-
           products(shop, singles_category(shop), @max_singles_pages, req_options) do
      products = Enum.map(sealed, &{:sealed, &1}) ++ Enum.map(singles, &{:single, &1})
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp sealed_category(%Shop{singles_only: true}), do: nil
  defp sealed_category(shop), do: shop.category

  defp singles_category(%Shop{singles_categories: nil}), do: nil
  defp singles_category(shop), do: Enum.join(shop.singles_categories, ",")

  defp products(_shop, nil, _max_pages, _req_options), do: {:ok, []}

  defp products(shop, category, max_pages, req_options),
    do: fetch_pages(shop, category, max_pages, req_options, 1, nil, [])

  defp fetch_pages(_shop, _category, _max_pages, _req_options, page, total, acc)
       when is_integer(total) and page > total,
       do: {:ok, acc |> Enum.reverse() |> List.flatten()}

  defp fetch_pages(shop, category, max_pages, req_options, page, total, acc) do
    with {:ok, products, page_total} <- request(shop, category, req_options, page),
         :ok <- check_total(max_pages, total, page_total) do
      fetch_pages(shop, category, max_pages, req_options, page + 1, page_total, [products | acc])
    end
  end

  defp check_total(max_pages, _total, page_total) when page_total > max_pages,
    do: {:error, :too_many_pages}

  defp check_total(_max_pages, nil, _page_total), do: :ok
  defp check_total(_max_pages, total, total), do: :ok
  defp check_total(_max_pages, _total, _page_total), do: {:error, :pagination_changed}

  defp request(shop, category, req_options, page) do
    params = [category: category, page: page, per_page: @per_page, _fields: @fields]

    with {:ok, response} <-
           ShopFeed.get(shop, "/wp-json/wc/store/v1/products", params, req_options),
         {:ok, products} when is_list(products) <- ShopFeed.decode(response),
         {:ok, total} <- total_pages(response) do
      {:ok, with_originals(shop, products, req_options), total}
    else
      {:ok, _not_a_list} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  # A WebP plugin on some shops (gralnia.org) replaces every image with a
  # 450 px `webp-450/<attachment id>.webp` copy, and the Store API reports only
  # that. The uploads the copies were made from are looked up in the WordPress
  # media API, one request for the page's images; when it fails, the copies stay.
  @webp_copy ~r|\A/wp-content/uploads/webp-[0-9]{1,4}/([0-9]{1,12})\.webp\z|

  defp with_originals(shop, products, req_options) do
    ids =
      for %{"images" => [%{"id" => id, "src" => src} | _]} <- products,
          webp_copy?(src, id),
          uniq: true,
          do: id

    with [_ | _] <- ids,
         {:ok, originals} <- originals(shop, ids, req_options) do
      Enum.map(products, &put_original(&1, originals))
    else
      [] ->
        products

      {:error, reason} ->
        Logger.warning("sealed fetch #{shop.key}: original images not found: #{inspect(reason)}")
        products
    end
  end

  defp webp_copy?(src, id) when is_binary(src) and is_integer(id) do
    case Regex.run(@webp_copy, URI.parse(src).path || "") do
      [_, copy_id] -> copy_id == Integer.to_string(id)
      nil -> false
    end
  end

  defp webp_copy?(_src, _id), do: false

  defp originals(shop, ids, req_options) do
    params = [include: Enum.join(ids, ","), per_page: @per_page, _fields: "id,source_url"]

    with {:ok, response} <- ShopFeed.get(shop, "/wp-json/wp/v2/media", params, req_options),
         {:ok, media} when is_list(media) <- ShopFeed.decode(response) do
      {:ok,
       for(
         %{"id" => id, "source_url" => url} when is_integer(id) <- media,
         url = ShopFeed.image_url(url, image_hosts(shop)),
         url != nil,
         into: %{},
         do: {id, url}
       )}
    else
      {:ok, _not_a_list} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_original(%{"images" => [%{"id" => id} = image | rest]} = product, originals)
       when is_map_key(originals, id),
       do: %{product | "images" => [Map.put(image, "src", originals[id]) | rest]}

  defp put_original(product, _originals), do: product

  defp total_pages(response) do
    with [value | _] <- Req.Response.get_header(response, "x-wp-totalpages"),
         {pages, ""} when pages >= 1 <- Integer.parse(String.trim(value)) do
      {:ok, pages}
    else
      _ -> {:error, :malformed_pagination}
    end
  end

  defp normalize(shop, {:sealed, %{} = product}) do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         true <- sealed?(shop, product["categories"], title) || :ignore,
         {:ok, offer} <- offer(shop, product, title, :sealed) do
      {:ok, [offer]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(shop, {:single, %{} = product}) do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         {:ok, offer} <- offer(shop, product, title, :single) do
      {:ok, [Map.merge(offer, %{kind: :single, category: single_category(product)})]}
    else
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  defp offer(shop, product, title, kind) do
    with {:ok, id} <- product_id(product["id"]),
         {:ok, url} <- product_url(shop, product["permalink"]),
         {:ok, price} <- price(product["prices"], shop.currency, kind) do
      {:ok,
       %{
         shop_product_id: id,
         title: title,
         url: url,
         image_url: image_url(shop, product["images"]),
         ean: Ean.normalize(product["sku"]),
         price: price,
         in_stock: in_stock?(product)
       }}
    end
  end

  # The Store API also returns products of subcategories, which come first in
  # their category list ("DRI - Holo" under English singles).
  defp single_category(%{"categories" => [%{"name" => name} | _]}) do
    case ShopFeed.title(name) do
      {:ok, name} -> name
      :error -> nil
    end
  end

  defp single_category(_product), do: nil

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

  defp price(
         %{"price" => value, "currency_code" => currency, "currency_minor_unit" => unit},
         currency,
         kind
       )
       when is_binary(value) and is_integer(unit) and unit in 0..4 do
    case Integer.parse(value) do
      {minor, ""} when minor > 0 ->
        minor
        |> Decimal.new()
        |> Decimal.div(Decimal.new(Integer.pow(10, unit)))
        |> ShopFeed.price(kind)

      _ ->
        :error
    end
  end

  defp price(_prices, _currency, _kind), do: :error

  defp in_stock?(product) do
    product["is_in_stock"] == true and product["is_purchasable"] == true and
      product["is_on_backorder"] == false
  end
end
