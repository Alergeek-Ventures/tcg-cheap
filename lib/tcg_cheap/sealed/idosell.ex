defmodule TcgCheap.Sealed.IdoSell do
  @moduledoc """
  Reads the XML view that every IdoSell shop offers for its listings: the
  shop's `feed_path` (a Pokémon category, or a search with its query) with
  `getProductXML=t`, one page per `counter` (from 0) up to the first page
  without products, at most `max_pages` pages. Every page states the
  listing's total; it must stay the same and match the distinct products
  read, so a page that is missing, replaced or shifted fails the fetch.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name and category).
  Its price is the gross product price, which must be shown in złoty; it is in
  stock when the product's availability status is `enable` (`disable`,
  `order` and `preorder` are not). Links, often relative, are made absolute
  on the shop's host without their query; so are product icons. The EAN is
  the product's `barcode`, else its first size's producer code. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Ean, Shop, ShopFeed, XmlRecords}

  @fields [
    [],
    ["name"],
    ["category"],
    ["subcategory"],
    ["icon"],
    ["price"],
    ["sizes", "size"],
    ["sizes", "availability"]
  ]
  @statuses %{"enable" => true, "disable" => false, "order" => false, "preorder" => false}

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- fetch_pages(shop, req_options, 0, nil, []) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, counter, total, acc) do
    case request(shop, req_options, counter) do
      {:ok, products, _page_total} when counter >= shop.max_pages and products != [] ->
        {:error, :too_many_pages}

      {:ok, products, page_total} when total in [nil, page_total] and products != [] ->
        fetch_pages(shop, req_options, counter + 1, page_total, [products | acc])

      {:ok, [], page_total} when total in [nil, page_total] ->
        acc |> Enum.reverse() |> List.flatten() |> complete(page_total)

      {:ok, _products, _page_total} ->
        {:error, :pagination_changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete(products, total) do
    distinct = products |> Enum.map(&XmlRecords.attr(&1, [], "id")) |> Enum.uniq() |> length()
    if distinct == total, do: {:ok, products}, else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, counter) do
    params = [getProductXML: "t", counter: counter]

    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, params, req_options),
         {:ok, products} <-
           XmlRecords.parse(response.body, ["page", "products", "product"], @fields, &listed?/1),
         {:ok, total} <- total(response.body) do
      {:ok, products, total}
    end
  end

  # The listing's size, from the page's navigation element.
  defp total(body) do
    with {:ok, [navigation]} <-
           XmlRecords.parse(body, ["page", "products", "navigation"], [[]], &listed?/1),
         {total, ""} when total >= 0 <-
           Integer.parse(XmlRecords.attr(navigation, [], "total") || "") do
      {:ok, total}
    else
      _ -> {:error, :malformed_pagination}
    end
  end

  # Every product counts towards the end of the listing; normalize/2 filters.
  defp listed?(_product), do: true

  defp normalize(shop, product) do
    attr = &XmlRecords.attr(product, [], &1)

    with {:ok, title} <- ShopFeed.title(XmlRecords.text(product, ["name"])),
         true <- ShopFeed.sealed_pokemon?(title, category(product)) || :ignore,
         {:ok, id} <- product_id(attr.("id")),
         {:ok, url} <- product_url(shop, attr.("link")),
         {:ok, price} <- price(product),
         {:ok, in_stock} <-
           Map.fetch(@statuses, XmlRecords.attr(product, ["sizes", "availability"], "status")) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, XmlRecords.text(product, ["icon"])),
           ean:
             Ean.normalize(attr.("barcode")) ||
               Ean.normalize(XmlRecords.attr(product, ["sizes", "size"], "code_producer")),
           price: price,
           in_stock: in_stock
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp category(product) do
    [["category"], ["subcategory"]]
    |> Enum.map(&XmlRecords.attr(product, &1, "name"))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp product_id(id) when is_binary(id) do
    if Regex.match?(~r/\A[1-9][0-9]{0,11}\z/, id), do: {:ok, id}, else: :error
  end

  defp product_id(_id), do: :error

  defp product_url(shop, "/" <> _path = link),
    do: product_url(shop, "https://#{shop.host}#{link}")

  defp product_url(shop, link) do
    with {:ok, uri} <- ShopFeed.https_url(link, [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end

  defp price(product) do
    formatted = XmlRecords.attr(product, ["price"], "price_formatted")

    if is_binary(formatted) and String.ends_with?(formatted, [" zł", " PLN"]),
      do: ShopFeed.decimal_price(XmlRecords.attr(product, ["price"], "value")),
      else: :error
  end

  defp image_url(_shop, nil), do: nil

  defp image_url(shop, icon) do
    url =
      if String.starts_with?(icon, "https://"),
        do: icon,
        else: "https://#{shop.host}/#{String.trim_leading(icon, "/")}"

    ShopFeed.image_url(url, image_hosts(shop))
  end
end
