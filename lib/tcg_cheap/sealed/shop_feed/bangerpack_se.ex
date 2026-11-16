defmodule TcgCheap.Sealed.ShopFeed.BangerpackSe do
  @moduledoc """
  Reads bangerpack.se, Bangerpack's shop for buyers in Sweden, priced in
  kronor. It publishes no product export (the Google Shopping exports on the
  shop's CDN are those of bangerpack.com, in euros), so the Pokémon category
  page (the shop's `feed_path`) is read: it answers every product of the
  category in one page, sold out ones included.

  The page states no total, so completeness rests on the shape: the fetch
  fails when the page has no product cards, and a card without an id, a
  title, a whole-krona price, a known stock state or a link is invalid.

  Each card carries the product id, title, price and stock state as data
  attributes; `i-lager` is in stock and `slut` is sold out. The price shown
  on the card must be that amount in kronor ("629 kr"). The category
  also lists accessories, figures and plush toys, so a product counts when
  it is sealed Pokémon (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its
  title). Links are relative to the shop's root; images are on the shop
  platform's CDN. There is no EAN in the listing. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @path ~r|\A/[a-z0-9-]+(?:/[a-z0-9-]+){1,3}\z|
  @price ~r/\A[1-9][0-9]{0,6}\z/
  @shown_price ~r/\A([0-9][0-9 \x{00A0}]*) kr\z/u

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.quickbutik.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, cards} <- cards(document) do
      {:ok, ShopFeed.offers(shop, cards, &normalize(shop, &1))}
    end
  end

  defp cards(document) do
    case Floki.find(document, "div.pcard[data-product-id]") do
      [] -> {:error, :malformed_listing}
      cards -> {:ok, cards}
    end
  end

  defp normalize(shop, card) do
    attribute = &(card |> Floki.attribute(&1) |> List.first())
    path = card |> Floki.find("a.pk-bild") |> Floki.attribute("href") |> List.first()

    with {:ok, title} <- ShopFeed.title(attribute.("data-s-title")),
         true <- ShopFeed.sealed_pokemon?(title, nil) || :ignore,
         {:ok, id} <- ShopFeed.product_id(attribute.("data-product-id")),
         true <- is_binary(path) and Regex.match?(@path, path),
         {:ok, price} <- price(attribute.("data-price"), card),
         {:ok, in_stock} <- in_stock(attribute.("data-lager")) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: "https://#{shop.host}#{path}",
           image_url: image_url(shop, card),
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

  defp price(value, card) when is_binary(value) do
    shown = card |> Floki.find(".pk-pris") |> Floki.text() |> String.trim()

    with true <- Regex.match?(@price, value),
         [_, digits] <- Regex.run(@shown_price, shown),
         ^value <- String.replace(digits, [" ", "\u00A0"], "") do
      ShopFeed.decimal_price(value)
    else
      _ -> :error
    end
  end

  defp price(_value, _card), do: :error

  defp in_stock("i-lager"), do: {:ok, true}
  defp in_stock("slut"), do: {:ok, false}
  defp in_stock(_state), do: :error

  # The card's picture is a 400 px rendition; the CDN serves the original
  # without the query.
  defp image_url(shop, card) do
    src = card |> Floki.find("img.bp-prod-img") |> Floki.attribute("src") |> List.first()

    case src && String.split(src, "?", parts: 2) do
      [original | _query] -> ShopFeed.image_url(original, image_hosts(shop))
      nil -> nil
    end
  end
end
