defmodule TcgCheap.Catalogue.Changes.NormalizeRetailer do
  @moduledoc "Canonicalizes retailer slugs."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    slug = Ash.Changeset.get_attribute(changeset, :slug)
    source_key = Ash.Changeset.get_attribute(changeset, :source_key)
    name = Ash.Changeset.get_attribute(changeset, :name)

    changeset =
      Ash.Changeset.change_attribute(
        changeset,
        :slug,
        slug
        |> to_string()
        |> String.trim()
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "-")
        |> String.trim("-")
      )

    changeset
    |> Ash.Changeset.change_attribute(:source_key, trim(source_key))
    |> Ash.Changeset.change_attribute(:name, trim(name))
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
