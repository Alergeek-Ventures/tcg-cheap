defmodule TcgCheap.Sealed.Shoptet do
  @moduledoc """
  Reads the singles of a Shoptet shop from its category listings: each of the
  shop's `singles_categories` (category paths such as
  `"/kusove-karty-pokemon/"`) is read page by page (`<path>strana-<n>/`) to
  the last page its pager names, at most `max_pages` pages a category.

  Shoptet marks every product of a listing with microdata
  (`data-micro="product"`): its id (`data-micro-product-id`), name and link,
  and an offer with the price (`data-micro-price`, a plain decimal), its
  currency, which must be the shop's `currency`, and its schema.org
  availability; only `InStock` is in stock. Every product read is a single,
  priced with a 0.10 minimum, without a category (the title names the set).
  Images (`data-micro-image`) come from the shop's host or Shoptet's CDN
  (`cdn.myshoptet.com`);
  listings carry no EAN. The pages must form a complete listing, the total
  being the listing's "položek celkem" count (see
  `TcgCheap.Sealed.HtmlListing.read/2`). See `TcgCheap.Sealed.ShopFeed` for
  the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed}

  @path ~r/\A\/[a-z0-9-]+\/\z/
  @in_stock "https://schema.org/InStock"

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.myshoptet.com"]

  @impl true
  def fetch(%Shop{singles_categories: [_ | _] = paths} = shop, req_options) do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case read_category(shop, path, req_options) do
        {:ok, products} -> {:cont, {:ok, acc ++ products}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, products} -> {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch(%Shop{}, _req_options), do: {:error, :no_singles_categories}

  defp read_category(shop, path, req_options) do
    if Regex.match?(@path, path),
      do: HtmlListing.read(&request(shop, path, req_options, &1), shop.max_pages),
      else: {:error, :invalid_category}
  end

  defp request(shop, path, req_options, number) do
    page_path = if number == 1, do: path, else: "#{path}strana-#{number}/"

    with {:ok, document} <- HtmlListing.page(shop, page_path, req_options),
         do: page(document)
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

  defp normalize(shop, product) do
    with {:ok, title} <- ShopFeed.title(product.title),
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.path),
         true <- product.currency == shop.currency,
         {:ok, price} <- ShopFeed.decimal_price(product.price, :single),
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
           kind: :single,
           category: nil
         }
       ]}
    else
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
