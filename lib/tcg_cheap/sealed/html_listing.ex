defmodule TcgCheap.Sealed.HtmlListing do
  @moduledoc """
  What the clients that read a shop's HTML category pages share: fetching
  and parsing a page, reading a node's text and price, walking a shop's
  `listing_paths`, and – for clients that describe each page as a `t:page/0`
  (`TcgCheap.Sealed.ShoperListing`, `TcgCheap.Sealed.SkyShop`) – paging
  through a listing and turning its products into offers.

  `read/2` accepts the pages only when they form the complete listing: each
  page names itself `n`, none announces more than `max_pages` pages, the
  stated total (when the listing has one) does not change between pages and
  equals the distinct products read, a page has products unless the listing
  states that it is empty, and a page where no product is readable (no id,
  name, link, price or availability) is not a product list the client
  recognises.
  """

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @type product :: %{
          required(:id) => String.t() | nil,
          required(:title) => String.t() | nil,
          required(:path) => String.t() | nil,
          required(:image) => String.t() | nil,
          required(:price) => String.t() | nil,
          required(:in_stock) => boolean() | nil
        }
  @type page :: %{
          number: pos_integer(),
          last: pos_integer(),
          total: non_neg_integer() | nil,
          products: [product()]
        }

  @doc "Fetches and parses the page at `path`."
  @spec page(Shop.t(), String.t(), keyword()) :: {:ok, Floki.html_tree()} | {:error, term()}
  def page(shop, path, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options),
         do: ShopFeed.html(response)
  end

  @doc """
  Runs `read` (path -> `{:ok, products}` | `{:error, reason}`) on each of the
  shop's listing paths and joins the products. Any failing listing fails the
  fetch.
  """
  @spec read_listings(Shop.t(), (String.t() -> {:ok, [map()]} | {:error, term()})) ::
          {:ok, [map()]} | {:error, term()}
  def read_listings(%Shop{listing_paths: [_ | _] = paths}, read) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case read.(path) do
        {:ok, products} -> {:cont, {:ok, acc ++ products}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Reads a listing page by page with `request`, which returns the parsed page
  `n` or an error. The result is every product of every page, in order.
  """
  @spec read((pos_integer() -> {:ok, page()} | {:error, term()}), pos_integer()) ::
          {:ok, [product()]} | {:error, term()}
  def read(request, max_pages), do: read(request, max_pages, 1, nil, [])

  defp read(request, max_pages, number, total, acc) do
    with {:ok, page} <- request.(number),
         :ok <- check(page, max_pages, number, total) do
      acc = [page.products | acc]

      if number < page.last,
        do: read(request, max_pages, number + 1, page.total, acc),
        else: acc |> Enum.reverse() |> List.flatten() |> complete(page.total)
    end
  end

  defp check(page, max_pages, number, total) do
    cond do
      page.number != number -> {:error, :pagination_changed}
      page.last > max_pages -> {:error, :too_many_pages}
      number > 1 and page.total != total -> {:error, :pagination_changed}
      true -> check_products(page)
    end
  end

  defp check_products(%{products: [], total: 0}), do: :ok
  defp check_products(%{products: []}), do: {:error, :empty_page}

  defp check_products(%{products: products}) do
    if Enum.any?(products, &readable?/1), do: :ok, else: {:error, :unrecognised_listing}
  end

  defp readable?(product) do
    Enum.all?([:id, :title, :path, :price], &is_binary(product[&1])) and
      is_boolean(product.in_stock)
  end

  defp complete(products, total) do
    distinct = products |> Enum.map(& &1.id) |> Enum.uniq() |> length()

    if is_nil(total) or distinct == total,
      do: {:ok, products},
      else: {:error, :incomplete_listing}
  end

  @doc """
  Turns the products of a complete listing into unique offers. `sealed?` says
  whether a title is a sealed Pokémon product; links and images, relative to
  the shop's host, are made absolute on it. Listings carry no EAN.
  """
  @spec offers(Shop.t(), [product()], (String.t() -> boolean())) :: [ShopFeed.offer()]
  def offers(shop, products, sealed?),
    do: ShopFeed.offers(shop, products, &normalize(shop, &1, sealed?))

  defp normalize(shop, product, sealed?) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- sealed?.(title) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.path),
         {:ok, price} <- ShopFeed.decimal_price(product.price),
         in_stock when is_boolean(in_stock) <- product.in_stock do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product.image),
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

  defp product_url(shop, "/" <> _rest = path) do
    with {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}#{path}", [shop.host]),
         do: {:ok, "https://#{shop.host}#{uri.path}"}
  end

  defp product_url(_shop, _path), do: :error

  defp image_url(_shop, nil), do: nil

  defp image_url(shop, "/" <> _path = image),
    do: ShopFeed.image_url("https://#{shop.host}#{image}", [shop.host])

  defp image_url(shop, image), do: ShopFeed.image_url(image, [shop.host])

  @doc "The text of a node (or the first of a list), whitespace collapsed; nil when empty."
  @spec text(Floki.html_tree() | Floki.html_node() | nil) :: String.t() | nil
  def text(nil), do: nil

  def text(node) do
    case node |> Floki.text(sep: " ") |> String.replace(~r/[\s\x{a0}]+/u, " ") |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  @doc "The first node matching `selector`, or nil."
  @spec first(Floki.html_tree() | Floki.html_node(), String.t()) :: Floki.html_node() | nil
  def first(node, selector), do: node |> Floki.find(selector) |> List.first()

  @doc "The first value of attribute `name` on nodes matching `selector`, or nil."
  @spec attr(Floki.html_tree() | Floki.html_node(), String.t(), String.t()) :: String.t() | nil
  def attr(node, selector, name), do: node |> Floki.attribute(selector, name) |> List.first()

  @doc """
  A price written in Polish style (`"1 369,99 zł"`, `"280,00 zł."`, `"89,90"`)
  or with a decimal point (`"25.00 zł"`), with an optional `zł`/`PLN`
  suffix, as a decimal string `ShopFeed.decimal_price/1` accepts.
  """
  @spec price_text(String.t() | nil) :: {:ok, String.t()} | :error
  def price_text(nil), do: :error

  def price_text(text) do
    squeezed = String.replace(text, ~r/[\s\x{a0}]+/u, "")

    case Regex.run(~r/\A([0-9]{1,7})(?:[,.]([0-9]{1,2}))?(?:zł|PLN)?\.?\z/u, squeezed) do
      [_, whole] -> {:ok, whole}
      [_, whole, cents] -> {:ok, whole <> "." <> cents}
      nil -> :error
    end
  end
end
