defmodule TcgCheap.Sealed.GoogleFeed do
  @moduledoc """
  Reads a shop's Google Merchant product feed (Atom with `g:` fields) at its
  `feed_path` in one request. Shoper publishes it for the whole shop at
  `/console/integration/execute/name/GoogleProductSearch`; such exports reach
  tens of megabytes, so the response may be up to 64 MB.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and
  `g:product_type`). Its price is `g:price`, or a lower `g:sale_price`
  while `g:sale_price_effective_date` (if given) includes now, in PLN;
  `g:availability` "in stock" (or `in_stock`) is in stock, "out of stock",
  "preorder" and "backorder" are not. Links and images must be on the shop's host; EANs come
  from `g:gtin`. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Shop, ShopFeed, XmlRecords}

  @max_body_bytes 64_000_000
  @fields [
    ["g:id"],
    ["title"],
    ["g:product_type"],
    ["link"],
    ["g:image_link"],
    ["g:availability"],
    ["g:price"],
    ["g:sale_price"],
    ["g:sale_price_effective_date"],
    ["g:gtin"]
  ]

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    opts = [max_body_bytes: @max_body_bytes]

    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [], req_options, opts),
         {:ok, entries} <-
           XmlRecords.parse(response.body, ["feed", "entry"], @fields, &sealed_pokemon?/1) do
      now = DateTime.utc_now()
      {:ok, ShopFeed.offers(shop, entries, &normalize(shop, now, &1))}
    end
  end

  # Products with an invalid title are kept for normalize/3 to count.
  defp sealed_pokemon?(entry) do
    case ShopFeed.title(XmlRecords.text(entry, ["title"])) do
      {:ok, title} -> ShopFeed.sealed_pokemon?(title, XmlRecords.text(entry, ["g:product_type"]))
      :error -> true
    end
  end

  defp normalize(shop, now, entry) do
    text = &XmlRecords.text(entry, [&1])

    with {:ok, title} <- ShopFeed.title(text.("title")),
         {:ok, id} <- ShopFeed.product_id(text.("g:id")),
         {:ok, _uri} <- ShopFeed.https_url(text.("link"), [shop.host]),
         {:ok, price} <- price(text.("g:price")),
         {:ok, sale_price} <-
           sale_price(text.("g:sale_price"), text.("g:sale_price_effective_date"), now),
         {:ok, in_stock} <- in_stock(text.("g:availability")) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: text.("link"),
           image_url: ShopFeed.image_url(text.("g:image_link"), image_hosts(shop)),
           ean: Ean.normalize(text.("g:gtin")),
           price: lower(sale_price, price),
           in_stock: in_stock
         }
       ]}
    else
      _ -> :invalid
    end
  end

  defp price(value) when is_binary(value) do
    case String.split(value, " ") do
      [amount, "PLN"] -> ShopFeed.decimal_price(amount)
      _ -> :error
    end
  end

  defp price(_value), do: :error

  # A "sale" price above the regular one is not a sale.
  defp lower(nil, price), do: price
  defp lower(sale_price, price), do: Decimal.min(sale_price, price)

  defp sale_price(nil, _dates, _now), do: {:ok, nil}
  defp sale_price(value, nil, _now), do: price(value)

  defp sale_price(value, dates, now) do
    with [from, to] <- String.split(dates, "/"),
         {:ok, from, _offset} <- DateTime.from_iso8601(from),
         {:ok, to, _offset} <- DateTime.from_iso8601(to),
         {:ok, price} <- price(value) do
      if DateTime.compare(now, from) != :lt and DateTime.compare(now, to) != :gt,
        do: {:ok, price},
        else: {:ok, nil}
    else
      _ -> :error
    end
  end

  defp in_stock(value) when value in ["in stock", "in_stock"], do: {:ok, true}

  defp in_stock(value)
       when value in ["out of stock", "out_of_stock", "preorder", "backorder"],
       do: {:ok, false}

  defp in_stock(_value), do: :error
end
