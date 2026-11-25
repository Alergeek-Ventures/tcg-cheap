defmodule TcgCheap.Sealed.ShopFeed.Sellaio do
  @moduledoc """
  Reads the category listings of a Sellaio storefront (a Next.js shop); Sellaio
  publishes no product feed. The shop's `listing_paths` are its Pokémon
  categories, each read page by page (`?page=<n>` from `n = 2`).

  A listing page carries the products it shows as JSON in the Next.js payload
  of its HTML (`self.__next_f.push` scripts): the category it lists
  (`Category`, which must be the one asked for) and `Products` with the
  category's `total`, the page `limit`, the page's `count` and its `docs`. The
  page count follows from `total` and `limit`; a page whose `count` is not the
  number of its docs or not the number its position implies, a payload that
  cannot be read, a page without products where the category has some, and
  going past `max_pages` pages fail the fetch, as does a listing whose distinct
  products are not `total` (`TcgCheap.Sealed.ShopFeed.HtmlListing.read/3`).

  A product counts when its title names a sealed product
  (`TcgCheap.Sealed.Matcher.sealed_title?/1`), the categories being the shop's
  Pokémon ones. The price is `price.amount`, the gross price in złoty. The
  shop keeps `available` true for products with no stock, so a product is in
  stock when it is `available`, not `presentationOnly` and its
  `stock.available` is above zero (the product page's own `availability` says
  the same). A product with a `preorder` or a pre-order title
  (`TcgCheap.Sealed.Matcher.preorder_title?/1`) is a pre-order (`preorder`) and
  never in stock. The id is the product's `_id`, the EAN its `codes.gtin`, the
  link its `seo.url` and the photo the first of its `media`, on Sellaio's media
  host. Requests are three seconds apart. See `TcgCheap.Sealed.ShopFeed` for the
  shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @image_host "media-manager.sellaio.com"
  @pause_ms 3_000
  @push ~r/self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)/s

  @impl true
  def image_hosts(%Shop{}), do: [@image_host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, &read_listing(shop, req_options, &1)) do
      {:ok, HtmlListing.offers(shop, products, &Matcher.sealed_title?/1)}
    end
  end

  defp read_listing(shop, req_options, path),
    do: HtmlListing.read(&request(shop, req_options, path, &1), shop.max_pages)

  defp request(shop, req_options, path, number) do
    params = if number == 1, do: [], else: [page: number]

    with {:ok, response} <- ShopFeed.get(shop, path, params, req_options, pause_ms: @pause_ms),
         {:ok, document} <- ShopFeed.html(response),
         {:ok, payload} <- payload(document),
         {:ok, category} <- object(payload, ~s("Category":), ~s({"_id")),
         {:ok, products} <- object(payload, ~s("Products":), ~s({"filters")),
         :ok <- listing_of(category, path) do
      page(products, number)
    end
  end

  # A listing path the shop does not know shows another page, not an error.
  defp listing_of(category, path) do
    if at(category, ["seo", "url"]) == path, do: :ok, else: {:error, :unrecognised_listing}
  end

  # The strings the page hands to the Next.js client, joined: the data it
  # renders is in them.
  defp payload(document) do
    scripts = document |> Floki.find("script") |> Floki.text(js: true, sep: "\n")

    literals = for [_all, literal] <- Regex.scan(@push, scripts), do: Jason.decode(literal)

    if literals != [] and Enum.all?(literals, &match?({:ok, text} when is_binary(text), &1)),
      do: {:ok, Enum.map_join(literals, fn {:ok, text} -> text end)},
      else: {:error, :unrecognised_listing}
  end

  # The JSON object that follows `key` where `key` and `opening` occur
  # together exactly once.
  defp object(payload, key, opening) do
    with [{start, _length}] <- :binary.matches(payload, key <> opening),
         rest =
           binary_part(
             payload,
             start + byte_size(key),
             byte_size(payload) - start - byte_size(key)
           ),
         {:ok, length} <- object_length(rest),
         {:ok, %{} = object} <-
           rest |> binary_part(0, length) |> Jason.decode(floats: :decimals) do
      {:ok, object}
    else
      _ -> {:error, :unrecognised_listing}
    end
  end

  # The length of the JSON object `<<?{, …>>` opens, skipping its strings.
  defp object_length(<<?{, rest::binary>>), do: object_length(rest, 1, 1)

  defp object_length(<<>>, _depth, _length), do: :error

  defp object_length(<<?", rest::binary>>, depth, length),
    do: string_length(rest, depth, length + 1)

  defp object_length(<<?{, rest::binary>>, depth, length),
    do: object_length(rest, depth + 1, length + 1)

  defp object_length(<<?}, _rest::binary>>, 1, length), do: {:ok, length + 1}

  defp object_length(<<?}, rest::binary>>, depth, length),
    do: object_length(rest, depth - 1, length + 1)

  defp object_length(<<_byte, rest::binary>>, depth, length),
    do: object_length(rest, depth, length + 1)

  defp string_length(<<>>, _depth, _length), do: :error

  defp string_length(<<?\\, _escaped, rest::binary>>, depth, length),
    do: string_length(rest, depth, length + 2)

  defp string_length(<<?", rest::binary>>, depth, length),
    do: object_length(rest, depth, length + 1)

  defp string_length(<<_byte, rest::binary>>, depth, length),
    do: string_length(rest, depth, length + 1)

  defp page(
         %{"total" => total, "limit" => limit, "count" => count, "docs" => docs},
         number
       )
       when is_integer(total) and total >= 0 and is_integer(limit) and limit > 0 and
              is_integer(count) and is_list(docs) do
    expected = total |> Kernel.-((number - 1) * limit) |> max(0) |> min(limit)

    if count == length(docs) and count == expected,
      do:
        {:ok,
         %{
           number: number,
           last: max(div(total + limit - 1, limit), 1),
           total: total,
           products: Enum.map(docs, &product/1)
         }},
      else: {:error, :malformed_pagination}
  end

  defp page(_products, _number), do: {:error, :unrecognised_listing}

  defp product(%{} = doc) do
    title = doc["name"]

    preorder? =
      not is_nil(doc["preorder"]) or (is_binary(title) and Matcher.preorder_title?(title))

    %{
      id: doc["_id"],
      title: title,
      path: at(doc, ["seo", "url"]),
      image: image(doc["media"]),
      price: price(at(doc, ["price", "amount"])),
      ean: at(doc, ["codes", "gtin"]),
      in_stock: if(preorder?, do: false, else: in_stock(doc)),
      preorder: preorder?
    }
  end

  defp product(_doc),
    do: %{id: nil, title: nil, path: nil, image: nil, price: nil, in_stock: nil}

  # `available` stays true when the stock is used up.
  defp in_stock(%{"available" => available, "stock" => %{"available" => stock}} = doc)
       when is_boolean(available) and is_integer(stock),
       do: available and doc["presentationOnly"] != true and stock > 0

  defp in_stock(_doc), do: nil

  defp image([%{"url" => url} | _media]), do: url
  defp image(_media), do: nil

  defp price(%Decimal{} = price), do: Decimal.to_string(price, :normal)
  defp price(price) when is_integer(price), do: Integer.to_string(price)
  defp price(_price), do: nil

  defp at(value, [key | keys]) when is_map(value), do: at(Map.get(value, key), keys)
  defp at(value, []), do: value
  defp at(_value, _keys), do: nil
end
