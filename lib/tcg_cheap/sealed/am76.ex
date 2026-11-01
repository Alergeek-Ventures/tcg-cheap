defmodule TcgCheap.Sealed.Am76 do
  @moduledoc """
  Reads the Pokémon category of am76.pl, a custom shop whose pages are
  windows-1250 (decoded to UTF-8 here, byte by byte, before parsing). The
  category (`feed_path`) lists 8 products per page, `?p=N`; its heading says
  which page of how many it is ("str. 2/3").

  Completeness is proved from that heading: every page must state the same
  page count, which must not exceed `max_pages`; pages 1 to that count are
  read, each with products and every page but the last as full as the first;
  the page after the last must have no products; and no product may appear
  twice. Anything else fails the fetch.

  A product counts when it is sealed Pokémon
  (`TcgCheap.Sealed.ShopFeed.sealed_pokemon?/2` on its name and the category
  heading). Its price is the shop's own current price (a struck-through
  comparison price is ignored); it is in stock when the listing offers the
  add-to-cart button, and not when it shows "Brak". The listing's names are
  shortened, so the full name is read from the product's info button. There is
  no EAN. See `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  # The characters of windows-1250 from byte 0x80 up; the five undefined bytes
  # are U+FFFD.
  @cp1250 "€�‚�„…†‡�‰Š‹ŚŤŽŹ�‘’“”•–—�™š›śťžź ˇ˘Ł¤Ą¦§¨©Ş«¬­®Ż°±˛ł´µ¶·¸ąş»Ľ˝ľżŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇÓÔŐÖ×ŘŮÚŰÜÝŢßŕáâăäĺćçčéęëěíîďđńňóôőö÷řůúűüýţ˙"
          |> String.to_charlist()
          |> List.to_tuple()

  @heading ~r/ - str\. ([0-9]{1,3})\/([0-9]{1,3})\z/
  @link ~r/\Aprodukt,[^\s:]{1,200}:([0-9]{1,9})\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, pages} <- fetch_pages(shop, req_options, 1, nil, []) do
      {:ok, ShopFeed.offers(shop, pages, &normalize(shop, &1))}
    end
  end

  defp fetch_pages(shop, req_options, number, count, acc) do
    with {:ok, page} <- request(shop, req_options, number) do
      cond do
        count not in [nil, page.count] or page.number != number -> {:error, :pagination_changed}
        page.count > shop.max_pages -> {:error, :too_many_pages}
        number > page.count and page.products != [] -> {:error, :incomplete_listing}
        number > page.count -> acc |> Enum.reverse() |> complete()
        page.products == [] -> {:error, :malformed_listing}
        true -> fetch_pages(shop, req_options, number + 1, page.count, [page | acc])
      end
    end
  end

  defp complete([]), do: {:error, :empty_listing}

  defp complete([first | _] = pages) do
    sizes = Enum.map(pages, &length(&1.products))
    {full, [last]} = Enum.split(sizes, -1)
    products = Enum.flat_map(pages, & &1.products)
    ids = Enum.map(products, &link/1)

    if Enum.all?(full, &(&1 == hd(sizes))) and last <= hd(sizes) and ids == Enum.uniq(ids),
      do: {:ok, Enum.map(products, &{&1, first.category})},
      else: {:error, :incomplete_listing}
  end

  defp request(shop, req_options, number) do
    with {:ok, response} <- ShopFeed.get(shop, shop.feed_path, [p: number], req_options),
         {:ok, document} <- ShopFeed.html(%{response | body: decode(response.body)}),
         {:ok, category, current, count} <- heading(document) do
      {:ok,
       %{
         products: Floki.find(document, "div.panel.popover-info-opis"),
         category: category,
         number: current,
         count: count
       }}
    end
  end

  defp heading(document) do
    text = document |> Floki.find("h1") |> Floki.text() |> String.trim()

    case Regex.run(@heading, text) do
      [match, number, count] ->
        {:ok, String.replace_suffix(text, match, ""), String.to_integer(number),
         String.to_integer(count)}

      nil ->
        {:error, :malformed_pagination}
    end
  end

  defp decode(body) do
    for <<byte <- body>>, into: "" do
      if byte < 0x80, do: <<byte>>, else: <<elem(@cp1250, byte - 0x80)::utf8>>
    end
  end

  defp link(product),
    do: product |> Floki.find("div.panel-body a") |> Floki.attribute("href") |> List.first()

  defp normalize(shop, {product, category}) do
    with {:ok, title} <- ShopFeed.title(name(product)),
         true <- ShopFeed.sealed_pokemon?(title, category) || :ignore,
         [_, id] <- Regex.run(@link, link(product) || ""),
         {:ok, url} <- ShopFeed.https_url("https://#{shop.host}/#{link(product)}", [shop.host]),
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

  defp name(product) do
    case product
         |> Floki.find("div.panel-footer a.btn-default")
         |> Floki.attribute("data-original-title") do
      [title | _] -> String.replace_prefix(title, "Więcej informacji o ", "")
      [] -> nil
    end
  end

  defp price(product) do
    product
    |> Floki.find("span.new span.price")
    |> Floki.text()
    |> String.trim()
    |> ShopFeed.decimal_price()
  end

  defp in_stock(product) do
    footer = Floki.find(product, "div.panel-footer")

    cond do
      Floki.find(footer, "a.btn-primary[onclick^=koszyk_dodaj]") != [] ->
        {:ok, true}

      footer |> Floki.find("span.ikona-brak") |> Floki.text() |> String.trim() == "Brak" ->
        {:ok, false}

      true ->
        :error
    end
  end

  defp image_url(shop, product) do
    case product |> Floki.find("div.panel-body img") |> Floki.attribute("src") |> List.first() do
      "/plik/" <> _ = src -> ShopFeed.image_url("https://#{shop.host}#{src}", image_hosts(shop))
      _ -> nil
    end
  end
end
