defmodule TcgCheap.Sealed.ShopFeed.HtmlListing do
  @moduledoc """
  What the clients that read a shop's HTML category pages share: fetching
  and parsing a page, reading a node's text and price, walking a shop's
  `listing_paths` and `singles_categories` (the listings of single cards,
  `read_singles/2`), and – for clients that describe each page as a
  `t:page/0` (`TcgCheap.Sealed.ShopFeed.ShoperListing`, `TcgCheap.Sealed.ShopFeed.SkyShop`) –
  paging through a listing and turning its products into offers.

  `read/3` accepts the pages only when they form the complete listing: each
  page names itself `n`, none announces more than `max_pages` pages, the
  page count and the stated total (when the listing has one) do not change
  between pages, the total equals the distinct ids read (in all passes,
  when a listing is read more than once), a page has products unless the listing
  states that it is empty, and a page where no product is readable (no id,
  name, link, price or availability) is not a product list the client
  recognises, unless the client explicitly recognises its card metadata
  (`recognised: true` on the page). This lets known cards without offers
  (for example sold-out products with no price) still prove completeness.
  A listing whose stated total also counts its promoted tiles (ids in the
  page's `promoted`, not products of the result) is compared like with like:
  the distinct products and promoted ids together must equal the total. The
  promoted ids must be the same on every page of every pass, otherwise a
  rotating advertisement could stand in for a missing product.
  """

  alias TcgCheap.Sealed.{Ean, Shop, ShopFeed}

  @spaces ~r/[\s\x{a0}]+/u
  @price ~r/\A([0-9]{1,7})(?:[,.]([0-9]{1,2}))?(?:zł|PLN)?\.?\z/u
  # Per singles listing, which is far longer than a sealed one. A page takes
  # 1–2.5 s with the pause (Arena's 32 pages of 96 singles: 78 s), so one full
  # listing stays well within the job's 5-minute timeout; a shop with several
  # long listings must keep their sum within it too.
  @max_singles_pages 40

  @type product :: %{
          required(:id) => String.t() | nil,
          required(:title) => String.t() | nil,
          required(:path) => String.t() | nil,
          required(:image) => String.t() | nil,
          required(:price) => String.t() | nil,
          required(:in_stock) => boolean() | nil,
          optional(:ean) => String.t() | nil,
          optional(:preorder) => boolean(),
          optional(:category) => String.t() | nil
        }
  @type page :: %{
          required(:number) => pos_integer(),
          required(:last) => pos_integer(),
          required(:total) => non_neg_integer() | nil,
          required(:products) => [product()],
          optional(:recognised) => boolean(),
          optional(:promoted) => [String.t()]
        }

  @doc "Fetches and parses the page at `path`."
  @spec page(Shop.t(), String.t(), keyword(), keyword()) ::
          {:ok, Floki.html_tree()} | {:error, term()}
  def page(shop, path, req_options, opts \\ []) do
    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options, opts),
         do: ShopFeed.html(response)
  end

  @doc """
  Runs `read` (path -> `{:ok, products}` | `{:error, reason}`) on each of the
  shop's listing paths and joins the products. Any failing listing fails the
  fetch.
  """
  @spec read_listings(Shop.t(), (String.t() -> {:ok, [map()]} | {:error, term()})) ::
          {:ok, [map()]} | {:error, term()}
  def read_listings(%Shop{listing_paths: [_ | _] = paths}, read), do: read_paths(paths, read)

  @doc """
  Reads the shop's `singles_categories`, the paths of its listings of single
  cards, with `read` (path, max pages -> `{:ok, products}` |
  `{:error, reason}`), at most #{@max_singles_pages} pages each, and tags
  every product as a single: `{:single, product}`. A shop without singles
  categories reads none. Any failing listing fails the fetch.
  """
  @spec read_singles(Shop.t(), (String.t(), pos_integer() -> {:ok, [term()]} | {:error, term()})) ::
          {:ok, [{:single, term()}]} | {:error, term()}
  def read_singles(%Shop{singles_categories: nil}, _read), do: {:ok, []}

  def read_singles(%Shop{singles_categories: [_ | _] = paths}, read) do
    with {:ok, products} <- read_paths(paths, &read.(&1, @max_singles_pages)),
         do: {:ok, Enum.map(products, &{:single, &1})}
  end

  @doc """
  Runs `read` on each of `listings` (any terms naming a listing) and joins
  the products. Any failing listing fails the fetch.
  """
  @spec read_paths([term()], (term() -> {:ok, [map()]} | {:error, term()})) ::
          {:ok, [map()]} | {:error, term()}
  def read_paths(paths, read) do
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

  A listing whose order is not stable between requests (products that tie
  on the sort key are shuffled anew for each page) can show a product on
  two pages and another on none, so one pass falls short of its stated
  total. With `passes` above 1 such a listing is read again, at most
  `passes` times in all, until the passes together hold the stated total;
  every pass must agree with the first on the page count and the total.
  The result then holds the products of every pass read (not the promoted
  tiles, which only count towards the total).

  A listing that is still short after the last pass fails with
  `{:incomplete_listing, read, stated, passes}`: the distinct ids read (the
  products and the promoted ids, overlap counted once), the total the listing
  states and the passes made, so that a failed run can be explained from the
  logs.
  """
  @spec read((pos_integer() -> {:ok, page()} | {:error, term()}), pos_integer(), pos_integer()) ::
          {:ok, [product()]}
          | {:error,
             term()
             | {:incomplete_listing, non_neg_integer(), non_neg_integer(), pos_integer()}}
  def read(request, max_pages, passes \\ 1), do: read(request, max_pages, passes, 1, nil, [])

  defp read(request, max_pages, passes, made, first, before) do
    with {:ok, first, pages} <- read_pass(request, max_pages, 1, first, []) do
      pages = before ++ pages

      case complete(pages, first) do
        {:error, {:incomplete_listing, _read, _stated}} when made < passes ->
          read(request, max_pages, passes, made + 1, first, pages)

        {:error, {:incomplete_listing, read, stated}} ->
          {:error, {:incomplete_listing, read, stated, made}}

        {:ok, products} ->
          {:ok, products}
      end
    end
  end

  defp read_pass(request, max_pages, number, first, acc) do
    with {:ok, page} <- request.(number),
         :ok <- check(page, max_pages, number, first || page) do
      first = first || page
      acc = [page | acc]

      if number < page.last,
        do: read_pass(request, max_pages, number + 1, first, acc),
        else: {:ok, first, Enum.reverse(acc)}
    end
  end

  # Every page must agree with the first on the page count and the total.
  defp check(page, max_pages, number, first) do
    cond do
      page.number != number -> {:error, :pagination_changed}
      page.last > max_pages -> {:error, :too_many_pages}
      {page.last, page.total} != {first.last, first.total} -> {:error, :pagination_changed}
      promoted(page) != promoted(first) -> {:error, :pagination_changed}
      not valid_promoted?(promoted(page)) -> {:error, :unrecognised_listing}
      true -> check_products(page)
    end
  end

  # The promoted ids of a page, as a set; a page without any promotes none.
  defp promoted(page), do: page |> Map.get(:promoted, []) |> MapSet.new()

  defp valid_promoted?(ids), do: Enum.all?(ids, &(is_binary(&1) and &1 != ""))

  defp check_products(%{products: [], total: 0}), do: :ok
  defp check_products(%{products: []}), do: {:error, :empty_page}
  defp check_products(%{recognised: true}), do: :ok

  defp check_products(%{products: products}) do
    if Enum.any?(products, &readable?/1), do: :ok, else: {:error, :unrecognised_listing}
  end

  defp readable?(product) do
    Enum.all?([:id, :title, :path, :price], &is_binary(product[&1])) and
      is_boolean(product.in_stock)
  end

  # The distinct ids read: those of the products plus the first page's promoted
  # ids (`check/4` makes every page carry the same ones, so later advertisements
  # never widen the allowance).
  defp complete(pages, %{total: total} = first) do
    products = Enum.flat_map(pages, & &1.products)

    distinct =
      products
      |> Enum.map(& &1.id)
      |> MapSet.new()
      |> MapSet.union(promoted(first))
      |> MapSet.size()

    if is_nil(total) or distinct == total,
      do: {:ok, products},
      else: {:error, {:incomplete_listing, distinct, total}}
  end

  @doc """
  Turns the products of a complete listing into unique offers. `sealed?` says
  whether a title is a sealed Pokémon product; every product of a singles
  listing (`{:single, product}`, see `read_singles/2`) is a single, priced
  with the singles minimum, whose category is its listing's `category`. Links
  and images, relative to the shop's host, are made absolute on it. Absolute
  image URLs are accepted only from the source's declared image hosts.
  A listing may carry an EAN, validated by `TcgCheap.Sealed.Ean`.
  """
  @spec offers(Shop.t(), [product() | {:single, product()}], (String.t() -> boolean())) ::
          [ShopFeed.offer()]
  def offers(shop, products, sealed?),
    do: ShopFeed.offers(shop, products, &normalize(shop, &1, sealed?))

  defp normalize(shop, {:single, product}, _sealed?) do
    with {:ok, title} <- ShopFeed.title(product.title),
         {:ok, offer} <- offer(shop, product, title, :single) do
      {:ok, [Map.merge(offer, %{kind: :single, category: Map.get(product, :category)})]}
    else
      _ -> :invalid
    end
  end

  defp normalize(shop, product, sealed?) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- sealed?.(title) || :ignore,
         {:ok, offer} <- offer(shop, product, title, :sealed) do
      {:ok, [offer]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp offer(shop, product, title, kind) do
    with {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.path),
         {:ok, price} <- ShopFeed.decimal_price(product.price, kind),
         in_stock when is_boolean(in_stock) <- product.in_stock do
      {:ok,
       %{
         shop_product_id: id,
         title: title,
         url: url,
         image_url: image_url(shop, product.image),
         ean: Ean.normalize(Map.get(product, :ean)),
         price: price,
         in_stock: in_stock,
         preorder: Map.get(product, :preorder, false)
       }}
    else
      _ -> :error
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

  defp image_url(shop, image), do: ShopFeed.image_url(image, ShopFeed.image_hosts(shop))

  @doc "The text of a node (or the first of a list), whitespace collapsed; nil when empty."
  @spec text(Floki.html_tree() | Floki.html_node() | nil) :: String.t() | nil
  def text(nil), do: nil

  def text(node) do
    case node |> Floki.text(sep: " ") |> String.replace(@spaces, " ") |> String.trim() do
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
    squeezed = String.replace(text, @spaces, "")

    case Regex.run(@price, squeezed) do
      [_, whole] -> {:ok, whole}
      [_, whole, cents] -> {:ok, whole <> "." <> cents}
      nil -> :error
    end
  end
end
