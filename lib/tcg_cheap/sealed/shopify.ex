defmodule TcgCheap.Sealed.Shopify do
  @moduledoc """
  Reads the public product list of a Shopify shop: `/products.json`, or
  `/collections/<collection>/products.json` when the shop has a Pokémon
  `collection`, 250 products per page up to the first empty page, at most
  `max_pages` pages. The shop's currency (`/meta.json`) must be its
  configured `currency`. Every product of the shop's `singles_categories`
  (collection handles, each read the same way) is a single, priced with a
  0.10 minimum, without a category (see `with_kind/2`).

  Price and availability are per variant, so each variant is one offer. A
  product counts as sealed when its title names a sealed product
  (`TcgCheap.Sealed.Matcher.sealed_title?/1`) and, when the whole shop is
  read, also says Pokémon. Product URLs are built from the validated handle;
  images (the variant's own, else the product's) may come from the shop's
  host or Shopify's CDN; EANs come from
  variant SKUs. See `TcgCheap.Sealed.ShopFeed` for the shared limits.

  Requests use HTTP/2: Shopify answers every HTTP/1.1 request for
  `/products.json` with 429 (`Retry-After: 60`, checked November 2026 on all
  four shops; production saw it for days), while the same request over
  HTTP/2 succeeds. They are also paced 5 s apart instead of the usual 1 s.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Matcher, Shop, ShopFeed}

  @per_page 250
  @request_opts [pause_ms: 5_000, protocols: [:http2]]
  @handle ~r/\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.shopify.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with :ok <- check_currency(shop, req_options),
         {:ok, sealed} <- sealed_products(shop, req_options),
         {:ok, singles} <- singles_products(shop, req_options) do
      products = Enum.map(sealed, &{:sealed, &1}) ++ Enum.map(singles, &{:single, &1})
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp sealed_products(%Shop{singles_only: true}, _req_options), do: {:ok, []}

  defp sealed_products(shop, req_options),
    do: fetch_pages(shop, products_path(shop), req_options, 1, [])

  defp singles_products(%Shop{singles_categories: nil}, _req_options), do: {:ok, []}

  defp singles_products(shop, req_options) do
    Enum.reduce_while(shop.singles_categories, {:ok, []}, fn handle, {:ok, acc} ->
      case fetch_pages(shop, "/collections/#{handle}/products.json", req_options, 1, []) do
        {:ok, products} -> {:cont, {:ok, acc ++ products}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp check_currency(shop, req_options) do
    with {:ok, response} <-
           ShopFeed.get(shop, "/meta.json", [], req_options, @request_opts),
         {:ok, %{"currency" => currency}} when currency == shop.currency <-
           ShopFeed.decode(response) do
      :ok
    else
      {:ok, _meta} -> {:error, :unexpected_currency}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_pages(shop, path, req_options, page, acc) do
    case request(shop, path, req_options, page) do
      {:ok, products} when page > shop.max_pages and products != [] ->
        {:error, :too_many_pages}

      {:ok, []} ->
        {:ok, acc |> Enum.reverse() |> List.flatten()}

      {:ok, products} ->
        fetch_pages(shop, path, req_options, page + 1, [products | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(shop, path, req_options, page) do
    params = [limit: @per_page, page: page]

    with {:ok, response} <- ShopFeed.get(shop, path, params, req_options, @request_opts),
         {:ok, %{"products" => products}} when is_list(products) <- ShopFeed.decode(response) do
      {:ok, products}
    else
      {:ok, _other} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp products_path(%Shop{collection: nil}), do: "/products.json"
  defp products_path(%Shop{collection: handle}), do: "/collections/#{handle}/products.json"

  defp normalize(shop, {kind, %{"variants" => [_ | _] = variants} = product}) do
    with {:ok, title} <- ShopFeed.title(product["title"]),
         true <- (kind == :single or sealed?(shop, title)) || :ignore,
         {:ok, handle} <- handle(product["handle"]) do
      product_offer = %{
        kind: kind,
        title: title,
        url: "https://#{shop.host}/products/#{handle}",
        image_url: image_url(shop, product["images"]),
        image_hosts: image_hosts(shop),
        single?: match?([_], variants)
      }

      offers = Enum.map(variants, &variant_offer(product_offer, &1))

      if Enum.all?(offers, &match?({:ok, _offer}, &1)),
        do: {:ok, Enum.map(offers, fn {:ok, offer} -> with_kind(offer, kind) end)},
        else: :invalid
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  defp with_kind(offer, :sealed), do: offer

  # Product types of singles name an era ("XY") or a condition, which the
  # card matcher would take for a conflicting set, so singles have no category.
  defp with_kind(offer, :single), do: Map.merge(offer, %{kind: :single, category: nil})

  defp sealed?(%Shop{collection: nil}, title), do: ShopFeed.sealed_pokemon?(title, nil)
  defp sealed?(_shop, title), do: Matcher.sealed_title?(title)

  defp handle(handle) when is_binary(handle) and byte_size(handle) <= 255 do
    if Regex.match?(@handle, handle), do: {:ok, handle}, else: :error
  end

  defp handle(_handle), do: :error

  defp variant_offer(product, %{"id" => id, "available" => available} = variant)
       when is_integer(id) and id > 0 and is_boolean(available) do
    with {:ok, price} <- ShopFeed.decimal_price(variant["price"], product.kind),
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
end
