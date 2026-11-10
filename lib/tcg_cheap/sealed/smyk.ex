defmodule TcgCheap.Sealed.Smyk do
  @moduledoc """
  Reads the Pokémon TCG listing of smyk.com, a React storefront rendered on the
  server whose page carries its state as JSON in `window.PRELOADED_STATE`: the
  one product list of the `feed_path` page and its `paging` (`pageSize`,
  `totalElements`). The listing fits on one page (29 products of 36 on
  2026-11-10). A list longer than a page, or one holding a different number of
  products than its stated total, fails the fetch instead of being read in
  part; reading further pages would need Smyk's page parameter, which this
  listing has never shown.

  The listing shows only products that can be ordered online. Each product
  states `productAvailability.inStock`, which is what counts as in stock, and
  `preSelling`, a pre-order. Its price is `productPrice.price`, the current one
  (`suggestedPrice` is the struck-through regular price). A product counts
  when it is sealed Pokémon (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on
  its name), so the listing's promo cards and albums drop out. The product id
  is Smyk's SKU; the image is its 760 px rendition on Smyk's image server.
  There is no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @state_prefix "window.PRELOADED_STATE = "
  @image_host "img.smyk.com"

  @impl true
  def image_hosts(%Shop{}), do: [@image_host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, state} <- state(document),
         {:ok, products} <- listing(state) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp state(document) do
    script =
      document
      |> Floki.find("script")
      |> Enum.find_value(fn
        {"script", _attributes, [@state_prefix <> json]} -> json
        _script -> nil
      end)

    with json when is_binary(json) <- script,
         json = json |> String.trim_trailing() |> String.trim_trailing(";"),
         {:ok, state} <- Jason.decode(json, floats: :decimals) do
      {:ok, state}
    else
      _ -> {:error, :malformed_listing}
    end
  end

  defp listing(%{"publications" => %{"items" => items}}) when is_map(items) do
    lists =
      for {_id, %{"content" => %{"products" => products, "paging" => paging}}} <- items,
          do: {products, paging}

    case lists do
      [{products, %{"pageSize" => size, "totalElements" => total}}]
      when is_list(products) and is_integer(size) and is_integer(total) ->
        complete(products, size, total)

      _ ->
        {:error, :malformed_listing}
    end
  end

  defp listing(_state), do: {:error, :malformed_listing}

  defp complete(_products, _size, 0), do: {:error, :empty_listing}
  defp complete(_products, size, total) when total > size, do: {:error, :too_many_pages}

  defp complete(products, _size, total) when length(products) != total,
    do: {:error, :incomplete_listing}

  defp complete(products, _size, _total), do: {:ok, products}

  defp normalize(shop, %{} = product) do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         true <- ShopFeed.sealed_pokemon?(title, nil) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product["productSku"]),
         "/p/" <> _ = path <- product["url"],
         url = "https://#{shop.host}/pl/pl#{path}",
         {:ok, _uri} <- ShopFeed.https_url(url, [shop.host]),
         {:ok, price} <- price(product["productPrice"]),
         %{"inStock" => in_stock, "preSelling" => preorder}
         when is_boolean(in_stock) and is_boolean(preorder) <- product["productAvailability"] do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(product),
           ean: nil,
           price: price,
           # A pre-order is never in stock (`TcgCheap.Sealed.ShopFeed`).
           in_stock: in_stock and not preorder,
           preorder: preorder
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  # Decoded with `floats: :decimals`; a whole-złoty price is an integer.
  defp price(%{"price" => %Decimal{} = price}), do: ShopFeed.price(price)
  defp price(%{"price" => price}) when is_integer(price), do: ShopFeed.price(Decimal.new(price))
  defp price(_price), do: :error

  defp image_url(%{"productImage" => %{"urls" => %{"760" => url}}}),
    do: ShopFeed.image_url(url, [@image_host])

  defp image_url(_product), do: nil
end
