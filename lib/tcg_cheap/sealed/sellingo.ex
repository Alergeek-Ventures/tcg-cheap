defmodule TcgCheap.Sealed.Sellingo do
  @moduledoc """
  Reads the category pages of a Sellingo shop (the shop's `listing_paths`,
  Pokémon categories whose listing includes their subcategories). A Sellingo
  shop's robots.txt disallows its `?page=` links, so only a listing that fits
  one page is read: the heading states the listing's size ("(14 Produktów)")
  and it must equal the distinct products on the page, so a listing that
  outgrows the page fails instead of passing for a complete one.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the listing's
  heading). The price is the current one, which must be in złoty. It is in
  stock when the product box says "Dostępny" (`avaible`) and out of stock
  when it says "Niedostępny" (`none`); a page where no box says either fails.
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

  defp read_listing(shop, req_options, path) do
    with {:ok, document} <- HtmlListing.page(shop, path, req_options),
         {:ok, total} <- total(document),
         {:ok, products} <- products(document),
         :ok <- complete(products, total) do
      {:ok, products}
    end
  end

  # "(14 Produktów)" in the listing's heading.
  defp total(document) do
    with text when is_binary(text) <-
           HtmlListing.text(HtmlListing.first(document, ".c-section-header__subtext")),
         [_, total] <- Regex.run(~r/\A\(([0-9]{1,6}) Produkt(?:y|ów)?\)\z/u, text) do
      {:ok, String.to_integer(total)}
    else
      _ -> {:error, :malformed_pagination}
    end
  end

  defp complete(products, total) do
    distinct = products |> Enum.map(& &1.id) |> Enum.uniq() |> length()
    if distinct == total, do: :ok, else: {:error, :incomplete_listing}
  end

  defp products(document) do
    category = HtmlListing.text(HtmlListing.first(document, "h1"))

    products =
      document
      |> Floki.find("div.js-product-box")
      |> Enum.map(&product(&1, category))

    if :error in products or (products != [] and Enum.all?(products, &is_nil(&1.in_stock))),
      do: {:error, :unrecognised_listing},
      else: {:ok, products}
  end

  defp product(box, category) do
    link = HtmlListing.first(box, "a.js-product-scope-url")
    id = HtmlListing.attr(box, "div.js-product-box", "data-id")
    href = if link, do: HtmlListing.attr(link, "a", "href")
    title = HtmlListing.text(HtmlListing.first(box, "h3.js-product-scope-title"))
    price = HtmlListing.text(HtmlListing.first(box, ".js-product-scope-price"))
    currency = HtmlListing.attr(box, ".js-product-prices", "data-currency")

    if Enum.all?([id, href, title, price, currency], &is_binary/1) do
      %{
        id: id,
        href: href,
        title: title,
        price: price,
        currency: currency,
        in_stock: in_stock(box),
        image: HtmlListing.attr(box, "img.js-product-scope-image", "src"),
        category: category
      }
    else
      :error
    end
  end

  defp in_stock(box) do
    cond do
      Floki.find(box, ".c-avaibility--avaible") != [] -> true
      Floki.find(box, ".c-avaibility--none") != [] -> false
      true -> nil
    end
  end

  defp normalize(shop, product) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- ShopFeed.sealed_pokemon?(title, product.category) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.href),
         "PLN" <- product.currency,
         {:ok, price} <- price(product.price),
         in_stock when is_boolean(in_stock) <- product.in_stock do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: ShopFeed.image_url(product.image, image_hosts(shop)),
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
    with {:ok, plain} <- HtmlListing.price_text(text), do: ShopFeed.decimal_price(plain)
  end

  defp product_url(shop, href) do
    with {:ok, uri} <- ShopFeed.https_url(href, [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end
end
