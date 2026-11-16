defmodule TcgCheap.Sealed.ShopFeed.Jumpseller do
  @moduledoc """
  Reads a Jumpseller shop's public HTML category listings (`listing_paths`),
  including the three storefront themes used by the Portuguese shops. Some
  themes' pagers link only the previous and the next page, so pages are read
  with `?page=N` while a page links the next one on the same listing, at most
  `max_pages`; an empty page or one without a readable product is an error.

  Tiles carry their title, link, euro price and an out-of-stock marker where
  the theme shows one. A product counts when its title names a sealed product.
  Images come from the shop or Jumpseller's CDN; listings carry no EAN.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @tiles "figure.product, .product-slide-entry, article.product-block"
  @stock_labels ".product-out-of-stock, .product-block__label--status, .product-image-label"
  @page_link ~r/(?:\A|&)page=(\d+)(?:&|\z)/
  @price ~r/\A€?([0-9]+(?:[\s\x{a0}][0-9]{3})*),([0-9]{2})€?\z/u

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdnx.jumpseller.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_listing(shop, &1, req_options)) do
      {:ok, HtmlListing.offers(shop, products, &sealed?(shop, &1))}
    end
  end

  defp sealed?(%Shop{mixed_listing: true}, title), do: ShopFeed.sealed_pokemon?(title, nil)
  defp sealed?(_shop, title), do: Matcher.sealed_title?(title)

  defp read_listing(shop, path, req_options), do: read_pages(shop, path, req_options, 1, [])

  defp read_pages(shop, path, req_options, number, acc) do
    with {:ok, page} <- request(shop, path, req_options, number),
         :ok <- check_products(page.products) do
      acc = [page.products | acc]

      cond do
        not page.next? -> {:ok, acc |> Enum.reverse() |> List.flatten()}
        number >= shop.max_pages -> {:error, :too_many_pages}
        true -> read_pages(shop, path, req_options, number + 1, acc)
      end
    end
  end

  defp request(shop, path, req_options, number) do
    params = if number == 1, do: [], else: [page: number]

    with {:ok, response} <- ShopFeed.get(shop, path, params, req_options),
         {:ok, document} <- ShopFeed.html(response) do
      {:ok,
       %{
         next?: links_page?(document, path, number + 1),
         products: document |> Floki.find(@tiles) |> Enum.map(&product/1)
       }}
    end
  end

  defp check_products([]), do: {:error, :empty_page}

  defp check_products(products) do
    if Enum.any?(products, &readable?/1), do: :ok, else: {:error, :unrecognised_listing}
  end

  defp readable?(product) do
    Enum.all?([:id, :title, :path, :price], &is_binary(product[&1])) and
      is_boolean(product.in_stock)
  end

  # Only a `?page=N` link to this same listing counts: no arbitrary
  # query-string-only path is followed from the page.
  defp links_page?(document, path, number) do
    document
    |> Floki.find("a[href]")
    |> Floki.attribute("href")
    |> Enum.any?(&(page_number(&1, path) == number))
  end

  defp page_number(href, path) do
    uri = URI.parse(href)

    with ^path <- uri.path || path,
         [_, page] <- Regex.run(@page_link, uri.query || ""),
         {number, ""} <- Integer.parse(page) do
      number
    else
      _ -> 1
    end
  end

  defp product(node) do
    link = HtmlListing.first(node, "a[href]")

    title =
      node |> HtmlListing.first("h5, h3 a.title, a.product-block__name") |> HtmlListing.text()

    preorder = Matcher.preorder_title?(title || "")

    %{
      id: id(node, link),
      title: title,
      path: link && HtmlListing.attr(link, "a", "href"),
      image: node |> HtmlListing.first("img") |> image(),
      price: node |> price_node() |> HtmlListing.text() |> price(),
      in_stock: not sold_out?(node) and not preorder,
      preorder: preorder
    }
  end

  # A theme without a microdata id still has a unique product URL. Hashing it
  # gives a stable id that stays within the shared length limit even for slugs.
  defp id(node, link) do
    List.first(Floki.attribute(node, "data-product-id")) ||
      case link && HtmlListing.attr(link, "a", "href") do
        "/" <> _ = path ->
          :sha256 |> :crypto.hash(path) |> Base.encode16(case: :lower) |> String.slice(0, 32)

        _ ->
          nil
      end
  end

  # Each theme marks a sold-out tile with its own label: "Esgotado" (sold out)
  # in a `.product-out-of-stock` node, a status label of the product block, or
  # the image label of the slide entry.
  defp sold_out?(node) do
    node
    |> Floki.find(@stock_labels)
    |> Enum.any?(&(&1 |> HtmlListing.text() |> to_string() |> String.downcase() == "esgotado"))
  end

  defp price_node(node) do
    HtmlListing.first(node, ".price .current, .product-price, .product-block__price")
  end

  defp price(nil), do: nil

  defp price(text) do
    text = text |> String.trim() |> String.replace("EUR", "€")

    case Regex.run(@price, text) do
      [_, whole, cents] -> String.replace(whole, ~r/[^0-9]/, "") <> "." <> cents
      nil -> nil
    end
  end

  defp image(nil), do: nil

  defp image(node) do
    # Prefer the largest declared candidate, the original where available.
    candidates =
      node
      |> Floki.attribute("srcset")
      |> List.first()
      |> to_string()
      |> String.split(",")
      |> Enum.flat_map(&candidate/1)

    case Enum.max_by(candidates, &elem(&1, 0), fn -> nil end) do
      {_width, url} -> url
      nil -> List.first(Floki.attribute(node, "src"))
    end
  end

  defp candidate(text) do
    with [url, size] <- String.split(String.trim(text), " ", parts: 2),
         {width, _} <- Integer.parse(size) do
      [{width, url}]
    else
      [url] when url != "" -> [{0, url}]
      _ -> []
    end
  end
end
