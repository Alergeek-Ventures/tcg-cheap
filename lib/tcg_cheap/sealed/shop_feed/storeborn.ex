defmodule TcgCheap.Sealed.ShopFeed.Storeborn do
  @moduledoc """
  Reads the category listings of a Storeborn storefront (a server-rendered
  Vike app); it publishes no product feed and its API paths are closed by
  robots.txt. The shop's `listing_paths` are its Pokémon categories
  (`/kategorier/<slug>`), each read page by page (`?page=<n>` from `n = 2`).

  A listing page carries the data it renders as JSON in its
  `script#vike_pageContext`: the `category` it lists (which must be the one
  asked for), the `pagination` (`page`, `totalPages`, `total`) and the page's
  `products`. The pages must agree with the stated total, and a page that is
  not the one asked for, a payload that cannot be read, and going past
  `max_pages` pages fail the fetch, as does a listing whose distinct products
  are not `total` (`TcgCheap.Sealed.ShopFeed.HtmlListing.read/3`). Products tie
  on the default sort (price), so their order between requests is not known to
  be stable: a listing short of its total is read again, up to three passes.

  The JSON holds the price without VAT for some products, so the price is the
  one the product card of the same page shows (`.sb-price--current`, whole
  krona, VAT included), found by the card's link. A product without a card
  or a readable price is skipped and counted, as everywhere. A product is in
  stock when it is `inStock` and `purchasable`; a product that may be bought
  beyond its stock (`allowBackorders` other than `never`) or whose title or
  slug says pre-order (`TcgCheap.Sealed.Matcher.preorder_title?/1`, "kommer
  snart") is a pre-order (`preorder`) and never in stock. Products the
  shop's `excluded_title_phrases` name in the title or the slug (packs opened
  live on stream) are left out. The id is the product's `id`, the link
  `/produkter/<slug>` and the photo its first image, on the platform's media
  hosts. The listings carry no EAN. Requests are three seconds apart. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @image_hosts ["cdn.storeborn.com", "storeborn.b-cdn.net"]
  @pause_ms 3_000
  @passes 3
  @category ~r|\A/kategorier/([a-z0-9]+(?:-[a-z0-9]+)*)\z|
  @slug ~r|\A[a-z0-9]+(?:-[a-z0-9]+)*\z|
  @price ~r/\A([0-9]{1,3}(?:[\s\x{a0}][0-9]{3})*|[0-9]+)\s*kr\z/u

  @impl true
  def image_hosts(%Shop{}), do: @image_hosts

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_listing(shop, req_options, &1)) do
      products = Enum.reject(products, &excluded?(shop, &1))
      {:ok, HtmlListing.offers(shop, products, &Matcher.sealed_title?/1)}
    end
  end

  defp read_listing(shop, req_options, path) do
    case Regex.run(@category, path) do
      [_, slug] ->
        HtmlListing.read(
          &request(shop, req_options, path, slug, &1),
          shop.max_pages,
          @passes
        )

      nil ->
        {:error, :invalid_category}
    end
  end

  defp request(shop, req_options, path, slug, number) do
    params = if number == 1, do: [], else: [page: number]

    with {:ok, response} <- ShopFeed.get(shop, path, params, req_options, pause_ms: @pause_ms),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, context} <- page_context(document),
         {:ok, data} <- listing_of(context, slug) do
      page(data, prices(document), number)
    end
  end

  # The page context is JSON in which Vike has escaped every slash once more
  # (`\\/`), so `\\/` is a slash.
  defp page_context(document) do
    with [script | _] <- Floki.find(document, "script#vike_pageContext"),
         text = script |> Floki.text(js: true) |> String.replace("\\\\/", "/"),
         {:ok, %{"data" => %{} = data}} <- Jason.decode(text) do
      {:ok, data}
    else
      _ -> {:error, :unrecognised_listing}
    end
  end

  # A listing path the shop does not know shows another page, not an error.
  defp listing_of(%{"category" => %{"slug" => slug}} = data, slug), do: {:ok, data}
  defp listing_of(_data, _slug), do: {:error, :unrecognised_listing}

  defp page(
         %{
           "products" => products,
           "pagination" => %{
             "page" => number,
             "pageSize" => size,
             "total" => total,
             "totalPages" => last
           }
         },
         prices,
         number
       )
       when is_list(products) and is_integer(size) and size > 0 and is_integer(total) and
              total >= 0 and is_integer(last) and last >= 1 do
    expected = total |> Kernel.-((number - 1) * size) |> max(0) |> min(size)

    if last == max(div(total + size - 1, size), 1) and length(products) == expected,
      do:
        {:ok,
         %{
           number: number,
           last: last,
           total: total,
           products: Enum.map(products, &product(&1, prices))
         }},
      else: {:error, :malformed_pagination}
  end

  defp page(_data, _prices, _number), do: {:error, :unrecognised_listing}

  # The price each product card shows, by the card's product slug.
  defp prices(document) do
    for card <- Floki.find(document, "a.sb-product-card"),
        ["/produkter/" <> slug] <- [Floki.attribute(card, "href")],
        text = card |> Floki.find(".sb-price--current") |> HtmlListing.text(),
        is_binary(text),
        [_, digits] <- [Regex.run(@price, text)],
        into: %{},
        do: {slug, String.replace(digits, ~r/\D/u, "")}
  end

  defp product(%{"slug" => slug} = doc, prices) when is_binary(slug) do
    if Regex.match?(@slug, slug) do
      title = doc["name"]
      preorder? = preorder?(doc, title, slug)

      %{
        id: doc["id"],
        title: title,
        path: "/produkter/" <> slug,
        image: image(doc["images"]),
        price: prices[slug],
        in_stock: if(preorder?, do: false, else: in_stock(doc)),
        preorder: preorder?
      }
    else
      unreadable()
    end
  end

  defp product(_doc, _prices), do: unreadable()

  defp unreadable, do: %{id: nil, title: nil, path: nil, image: nil, price: nil, in_stock: nil}

  defp preorder?(doc, title, slug) do
    backorders = doc["inventorySettings"]["allowBackorders"]

    backorders not in [nil, "never"] or
      (is_binary(title) and Matcher.preorder_title?(title)) or
      Matcher.preorder_title?(String.replace(slug, "-", " ")) or
      String.contains?(Matcher.normalize(to_string(title)), "kommer snart")
  end

  defp in_stock(%{"inStock" => in_stock, "purchasable" => purchasable})
       when is_boolean(in_stock) and is_boolean(purchasable),
       do: in_stock and purchasable

  defp in_stock(_doc), do: nil

  defp image([%{"url" => url} | _images]) when is_binary(url), do: url
  defp image(_images), do: nil

  # A pack opened live is named so in its title or its slug.
  defp excluded?(shop, %{title: title, path: "/produkter/" <> slug}) do
    ShopFeed.excluded_text?(shop, to_string(title)) or ShopFeed.excluded_text?(shop, slug)
  end

  defp excluded?(_shop, _product), do: false
end
