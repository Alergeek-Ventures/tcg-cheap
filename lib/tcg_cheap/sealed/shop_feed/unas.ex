defmodule TcgCheap.Sealed.ShopFeed.Unas do
  @moduledoc """
  Reads sealed products from the category listings of an UNAS shop
  (`listing_paths`, each read to its last page, `<path>,N`).

  UNAS themes differ in markup but share the product card
  (`article#page_artlist_artlist_<sku>`), its link (whose `data-sku` is the
  product's id and whose text or title is the name), its price (the consumer
  price in whole forints, grouped by dots or spaces: `price_akcio_brutto_…`
  when the product is on sale, else `price_net_brutto_…`) and its cart call
  (`cart_add('<sku>', ...)`). Every card must state one of the availabilities
  the shops print: in stock (the shop's marker `.on-stock` with that cart call),
  sold out (`.no-stock`, or `.not-orderable` on the stock line), or a pre-order
  (its title or any "előrendelés" on the card,
  `TcgCheap.Sealed.Matcher.preorder_title?/1`, never in stock). A card without
  its sku, name or link on the shop's host, or without a recognised
  availability, is a layout this reader does not know and fails the listing
  (`:unrecognised_listing`). A sold-out or pre-order card that shows no price
  is no offer (every offer has a price) and is left out; a listing in which
  every sealed card is such a card yields no offers, which `TcgCheap.Sealed.Refresh`
  reports as an empty feed. The product's image must be on the shop's host;
  listings carry no EAN.

  A listing is complete when its pager's numbers (`.pager-item`) are all read,
  the pager marks the page asked for as the selected one (a listing with a pager
  or a page beyond the first without one fails), no page links further
  (`rel="next"`) after the last, and, where the theme states how many products
  the category holds (`.product-num`, which must then be a number), the pages
  together hold exactly that many distinct products (`TcgCheap.Sealed.ShopFeed.HtmlListing.read/2`). See
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
      numbers == [] and number > 1 ->
        {:error, :malformed_pagination}

      numbers != [] and selected(document) != number ->
        {:error, :pagination_changed}

      number >= last and next_link?(document) ->
        {:error, :malformed_pagination}

      true ->
        cards =
          document
          |> Floki.find(~s(article[id^="page_artlist_artlist_"]))
          |> Enum.map(&product(shop, &1))

        with {:ok, total} <- total(document), do: described(cards, number, last, total)
    end
  end

  # A sold-out product shows no price, but a page of such cards is still a
  # product list: what every card must state is its identity and availability.
  defp described(cards, number, last, total) do
    if Enum.all?(cards, &described?/1),
      do:
        {:ok,
         %{number: number, last: last, total: total, recognised: cards != [], products: cards}},
      else: {:error, :unrecognised_listing}
  end

  defp described?(product) do
    Enum.all?([:id, :title, :path], &is_binary(product[&1])) and is_boolean(product.in_stock)
  end

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

  # The product count on themes that state it (nil on those that do not); a
  # counter that is there but not a number is a layout this reader does not know.
  defp total(document) do
    case HtmlListing.first(document, ".product-num") do
      nil ->
        {:ok, nil}

      node ->
        case Integer.parse(HtmlListing.text(node) || "") do
          {total, ""} -> {:ok, total}
          _ -> {:error, :malformed_pagination}
        end
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
      in_stock: availability(card, preorder),
      preorder: preorder
    }
  end

  # In stock (true), sold out or pre-order (false), or a state this reader does
  # not know (nil): the page does not say, so it is not read as sold out.
  defp availability(_card, true), do: false

  defp availability(card, false) do
    cond do
      Floki.find(card, ".on-stock") != [] and cart?(card) -> true
      Floki.find(card, ".no-stock, .stock-item.not-orderable") != [] -> false
      true -> nil
    end
  end

  defp cart?(card) do
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
