defmodule TcgCheap.Sealed.Empik do
  @moduledoc """
  Reads Empik's own collectible cards on empik.com: the category listing
  `feed_path` filtered to the seller Empik (`mpShopIdFacet=0`), so the offers
  of empik.com's marketplace sellers are left out. Pages hold 60 products;
  page n is the path with `,<60·(n−1)+1>` appended. The listing states its
  size ("Znaleziono 314 produktów"), from which its page count follows;
  `TcgCheap.Sealed.HtmlListing.read/3` reads every page, at most `max_pages`,
  and fails the fetch unless the distinct products read match that size.
  Empik orders products that tie on the sort key anew for each page, so one
  pass shows some products twice at a page edge and misses as many others
  (2026-11-12: 280–295 distinct of 312, three passes together all 312); the
  listing is read again, up to four passes in all, until the passes
  together hold every product. Each page also holds a sponsored tile
  (`data-ad-info`), usually another seller's, which is skipped; a marketplace
  product among the rest would break the count and fail the fetch too.

  The category mixes Panini, Lorcana and card accessories, so a product counts
  when it is sealed Pokémon (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on
  its name). The listing shows only products that can be ordered, each with
  its dispatch time (`data-availabilityType`, e.g. `IN_24_H`), which is what
  counts as in stock; `PRE_SALE` marks a pre-order. Its price is the tile's current price
  (`data-product-price`; app-only prices are not shown). The product id is
  Empik's own (`p…`); the image is on Empik's media server. There is no EAN.
  See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed}

  @page_size 60
  # A pass is six pages of about 2 s each, so four stay well within the job's
  # 5-minute timeout.
  @passes 4
  @image_host "ecsmedia.pl"
  @found ~r/\AZnaleziono ([0-9]{1,6}) produkt/

  @impl true
  def image_hosts(%Shop{}), do: [@image_host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read(&request(shop, req_options, &1), shop.max_pages, @passes) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp request(shop, req_options, number) do
    path =
      if number == 1,
        do: shop.feed_path,
        else: "#{shop.feed_path},#{@page_size * (number - 1) + 1}"

    with {:ok, response} <- ShopFeed.get(shop, path, [mpShopIdFacet: 0], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, total} <- total(document),
         {:ok, current} <- current(document) do
      {:ok,
       %{
         number: current,
         last: max(div(total + @page_size - 1, @page_size), 1),
         total: total,
         products:
           document
           |> Floki.find("div.search-list-item[data-product-id]")
           |> Enum.reject(&(Floki.attribute(&1, "data-ad-info") != []))
           |> Enum.map(&product/1)
       }}
    end
  end

  defp total(document) do
    with text when is_binary(text) <- HtmlListing.text(Floki.find(document, ".switcher__found")),
         [_, count] <- Regex.run(@found, text),
         {total, ""} when total > 0 <- Integer.parse(count) do
      {:ok, total}
    else
      _ -> {:error, :malformed_listing}
    end
  end

  # A listing of one page has no pagination.
  defp current(document) do
    case Floki.find(document, ".pagination a.active") do
      [] ->
        {:ok, 1}

      [active | _] ->
        case Integer.parse(HtmlListing.text(active) || "") do
          {number, ""} when number > 0 -> {:ok, number}
          _ -> {:error, :malformed_pagination}
        end
    end
  end

  defp product(tile) do
    attribute = &(tile |> Floki.attribute(&1) |> List.first())
    availability = HtmlListing.attr(tile, "div.info__availability", "data-availabilitytype")

    %{
      id: attribute.("data-product-id"),
      title: attribute.("data-product-name"),
      merchant: attribute.("data-merchant-id"),
      path: HtmlListing.attr(tile, "a.seoTitle", "href"),
      image: HtmlListing.attr(tile, "meta[itemprop=image]", "content"),
      price: attribute.("data-product-price"),
      in_stock: in_stock(availability),
      preorder: availability == "PRE_SALE"
    }
  end

  # A dispatch time ("IN_24_H", "IN_4_5_DAYS"…) is stock; "PRE_SALE" (a
  # pre-order), "RE_SALE" (a reprint awaited) and "UNAVAILABLE" are not.
  defp in_stock("IN_" <> _time), do: true
  defp in_stock(type) when is_binary(type), do: false
  defp in_stock(nil), do: nil

  defp normalize(shop, product) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- ShopFeed.sealed_pokemon?(title, nil) || :ignore,
         "0" <- product.merchant,
         {:ok, id} <- ShopFeed.product_id(product.id),
         "/" <> _ = link <- product.path,
         {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}#{link}", [shop.host]),
         {:ok, price} <- ShopFeed.decimal_price(product.price),
         in_stock when is_boolean(in_stock) <- product.in_stock do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: "https://#{shop.host}#{uri.path}",
           image_url: ShopFeed.image_url(product.image, [@image_host]),
           ean: nil,
           price: price,
           in_stock: in_stock,
           preorder: product.preorder
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end
end
