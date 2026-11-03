defmodule TcgCheap.Storage.Changes.StorePlaceholder do
  @moduledoc """
  Keeps a variant's inline placeholder (`TcgCheap.Storage.Variants.Webp`) in
  the blob's `placeholder` column. AshStorage puts whatever a variant writer
  returns into `metadata`; listings read the placeholder of every photo they
  show, so it lives in a column of its own.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :metadata) do
      %{placeholder: placeholder} = metadata ->
        changeset
        |> Ash.Changeset.force_change_attribute(:placeholder, placeholder)
        |> Ash.Changeset.force_change_attribute(:metadata, Map.delete(metadata, :placeholder))

      _metadata ->
        changeset
    end
  end
end
