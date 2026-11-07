defmodule TcgCheap.Sealed.NopCommerce do
  @moduledoc """
  Reads the singles in stock of a nopCommerce shop from the HTML its category
  pages load their products with: `/category/products?categoryId=…`, 96
  products a page, each page to the last one its pager names, at most
  `max_pages` pages a category.

  Each of the shop's `singles_categories` is `"<category id>:<option id>"`:
  a category of single cards and the specification option that the shop's
  stock filter sends for "In Stock" (`specs`; a shop's own attribute, not
  part of nopCommerce), so that only cards in stock are read. Every product
  read is a single without a category (the title names the set), in stock
  unless its tile is marked `product-item-out-of-stock`.

  A product (`.product-item`) has its id (`data-productid`), title, link on
  the shop's host, thumbnail and its price in the shop's `currency` as the
  shop prints it in pounds (`£1,234.50`), with a 0.10 minimum. Listings
  carry no EAN. The pages must form a complete listing (see
  `TcgCheap.Sealed.HtmlListing.read/2`). See `TcgCheap.Sealed.ShopFeed` for
  the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed}

  @page_size 96
  @category ~r/\A([0-9]{1,9}):([0-9]{1,9})\z/
  @price ~r/\A£((?:[0-9]{1,3}(?:,[0-9]{3})+)|[0-9]{1,7})\.([0-9]{2})\z/u
  @spaces ~r/[\s\x{a0}]+/u

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{singles_categories: [_ | _] = categories} = shop, req_options) do
    categories
    |> Enum.reduce_while({:ok, []}, fn category, {:ok, acc} ->
      case read_category(shop, category, req_options) do
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

  defp read_category(shop, category, req_options) do
    case Regex.run(@category, category) do
      [_, id, in_stock] ->
        HtmlListing.read(&request(shop, id, in_stock, req_options, &1), shop.max_pages)

      nil ->
        {:error, :invalid_category}
    end
  end

  defp request(shop, id, in_stock, req_options, number) do
    params = [categoryId: id, pagenumber: number, pagesize: @page_size, specs: in_stock]

    with {:ok, response} <- ShopFeed.get(shop, "/category/products", params, req_options),
         {:ok, document} <- ShopFeed.html(response) do
      page(document)
    end
  end

  defp page(document) do
    products = document |> Floki.find(".product-item") |> Enum.map(&product/1)

    with {:ok, number, last} <- pages(Floki.find(document, ".pager")),
         do: {:ok, %{number: number, last: last, total: nil, products: products}}
  end

  # A listing short enough for one page has no pager.
  defp pages([]), do: {:ok, 1, 1}

  defp pages(pager) do
    current = pager |> HtmlListing.first("li.current-page") |> HtmlListing.text() |> integer()
    linked = pager |> Floki.attribute("a", "data-page") |> Enum.map(&integer/1)

    if Enum.all?([current | linked], &is_integer/1),
      do: {:ok, current, Enum.max([current | linked])},
      else: {:error, :malformed_pagination}
  end

  defp integer(nil), do: nil

  defp integer(text) do
    case Integer.parse(text) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp product(node) do
    %{
      id: node |> Floki.attribute("data-productid") |> List.first(),
      title: node |> HtmlListing.first("a.product-title__link") |> HtmlListing.text(),
      path: HtmlListing.attr(node, "a.product-title__link", "href"),
      image: HtmlListing.attr(node, ".picture img", "src"),
      price: node |> HtmlListing.first(".actual-price") |> HtmlListing.text(),
      # The filter alone is not proof: nopCommerce ignores an unknown option
      # and lists every product, so a sold-out tile still says so.
      in_stock: node |> Floki.attribute("class") |> List.first("") |> in_stock?()
    }
  end

  defp normalize(shop, product) do
    with {:ok, title} <- ShopFeed.title(product.title),
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.path),
         {:ok, price} <- price(product.price) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: ShopFeed.image_url(product.image, image_hosts(shop)),
           ean: nil,
           price: price,
           in_stock: product.in_stock,
           kind: :single,
           category: nil
         }
       ]}
    else
      _ -> :invalid
    end
  end

  defp in_stock?(classes), do: "product-item-out-of-stock" not in String.split(classes)

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

  defp price(text) when is_binary(text) do
    case Regex.run(@price, String.replace(text, @spaces, "")) do
      [_, pounds, pence] ->
        ShopFeed.decimal_price(String.replace(pounds, ",", "") <> "." <> pence, :single)

      nil ->
        :error
    end
  end

  defp price(_text), do: :error
end
