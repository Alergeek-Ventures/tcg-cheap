defmodule TcgCheap.Sealed.Changes.DropUnsourcedPhoto do
  @moduledoc """
  Removes the stored photo of a product left with neither a checked photo nor
  a shop photo, so a cleared wrong photo does not stay on its page.
  `TcgCheap.Sealed.PhotoMirror` replaces it otherwise.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, product -> drop(product) end)
  end

  defp drop(%{checked_photo_url: nil, image_url: nil} = product) do
    with {:ok, _purged} <- AshStorage.Operations.purge(product, :photo), do: {:ok, product}
  end

  defp drop(product), do: {:ok, product}

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
