defmodule TcgCheap.Catalogue.Preparations.PublicSearch do
  @moduledoc false
  use Ash.Resource.Preparation

  import Ash.Expr
  require Ash.Query
  alias TcgCheap.Catalogue.Preparations.Search

  @impl true
  def prepare(query, opts, context) do
    query
    |> Search.prepare(opts, context)
    |> Ash.Query.filter(
      expr(
        collection_scopes != [] and
          (is_nil(collection_expires_on) or collection_expires_on >= today())
      )
    )
  end
end
