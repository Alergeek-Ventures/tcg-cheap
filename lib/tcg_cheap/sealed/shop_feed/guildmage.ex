defmodule TcgCheap.Sealed.ShopFeed.Guildmage do
  @moduledoc """
  Reads the Pokémon category of guildmage.pl, a Next.js storefront that renders
  its product cards on the server: the category's `feed_path` with `?page=N`
  from 1 to the `totalPages` the page's pagination data states, which must not
  exceed `max_pages`. The pagination data also states the category's size
  (`totalElements`); it must stay the same on every page and match the distinct
  products read, so a missing or shifted page fails the fetch.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name and the game the
  card names). It is in stock when its card says "Dostępne N szt." and not when
  it says "Brak w magazynie". Prices are in złoty; the product id is the number
  closing the product's slug. Images are the shop's BaseLinker pictures,
  unwrapped from the Next.js image proxy. There is no EAN. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.Pages

  @cdn "upload.cdn.baselinker.com"
  @pagination ~r/\\"pagination\\":\{\\"size\\":[0-9]+,\\"totalElements\\":([0-9]+),\\"totalPages\\":([0-9]+),\\"number\\":([0-9]+)\}/
  @slug ~r|\A/product/[^\s/?#]*-([0-9]{1,12})\z|
  @price ~r/\A([0-9]{1,7}),([0-9]{2}) zł\z/u
  @available ~r/\ADostępne [0-9]{1,6} szt\.\z/u
  @spaces ~r/\s+/u

  @impl true
  def image_hosts(%Shop{}), do: [@cdn]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, pages} <- Pages.read(&request(shop, req_options, &1), shop.max_pages),
         {:ok, products} <- Pages.products(pages, &link/1) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: number], req_options),
         {:ok, document} <- ShopFeed.html(response),
         [_, total, pages, current] <- Regex.run(@pagination, response.body) do
      {:ok,
       %{
         products: Floki.find(document, "article.MuiCard-root"),
         total: String.to_integer(total),
         stated: {String.to_integer(total), String.to_integer(pages)},
         pages: String.to_integer(pages),
         number: String.to_integer(current)
       }}
    else
      # The shop's answer ({:http_status, 503}, a transport error), not ours.
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_response}
    end
  end

  defp link(product),
    do: product |> Floki.find("a[href^='/product/']") |> Floki.attribute("href") |> List.first()

  defp normalize(shop, product) do
    link = link(product)

    with {:ok, title} <- ShopFeed.title(product |> Floki.find("h3") |> Floki.text()),
         category = product |> Floki.find("p") |> Floki.text(),
         true <- ShopFeed.sealed_pokemon?(title, category) || :ignore,
         [_, id] <- Regex.run(@slug, link || ""),
         url = "https://#{shop.host}#{URI.encode(link)}",
         {:ok, _uri} <- ShopFeed.https_url(url, [shop.host]),
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

  defp price(product) do
    text =
      product
      |> Floki.find("h6")
      |> Floki.text()
      |> String.replace(@spaces, " ")
      |> String.trim()

    case Regex.run(@price, text) do
      [_, zloty, grosze] -> ShopFeed.decimal_price("#{zloty}.#{grosze}")
      nil -> :error
    end
  end

  defp in_stock(product) do
    chip = product |> Floki.find(".MuiChip-label") |> Floki.text() |> String.trim()

    cond do
      Regex.match?(@available, chip) -> {:ok, true}
      chip == "Brak w magazynie" -> {:ok, false}
      true -> :error
    end
  end

  # The card's picture goes through `/_next/image?url=<picture>&w=…`.
  defp image_url(product) do
    with [src] <- product |> Floki.find("img") |> Floki.attribute("src") |> Enum.take(1),
         %URI{path: "/_next/image", query: query} when is_binary(query) <- URI.parse(src),
         {:ok, url} <- query |> URI.decode_query() |> Map.fetch("url") do
      ShopFeed.image_url(url, [@cdn])
    else
      _ -> nil
    end
  end
end
