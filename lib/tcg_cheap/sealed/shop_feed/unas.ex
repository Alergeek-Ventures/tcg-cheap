defmodule TcgCheap.Sealed.ShopFeed.Unas do
  @moduledoc """
  Reads sealed products from the category listings of an UNAS shop
  (`listing_paths`, each read to its last page, `<path>,N`).

  UNAS themes differ in markup but share the product card
  (`article#page_artlist_artlist_<sku>`), its link (whose `data-sku` is the
  product's id and whose text or title is the name), its price (the consumer
  price in whole forints, grouped by dots or spaces: `price_akcio_brutto_…`
  when the product is on sale, else `price_net_brutto_…`) and its cart call
  (`cart_add('<sku>', ...)`). A
  product is in stock when the card shows the shop's in-stock marker
  (`.on-stock`) and offers that cart call; a product the shop will not sell
  (`not-orderable`, `no-stock`) has neither. A pre-order (its title or any
  "előrendelés" on the card, `TcgCheap.Sealed.Matcher.preorder_title?/1`) is
  never in stock. The product's link and image must be on the shop's host;
  listings carry no EAN.

  A listing is complete when its pager's numbers (`.pager-item`) are all read,
  the pager marks the page asked for as the selected one, no page links further
  (`rel="next"`) after the last, and, where the theme states how many products
  the category holds (`.product-num`), the pages together hold exactly that many
  distinct products (`TcgCheap.Sealed.ShopFeed.HtmlListing.read/2`). See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @path ~r/\A\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*\z/
  @price ~r/\A\d{1,3}(?:[. \x{a0}]\d{3})*\z|\A\d+\z/u
  @cart ~r/cart_add\(/
  # One request per 3 seconds, as for the other HTML listings of Hungarian shops.
  @pause_ms 3_000

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_category(shop, &1, req_options)) do
      # A sold-out product shows no price: there is nothing to offer.
      priced = Enum.reject(products, &(&1.price == nil and not &1.in_stock))
      {:ok, HtmlListing.offers(shop, priced, &Matcher.sealed_title?/1)}
    end
  end

  defp read_category(shop, path, req_options) do
    if Regex.match?(@path, path),
      do: HtmlListing.read(&request(shop, path, &1, req_options), shop.max_pages),
      else: {:error, :invalid_category}
  end

  defp request(shop, path, number, req_options) do
    page_path = if number == 1, do: path, else: "#{path},#{number}"

    with {:ok, response} <- ShopFeed.get(shop, page_path, [], req_options, pause_ms: @pause_ms),
         {:ok, document} <- ShopFeed.html(response) do
      page(shop, document, number)
    end
  end

  defp page(shop, document, number) do
    numbers = pager_numbers(document)
    last = Enum.max([1 | numbers])

    cond do
      selected(document) not in [nil, number] ->
        {:error, :pagination_changed}

      numbers == [] and number > 1 ->
        {:error, :malformed_pagination}

      number >= last and next_link?(document) ->
        {:error, :malformed_pagination}

      true ->
        cards =
          document
          |> Floki.find(~s(article[id^="page_artlist_artlist_"]))
          |> Enum.map(&product(shop, &1))

        {:ok,
         %{
           number: number,
           last: last,
           total: total(document),
           # A sold-out product shows no price, but a page of such cards is
           # still a product list.
           recognised: cards != [] and Enum.all?(cards, &identified?/1),
           products: cards
         }}
    end
  end

  defp identified?(product), do: Enum.all?([:id, :title, :path], &is_binary(product[&1]))

  defp pager_numbers(document) do
    for node <- Floki.find(document, "a.pager-item"),
        {number, ""} <- [Integer.parse(HtmlListing.text(node) || "")],
        do: number
  end

  defp selected(document) do
    with node when node != nil <- HtmlListing.first(document, "a.pager-item.selected"),
         {number, ""} <- Integer.parse(HtmlListing.text(node) || "") do
      number
    else
      _ -> nil
    end
  end

  defp next_link?(document),
    do: Floki.find(document, ~s|link[rel="next"], a.next-button:not(.inactive)|) != []

  # "9 termék" on themes that state it; nil on those that do not.
  defp total(document) do
    with node when node != nil <- HtmlListing.first(document, ".product-num"),
         {total, ""} <- Integer.parse(HtmlListing.text(node) || "") do
      total
    else
      _ -> nil
    end
  end

  defp product(shop, card) do
    link = HtmlListing.first(card, "a.name-link, a.product__name-link")
    title = link && (HtmlListing.text(link) || link |> Floki.attribute("title") |> List.first())
    preorder = Matcher.preorder_title?("#{title} #{HtmlListing.text(card)}")

    %{
      id: link && link |> Floki.attribute("data-sku") |> List.first(),
      title: title,
      path: link && link |> Floki.attribute("href") |> List.first() |> shop_path(shop),
      image: HtmlListing.attr(card, "img[data-src]", "data-src"),
      price: price(shop, card),
      in_stock: in_stock?(card) and not preorder,
      preorder: preorder
    }
  end

  defp in_stock?(card) do
    Floki.find(card, ".on-stock") != [] and
      card
      |> Floki.find("[onclick]")
      |> Enum.any?(&(&1 |> Floki.attribute("onclick") |> Enum.any?(fn call -> call =~ @cart end)))
  end

  # Forints have no fractions; the dots or spaces group thousands.
  defp price(%Shop{currency: "HUF"}, card) do
    # A product on sale shows its regular price struck through
    # (`price_net_brutto`) and the price a buyer pays as `price_akcio_brutto`.
    with node when node != nil <-
           HtmlListing.first(card, ~s(span[id^="price_akcio_brutto_artlist_"])) ||
             HtmlListing.first(card, ~s(span[id^="price_net_brutto_artlist_"])),
         text when is_binary(text) <- HtmlListing.text(node),
         true <- Regex.match?(@price, text) do
      String.replace(text, ~r/[^0-9]/, "")
    else
      _ -> nil
    end
  end

  defp shop_path(href, %Shop{host: host}) when is_binary(href) do
    case URI.parse(href) do
      %URI{scheme: "https", host: ^host, path: "/" <> _ = path, query: nil} -> path
      _ -> nil
    end
  end

  defp shop_path(_href, _shop), do: nil
end
