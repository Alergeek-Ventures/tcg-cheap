defmodule TcgCheap.Sealed.Smajk do
  @moduledoc """
  Reads the Pokémon category of smajk.pl (Selesto software), whose HTML already
  carries the product grid although the page is finished by Vue in the browser:
  the category's `feed_path` with `?page=N` from 1 to the grid's `data-max-page`,
  which must not exceed `max_pages`. The grid states no total, so the fetch
  fails unless every page says it is the page asked for, every page but the last
  holds exactly `data-p-size` products, the last holds some, and no product
  appears twice.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name and the page's
  title, which is how Japanese boxes titled without "Pokémon" qualify). It is in
  stock when the grid's stock count is above zero and it is not marked
  "Wyprzedane". Its price is the current one (the struck-through original, when
  given, is ignored). The product id is the shop's own. There is no EAN. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @price ~r/\A([0-9]{1,7})\.([0-9]{2}) PLN\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, pages} <- fetch_pages(shop, req_options, 1, []) do
      {:ok, ShopFeed.offers(shop, pages, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, number, acc) do
    with {:ok, page} <- request(shop, req_options, number) do
      cond do
        page.number != number -> {:error, :pagination_changed}
        page.pages > shop.max_pages -> {:error, :too_many_pages}
        page.products == [] -> {:error, :malformed_listing}
        number < page.pages -> fetch_pages(shop, req_options, number + 1, [page | acc])
        true -> complete(Enum.reverse([page | acc]))
      end
    end
  end

  defp complete([first | _] = pages) do
    {full, [last]} = Enum.split(pages, -1)
    products = Enum.flat_map(pages, fn page -> Enum.map(page.products, &{&1, page.category}) end)
    ids = Enum.map(products, fn {product, _category} -> id(product) end)

    if Enum.all?(full, &(length(&1.products) == &1.size)) and length(last.products) <= first.size and
         ids == Enum.uniq(ids),
       do: {:ok, products},
       else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: number], req_options),
         {:ok, document} <- ShopFeed.html(response),
         [grid] <- Floki.find(document, "div[data-role=grid]"),
         {:ok, current} <- integer(grid, "data-page"),
         {:ok, pages} <- integer(grid, "data-max-page"),
         {:ok, size} <- integer(grid, "data-p-size") do
      {:ok,
       %{
         products: Floki.find(grid, "div[data-role='grid:list'] > a.product-box"),
         category: document |> Floki.find("title") |> Floki.text(),
         number: current,
         pages: pages,
         size: size
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_listing}
    end
  end

  defp integer(node, attribute) do
    case node |> Floki.attribute(attribute) |> List.first() |> Integer.parse() do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :malformed_pagination}
    end
  end

  defp id(product), do: product |> Floki.attribute("data-id") |> List.first()

  defp normalize(shop, {product, category}) do
    link = product |> Floki.attribute("href") |> List.first()

    with {:ok, title} <- ShopFeed.title(product |> Floki.find("header") |> Floki.text()),
         true <- ShopFeed.sealed_pokemon?(title, category) || :ignore,
         {:ok, id} <- ShopFeed.product_id(id(product)),
         "/p/" <> _ <- link,
         {:ok, url} <- ShopFeed.https_url("https://#{shop.host}#{URI.encode(link)}", [shop.host]),
         {:ok, price} <- price(product),
         {:ok, in_stock} <- in_stock(product) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: URI.to_string(url),
           image_url: image_url(shop, product),
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
    current =
      case Floki.find(product, "div.price span.discounted") do
        [] -> Floki.find(product, "div.price span")
        discounted -> discounted
      end

    text =
      current |> Enum.take(1) |> Floki.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

    case Regex.run(@price, String.replace(text, ~r/(?<=\d) (?=\d)/, "")) do
      [_, zloty, grosze] -> ShopFeed.decimal_price("#{zloty}.#{grosze}")
      nil -> :error
    end
  end

  defp in_stock(product) do
    stock = product |> Floki.find("div.stock") |> Floki.attribute("data-stock") |> List.first()
    sold_out? = Floki.find(product, "div.soldOut") != []

    case {Integer.parse(stock || ""), sold_out?} do
      {{0, ""}, _} -> {:ok, false}
      {{count, ""}, false} when count > 0 -> {:ok, true}
      {{_count, ""}, true} -> {:ok, false}
      _ -> :error
    end
  end

  defp image_url(shop, product) do
    case product |> Floki.find("img") |> Floki.attribute("src") |> List.first() do
      "/upload/" <> _ = src ->
        ShopFeed.image_url("https://#{shop.host}#{URI.encode(src)}", image_hosts(shop))

      _ ->
        nil
    end
  end
end
