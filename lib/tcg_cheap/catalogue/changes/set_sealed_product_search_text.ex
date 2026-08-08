defmodule TcgCheap.Catalogue.Changes.SetSealedProductSearchText do
  @moduledoc "Derives the private normalized sealed-product search name."
  use Ash.Resource.Change

  alias Ash.Changeset
  alias TcgCheap.Catalogue.SearchText

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.change_attribute(
      changeset,
      :search_name,
      SearchText.normalize(Changeset.get_attribute(changeset, :name))
    )
  end
end
