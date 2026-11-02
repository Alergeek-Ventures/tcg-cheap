defmodule TcgCheap.Sealed.ShoperListing do
  @moduledoc """
  Reads a Shoper storefront's category listing for shops that have switched
  off both feed exports (`TcgCheap.Sealed.GoogleFeed`,
  `TcgCheap.Sealed.CeneoFeed`). Shoper has no public JSON for the storefront,
  so this parses the HTML of the shop's Pokémon category, `feed_path`
  (`/pl/c/<name>/<id>`), page by page: `<feed_path>/<n>` from 1 up to the last
  page the pagination announces, at most `max_pages` pages.

  Two page layouts exist and are told apart by their markup:

    * current themes list `<product-tile>` elements and state the category's
      size ("Liczba produktów na stronie: N") and its page count ("z N"); the
      distinct products read must equal that size, so a page that is missing,
      replaced or shifted fails the fetch. An empty category states "Brak"
      instead and yields no offers;
    * classic themes list `div.product` blocks and give only page numbers, so
      completeness rests on the page count: every page up to the last number
      the pagination shows must be read and name itself as the selected page.

  A page without products (but for the empty category), or whose products
  all lack a recognisable id, link, price or availability, fails the fetch;
  single products with such gaps are skipped and counted. A product counts when its
  title names a sealed product (`TcgCheap.Sealed.Matcher.sealed_title?/1`);
  the category is the shop's Pokémon one, except for a `mixed_listing` shop
  whose title must also say Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2`).

  The listing price is the current gross price in złoty. A product is in
  stock when its tile offers an add-to-cart button (current themes) or a
  quantity field (classic themes); "Powiadom mnie o dostępności", "Niedostępny"
  and "na zamówienie" products are not. Shoper marks no pre-orders on the
  tile: a shop that collects them in a listing of their own names it as
  `preorder_path` (its first page only), and its products are never in
  stock; the matcher also excludes titles that say pre-order. Links and images are made absolute on the
  shop's host, which is the `www.` one where the apex redirects there (no
  redirects are followed); tile images are swapped for the full-size photo
  (`full_size_image/1`). Listings carry no EAN. See `TcgCheap.Sealed.ShopFeed` for
  the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Matcher, Shop, ShopFeed}

  @current_cache_image ~r|\A((?:https://[^/]+)?/environment/cache/images/)productGfx_(\d{1,12})_\d{1,4}_\d{1,4}/|
  @classic_cache_image ~r|\A((?:https://[^/]+)?)/environment/cache/images/\d{1,4}_\d{1,4}_productGfx_([0-9a-f]{32}\.[A-Za-z]{3,4})\z|

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @doc """
  The full-size copy of a Shoper product photo, given any of the thumbnails
  the shop's image cache serves (an absolute URL or a path on the shop).

  Current shops name a cached copy
  `/environment/cache/images/productGfx_<id>_<width>_<height>/<name>` and
  make it in larger boxes too, scaling the upload down to fit but never up;
  some themes already list the 1500 × 1500 copy, which is used. Classic shops name
  it `/environment/cache/images/<width>_<height>_productGfx_<hash>.<ext>` and
  make only a few small sizes; their product pages zoom into the upload
  itself, `/userdata/gfx/<hash>.<ext>`. Any other URL is returned unchanged.
  """
  @spec full_size_image(String.t() | nil) :: String.t() | nil
  def full_size_image(nil), do: nil

  def full_size_image(url) do
    url = Regex.replace(@current_cache_image, url, "\\1productGfx_\\2_1500_1500/")
    Regex.replace(@classic_cache_image, url, "\\1/userdata/gfx/\\2")
  end

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- HtmlListing.read(&request(shop, req_options, &1), shop.max_pages),
         {:ok, preorders} <- preorder_ids(shop, req_options) do
      products =
        Enum.map(products, &if(&1.id in preorders, do: %{&1 | in_stock: false}, else: &1))

      {:ok, HtmlListing.offers(shop, products, &sealed?(shop, &1))}
    end
  end

  defp request(shop, req_options, number) do
    path = if number == 1, do: shop.feed_path, else: "#{shop.feed_path}/#{number}"
    request_path(shop, path, req_options)
  end

  defp request_path(shop, path, req_options) do
    with {:ok, document} <- HtmlListing.page(shop, path, req_options),
         do: parse_page(document)
  end

  defp preorder_ids(%Shop{preorder_path: nil}, _req_options), do: {:ok, MapSet.new()}

  defp preorder_ids(shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read(
             fn _number -> request_path(shop, shop.preorder_path, req_options) end,
             1
           ),
         do: {:ok, MapSet.new(products, & &1.id)}
  end

  defp sealed?(%Shop{mixed_listing: true}, title), do: ShopFeed.sealed_pokemon?(title, nil)
  defp sealed?(_shop, title), do: Matcher.sealed_title?(title)

  # -- Pages -----------------------------------------------------------------

  defp parse_page(document) do
    case Floki.find(document, "product-list product-tile") do
      [] -> parse_empty_or_classic(document)
      tiles -> parse_tiles(document, tiles)
    end
  end

  defp parse_empty_or_classic(document) do
    case Floki.find(document, ".products div.product") do
      [] -> parse_empty(document)
      blocks -> parse_blocks(document, blocks)
    end
  end

  # An empty current-theme category: no product list, the count says "Brak".
  defp parse_empty(document) do
    case count_label(document) do
      "Brak" -> {:ok, %{number: 1, last: 1, total: 0, products: []}}
      _ -> {:error, :unrecognised_listing}
    end
  end

  defp parse_tiles(document, tiles) do
    with {total, ""} <- Integer.parse(count_label(document) || ""),
         [{current, ""}] <-
           document |> Floki.attribute("pagination-page-number", "current-page") |> parse_all(),
         [last] <- pages_label(document) do
      {:ok, %{number: current, last: last, total: total, products: Enum.map(tiles, &tile/1)}}
    else
      _ -> {:error, :unrecognised_listing}
    end
  end

  defp parse_blocks(document, blocks) do
    numbers = document |> Floki.find("ul.paginator li") |> Enum.flat_map(&page_number/1)
    selected = document |> Floki.find("ul.paginator li.selected") |> Enum.flat_map(&page_number/1)

    case {numbers, Enum.uniq(selected)} do
      {[], []} -> {:ok, page(1, 1, blocks)}
      {numbers, [selected]} -> {:ok, page(selected, Enum.max(numbers), blocks)}
      _ -> {:error, :unrecognised_listing}
    end
  end

  defp page(number, last, blocks),
    do: %{number: number, last: last, total: nil, products: Enum.map(blocks, &block/1)}

  defp page_number(li) do
    case Integer.parse(String.trim(Floki.text(li))) do
      {number, ""} -> [number]
      _ -> []
    end
  end

  # "Liczba produktów na stronie: 29" (or "Brak"), from the category header.
  defp count_label(document) do
    case document |> Floki.attribute("span.number-of-products", "aria-label") |> Enum.uniq() do
      [label] -> label |> String.split(": ") |> List.last()
      _ -> nil
    end
  end

  # The "z 2" next to the page selector.
  defp pages_label(document) do
    for text <-
          document |> Floki.find(".pagination__page-selector-text") |> Enum.map(&Floki.text/1),
        [_, pages] <- [Regex.run(~r/\Az (\d{1,3})\z/, String.trim(text))],
        uniq: true,
        do: String.to_integer(pages)
  end

  defp parse_all(values),
    do: values |> Enum.uniq() |> Enum.map(&Integer.parse/1)

  # -- Products --------------------------------------------------------------

  defp tile(tile) do
    %{
      id: first(Floki.attribute(tile, "product-id")),
      title: first(Floki.attribute(tile, "name")),
      path: first(Floki.attribute(tile, "product-link a", "href")),
      image: full_size_image(first(Floki.attribute(tile, ".product-tile__image img", "src"))),
      price: tile_price(tile),
      in_stock: tile_in_stock(tile)
    }
  end

  defp tile_price(tile) do
    if first(Floki.attribute(tile, "currency")) == "PLN",
      do: first(Floki.attribute(tile, "price"))
  end

  defp tile_in_stock(tile) do
    text = Floki.text(tile)

    cond do
      "1" in Floki.attribute(tile, "buy-button", "is-buyable") -> true
      String.contains?(text, ["Powiadom mnie o dostępności", "Niedostępny"]) -> false
      true -> nil
    end
  end

  defp block(block) do
    path = first(Floki.attribute(block, "a.prodname", "href"))

    %{
      id: block_id(path),
      title: block |> Floki.find(".productname") |> Floki.text() |> String.trim(),
      path: path,
      image: block_image(block),
      price: block_price(block),
      in_stock: block_in_stock(block)
    }
  end

  defp block_id(path) when is_binary(path) do
    case Regex.run(~r|\A/pl/p/[^/]+/(\d{1,12})\z|, path) do
      [_, id] -> id
      nil -> nil
    end
  end

  defp block_id(_path), do: nil

  # Lazy-loaded images keep the real address in data-src; the 1 px images
  # (`px1`) belong to buttons. A product without a photo shows Shoper's
  # placeholder (`productGfx___overlay`), which is no photo of it.
  defp block_image(block) do
    src =
      first(Floki.attribute(block, "img:not(.px1)", "data-src")) ||
        first(Floki.attribute(block, "img:not(.px1)", "src"))

    if is_binary(src) and not String.starts_with?(src, "data:") and
         not String.contains?(src, "productGfx___"),
       do: full_size_image(src)
  end

  # "59,00 zł" (a non-breaking space in some themes) -> "59.00".
  defp block_price(block) do
    text =
      block
      |> Floki.find("div.price em")
      |> Enum.take(1)
      |> Floki.text()
      |> String.replace(~r/\s/u, " ")

    case Regex.run(~r/\A(\d{1,7}),(\d{2}) zł\z/, String.trim(text)) do
      [_, zloty, grosze] -> "#{zloty}.#{grosze}"
      nil -> nil
    end
  end

  defp block_in_stock(block) do
    cond do
      Floki.find(block, "input[name=quantity]") != [] -> true
      Floki.find(block, "form.availability-notifier, div.price.noform") != [] -> false
      true -> nil
    end
  end

  defp first([value | _]), do: value
  defp first([]), do: nil
end
