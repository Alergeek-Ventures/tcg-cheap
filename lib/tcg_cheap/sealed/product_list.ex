defmodule TcgCheap.Sealed.ProductList do
  @moduledoc """
  The public product list: one page of the products matching the filters, in
  stock in the market first, then newest (`TcgCheap.Sealed.Stock` says which
  are in stock, `TcgCheap.Sealed.ProductFacets` what the filters offer).
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Market, Stock, Summary}

  @page_size 30
  # The most products an expansion has is about 55: its page lists them all,
  # so its pull rates and cards follow right after.
  @expansion_page_size 60

  @type filters :: %{
          query: String.t(),
          kind: atom() | nil,
          region: atom() | nil,
          expansion: integer() | nil
        }

  @doc """
  One page of the public list: products matching the filters, in stock in
  the market first, then newest. Returns the summaries, whether more pages
  follow and the total count.
  """
  @spec browse(filters(), non_neg_integer(), DateTime.t(), Market.t()) ::
          {[Summary.t()], boolean(), non_neg_integer()}
  def browse(filters, offset, %DateTime{} = now, market) do
    page =
      Sealed.browse_products!(
        filters.query,
        filters.kind,
        filters.region,
        filters.expansion,
        Stock.list_order(market, now),
        page: [limit: page_size(filters), offset: offset, count: true],
        query: [select: Summary.fields()],
        load: [
          :stored_photo_small_url,
          :stored_photo_card_url,
          :stored_photo_page_url,
          :photo_placeholder
        ]
      )

    {Summary.list(page.results, now, market), page.more?, page.count || 0}
  end

  defp page_size(%{expansion: id}) when is_integer(id), do: @expansion_page_size
  defp page_size(_filters), do: @page_size
end
