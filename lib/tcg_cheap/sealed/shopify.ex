defmodule TcgCheap.Sealed.Shopify do
  @moduledoc """
  Reads the public product list of a Shopify shop: `/products.json`, or
  `/collections/<collection>/products.json` when the shop has a Pokémon
  `collection`, 250 products per page up to the first empty page, at most
  `max_pages` pages. The shop's currency (`/meta.json`) must be PLN.

  Price and availability are per variant, so each variant is one offer. A
  product counts as sealed when its title names a sealed product
  (`TcgCheap.Sealed.Matcher.sealed_title?/1`) and, when the whole shop is
  read, also says Pokémon. Product URLs are built from the validated handle;
  images (the variant's own, else the product's) may come from the shop's
  host or Shopify's CDN; EANs come from
  variant SKUs. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Matcher, Shop, ShopFeed}

  @per_page 250

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.shopify.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with :ok <- check_currency(shop, req_options),
         {:ok, products} <- fetch_pages(shop, req_options, 1, []) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp check_currency(shop, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, "/meta.json", [], req_options),
         {:ok, %{"currency" => "PLN"}} <- ShopFeed.decode(response) do
      :ok
    else
      {:ok, _meta} -> {:error, :not_pln}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_pages(shop, req_options, page, acc) do
    case request(shop, req_options, page) do
      {:ok, products} when page > shop.max_pages and products != [] ->
        {:error, :too_many_pages}

      {:ok, []} ->
        {:ok, acc |> Enum.reverse() |> List.flatten()}

      {:ok, products} ->
        fetch_pages(shop, req_options, page + 1, [products | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(shop, req_options, page) do
    params = [limit: @per_page, page: page]

    with {:ok, response} <- ShopFeed.get(shop, products_path(shop), params, req_options),
         {:ok, %{"products" => products}} when is_list(products) <- ShopFeed.decode(response) do
      {:ok, products}
    else
      {:ok, _other} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp products_path(%Shop{collection: nil}), do: "/products.json"
  defp products_path(%Shop{collection: handle}), do: "/collections/#{handle}/products.json"

  defp normalize(shop, %{"variants" => [_ | _] = variants} = product) do
    with {:ok, title} <- ShopFeed.title(product["title"]),
         true <- sealed?(shop, title) || :ignore,
         {:ok, handle} <- handle(product["handle"]) do
      product_offer = %{
        title: title,
        url: "https://#{shop.host}/products/#{handle}",
        image_url: image_url(shop, product["images"]),
        image_hosts: image_hosts(shop),
        single?: match?([_], variants)
      }

      offers = Enum.map(variants, &variant_offer(product_offer, &1))

      if Enum.all?(offers, &match?({:ok, _offer}, &1)),
        do: {:ok, Enum.map(offers, fn {:ok, offer} -> offer end)},
        else: :invalid
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  defp sealed?(shop, title) do
    Matcher.sealed_title?(title) and
      (is_binary(shop.collection) or "pokemon" in String.split(Matcher.normalize(title)))
  end

  defp handle(handle) when is_binary(handle) and byte_size(handle) <= 255 do
    if Regex.match?(~r/\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/, handle), do: {:ok, handle}, else: :error
  end

  defp handle(_handle), do: :error

  defp variant_offer(product, %{"id" => id, "available" => available} = variant)
       when is_integer(id) and id > 0 and is_boolean(available) do
    with {:ok, price} <- price(variant["price"]),
         {:ok, title} <- variant_title(product, variant["title"]) do
      {:ok,
       %{
         shop_product_id: Integer.to_string(id),
         title: title,
         url: if(product.single?, do: product.url, else: "#{product.url}?variant=#{id}"),
         image_url: variant_image_url(product, variant["featured_image"]),
         ean: Ean.normalize(variant["sku"]),
         price: price,
         in_stock: available
       }}
    end
  end

  defp variant_offer(_product, _variant), do: :error

  # A product's only variant is called "Default Title"; other variants name
  # what differs (a Pokémon, a language), sometimes repeating the product title.
  defp variant_title(%{single?: true, title: title}, _variant_title), do: {:ok, title}

  defp variant_title(%{title: title}, variant_title) do
    with {:ok, variant_title} <- ShopFeed.title(variant_title) do
      if String.contains?(variant_title, title),
        do: {:ok, variant_title},
        else: ShopFeed.title("#{title} – #{variant_title}")
    end
  end

  defp image_url(shop, [%{"src" => src} | _]), do: ShopFeed.image_url(src, image_hosts(shop))
  defp image_url(_shop, _images), do: nil

  defp variant_image_url(product, %{"src" => src}),
    do: ShopFeed.image_url(src, product.image_hosts) || product.image_url

  defp variant_image_url(product, _image), do: product.image_url

  defp price(value) when is_binary(value) do
    if Regex.match?(~r/\A[0-9]{1,7}(?:\.[0-9]{1,2})?\z/, value),
      do: ShopFeed.price(Decimal.new(value)),
      else: :error
  end

  defp price(_value), do: :error
end
