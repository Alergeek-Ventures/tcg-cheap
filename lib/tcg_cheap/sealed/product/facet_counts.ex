defmodule TcgCheap.Sealed.Product.FacetCounts do
  @moduledoc """
  The products the public list would show for a search (the `:facets` read),
  counted in the database per language edition, kind, expansion and set name,
  with the newest Cardmarket addition and whether any is in a Polish shop. The
  filter counts are sums of these few hundred groups instead of every product.
  """

  use Ash.Resource.Actions.Implementation

  import Ecto.Query

  alias TcgCheap.Sealed.Product

  @impl true
  def run(input, _opts, _context) do
    with {:ok, products} <-
           Product
           |> Ash.Query.for_read(:facets, %{query: input.arguments.query})
           |> Ash.Query.data_layer_query() do
      {:ok,
       products
       |> exclude(:order_by)
       |> exclude(:select)
       |> group_by([product], [
         product.region,
         product.kind,
         product.cardmarket_expansion_id,
         product.set_name
       ])
       |> select([product], %{
         region: product.region,
         kind: product.kind,
         cardmarket_expansion_id: product.cardmarket_expansion_id,
         set_name: product.set_name,
         count: count(),
         newest: max(product.cardmarket_added_on),
         available?: fragment("bool_or(?)", product.available)
       })
       |> TcgCheap.Repo.all()}
    end
  end
end
