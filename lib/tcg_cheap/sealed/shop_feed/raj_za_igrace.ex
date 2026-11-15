defmodule TcgCheap.Sealed.ShopFeed.RajZaIgrace do
  @moduledoc """
  Reads Raj za igrače's Pokémon TCG category (`feed_path`) and its JSON-LD
  `ItemList`. Every position must be present, distinct and consecutive from 1;
  every product must have a valid URL, euro price,
  availability and SKU. Unexpected pagination fails the fetch rather than
  accepting an unknown subset of the category.

  Only sealed Pokémon products are read; accessories and repacks stay out.
  EANs come from the product's GTIN. Product photos are on the platform's CDN,
  whose observed HTTP URLs are rewritten to HTTPS. See `ShopFeed` for shared
  validation and request limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @image_host "images-rajhraciek-cdn.rshop.sk"
  @product_path ~r|\A/[a-z0-9-]+-p\d+\z|

  @impl true
  def image_hosts(_shop), do: [@image_host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with :ok <- single_listing(shop, req_options),
         {:ok, document} <- HtmlListing.page(shop, shop.feed_path, req_options),
         {:ok, products} <- products(document) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  # A second page proves there's another listing to read. The shop answers
  # `?page=2` with an empty product list (HTTP 200), which is complete proof
  # that page one contains the entire category.
  defp single_listing(shop, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: 2], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, items} <- listing_items(document) do
      if items == [] and Floki.find(document, "link[rel=next], a[rel=next]") == [],
        do: :ok,
        else: {:error, :too_many_pages}
    end
  end

  defp products(document) do
    if Floki.find(document, "link[rel=next], a[rel=next]") == [] do
      with {:ok, items} <- listing_items(document), do: validate_products(items)
    else
      {:error, :too_many_pages}
    end
  end

  defp listing_items(document) do
    document
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.find_value({:error, :malformed_listing}, fn script ->
      case Jason.decode(Floki.text(script, js: true)) do
        {:ok, %{"@type" => "ItemList", "itemListElement" => items}} when is_list(items) ->
          {:ok, items}

        _ ->
          nil
      end
    end)
  end

  defp validate_products(items) do
    with {:ok, products} <- Enum.reduce_while(items, {:ok, []}, &reduce_item/2),
         true <- positions_in_order?(Enum.reverse(products)) do
      {:ok, Enum.reverse(products)}
    else
      _ -> {:error, :malformed_listing}
    end
  end

  defp reduce_item(%{"position" => position, "item" => item}, {:ok, acc})
       when is_integer(position) and position > 0 and is_map(item) do
    {:cont, {:ok, [{position, item} | acc]}}
  end

  defp reduce_item(_item, _acc), do: {:halt, :error}

  defp positions_in_order?([]), do: true

  defp positions_in_order?(products) do
    Enum.map(products, &elem(&1, 0)) == Enum.to_list(1..length(products))
  end

  defp normalize(shop, {_position, %{"sku" => sku} = product}) when is_integer(sku) and sku > 0 do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         true <- not String.contains?(title, "naslovni album prstanov") || :ignore,
         true <- Matcher.sealed_title?(title) || :ignore,
         {:ok, url} <- product_url(shop, product["offers"]["url"]),
         {:ok, price} <- ShopFeed.decimal_price(product["offers"]["price"]),
         {:ok, in_stock} <- in_stock(product["offers"]["availability"]) do
      preorder =
        product["offers"]["availability"] == "https://schema.org/PreOrder" or
          Matcher.preorder_title?(title)

      {:ok,
       [
         %{
           shop_product_id: Integer.to_string(sku),
           title: title,
           url: url,
           image_url: image_url(product["image"]),
           ean: Ean.normalize(product["gtin"]),
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

  defp normalize(_shop, {_position, nil}), do: :ignore
  defp normalize(_shop, _product), do: :invalid

  defp product_url(shop, url) do
    with {:ok, uri} <- ShopFeed.https_url(url, [shop.host]),
         true <- is_nil(uri.query) and Regex.match?(@product_path, uri.path) do
      {:ok, url}
    else
      _ -> :error
    end
  end

  defp image_url("http://" <> rest), do: ShopFeed.image_url("https://" <> rest, [@image_host])
  defp image_url(url), do: ShopFeed.image_url(url, [@image_host])

  defp in_stock("https://schema.org/InStock"), do: {:ok, true}

  defp in_stock(availability)
       when availability in [
              "https://schema.org/OutOfStock",
              "https://schema.org/BackOrder"
            ],
       do: {:ok, false}

  defp in_stock("https://schema.org/PreOrder"), do: {:ok, false}
  defp in_stock(_availability), do: :error
end
