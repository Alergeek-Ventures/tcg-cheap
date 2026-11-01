defmodule TcgCheap.Sealed.Pasaz24 do
  @moduledoc """
  Reads a category listing of a Pasaz24 / Vendero shop (`/category/NAME-ID`,
  the shop's `feed_path`), one page per `OfferPage` from 1 to the page count
  the listing states, which must not exceed `max_pages`. Every page states the
  category's size ("Ilość ofert: 94") and the page count; the fetch fails when
  they change between pages or when the distinct products read do not add up
  to the stated size, so a missing or shifted page is never taken for a
  complete listing.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the category
  heading, which is how titles like "PTCG … Booster Box" qualify). It is in
  stock when it shows an availability count and an add-to-cart button; "Brak
  produktu" is not. Prices are in złoty, links are relative to the shop with
  the category query dropped, and images come from the platform's CDN. The
  listing has no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @cdn "www.pasaz24cdn.pl"
  @link ~r|\A/product/[^/?\s]+-s([0-9]{1,9})(?:\?[^\s]*)?\z|
  @price ~r/\A([0-9]{1,7}),([0-9]{2}) zł\z/

  @impl true
  def image_hosts(%Shop{}), do: [@cdn]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, pages} <- fetch_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, pages, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, number, stated, acc) do
    with {:ok, page} <- request(shop, req_options, number) do
      stated = stated || page.stated

      cond do
        page.stated != stated -> {:error, :pagination_changed}
        page.products == [] -> {:error, :malformed_listing}
        number > shop.max_pages or page.pages > shop.max_pages -> {:error, :too_many_pages}
        number < page.pages -> fetch_pages(shop, req_options, number + 1, stated, [page | acc])
        true -> complete([page | acc], stated)
      end
    end
  end

  defp complete(pages, {total, page_count}) do
    products = pages |> Enum.reverse() |> Enum.flat_map(& &1.products)
    distinct = products |> Enum.map(&link/1) |> Enum.uniq() |> length()

    if length(pages) == page_count and distinct == total and length(products) == total,
      do: {:ok, Enum.map(products, &{&1, hd(pages).category})},
      else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <-
           ShopFeed.get(shop, shop.feed_path, [OfferPage: number], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, total} <- total(document),
         {:ok, pages} <- page_count(response.body) do
      {:ok,
       %{
         products: Floki.find(document, "div.product-item"),
         category: document |> Floki.find("div.widget-header h1") |> Floki.text(),
         stated: {total, pages},
         pages: pages
       }}
    end
  end

  defp total(document) do
    text = document |> Floki.find("h4.list-products-amount") |> Floki.text()

    case Regex.run(~r/\AIlość ofert: ([0-9]{1,6})\z/u, String.trim(text)) do
      [_, total] -> {:ok, String.to_integer(total)}
      nil -> {:error, :malformed_pagination}
    end
  end

  defp page_count(body) do
    case Regex.run(~r/OfferPaginationVm\(\{\s*pagesCount:\s*([0-9]{1,4})\s*\}\)/, body) do
      [_, pages] -> {:ok, String.to_integer(pages)}
      nil -> {:error, :malformed_pagination}
    end
  end

  defp link(product),
    do: product |> Floki.find("h3.product-title a") |> Floki.attribute("href") |> List.first()

  defp normalize(shop, {product, category}) do
    with {:ok, title} <-
           ShopFeed.title(product |> Floki.find("h3.product-title a") |> Floki.text()),
         true <- ShopFeed.sealed_pokemon?(title, category) || :ignore,
         [_, id] <- Regex.run(@link, link(product) || ""),
         {:ok, url} <- product_url(shop, link(product)),
         {:ok, price} <- price(product),
         {:ok, in_stock} <- in_stock(product) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(product),
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

  defp product_url(shop, "/" <> _ = link) do
    with {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}#{link}", [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end

  defp price(product) do
    text =
      product
      |> Floki.find("span.product-price-wrap")
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
    cond do
      Floki.find(product, "span.availability-num") != [] and
          Floki.find(product, "button.btn-add-to-cart") != [] ->
        {:ok, true}

      product |> Floki.text() |> String.contains?("Brak produktu") ->
        {:ok, false}

      true ->
        :error
    end
  end

  defp image_url(product) do
    product
    |> Floki.find("div.product-image-container img")
    |> Floki.attribute("src")
    |> List.first()
    |> ShopFeed.image_url([@cdn])
  end
end
