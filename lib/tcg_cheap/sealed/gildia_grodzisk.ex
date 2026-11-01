defmodule TcgCheap.Sealed.GildiaGrodzisk do
  @moduledoc """
  Reads the Pokémon category of gildiagrodzisk.pl, a custom shop: the
  category's `feed_path` with `?page=N` from 1, until a page that no longer
  links to a next one, at most `max_pages` pages. The listing states its size
  ("67 produktów"); it must stay the same on every page and match the distinct
  products read, so a missing, replaced or shifted page fails the fetch.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the category
  heading). It is in stock when its card has a working add-to-cart button and
  is marked "Dostępny" without "Przedsprzedaż" (pre-order); a disabled button
  ("Niedostępny", "Sprawdź dostępność") is not. The product id is the shop's
  own, from the cart form or the availability dialog of the card. Prices are in
  złoty. The listing has no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared
  limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @price ~r/\A([0-9]{1,7}),([0-9]{2}) PLN\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, pages} <- fetch_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, pages, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, number, total, acc) do
    with {:ok, page} <- request(shop, req_options, number) do
      cond do
        total not in [nil, page.total] -> {:error, :pagination_changed}
        page.products == [] -> {:error, :malformed_listing}
        page.more? and number >= shop.max_pages -> {:error, :too_many_pages}
        page.more? -> fetch_pages(shop, req_options, number + 1, page.total, [page | acc])
        true -> complete(Enum.reverse([page | acc]), page.total)
      end
    end
  end

  defp complete(pages, total) do
    products = Enum.flat_map(pages, fn page -> Enum.map(page.products, &{&1, page.category}) end)
    ids = Enum.map(products, fn {product, _category} -> product_id(product) end)

    if length(products) == total and ids == Enum.uniq(ids),
      do: {:ok, products},
      else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: number], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, total} <- total(document) do
      {:ok,
       %{
         products: Floki.find(document, "article.front-product-card"),
         category: document |> Floki.find("div.front-listing__heading h1") |> Floki.text(),
         more?: Floki.find(document, "link[rel=next]") != [],
         total: total
       }}
    end
  end

  defp total(document) do
    text =
      document |> Floki.find("div.front-listing__toolbar > p") |> Floki.text() |> String.trim()

    case Regex.run(~r/\A([0-9]{1,6}) produkt(?:ów|y)?\z/u, text) do
      [_, total] -> {:ok, String.to_integer(total)}
      nil -> {:error, :malformed_pagination}
    end
  end

  # The cart form carries the id of an available product, the availability
  # dialog that of an unavailable one.
  defp product_id(product) do
    form = product |> Floki.find("input[name=product_id]") |> Floki.attribute("value")
    dialog = product |> Floki.find("button[aria-controls]") |> Floki.attribute("aria-controls")

    case {form, dialog} do
      {[id], _dialogs} -> id
      {[], ["availability-dialog-" <> id]} -> id
      _ -> nil
    end
  end

  defp normalize(shop, {product, category}) do
    with {:ok, title} <-
           ShopFeed.title(product |> Floki.find(".front-product-card__title") |> Floki.text()),
         true <- ShopFeed.sealed_pokemon?(title, category) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product_id(product)),
         {:ok, url} <- product_url(shop, product),
         {:ok, price} <- price(product),
         {:ok, in_stock} <- in_stock(product) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product),
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

  defp product_url(shop, product) do
    link = product |> Floki.find("a.front-product-card__overlay") |> Floki.attribute("href")

    with [link] <- link,
         {:ok, uri} <- ShopFeed.https_url(link, [shop.host]),
         true <- String.starts_with?(uri.path, "/product/"),
         do: {:ok, "https://#{shop.host}#{uri.path}"},
         else: (_ -> :error)
  end

  defp price(product) do
    text =
      product
      |> Floki.find(".front-product-card__final")
      |> Floki.text()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.replace(~r/(?<=\d) (?=\d)/, "")

    case Regex.run(@price, text) do
      [_, zloty, grosze] -> ShopFeed.decimal_price("#{zloty}.#{grosze}")
      nil -> :error
    end
  end

  defp in_stock(product) do
    button = Floki.find(product, "button.front-product-card__cart-button")
    badges = product |> Floki.find(".front-product-card__badge") |> Floki.text()

    cond do
      Floki.attribute(button, "disabled") != [] -> {:ok, false}
      button == [] -> :error
      String.contains?(badges, "Przedsprzedaż") -> {:ok, false}
      String.contains?(badges, "Dostępny") -> {:ok, true}
      true -> :error
    end
  end

  defp image_url(shop, product) do
    product
    |> Floki.find(".front-product-card__image img")
    |> Floki.attribute("src")
    |> List.first()
    |> ShopFeed.image_url(image_hosts(shop))
  end
end
