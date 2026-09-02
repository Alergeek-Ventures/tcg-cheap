defmodule TcgCheap.Catalogue.Preparations.PublicSearch do
  @moduledoc false
  use Ash.Resource.Preparation

  alias TcgCheap.Catalogue.Preparations.PublicPaperCard
  alias TcgCheap.Catalogue.Preparations.Search

  @impl true
  def prepare(query, opts, context) do
    query
    |> Search.prepare(opts, context)
    |> PublicPaperCard.prepare([], context)
  end
end
