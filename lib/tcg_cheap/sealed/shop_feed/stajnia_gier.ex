defmodule TcgCheap.Sealed.ShopFeed.StajniaGier do
  @moduledoc """
  Reads the Pokémon category of stajnia-gier.pl, a Next.js storefront (it
  replaced its PrestaShop shop in November 2026) that renders its product
  tiles on the server: the shop's `feed_path` with `?strona=N` from 1 to the
  last page its "Strona N z M" label announces, at most `max_pages`. Every
  page states the category's size ("Znaleziono 33 produkty"); it must stay
  the same on every page and match the distinct products read (see
  `TcgCheap.Sealed.ShopFeed.HtmlListing`), so a missing or shifted page fails
  the fetch.

  The category mixes sealed products with accessories, so a product counts
  when its title names a sealed product
  (`TcgCheap.Sealed.Matcher.sealed_title?/1`). The tile shows one price, in
  złoty. A product is in stock unless its tile says "Niedostępny"; a tile with
  a "Przedsprzedaż" or "Zapowiedź" label is a pre-order (`preorder`) when in
  stock. The shop's id is the product's slug (`/produkt/<slug>`), which the
  tile does not repeat in any number; a slug longer than the 40 characters an
  offer allows is shortened and given a hash of the whole slug. There is no
  EAN. Links and images, relative to the shop's root, are made absolute. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @max_id_length 40
  @link ~r|\A/produkt/([a-z0-9-]+)\z|
  @page_label ~r/\AStrona (\d{1,3}) z (\d{1,3})\z/
  @total ~r/\AZnaleziono (\d{1,5}) produkt/
  @preorder ~r/\b(?:przedsprzedaz|zapowiedz)/

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <- HtmlListing.read(&request(shop, req_options, &1), shop.max_pages) do
      {:ok, HtmlListing.offers(shop, products, &Matcher.sealed_title?/1)}
    end
  end

  defp request(shop, req_options, number) do
    params = if number == 1, do: [], else: [strona: number]

    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, params, req_options),
         {:ok, document} <- ShopFeed.html(response),
         do: parse_page(document)
  end

  defp parse_page(document) do
    with {:ok, number, last} <- pagination(document),
         {:ok, total} <- total(document),
         [_ | _] = tiles <- Floki.find(document, "main ul > li > article") do
      {:ok, %{number: number, last: last, total: total, products: Enum.map(tiles, &tile/1)}}
    else
      _ -> {:error, :unrecognised_listing}
    end
  end

  # "Strona 2 z 2"; a listing of one page may state none.
  defp pagination(document) do
    labels =
      document
      |> Floki.find("nav")
      |> Enum.flat_map(&Floki.find(&1, "span, p, li"))
      |> Enum.map(&HtmlListing.text/1)
      |> Enum.filter(&(&1 && Regex.match?(@page_label, &1)))
      |> Enum.uniq()

    case labels do
      [] ->
        {:ok, 1, 1}

      [label] ->
        [_, number, last] = Regex.run(@page_label, label)
        {:ok, String.to_integer(number), String.to_integer(last)}

      _ ->
        :error
    end
  end

  defp total(document) do
    document
    |> Floki.find("p")
    |> Enum.map(&HtmlListing.text/1)
    |> Enum.flat_map(&(Regex.run(@total, &1 || "", capture: :all_but_first) || []))
    |> Enum.uniq()
    |> case do
      [total] -> {:ok, String.to_integer(total)}
      _ -> :error
    end
  end

  defp tile(tile) do
    link = HtmlListing.attr(tile, "a[href^='/produkt/']", "href")
    text = tile |> Floki.text(sep: " ") |> Matcher.normalize()
    in_stock = in_stock(tile)

    %{
      id: link && id(link),
      title: tile |> HtmlListing.first("h2") |> HtmlListing.text(),
      path: link,
      image: HtmlListing.attr(tile, "img", "src"),
      price: price(tile),
      in_stock: in_stock && not preorder?(text),
      preorder: in_stock && preorder?(text)
    }
  end

  defp id(link) do
    with [_, slug] <- Regex.run(@link, link) do
      if byte_size(slug) <= @max_id_length do
        slug
      else
        hash = :sha256 |> :crypto.hash(slug) |> Base.encode16(case: :lower) |> binary_part(0, 8)
        binary_part(slug, 0, @max_id_length - 9) <> "-" <> hash
      end
    else
      _ -> nil
    end
  end

  # The tile's price is the only text in the price paragraph; a reduced price
  # is not shown by this shop, so more than one is unreadable.
  defp price(tile) do
    case tile |> Floki.find("span.tabular") |> Enum.map(&HtmlListing.text/1) do
      [text] ->
        case HtmlListing.price_text(text) do
          {:ok, price} -> price
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp in_stock(tile) do
    tile |> Floki.text(sep: " ") |> String.contains?("Niedostępny") |> Kernel.not()
  end

  defp preorder?(text), do: Regex.match?(@preorder, text)
end
