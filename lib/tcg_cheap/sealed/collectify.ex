defmodule TcgCheap.Sealed.Collectify do
  @moduledoc """
  Reads the sealed products listing of collectify.pl, a Pokémon-only Next.js
  storefront that renders its product cards on the server: the listing's
  `feed_path` with `?page=N` from 1 to the highest page its pagination links
  to, at most `max_pages`. The listing's size is the `numberOfItems` of its
  structured data; it must stay the same on every page and match the distinct
  products read, so a missing or shifted page fails the fetch. (The shop's
  API is off limits in its robots.txt and is not used.)

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name, the shop selling
  only Pokémon). It is in stock when its card has an add-to-cart button and not
  when it is marked "Wyprzedane". The shop's product id is the slug, which must
  fit the 40 characters an offer allows. Prices are in złoty. There is no EAN.
  See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @link ~r|\A/product/([a-z0-9-]+)\z|
  @price ~r/\A([0-9]{1,7}),([0-9]{2}) zł\z/u
  @page_label ~r/\AStrona ([0-9]{1,3})(?:, bieżąca)?\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- fetch_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, number, total, acc) do
    with {:ok, page} <- request(shop, req_options, number) do
      cond do
        total not in [nil, page.total] ->
          {:error, :pagination_changed}

        page.current != number ->
          {:error, :pagination_changed}

        page.pages > shop.max_pages ->
          {:error, :too_many_pages}

        page.products == [] ->
          {:error, :malformed_listing}

        number < page.pages ->
          fetch_pages(shop, req_options, number + 1, page.total, [page | acc])

        true ->
          complete(Enum.reverse([page | acc]), page.total)
      end
    end
  end

  defp complete(pages, total) do
    products = Enum.flat_map(pages, & &1.products)
    links = Enum.map(products, &link/1)

    if length(products) == total and links == Enum.uniq(links),
      do: {:ok, products},
      else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [page: number], req_options),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, total} <- total(document),
         {:ok, current, pages} <- pagination(document) do
      {:ok,
       %{
         products:
           document |> Floki.find("div.group.relative") |> Enum.filter(&(link(&1) != nil)),
         total: total,
         current: current,
         pages: pages
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_response}
    end
  end

  # The CollectionPage block of the page's structured data.
  defp total(document) do
    document
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.map(&Floki.text(&1, js: true))
    |> Enum.find_value({:error, :malformed_pagination}, fn json ->
      case Jason.decode(json) do
        {:ok, %{"@type" => "CollectionPage", "mainEntity" => %{"numberOfItems" => total}}}
        when is_integer(total) and total >= 0 ->
          {:ok, total}

        _ ->
          nil
      end
    end)
  end

  # The current page is a `span`, the others links.
  defp pagination(document) do
    items = Floki.find(document, "nav[aria-label=Paginacja] li > *")

    with [current] <- items |> Floki.find("[aria-current=page]") |> page_numbers(),
         [_ | _] = numbers <- page_numbers(items) do
      {:ok, current, Enum.max(numbers)}
    else
      _ -> {:error, :malformed_pagination}
    end
  end

  defp page_numbers(links) do
    for label <- Floki.attribute(links, "aria-label"),
        [number] <- [Regex.run(@page_label, label, capture: :all_but_first)],
        do: String.to_integer(number)
  end

  defp link(card),
    do: card |> Floki.find("a[href^='/product/']") |> Floki.attribute("href") |> List.first()

  defp normalize(shop, card) do
    with {:ok, title} <- ShopFeed.title(card |> Floki.find("h3") |> Floki.text()),
         true <- ShopFeed.sealed_pokemon?(title, "Pokemon") || :ignore,
         [_, slug] <- Regex.run(@link, link(card)),
         {:ok, id} <- ShopFeed.product_id(slug),
         {:ok, url} <- ShopFeed.https_url("https://#{shop.host}#{link(card)}", [shop.host]),
         {:ok, price} <- price(card),
         {:ok, in_stock} <- in_stock(card) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: URI.to_string(url),
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

  defp price(card) do
    case card |> Floki.find("span.tabular-nums") |> Enum.map(&Floki.text/1) do
      [text] ->
        case Regex.run(
               @price,
               text
               |> String.replace(~r/\s+/u, " ")
               |> String.trim()
               |> String.replace(~r/(?<=\d) (?=\d)/, "")
             ) do
          [_, zloty, grosze] -> ShopFeed.decimal_price("#{zloty}.#{grosze}")
          nil -> :error
        end

      _ ->
        :error
    end
  end

  defp in_stock(card) do
    cond do
      Floki.find(card, "button[aria-label='Dodaj do koszyka']") != [] -> {:ok, true}
      card |> Floki.text() |> String.contains?("Wyprzedane") -> {:ok, false}
      true -> :error
    end
  end

  defp image_url(shop, card),
    do:
      card
      |> Floki.find("img")
      |> Floki.attribute("src")
      |> List.first()
      |> ShopFeed.image_url(image_hosts(shop))
end
