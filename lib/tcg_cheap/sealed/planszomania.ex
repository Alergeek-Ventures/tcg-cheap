defmodule TcgCheap.Sealed.Planszomania do
  @moduledoc """
  Reads the search results of planszomania.pl, which runs its own shop
  software. Its Pokémon category lists only accessories and its collectible
  card category only what is in stock, but the search for `pokemon` (the
  shop's `feed_path`) answers one page with every matching product, sold out
  ones included.

  The page states no total, so completeness rests on the shape: the fetch
  fails when the page is not a result table, has no product rows, or a row
  lacks a link, price or availability. The search is not capped (a broader
  search returns far more rows than this one).

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its title and the category
  the row names). It is in stock when its row has an add-to-cart button;
  `niedostępny` and `na zamówienie` (made to order in 7–30 days) are not.
  Prices are in złoty; links and thumbnails are relative to the shop's root.
  There is no EAN in the listing. Bytes that are not valid UTF-8, which some
  titles contain, are dropped. See `TcgCheap.Sealed.ShopFeed` for the shared
  limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @link ~r|\A[a-z0-9-]+/([0-9]{1,9})/[^\s]+\.html\z|
  @price ~r/\A([0-9]{1,7}\.[0-9]{2}) PLN/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [], req_options),
         {:ok, document} <- ShopFeed.html(scrub(response)),
         {:ok, rows} <- rows(document) do
      {:ok, ShopFeed.offers(shop, rows, &normalize(shop, &1))}
    end
  end

  # The shop's pages sometimes carry a broken byte inside a title ("Pok\xC3mon").
  defp scrub(%Req.Response{body: body} = response),
    do: %{response | body: String.replace_invalid(body, "")}

  defp rows(document) do
    rows =
      document
      |> Floki.find("table#tab_itemlist tr")
      |> Enum.filter(&(Floki.find(&1, "td[class^=td_itemlist_nazwa]") != []))

    if rows == [], do: {:error, :malformed_listing}, else: {:ok, rows}
  end

  defp normalize(shop, row) do
    link = row |> Floki.find("a.title") |> Floki.attribute("href") |> List.first()

    with {:ok, title} <- ShopFeed.title(row |> Floki.find("a.title") |> Floki.text()),
         true <- ShopFeed.sealed_pokemon?(title, category(row)) || :ignore,
         [_, id] <- Regex.run(@link, link || ""),
         {:ok, url} <- ShopFeed.https_url("https://#{shop.host}/#{link}", [shop.host]),
         {:ok, price} <- price(row),
         {:ok, in_stock} <- in_stock(row) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: URI.to_string(url),
           image_url: image_url(shop, row),
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

  defp category(row),
    do: row |> Floki.find("td[class^=td_itemlist_nazwa] span.span_small") |> Floki.text()

  defp price(row) do
    text = row |> Floki.find("td[class^=td_itemlist_cena]") |> Floki.text() |> String.trim()

    case Regex.run(@price, text) do
      [_, value] -> ShopFeed.decimal_price(value)
      nil -> :error
    end
  end

  defp in_stock(row) do
    cell = Floki.find(row, "td[class^=td_itemlist_cena]")
    text = Floki.text(cell)

    cond do
      Floki.find(cell, "a.a_small_button") != [] -> {:ok, true}
      String.contains?(text, ["niedostępny", "na zamówienie"]) -> {:ok, false}
      true -> :error
    end
  end

  defp image_url(shop, row) do
    case row
         |> Floki.find("td.td_itemlist_gamebox img")
         |> Floki.attribute("src")
         |> List.first() do
      "thumbs/" <> _ = src -> ShopFeed.image_url("https://#{shop.host}/#{src}", image_hosts(shop))
      _ -> nil
    end
  end
end
