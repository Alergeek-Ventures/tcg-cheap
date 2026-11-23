defmodule TcgCheap.Sealed.ShopFeed.ZboziFeed do
  @moduledoc """
  Reads a Shoptet shop whose robots.txt forbids its listing pagination from
  its Zboží.cz feed (`<SHOP><SHOPITEM>`, at `feed_path`, one request for the
  whole shop, up to 64 MB) and the product pages of the Pokémon products in it.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its `PRODUCT` title and
  `CATEGORYTEXT`). The feed gives its URL, title, image and EAN. Its
  `PRICE_VAT` (`PRICE` is without VAT) is only a first reading and its
  `DELIVERY_DATE` says nothing reliable about stock, so the product page
  decides both: it is asked for once per product (the URL without its query),
  at most `max_pages` pages, and more fail the fetch instead of being cut off.
  Every such page is required: one that cannot be read fails the fetch, and
  one whose price differs from the feed's is a reading of the price a buyer
  sees, which wins.

  A product with variants lists them on its page as `priceId` radio buttons
  (`data-customerprice`, and `data-disable-button` on one that cannot be
  ordered), which the feed's `?variantId=` URLs name; any other product has
  one schema.org offer (price, currency, availability). Only `InStock` is in
  stock; `PreOrder`, or a pre-order title, is a pre-order. A feed product the
  page does not show (a variant it does not list, another shape of page) is
  skipped like any invalid product. The feed has no product ids: the id is the
  variant's (`v…`) or the page's product id (`p…`). Images come from the shop's
  host or Shoptet's CDN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  require Logger

  alias TcgCheap.Sealed.{Ean, Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.{HtmlListing, XmlRecords}

  @max_body_bytes 64_000_000
  # The shop's bot policy allows one request every 3 seconds.
  @page_pause_ms 3_000
  @fields [["PRODUCT"], ["CATEGORYTEXT"], ["URL"], ["IMGURL"], ["PRICE_VAT"], ["EAN"]]
  @form "#product-detail-form"
  @variant_radios "#{@form} input[type=radio][name=priceId][data-customerprice]"
  @variant_id ~r/\A[0-9]{1,12}\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.myshoptet.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, response} <-
           ShopFeed.get(shop, shop.feed_path, [], req_options, max_body_bytes: @max_body_bytes),
         {:ok, items} <-
           XmlRecords.parse(response.body, ["SHOP", "SHOPITEM"], @fields, &included?/1),
         {:ok, pages} <- read_pages(shop, items, req_options) do
      {:ok, ShopFeed.offers(shop, items, &normalize(shop, pages, &1))}
    end
  end

  # Items with an invalid title are kept for normalize/3 to count.
  defp included?(item) do
    case ShopFeed.title(XmlRecords.text(item, ["PRODUCT"])) do
      {:ok, title} -> ShopFeed.sealed_pokemon?(title, XmlRecords.text(item, ["CATEGORYTEXT"]))
      :error -> true
    end
  end

  defp read_pages(shop, items, req_options) do
    paths =
      items
      |> Enum.flat_map(fn item ->
        case product_url(shop, item) do
          {:ok, uri, _variant} -> [uri.path]
          :error -> []
        end
      end)
      |> Enum.uniq()

    if length(paths) > shop.max_pages,
      do: {:error, {:too_many_pages, length(paths)}},
      else: Enum.reduce_while(paths, {:ok, %{}}, &add_page(shop, req_options, &1, &2))
  end

  defp add_page(shop, req_options, path, {:ok, pages}) do
    case read_page(shop, path, req_options) do
      {:ok, page} -> {:cont, {:ok, Map.put(pages, path, page)}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp read_page(shop, path, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options, pause_ms: @page_pause_ms),
         {:ok, document} <- ShopFeed.html(response),
         do: page(document)
  end

  # The page's readings by variant id (nil for a product without variants):
  # `%{id: …, price: …, availability: :in_stock | :preorder | :out_of_stock}`.
  defp page(document) do
    currency = HtmlListing.attr(document, ~s(#{@form} [itemprop="priceCurrency"]), "content")

    with {:ok, readings} <- readings(document) do
      {:ok,
       Map.new(readings, fn {key, reading} -> {key, Map.put(reading, :currency, currency)} end)}
    end
  end

  defp readings(document) do
    case Floki.find(document, @variant_radios) do
      [] -> single_offer(document)
      radios -> {:ok, Enum.map(radios, &variant/1)}
    end
  end

  defp variant(radio) do
    id = radio |> Floki.attribute("value") |> List.first()
    price = radio |> Floki.attribute("data-customerprice") |> List.first()
    orderable? = Floki.attribute(radio, "data-disable-button") == []

    {id,
     %{
       id: "v#{id}",
       price: price,
       availability: if(orderable?, do: :in_stock, else: :out_of_stock)
     }}
  end

  defp single_offer(document) do
    offer = HtmlListing.first(document, ~s(#{@form} [itemprop="offers"]))
    product_id = HtmlListing.attr(document, ~s(#{@form} [itemprop="productID"]), "content")
    price = offer && HtmlListing.attr(offer, ~s([itemprop="price"]), "content")
    availability = offer && HtmlListing.attr(offer, ~s([itemprop="availability"]), "href")

    if is_binary(product_id) and is_binary(price) and is_binary(availability),
      do:
        {:ok,
         [{nil, %{id: "p#{product_id}", price: price, availability: availability(availability)}}]},
      else: {:error, :malformed_response}
  end

  defp availability("https://schema.org/InStock"), do: :in_stock
  defp availability("https://schema.org/PreOrder"), do: :preorder
  defp availability(_other), do: :out_of_stock

  # The product's URL on the shop's host: its path names the page, a
  # `variantId` query one of its variants.
  defp product_url(shop, item) do
    with {:ok, uri} <- ShopFeed.https_url(XmlRecords.text(item, ["URL"]), [shop.host]),
         {:ok, variant} <- variant_id(uri.query) do
      {:ok, uri, variant}
    end
  end

  defp variant_id(nil), do: {:ok, nil}

  defp variant_id(query) do
    with %{"variantId" => id} = params when map_size(params) == 1 <- URI.decode_query(query),
         true <- Regex.match?(@variant_id, id) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  defp normalize(shop, pages, item) do
    text = &XmlRecords.text(item, [&1])

    with {:ok, title} <- ShopFeed.title(text.("PRODUCT")),
         {:ok, uri, variant} <- product_url(shop, item),
         %{} = reading <- pages |> Map.get(uri.path, %{}) |> Map.get(variant),
         true <- reading.currency == shop.currency,
         {:ok, price} <- ShopFeed.decimal_price(reading.price) do
      log_price_difference(shop, text.("URL"), price, text.("PRICE_VAT"))
      preorder = reading.availability == :preorder or Matcher.preorder_title?(title)

      {:ok,
       [
         %{
           shop_product_id: reading.id,
           title: title,
           url: text.("URL"),
           image_url: ShopFeed.image_url(text.("IMGURL"), image_hosts(shop)),
           ean: Ean.normalize(text.("EAN")),
           price: price,
           in_stock: reading.availability == :in_stock and not preorder,
           preorder: preorder
         }
       ]}
    else
      _ -> :invalid
    end
  end

  defp log_price_difference(shop, url, price, feed_price) do
    with {:ok, feed_price} <- ShopFeed.decimal_price(feed_price),
         false <- Decimal.equal?(price, feed_price) do
      Logger.info(
        "sealed fetch #{shop.key}: #{url} costs #{price} on its page, #{feed_price} in the feed"
      )
    else
      _ -> :ok
    end
  end
end
