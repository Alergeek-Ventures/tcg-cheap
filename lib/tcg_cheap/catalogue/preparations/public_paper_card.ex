defmodule TcgCheap.Catalogue.Preparations.PublicPaperCard do
  @moduledoc "Restricts public and pricing card reads to canonical paper cards."
  use Ash.Resource.Preparation

  require Ash.Query
  import Ash.Expr

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.filter(query, expr(not is_nil(card_set.series_id) and card_set.series_id != "tcgp"))
  end
end
