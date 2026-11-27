defmodule TcgCheap.Sealed.ShopFeed.Empik do
  @moduledoc """
  Reads Empik's own collectible cards on empik.com, filtered to the seller
  Empik (`mpShopIdFacet=0`), so the offers of empik.com's marketplace sellers
  are left out. Pages hold 60 products; page n is the path with
  `,<60·(n−1)+1>` appended. A listing states its size ("Znaleziono 314
  produktów"), from which its page count follows;
  `TcgCheap.Sealed.ShopFeed.HtmlListing.read/3` reads every page, at most
  `max_pages`, and fails the fetch unless the distinct products read match that
  size.

  The whole category (`feed_path`) is not read:
  Empik orders products that tie on the sort key anew for every page, so a
  pass over its five pages shows some products twice and misses as many
  others, even four passes can leave some out, and `robots.txt` forbids
  choosing a sort order (`sort=`). Instead
  the listings that hold the Pokémon products are read, each short enough
  for one page, where nothing can tie across pages and a pass is exact: the
  category filtered to the licence Pokémon (`licenseFacet=pokemon`) and the
  subcategories of `listing_paths` that hold sealed products (box sets, packs,
  tins), so a product missing the licence tag is still found by its
  subcategory. A listing that grows past one page is still read in up to
  four passes.

  Each page also holds sponsored tiles (`data-ad-info`), products of any
  category, which are skipped as products but counted by the listing's stated
  size (the distinct products plus the sponsored tiles that are not among them), so their ids go to the
  completeness check as `promoted`; see `TcgCheap.Sealed.ShopFeed.HtmlListing`
  for the rule they must follow.

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

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @page_size 60
  # Only a listing of several pages can fall short of its total, so a pass of
  # one page ends the read; four passes of the longest stay well within the
  # job's 5-minute timeout.
  @passes 4
  @licence [licenseFacet: "pokemon"]
  @image_host "ecsmedia.pl"
  @found ~r/\AZnaleziono ([0-9]{1,6}) produkt/

  @impl true
  def image_hosts(%Shop{}), do: [@image_host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    listings = [{shop.feed_path, @licence} | Enum.map(shop.listing_paths, &{&1, []})]

    with {:ok, products} <- HtmlListing.read_paths(listings, &read(shop, req_options, &1)) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp read(shop, req_options, {path, filter}),
    do: HtmlListing.read(&request(shop, req_options, path, filter, &1), shop.max_pages, @passes)

  defp request(shop, req_options, listing, filter, number) do
    path =
      if number == 1,
        do: listing,
        else: "#{listing},#{@page_size * (number - 1) + 1}"

    with {:ok, response} <- ShopFeed.get(shop, path, [mpShopIdFacet: 0] ++ filter, req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, total} <- total(document),
         {:ok, current} <- current(document) do
      {promoted, products} =
        document
        |> Floki.find("div.search-list-item[data-product-id]")
        |> Enum.split_with(&(Floki.attribute(&1, "data-ad-info") != []))

      {:ok,
       %{
         number: current,
         last: max(div(total + @page_size - 1, @page_size), 1),
         total: total,
         products: Enum.map(products, &product/1),
         promoted: Enum.map(promoted, &(&1 |> Floki.attribute("data-product-id") |> List.first()))
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
