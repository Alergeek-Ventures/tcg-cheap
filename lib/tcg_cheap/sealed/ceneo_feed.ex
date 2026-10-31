defmodule TcgCheap.Sealed.CeneoFeed do
  @moduledoc """
  Reads a shop's Ceneo product feed (`<offers><o …>`) at its `feed_path` in
  one request. Shoper publishes it for the whole shop at
  `/console/integration/execute/name/CeneoV2`; the response may be up to
  64 MB. Ceneo feeds carry prices in PLN by definition and Shoper lists only
  products it has in stock.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name and `cat`). It is
  in stock when its `stock` is positive and its `avail` is one of Ceneo's
  shipping times (1, 3, 7 or 14 days) or 99 ("ask the shop"); 90 (on order)
  and 110 (preorder) are not. URLs and images must be on the shop's host;
  the EAN is the `EAN` attribute. See `TcgCheap.Sealed.ShopFeed` for the
  shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Shop, ShopFeed, XmlRecords}

  @max_body_bytes 64_000_000
  @fields [[], ["name"], ["cat"], ["imgs", "main"], ["attrs", "a"]]
  @in_stock_avail ~w(1 3 7 14 99)
  @out_of_stock_avail ~w(90 110)

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    opts = [max_body_bytes: @max_body_bytes]

    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [], req_options, opts),
         {:ok, offers} <-
           XmlRecords.parse(response.body, ["offers", "o"], @fields, &sealed_pokemon?/1) do
      {:ok, ShopFeed.offers(shop, offers, &normalize(shop, &1))}
    end
  end

  # Products with an invalid name are kept for normalize/2 to count.
  defp sealed_pokemon?(offer) do
    case ShopFeed.title(XmlRecords.text(offer, ["name"])) do
      {:ok, title} -> ShopFeed.sealed_pokemon?(title, XmlRecords.text(offer, ["cat"]))
      :error -> true
    end
  end

  defp normalize(shop, offer) do
    attr = &XmlRecords.attr(offer, [], &1)

    with {:ok, title} <- ShopFeed.title(XmlRecords.text(offer, ["name"])),
         {:ok, id} <- ShopFeed.product_id(attr.("id")),
         {:ok, _uri} <- ShopFeed.https_url(attr.("url"), [shop.host]),
         {:ok, price} <- ShopFeed.decimal_price(attr.("price")),
         {:ok, in_stock} <- in_stock(attr.("avail"), attr.("stock")) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: attr.("url"),
           image_url:
             ShopFeed.image_url(
               XmlRecords.attr(offer, ["imgs", "main"], "url"),
               image_hosts(shop)
             ),
           ean: Ean.normalize(ean(offer)),
           price: price,
           in_stock: in_stock
         }
       ]}
    else
      _ -> :invalid
    end
  end

  defp in_stock(avail, stock) when is_binary(stock) do
    case Integer.parse(stock) do
      {count, ""} when avail in @in_stock_avail -> {:ok, count > 0}
      {_count, ""} when avail in @out_of_stock_avail -> {:ok, false}
      _ -> :error
    end
  end

  defp in_stock(_avail, _stock), do: :error

  defp ean(offer) do
    Enum.find_value(Map.get(offer, ["attrs", "a"], []), fn
      %{attrs: %{"name" => "EAN"}, text: text} -> text
      _ -> nil
    end)
  end
end
