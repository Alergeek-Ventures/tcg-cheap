defmodule TcgCheap.Sealed.ShopFeed.ShopRenter do
  @moduledoc """
  Reads sealed products from a ShopRenter shop's `listing_paths`, the shop's
  Pokémon category listings, each read to its last page (at most `max_pages`
  pages, `?page=N`). A category that only holds subcategories lists no
  products, so the paths name the categories that do.

  ShopRenter themes differ in markup but share the product card
  (`.product-snapshot`) and its cart link, which carries the product's
  data: `data-product-id`, `data-name`, `data-price-without-currency` (the
  price a buyer pays, in whole forints for a shop in HUF) and `data-currency`,
  which must be the shop's `currency`. A product is in stock when that link adds it to the
  cart; for a product that cannot be bought the shop turns the link into a
  waiting-list request (`notify-request`: "Értesítés"). A pre-order (its
  badge or title, `TcgCheap.Sealed.Matcher.preorder_title?/1`) is never in
  stock. The product's link and image must be on the shop's host or its
  ShopRenter CDN (`<shop>.cdn.shoprenter.hu`); listings carry no EAN.

  Every page states "from - to / total termék": the first page's `to` is the
  page size, so the number of pages is known up front, every page must start
  at the item it should, and the pages together must hold exactly the stated
  total of distinct products
  (`TcgCheap.Sealed.ShopFeed.HtmlListing.read/2`). A listing of one page may
  state no total. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @path ~r/\A\/[a-z0-9-]+(?:\/[a-z0-9-]+)*\z/
  @range ~r/\A(\d+) - (\d+) \/ (\d+) term[ée]k\z/u
  # One request per 3 seconds: ShopRenter shops answer faster requests slowly.
  @pause_ms 3_000

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, cdn_host(host)]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_category(shop, &1, req_options)) do
      {:ok, HtmlListing.offers(shop, products, &Matcher.sealed_title?/1)}
    end
  end

  # `www.example.hu` → `example.cdn.shoprenter.hu`
  defp cdn_host(host) do
    name = host |> String.replace_prefix("www.", "") |> String.split(".") |> hd()
    "#{name}.cdn.shoprenter.hu"
  end

  defp read_category(shop, path, req_options) do
    with true <- Regex.match?(@path, path),
         {:ok, first} <- request(shop, path, 1, nil, req_options) do
      HtmlListing.read(
        fn
          1 -> {:ok, first}
          number -> request(shop, path, number, length(first.products), req_options)
        end,
        shop.max_pages
      )
    else
      false -> {:error, :invalid_category}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(shop, path, number, size, req_options) do
    params = if number == 1, do: [], else: [page: number]

    with {:ok, response} <-
           ShopFeed.get(shop, path, params, req_options, pause_ms: @pause_ms),
         {:ok, document} <- ShopFeed.html(response) do
      page(shop, document, number, size)
    end
  end

  defp page(shop, document, number, size) do
    products = document |> Floki.find(".product-snapshot") |> Enum.map(&product(shop, &1))

    case range(document) do
      {:ok, {from, to, total}} ->
        size = size || to

        if from == (number - 1) * size + 1 and to - from + 1 == length(products),
          do:
            {:ok,
             %{
               number: number,
               last: max(div(total + size - 1, size), 1),
               total: total,
               products: products
             }},
          else: {:error, :pagination_changed}

      :none when number == 1 ->
        if further_pages?(document),
          do: {:error, :malformed_pagination},
          else:
            {:ok,
             %{number: 1, last: 1, total: empty_total(document, products), products: products}}

      _malformed ->
        {:error, :malformed_pagination}
    end
  end

  # A listing without the counter is taken as one whole page only when nothing
  # on it leads to another page.
  defp further_pages?(document),
    do: Floki.find(document, ~s(a.page-link, a[rel="next"], link[rel="next"])) != []

  # An empty category says so ("Nincs megjeleníthető termék."); any other
  # listing without products states no total and fails as an empty page.
  defp empty_total(document, []) do
    if document
       |> Floki.find(".alert-info")
       |> Enum.any?(&((HtmlListing.text(&1) || "") =~ "Nincs megjeleníthető termék")),
       do: 0
  end

  defp empty_total(_document, _products), do: nil

  # "13 - 24 / 148 termék"; a listing of a single page may state none.
  defp range(document) do
    case document |> Floki.find(".results, .pagination__results") |> List.first() do
      nil ->
        :none

      node ->
        case Regex.run(@range, HtmlListing.text(node) || "") do
          [_, from, to, total] ->
            {:ok, {String.to_integer(from), String.to_integer(to), String.to_integer(total)}}

          nil ->
            :error
        end
    end
  end

  defp product(shop, card) do
    cart = HtmlListing.first(card, "a[data-product-id]")
    title = cart && Floki.attribute(cart, "data-name") |> List.first()
    badges = card |> Floki.find(".product_badges") |> HtmlListing.text() || ""
    preorder = Matcher.preorder_title?("#{title} #{badges}")

    %{
      id: cart && Floki.attribute(cart, "data-product-id") |> List.first(),
      title: title,
      path: card |> HtmlListing.attr("h2 a[href], h3 a[href]", "href") |> shop_path(shop),
      image: image(card),
      price: cart && price(shop, cart),
      in_stock: cart != nil and not notify_request?(cart) and not preorder,
      preorder: preorder
    }
  end

  defp notify_request?(cart),
    do: cart |> Floki.attribute("class") |> Enum.any?(&(&1 =~ ~r/\bnotify-request\b/))

  # Forints have no fractions, and some carts write the net price times the VAT
  # as a float ("11989.99" for the 11 990 Ft the card shows).
  defp price(%Shop{currency: currency}, cart) do
    with [^currency] <- Floki.attribute(cart, "data-currency"),
         [text] <- Floki.attribute(cart, "data-price-without-currency"),
         {price, ""} <- Decimal.parse(text) do
      price = if currency == "HUF", do: Decimal.round(price, 0), else: price
      Decimal.to_string(price, :normal)
    else
      _ -> nil
    end
  end

  # Thumbnails load lazily (`data-src`) in some themes.
  defp image(card) do
    HtmlListing.attr(card, "img[data-src]", "data-src") ||
      HtmlListing.attr(card, "img[src]", "src")
  end

  defp shop_path(href, %Shop{host: host}) when is_binary(href) do
    case URI.parse(href) do
      %URI{scheme: "https", host: ^host, path: "/" <> _ = path, query: nil} -> path
      _ -> nil
    end
  end

  defp shop_path(_href, _shop), do: nil
end
