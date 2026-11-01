defmodule TcgCheap.Sealed.SkyShop do
  @moduledoc """
  Reads a Sky-Shop storefront's category listing; Sky-Shop publishes no
  product feed. The shop's `feed_path` is its Pokémon category
  (`/<name>-c<id>` or a custom alias); it is read sorted by name, so that
  products going in and out of stock do not shift between pages while they
  are read: `<feed_path>/sort/name/`, then `<feed_path>/sort/name/pa/<n>` up
  to the last page the pagination announces ("Strona 2 z 9"), at most
  `max_pages` pages. A listing without pagination is one page.

  Current themes state the category's size ("Liczba produktów: N"); the
  distinct products read must equal it, so a page that is missing, replaced
  or shifted fails the fetch. Older themes state no size, so completeness
  rests on the page count alone. A page without product tiles or without a
  readable tile (see `TcgCheap.Sealed.HtmlListing`) fails the fetch.

  A product counts when its title names a sealed product
  (`TcgCheap.Sealed.Matcher.sealed_title?/1`), the category being the shop's
  Pokémon one. The listing price is the current gross price in złoty (the
  promotional one, not the lowest price of the last 30 days). A product is in
  stock when its tile has an add-to-cart button and is not marked "Preorder"
  or "Przedsprzedaż"; "Produkt niedostępny" and "Oczekuje na dostawę"
  products are not. Links and images are made absolute on the shop's host.
  Listings carry no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Matcher, Shop}

  @tiles ".products_lists_pages_products_presentation figure.product-tile, " <>
           ".product-tiles-wrapper figure.product-tile"
  @preorder ["Preorder", "Przedsprzedaż"]
  @unavailable ["Produkt niedostępny", "Oczekuje na dostawę"]

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- HtmlListing.read(&request(shop, req_options, &1), shop.max_pages) do
      {:ok, HtmlListing.offers(shop, products, &Matcher.sealed_title?/1)}
    end
  end

  defp request(shop, req_options, number) do
    path = "#{shop.feed_path}/sort/name/" <> if(number == 1, do: "", else: "pa/#{number}")

    with {:ok, document} <- HtmlListing.page(shop, path, req_options),
         do: parse_page(document)
  end

  defp parse_page(document) do
    with {:ok, number, last} <- pagination(document),
         {:ok, total} <- total(document),
         [_ | _] = tiles <- Floki.find(document, @tiles) do
      {:ok, %{number: number, last: last, total: total, products: Enum.map(tiles, &tile/1)}}
    else
      _ -> {:error, :unrecognised_listing}
    end
  end

  # "Strona 2 z 9" on the selected page's link; no such link, one page.
  defp pagination(document) do
    case document
         |> Floki.attribute("[data-translate-page]", "data-translate-page")
         |> Enum.uniq() do
      [] ->
        {:ok, 1, 1}

      [label] ->
        case Regex.run(~r/\AStrona (\d{1,3}) z (\d{1,3})\z/, label) do
          [_, number, last] -> {:ok, String.to_integer(number), String.to_integer(last)}
          nil -> :error
        end

      _ ->
        :error
    end
  end

  # "Liczba produktów: 30" on current themes; nil where the theme has none.
  defp total(document) do
    case document |> Floki.find(".core_itemCount") |> Enum.map(&Floki.text/1) |> Enum.uniq() do
      [] -> {:ok, nil}
      [text] -> integer(String.trim(text))
      _ -> :error
    end
  end

  defp integer(text) do
    case Integer.parse(text) do
      {number, ""} when number >= 0 -> {:ok, number}
      _ -> :error
    end
  end

  defp tile(tile) do
    link = tile |> Floki.find("a.product-name, .product-name a") |> List.first()

    %{
      id: first(Floki.attribute(tile, ".core_addToStore", "data-product-id")),
      title: link && link |> Floki.text() |> String.trim(),
      path: link && first(Floki.attribute(link, "href")),
      image: first(Floki.attribute(tile, "img.product-img, img.product-main-img", "src")),
      price:
        first(
          Floki.attribute(
            tile,
            ".product-price-default .core_priceFormat, .price-special .core_priceFormat",
            "data-price"
          )
        ),
      in_stock: in_stock(tile)
    }
  end

  defp in_stock(tile) do
    text = Floki.text(tile)

    cond do
      String.contains?(text, @unavailable) -> false
      Floki.find(tile, "[data-cy=addToCartButton]") == [] -> nil
      preorder?(tile) -> false
      true -> true
    end
  end

  defp preorder?(tile) do
    badges = tile |> Floki.find(".product-status span") |> Enum.map(&String.trim(Floki.text(&1)))
    Enum.any?(badges, &(&1 in @preorder))
  end

  defp first([value | _]), do: value
  defp first([]), do: nil
end
