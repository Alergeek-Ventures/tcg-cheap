defmodule TcgCheap.Sealed.MagicznyRynek do
  @moduledoc """
  Reads the Pokémon collection of magicznyrynek.pl, a Next.js storefront whose
  pages carry the listing as JSON in `__NEXT_DATA__`: the collection's
  `feed_path` with `?page=N` from 1 to the `totalPages` it states, which must
  not exceed `max_pages`. The listing states its size (`totalProducts`); it
  and the page count must stay the same on every page and the distinct
  products read must match the size, so a missing or shifted page fails the
  fetch.

  The collection mixes singles, binders and sealed products, so a product
  counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name, the collection
  being Pokémon). Each product states `inStock`, which is what counts as in
  stock. The listing defaults to a `stock=in-stock` filter, so sold out products
  are most likely hidden (checked 2026-11-01: `stock=all` returned the same 76
  products, all in stock); they then simply drop out of the offers. Prices are
  in groszy in the data (the cheapest variant's when a product has several).
  There is no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @images ["magicznyrynek.pl", "cards.magicznyrynek.aexol.work"]
  @next_data ~r|<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>|s

  @impl true
  def image_hosts(%Shop{}), do: @images

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- fetch_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, number, stated, acc) do
    with {:ok, page} <- request(shop, req_options, number) do
      cond do
        stated not in [nil, {page.total, page.pages}] ->
          {:error, :pagination_changed}

        page.number != number ->
          {:error, :pagination_changed}

        page.pages > shop.max_pages ->
          {:error, :too_many_pages}

        page.products == [] ->
          {:error, :malformed_listing}

        number < page.pages ->
          fetch_pages(shop, req_options, number + 1, {page.total, page.pages}, [page | acc])

        true ->
          complete(Enum.reverse([page | acc]), page.total)
      end
    end
  end

  defp complete(pages, total) do
    products = Enum.flat_map(pages, & &1.products)
    ids = Enum.map(products, & &1["productId"])

    if length(products) == total and ids == Enum.uniq(ids),
      do: {:ok, products},
      else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: number], req_options),
         [_, json] <- Regex.run(@next_data, response.body),
         {:ok, data} <- ShopFeed.decode(%Req.Response{response | body: json}),
         %{
           "products" => products,
           "totalProducts" => total,
           "totalPages" => pages,
           "page" => current
         }
         when is_list(products) and is_integer(total) and is_integer(pages) and
                is_integer(current) <- get_in(data, ["props", "pageProps"]) do
      {:ok, %{products: products, total: total, pages: pages, number: current}}
    else
      _ -> {:error, :malformed_response}
    end
  end

  defp normalize(shop, %{"inStock" => in_stock} = product) when is_boolean(in_stock) do
    with {:ok, title} <- ShopFeed.title(product["productName"]),
         true <- ShopFeed.sealed_pokemon?(title, "Pokemon") || :ignore,
         {:ok, id} <- ShopFeed.product_id(product["productId"]),
         {:ok, variant} <- variant_id(product["productVariantId"]),
         {:ok, url} <-
           ShopFeed.https_url("https://#{shop.host}/products/#{product["slug"]}/#{variant}/", [
             shop.host
           ]),
         {:ok, price} <- price(product["priceWithTax"]) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: URI.to_string(url),
           image_url: image_url(product["productAsset"]),
           ean: nil,
           price: price,
           in_stock: in_stock
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  defp variant_id(id) when is_binary(id) do
    if Regex.match?(~r/\A[0-9]{1,12}\z/, id), do: {:ok, id}, else: :error
  end

  defp variant_id(_id), do: :error

  defp price(%{"value" => groszy}), do: price_in_groszy(groszy)
  defp price(%{"min" => groszy}), do: price_in_groszy(groszy)
  defp price(_price), do: :error

  defp price_in_groszy(groszy) when is_integer(groszy),
    do: groszy |> Decimal.new() |> Decimal.div(100) |> ShopFeed.price()

  defp price_in_groszy(_groszy), do: :error

  defp image_url(%{"preview" => url}), do: ShopFeed.image_url(url, @images)
  defp image_url(_asset), do: nil
end
