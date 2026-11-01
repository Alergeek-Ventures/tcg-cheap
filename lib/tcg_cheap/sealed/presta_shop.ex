defmodule TcgCheap.Sealed.PrestaShop do
  @moduledoc """
  Reads the JSON that a PrestaShop 1.7/8 category listing answers to an
  AJAX request (`Accept: application/json`, `X-Requested-With: XMLHttpRequest`
  and `from-xhr`, the way the shop's own faceted navigation loads pages): the
  products of each of the shop's `listing_paths` (Pokémon categories), page
  by page with `page=N`.

  Completeness is proven per listing. The first page states the listing's
  `total_items`; its product count is the page size, so the number of pages
  is known up front (at most `max_pages`, and equal to `pages_count` where the
  shop states it). Every page must repeat the same total, start at the item
  it should (`items_shown_from`), hold as many products as it should, and all
  pages together must hold exactly `total_items` distinct products. A page
  that is missing, repeated (PrestaShop answers a page past the end with the
  last page again), shifted or replaced fails the fetch.

  The listings are the shop's Pokémon categories, so a product counts when its
  title names a sealed product (`TcgCheap.Sealed.Matcher.sealed_title?/1`;
  titles often omit "Pokémon" there); accessories and other games' items that
  pass are left to `TcgCheap.Sealed.Matcher`. Its price is the current price
  in złoty. It is in stock when PrestaShop offers it for adding to the cart
  (`add_to_cart_url`, which PrestaShop leaves out of unavailable products)
  and its listing tile names no pre-order ("Przedsprzedaż", "Zapowiedź",
  "Premiera", …): the shops' faceted stock counts ("W magazynie") equal this
  rule on the shops that show them. A shop that lets customers buy an item
  that is out of stock cannot be told apart from stock by the listing, so it
  does not belong here. The JSON carries no EAN, so offers have none. Links
  and images must be on the shop's host. See `TcgCheap.Sealed.ShopFeed` for
  the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}

  @headers [{"accept", "application/json"}, {"x-requested-with", "XMLHttpRequest"}]
  @preorder ~r/\b(?:przedsprzedaz|przedpremier|zapowiedz|preorder|pre order)/
  @premiere ~r/\bpremier\w*(?: (\d{1,2}) (\d{1,2}|[a-z]{3}) (\d{4}))?/
  @months ~w(sty lut mar kwi maj cze lip sie wrz paz lis gru)

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    req_options = Keyword.update(req_options, :headers, @headers, &(@headers ++ &1))

    shop.listing_paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case fetch_listing(shop, path, req_options) do
        {:ok, products} -> {:cont, {:ok, [products | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, listings} ->
        products = listings |> Enum.reverse() |> List.flatten()
        {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_listing(shop, path, req_options) do
    with {:ok, first} <- request(shop, path, req_options, 1),
         {:ok, pages} <- page_count(shop, first),
         {:ok, rest} <- fetch_rest(shop, path, req_options, first, pages) do
      listed = Enum.flat_map([first | rest], & &1.products)
      distinct = listed |> Enum.map(& &1.id) |> Enum.uniq() |> length()
      if distinct == first.total, do: {:ok, listed}, else: {:error, :incomplete_listing}
    end
  end

  defp page_count(_shop, %{total: 0}), do: {:error, :empty_listing}
  defp page_count(_shop, %{products: []}), do: {:error, :malformed_response}
  defp page_count(_shop, %{from: from}) when from != 1, do: {:error, :malformed_pagination}

  defp page_count(shop, %{total: total, products: products, pages_count: pages_count}) do
    size = length(products)
    pages = div(total + size - 1, size)

    cond do
      pages > shop.max_pages -> {:error, :too_many_pages}
      pages == 1 and size != total -> {:error, :incomplete_listing}
      pages_count not in [nil, pages] -> {:error, :malformed_pagination}
      true -> {:ok, pages}
    end
  end

  defp fetch_rest(_shop, _path, _req_options, _first, 1), do: {:ok, []}

  defp fetch_rest(shop, path, req_options, first, pages) do
    size = length(first.products)

    Enum.reduce_while(2..pages, {:ok, []}, fn page, {:ok, acc} ->
      expected = min(size, first.total - (page - 1) * size)

      with {:ok, current} <- request(shop, path, req_options, page),
           :ok <- check_page(current, first.total, (page - 1) * size + 1, expected) do
        {:cont, {:ok, [current | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rest} -> {:ok, Enum.reverse(rest)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_page(%{total: total, from: from, products: products}, total, from, expected)
       when length(products) == expected,
       do: :ok

  defp check_page(%{total: total}, total, _from, _expected), do: {:error, :incomplete_listing}
  defp check_page(_page, _total, _from, _expected), do: {:error, :pagination_changed}

  defp request(shop, path, req_options, page) do
    params = if page == 1, do: ["from-xhr": ""], else: ["from-xhr": "", page: page]

    with {:ok, response} <- ShopFeed.get(shop, path, params, req_options),
         {:ok, %{} = body} <- ShopFeed.decode(response) do
      parse(body)
    else
      {:ok, _not_an_object} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse(%{
         "products" => products,
         "pagination" => %{"total_items" => total, "items_shown_from" => from} = pagination,
         "rendered_products" => rendered
       })
       when is_list(products) and is_integer(total) and total >= 0 and is_integer(from) and
              is_binary(rendered) do
    with {:ok, tiles} <- tiles(rendered),
         {:ok, products} <- products(products, tiles) do
      {:ok,
       %{
         total: total,
         from: from,
         pages_count: pagination["pages_count"],
         products: products
       }}
    end
  end

  defp parse(_body), do: {:error, :malformed_response}

  # The text of each product's listing tile, by product id.
  defp tiles(rendered) do
    case Floki.parse_fragment(rendered) do
      {:ok, document} ->
        tiles =
          document
          |> Floki.find("[data-id-product]")
          |> Enum.group_by(
            fn node -> node |> Floki.attribute("data-id-product") |> List.first() end,
            &Floki.text(&1, sep: " ")
          )
          |> Map.new(fn {id, texts} -> {id, Enum.join(texts, " ")} end)

        {:ok, tiles}

      {:error, _reason} ->
        {:error, :malformed_response}
    end
  end

  # A product the JSON lists must have its tile, or the pre-order check could
  # be skipped silently.
  defp products(products, tiles) do
    Enum.reduce_while(products, {:ok, []}, fn
      %{"id_product" => id} = product, {:ok, acc} ->
        id = if is_integer(id), do: Integer.to_string(id), else: id

        case tiles do
          %{^id => tile} -> {:cont, {:ok, [%{id: id, product: product, tile: tile} | acc]}}
          _ -> {:halt, {:error, :malformed_response}}
        end

      _product, _acc ->
        {:halt, {:error, :malformed_response}}
    end)
    |> case do
      {:ok, products} -> {:ok, Enum.reverse(products)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(shop, %{id: id, product: product, tile: tile}) do
    with {:ok, title} <- ShopFeed.title(product["name"]),
         true <- Matcher.sealed_title?(title) || :ignore,
         {:ok, id} <- ShopFeed.product_id(id),
         {:ok, url} <- product_url(shop, product["url"]),
         {:ok, price} <- price(product["price"]) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product["cover"]),
           ean: nil,
           price: price,
           in_stock: in_stock?(product, title, tile)
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp product_url(shop, url) do
    with {:ok, uri} <- ShopFeed.https_url(url, [shop.host]),
         true <- is_nil(uri.query),
         do: {:ok, url},
         else: (_ -> :error)
  end

  # "1 799,95 zł", with a no-break space for the thousands and before "zł".
  defp price(text) when is_binary(text) do
    case Regex.run(~r/\A([0-9][0-9\s\x{a0}]*),([0-9]{2})[\s\x{a0}]zł\z/u, text) do
      [_text, whole, fraction] ->
        ShopFeed.decimal_price(String.replace(whole, ~r/[^0-9]/, "") <> "." <> fraction)

      nil ->
        :error
    end
  end

  defp price(_text), do: :error

  defp image_url(shop, %{} = cover) do
    url = get_in(cover, ["large", "url"]) || get_in(cover, ["medium", "url"])
    ShopFeed.image_url(url, image_hosts(shop))
  end

  defp image_url(_shop, _cover), do: nil

  defp in_stock?(product, title, tile) do
    product["add_to_cart_url"] not in [nil, ""] and not preorder?(title, tile)
  end

  # The tile's own labels, without the title that may name a pre-order itself.
  # A premiere ("Premiera: 06.11.2026", "Premiera 06 lis 2026") makes it a
  # pre-order until its date; a premiere without a readable date counts too.
  defp preorder?(title, tile) do
    normalized = Matcher.normalize(tile)
    title = Matcher.normalize(title)
    labels = if title == "", do: normalized, else: String.replace(normalized, title, " ")

    Regex.match?(@preorder, labels) or
      Enum.any?(Regex.scan(@premiere, labels), &(not released?(&1)))
  end

  defp released?([_premiere, day, month, year]) do
    with {day, ""} <- Integer.parse(day),
         {month, ""} <- parse_month(month),
         {year, ""} <- Integer.parse(year),
         {:ok, date} <- Date.new(year, month, day) do
      Date.compare(date, Date.utc_today()) != :gt
    else
      _ -> false
    end
  end

  defp released?(_premiere), do: false

  defp parse_month(month) do
    case Enum.find_index(@months, &(&1 == month)) do
      nil -> Integer.parse(month)
      index -> {index + 1, ""}
    end
  end
end
