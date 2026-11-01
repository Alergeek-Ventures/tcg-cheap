defmodule TcgCheap.Sealed.Sote do
  @moduledoc """
  Reads the category pages of a SOTE shop (the shop's `listing_paths`,
  `/category/<name>`), page by page (`/category/<name>/<n>` from `n = 2`).
  The listing states no product count, so completeness is proven by its
  paging: every page must name itself as the active one and agree on the
  number of the last page, the page that is that last one ends the listing,
  every page but the last holds as many products as the first, none holds
  more, and the distinct products must be as many as the products read. Going
  past `max_pages` pages, a product box that cannot be read or a page where no
  box says whether it can be bought fails the fetch.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the listing's
  heading). The price is the current one shown in złoty. It is in stock when
  its availability says there is some ("Duża ilość", "Średnia ilość",
  "Ostatnie sztuki") and its "add to cart" button is enabled; "Brak", a
  disabled button and "Przedsprzedaż" (pre-sale) are not. The listing carries
  no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed}

  @in_stock ["Duża ilość", "Średnia ilość", "Ostatnie sztuki"]
  @out_of_stock ["Brak", "Przedsprzedaż"]

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_pages(shop, req_options, &1, 1, nil, nil, [])) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp read_pages(%Shop{max_pages: max}, _req_options, _path, page, _last, _size, _acc)
       when page > max,
       do: {:error, :too_many_pages}

  defp read_pages(shop, req_options, path, page, last, size, acc) do
    with {:ok, document} <- HtmlListing.page(shop, page_path(path, page), req_options),
         {:ok, products} <- products(document),
         {:ok, page_last} <- paging(document, page),
         :ok <- same_last(last, page_last) do
      acc = acc ++ products
      size = size || length(products)

      cond do
        products == [] or length(products) > size -> {:error, :incomplete_listing}
        page == page_last -> complete(acc)
        length(products) < size -> {:error, :incomplete_listing}
        true -> read_pages(shop, req_options, path, page + 1, page_last, size, acc)
      end
    end
  end

  defp page_path(path, 1), do: path
  defp page_path(path, page), do: "#{path}/#{page}"

  defp same_last(nil, _page_last), do: :ok
  defp same_last(last, last), do: :ok
  defp same_last(_last, _page_last), do: {:error, :pagination_changed}

  defp complete(products) do
    distinct = products |> Enum.map(& &1.id) |> Enum.uniq() |> length()
    if distinct == length(products), do: {:ok, products}, else: {:error, :incomplete_listing}
  end

  # The page must be the one asked for; returns the number of the last page.
  defp paging(document, page) do
    active =
      document |> Floki.find("ul.pagination li.active a") |> List.first() |> HtmlListing.text()

    numbers =
      document
      |> Floki.find("ul.pagination li a")
      |> Enum.map(&HtmlListing.text/1)
      |> Enum.filter(&(is_binary(&1) and Regex.match?(~r/\A[0-9]{1,3}\z/, &1)))
      |> Enum.map(&String.to_integer/1)

    if active == Integer.to_string(page) and numbers != [],
      do: {:ok, Enum.max(numbers)},
      else: {:error, :malformed_pagination}
  end

  defp products(document) do
    category = HtmlListing.text(HtmlListing.first(document, "h1"))

    products =
      document
      |> Floki.find("div.product.thumbnail")
      |> Enum.map(&product(&1, category))
      |> Enum.reject(&(&1 == :options))

    if :error in products or (products != [] and Enum.all?(products, &is_nil(&1.in_stock))),
      do: {:error, :unrecognised_listing},
      else: {:ok, products}
  end

  # A product with options ("Wybierz opcje") has no price or stock of its own.
  defp product(box, category) do
    link = HtmlListing.first(box, "a.product_name")
    href = if link, do: HtmlListing.attr(link, "a", "href")
    # The visible name is cut with "..."; the full one is the hint's title.
    title = HtmlListing.attr(box, "span.hint", "title") || HtmlListing.text(link)
    price = HtmlListing.text(HtmlListing.first(box, "div.price.nowrap"))

    case HtmlListing.first(box, "a.basket_add_link") do
      nil ->
        if HtmlListing.text(HtmlListing.first(box, "div.product-shopping-cart a")) ==
             "Wybierz opcje",
           do: :options,
           else: :error

      cart ->
        product(box, category, cart, href, title, price)
    end
  end

  defp product(box, category, cart, href, title, price) do
    with true <- Enum.all?([href, title, price], &is_binary/1),
         "product_list_" <> id <- HtmlListing.attr(cart, "a", "id") do
      %{
        id: id,
        href: href,
        title: title,
        price: price,
        in_stock: in_stock(box, cart),
        image: HtmlListing.attr(box, "div.image img", "src"),
        category: category
      }
    else
      _ -> :error
    end
  end

  defp in_stock(box, cart) do
    label = HtmlListing.text(HtmlListing.first(box, ".product-availability-label"))
    disabled? = "disabled" in (cart |> Floki.attribute("class") |> classes())

    cond do
      label in @out_of_stock or disabled? -> false
      label in @in_stock -> true
      true -> nil
    end
  end

  defp classes(values), do: values |> Enum.flat_map(&String.split/1)

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

  defp price(text) do
    with true <- String.ends_with?(text, " zł"),
         {:ok, plain} <- HtmlListing.price_text(text),
         do: ShopFeed.decimal_price(plain)
  end

  defp product_url(shop, "/" <> _path = href) do
    with {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}#{href}", [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end

  defp product_url(_shop, _href), do: :error

  defp image_url(_shop, nil), do: nil

  defp image_url(shop, "/" <> _path = path),
    do: ShopFeed.image_url("https://#{shop.host}#{path}", image_hosts(shop))

  defp image_url(_shop, _path), do: nil
end
