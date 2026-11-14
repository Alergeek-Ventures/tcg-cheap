defmodule TcgCheap.Sealed.Shoptet do
  @moduledoc """
  Reads sealed products from a Shoptet shop's `listing_paths` and singles
  from its `singles_categories`. Each category is read to the last page its
  pager names, at most `max_pages` pages. The pagination path is taken from
  the listing's links, supporting localized pagers without language rules.

  Shoptet marks every product of a listing with microdata
  (`data-micro="product"`): its id (`data-micro-product-id`), name and link,
  and an offer with the price (`data-micro-price`, a plain decimal), its
  currency, which must be the shop's `currency`, and its schema.org
  availability; only `InStock` is in stock. Sealed products must name a
  sealed product; singles have a 0.10 minimum and no category (the title
  names the set).
  Images (`data-micro-image`) come from the shop's host or Shoptet's CDN
  (`cdn.myshoptet.com`);
  listings carry no EAN. The pages must form a complete listing, the total
  being the listing's "položek celkem" count (see
  `TcgCheap.Sealed.HtmlListing.read/2`). See `TcgCheap.Sealed.ShopFeed` for
  the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Matcher, Shop, ShopFeed}

  @path ~r/\A\/[a-z0-9-]+\/\z/
  @in_stock "https://schema.org/InStock"

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.myshoptet.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, sealed} <- sealed_products(shop, req_options) do
      singles =
        HtmlListing.read_singles(shop, fn path, _max_pages ->
          read_category(shop, path, req_options)
        end)

      sealed
      |> Enum.map(&{:sealed, &1})
      |> ShopFeed.with_singles(
        singles,
        &ShopFeed.offers(shop, &1, fn product -> normalize(shop, product) end)
      )
    end
  end

  defp sealed_products(%Shop{singles_only: true}, _req_options), do: {:ok, []}

  defp sealed_products(shop, req_options),
    do: HtmlListing.read_listings(shop, &read_category(shop, &1, req_options))

  defp read_category(shop, path, req_options) do
    with true <- Regex.match?(@path, path),
         {:ok, document} <- HtmlListing.page(shop, path, req_options),
         {:ok, first} <- page(document),
         {:ok, prefix} <- pagination_prefix(document, path, first.last) do
      HtmlListing.read(
        fn
          1 -> {:ok, first}
          number -> request(shop, "#{prefix}#{number}/", req_options)
        end,
        shop.max_pages
      )
    else
      false -> {:error, :invalid_category}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pagination_prefix(_document, _path, 1), do: {:ok, nil}

  defp pagination_prefix(document, path, _last) do
    pattern = Regex.compile!("\\A(" <> Regex.escape(path) <> "[a-z-]+-)[0-9]+/\\z")

    prefix =
      document
      |> Floki.find(".pagination a[href]")
      |> Floki.attribute("href")
      |> Enum.find_value(fn href ->
        case Regex.run(pattern, URI.parse(href).path || "") do
          [_, prefix] -> prefix
          nil -> nil
        end
      end)

    if prefix, do: {:ok, prefix}, else: {:error, :malformed_pagination}
  end

  defp request(shop, path, req_options) do
    with {:ok, document} <- HtmlListing.page(shop, path, req_options), do: page(document)
  end

  defp page(document) do
    products =
      document |> Floki.find(~s([data-micro="product"])) |> Enum.map(&product/1)

    with {:ok, number} <- page_number(document),
         {:ok, total} <- total(document) do
      last =
        case HtmlListing.first(document, ".pagination__link--last") do
          nil -> number
          link -> integer(HtmlListing.text(link))
        end

      if is_integer(last),
        do: {:ok, %{number: number, last: max(last, number), total: total, products: products}},
        else: {:error, :malformed_pagination}
    end
  end

  # A listing of one page has no pager.
  defp page_number(document) do
    case HtmlListing.first(document, ".pagination__currentPage") do
      nil ->
        {:ok, 1}

      node ->
        case integer(HtmlListing.text(node)) do
          nil -> {:error, :malformed_pagination}
          number -> {:ok, number}
        end
    end
  end

  defp total(document) do
    case document |> HtmlListing.first(".itemsTotal strong") |> HtmlListing.text() |> integer() do
      nil -> {:error, :malformed_pagination}
      total -> {:ok, total}
    end
  end

  defp integer(nil), do: nil

  defp integer(text) do
    case Integer.parse(String.replace(text, ~r/\s/u, "")) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp product(node) do
    offer = HtmlListing.first(node, ~s([data-micro="offer"]))

    %{
      id: node |> Floki.attribute("data-micro-product-id") |> List.first(),
      title: node |> HtmlListing.first(~s([data-micro="name"])) |> HtmlListing.text(),
      path: HtmlListing.attr(node, ~s(a[data-micro="url"]), "href"),
      # Thumbnails load lazily; the microdata names the full image.
      image: HtmlListing.attr(node, "img[data-micro-image]", "data-micro-image"),
      price: offer && offer |> Floki.attribute("data-micro-price") |> List.first(),
      currency: offer && offer |> Floki.attribute("data-micro-price-currency") |> List.first(),
      in_stock:
        offer && offer |> Floki.attribute("data-micro-availability") |> List.first() == @in_stock
    }
  end

  defp normalize(shop, {kind, product}) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- (kind == :single or Matcher.sealed_title?(title)) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.path),
         true <- product.currency == shop.currency,
         {:ok, price} <- ShopFeed.decimal_price(product.price, kind),
         in_stock when is_boolean(in_stock) <- product.in_stock do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product.image),
           ean: nil,
           price: price,
           in_stock: in_stock,
           kind: kind,
           category: nil
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp product_url(shop, "/" <> _rest = path) do
    url = "https://#{shop.host}#{path}"

    with {:ok, uri} <- ShopFeed.https_url(url, [shop.host]),
         true <- is_nil(uri.query) do
      {:ok, url}
    else
      _ -> :error
    end
  end

  defp product_url(_shop, _path), do: :error

  defp image_url(shop, src), do: ShopFeed.image_url(src, image_hosts(shop))
end
