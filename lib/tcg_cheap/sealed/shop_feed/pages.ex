defmodule TcgCheap.Sealed.ShopFeed.Pages do
  @moduledoc """
  What the clients that read a listing page by page, from page 1 to the last
  page it states, share (`TcgCheap.Sealed.ShopFeed.Collectify`,
  `TcgCheap.Sealed.ShopFeed.Guildmage`, `TcgCheap.Sealed.ShopFeed.MagicznyRynek`,
  `TcgCheap.Sealed.ShopFeed.Smajk`): the walk through the pages and, for the
  listings that state their size, the count of what was read. Listings that
  paginate differently (a counter from 0, a link to the next page, a page
  count stated once) keep their own loop; the ones that parse a
  `t:TcgCheap.Sealed.ShopFeed.HtmlListing.page/0` use
  `TcgCheap.Sealed.ShopFeed.HtmlListing.read/3`.
  """

  @type page :: %{
          required(:number) => pos_integer(),
          required(:pages) => pos_integer(),
          required(:products) => [term()],
          optional(:stated) => term(),
          optional(:total) => non_neg_integer()
        }

  @doc """
  Reads pages 1 to the last one stated, each requested with `request`
  (page number -> `{:ok, page}` | `{:error, reason}`), and returns them in
  order.

  A page names itself `number` and the last page `pages`; `stated` is
  whatever else it says about the whole listing (its size, its page count),
  which must be the same on every page. The walk fails with
  `:pagination_changed` when a page is not the one asked for or its `stated`
  differs from the previous page's, with `:too_many_pages` when a page names
  more than `max_pages` pages and with `:malformed_listing` when a page has
  no products.
  """
  @spec read((pos_integer() -> {:ok, page()} | {:error, term()}), pos_integer()) ::
          {:ok, [page()]} | {:error, term()}
  def read(request, max_pages), do: read(request, max_pages, 1, nil, [])

  defp read(request, max_pages, number, stated, acc) do
    with {:ok, page} <- request.(number) do
      page_stated = Map.get(page, :stated)

      cond do
        stated not in [nil, page_stated] or page.number != number ->
          {:error, :pagination_changed}

        page.pages > max_pages ->
          {:error, :too_many_pages}

        page.products == [] ->
          {:error, :malformed_listing}

        number < page.pages ->
          read(request, max_pages, number + 1, page_stated, [page | acc])

        true ->
          {:ok, Enum.reverse([page | acc])}
      end
    end
  end

  @doc """
  The products of `pages` (each stating the listing's `total`) when there are
  as many as it states and `id` (product -> id) names each one once; else
  `:incomplete_listing`.
  """
  @spec products([page()], (term() -> term())) :: {:ok, [term()]} | {:error, :incomplete_listing}
  def products([%{total: total} | _] = pages, id) do
    products = Enum.flat_map(pages, & &1.products)
    ids = Enum.map(products, id)

    if length(products) == total and ids == Enum.uniq(ids),
      do: {:ok, products},
      else: {:error, :incomplete_listing}
  end
end
