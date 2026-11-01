defmodule TcgCheap.Sealed.ShopGold do
  @moduledoc """
  Reads the category pages of a shopGold shop (the shop's `listing_paths`,
  Pokémon categories whose listing includes their subcategories). shopGold
  shops publish comparison feeds only under `/xml/`, which their robots.txt
  disallows, so the HTML listing is the source.

  A listing is read page by page (`<path>/s=<page>`, a page size fixed by the
  shop) until the products read are as many as the listing states in
  "ogółem produktów: N". The statement must stay the same on every page and
  match the distinct products read; an empty page before that fails, and so
  does going past `max_pages` pages per listing, so a missing, shifted or
  unrecognised page never passes for a complete listing. A product box that
  has no link, title or price, or a page where no box shows whether it can be
  bought, fails the fetch. The products of several listings are joined by
  product id.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the listing's
  heading). The price is the current one shown in złoty (not the old price of
  a promotion); a product priced "Zapytaj o cenę" is ignored. It is in stock
  when its box has an "add to cart" button; a box without one (the listing's
  `ProduktBezZakupu`) or marked "Produkt będzie dostępny od dnia" (a release
  date) is not. Shops whose listing template has no purchase buttons are not
  supported: their "Dostępność" label does not follow what a buyer can order.
  The listing carries no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared
  limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed}

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_listing(shop, req_options, &1)) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp read_listing(shop, req_options, path), do: read_pages(shop, req_options, path, 1, nil, [])

  defp read_pages(%Shop{max_pages: max}, _req_options, _path, page, _total, _acc)
       when page > max,
       do: {:error, :too_many_pages}

  defp read_pages(shop, req_options, path, page, total, acc) do
    case request(shop, req_options, path, page) do
      {:ok, _products, page_total} when total not in [nil, page_total] ->
        {:error, :pagination_changed}

      {:ok, products, page_total} ->
        acc = acc ++ products
        seen = acc |> Enum.map(& &1.id) |> Enum.uniq() |> length()

        cond do
          seen == page_total -> {:ok, acc}
          seen > page_total or products == [] -> {:error, :incomplete_listing}
          true -> read_pages(shop, req_options, path, page + 1, page_total, acc)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(shop, req_options, path, page) do
    page_path = if page == 1, do: path, else: "#{path}/s=#{page}"

    with {:ok, document} <- HtmlListing.page(shop, page_path, req_options, page - 1),
         {:ok, total} <- total(document),
         {:ok, products} <- products(document) do
      {:ok, products, total}
    end
  end

  # "ogółem produktów: 85", shown above and below the listing.
  defp total(document) do
    with text when is_binary(text) <-
           HtmlListing.text(HtmlListing.first(document, ".IndexStron span")),
         [_, total] <- Regex.run(~r/\Aogółem produktów: ([0-9]{1,6})\z/u, text) do
      {:ok, String.to_integer(total)}
    else
      _ -> {:error, :malformed_pagination}
    end
  end

  defp products(document) do
    category = HtmlListing.text(HtmlListing.first(document, "h1"))

    products =
      document
      |> Floki.find("div.OknaRwd > div.Okno")
      |> Enum.map(&product(&1, category))

    # A box we cannot read, or a page where no box shows a purchase state,
    # means the template changed.
    if :error in products or (products != [] and Enum.all?(products, &is_nil(&1.in_stock))),
      do: {:error, :unrecognised_listing},
      else: {:ok, products}
  end

  defp product(box, category) do
    link = HtmlListing.first(box, "h3 a")
    href = if link, do: HtmlListing.attr(link, "a", "href")
    title = HtmlListing.text(link)
    price = price_text(box)

    with true <- is_binary(href) and is_binary(title) and is_binary(price),
         [_, id] <- Regex.run(~r/-p-([0-9]+)\.html\z/, href) do
      %{
        id: id,
        href: href,
        title: title,
        price: price,
        in_stock: in_stock(box),
        image: HtmlListing.attr(box, ".Foto img", "data-src-original"),
        category: category
      }
    else
      _ -> :error
    end
  end

  # The current price: promotions show the old price and the lowest price of
  # the last 30 days beside it.
  defp price_text(box) do
    case HtmlListing.first(box, ".ProduktCena") do
      nil ->
        nil

      node ->
        node = node |> Floki.filter_out(".CenaPoprzednia") |> Floki.filter_out(".InfoCena30dni")
        HtmlListing.text(HtmlListing.first(node, ".CenaAktualna")) || HtmlListing.text(node)
    end
  end

  # nil when the box shows neither a cart button nor the refusal to sell (a
  # template without purchase buttons, whose "Dostępność" label says nothing
  # reliable about stock).
  defp in_stock(box) do
    classes = box |> Floki.attribute("class") |> List.first("")

    cond do
      Floki.find(box, ".DataDostepnosci") != [] -> false
      Floki.find(box, ".DoKoszyka") != [] -> true
      String.contains?(classes, "ProduktBezZakupu") -> false
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
           ean: nil,
           price: price,
           in_stock: in_stock
         }
       ]}
    else
      :ignore ->
        :ignore

      :unpriced ->
        :ignore

      _ ->
        :invalid
    end
  end

  defp price("Zapytaj o cenę"), do: :unpriced

  defp price(text) do
    with {:ok, plain} <- HtmlListing.price_text(text), do: ShopFeed.decimal_price(plain)
  end

  # Some links are relative to the shop's root.
  defp product_url(shop, "https://" <> _ = href), do: absolute_url(shop, href)
  defp product_url(shop, href), do: absolute_url(shop, "https://#{shop.host}/#{href}")

  defp absolute_url(shop, href) do
    with {:ok, uri} <- ShopFeed.https_url(href, [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end

  # Thumbnails are relative to the shop's root and may contain spaces.
  defp image_url(_shop, nil), do: nil

  defp image_url(shop, path) do
    ShopFeed.image_url(
      "https://#{shop.host}/#{path |> String.trim_leading("/") |> URI.encode()}",
      [
        shop.host
      ]
    )
  end
end
