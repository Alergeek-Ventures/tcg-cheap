defmodule TcgCheap.Catalogue.Changes.NormalizeSealedIdentifier do
  @moduledoc "Stores a canonical alias value while retaining its original display value."
  use Ash.Resource.Change

  alias Ash.Changeset
  alias TcgCheap.Catalogue.SealedIdentifier

  @impl true
  def change(changeset, _opts, _context) do
    kind = Changeset.get_attribute(changeset, :kind)
    value = Changeset.get_attribute(changeset, :original_value)

    Changeset.change_attribute(
      changeset,
      :normalized_value,
      SealedIdentifier.normalize(kind, value)
    )
  end
end
