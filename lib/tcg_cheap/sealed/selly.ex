defmodule TcgCheap.Sealed.Selly do
  @moduledoc """
  Reads the category pages of a Selly shop (the shop's `listing_paths`,
  `<name>,c<id>.html`), page by page (`<name>,c<id>,s<n>.html` from `n = 1`
  for the second page). The listing states no product count, so completeness
  is proven by its paging: every page must name itself as the active one, a
  page links the next one exactly when it is not the last, every page but the
  last holds as many products as the first, none holds more, and the distinct
  products must be as many as the products read. Going past `max_pages`
  pages, a product box that cannot be read or a page where no box says
  whether it can be bought fails the fetch.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the listing's
  heading). The price is the one shown, which must be in złoty. It is in stock
  when its box has an "add to cart" button and out of stock when it has "Zapytaj
  o produkt" instead. The EAN is the barcode shown under the name. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, HtmlListing, Shop, ShopFeed}

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_pages(shop, req_options, &1, 1, nil, [])) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp read_pages(%Shop{max_pages: max}, _req_options, _path, page, _size, _acc)
       when page > max,
       do: {:error, :too_many_pages}

  defp read_pages(shop, req_options, path, page, size, acc) do
    with {:ok, document} <- HtmlListing.page(shop, page_path(path, page), req_options, page - 1),
         {:ok, products} <- products(document),
         {:ok, last?} <- paging(document, page) do
      acc = acc ++ products
      size = size || length(products)

      cond do
        products == [] or length(products) > size -> {:error, :incomplete_listing}
        last? -> complete(acc)
        length(products) < size -> {:error, :incomplete_listing}
        true -> read_pages(shop, req_options, path, page + 1, size, acc)
      end
    end
  end

  defp page_path(path, 1), do: path

  defp page_path(path, page),
    do: String.replace_suffix(path, ".html", ",s#{page - 1}.html")

  defp complete(products) do
    distinct = products |> Enum.map(& &1.id) |> Enum.uniq() |> length()
    if distinct == length(products), do: {:ok, products}, else: {:error, :incomplete_listing}
  end

  # The page must be the one asked for; the last one has no "next" link.
  defp paging(document, page) do
    active = document |> Floki.find("ul.pages span.aktywna") |> List.first() |> HtmlListing.text()
    next? = Floki.find(document, "ul.pages li.pages__item--next") != []

    if active == Integer.to_string(page),
      do: {:ok, not next?},
      else: {:error, :malformed_pagination}
  end

  defp products(document) do
    category = HtmlListing.text(HtmlListing.first(document, "h1"))

    products =
      document
      |> Floki.find("div.product-box")
      |> Enum.map(&product(&1, category))

    if :error in products or (products != [] and Enum.all?(products, &is_nil(&1.in_stock))),
      do: {:error, :unrecognised_listing},
      else: {:ok, products}
  end

  defp product(box, category) do
    link = HtmlListing.first(box, "a.product__name-link")
    href = if link, do: HtmlListing.attr(link, "a", "href")
    title = HtmlListing.text(link)
    price = HtmlListing.text(HtmlListing.first(box, "strong.price"))

    with true <- is_binary(href) and is_binary(title) and is_binary(price),
         [_, id] <- Regex.run(~r/,id([0-9]+)\.html\z/, href) do
      %{
        id: id,
        href: href,
        title: title,
        price: price,
        ean: HtmlListing.text(HtmlListing.first(box, "h4.product__additional-name")),
        in_stock: in_stock(box),
        image: HtmlListing.attr(box, "img.product-box__image", "data-src"),
        category: category
      }
    else
      _ -> :error
    end
  end

  defp in_stock(box) do
    cond do
      Floki.find(box, "a.add-to-cart") != [] -> true
      Floki.find(box, "a.ask") != [] -> false
      true -> nil
    end
  end

  defp normalize(shop, product) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- ShopFeed.sealed_pokemon?(title, product.category) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.href),
         {:ok, price} <- price(product.price),
         in_stock when is_boolean(in_stock) <- product.in_stock do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product.image),
           ean: Ean.normalize(product.ean),
           price: price,
           in_stock: in_stock
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  # "25.00 zł": the shop shows złoty only.
  defp price(text) do
    with true <- String.ends_with?(text, " zł"),
         {:ok, plain} <- HtmlListing.price_text(text),
         do: ShopFeed.decimal_price(plain)
  end

  # Links are relative to the shop's root.
  defp product_url(shop, href) do
    with {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}/#{href}", [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end

  defp image_url(_shop, nil), do: nil

  defp image_url(shop, path) do
    ShopFeed.image_url("https://#{shop.host}#{path}", image_hosts(shop))
  end
end
