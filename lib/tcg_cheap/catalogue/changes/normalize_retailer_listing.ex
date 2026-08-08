defmodule TcgCheap.Catalogue.Changes.NormalizeRetailerListing do
  @moduledoc "Stores normalized listing title and GTIN values."
  use Ash.Resource.Change
  alias TcgCheap.Catalogue.{SealedIdentifier, SearchText}
  @impl true
  def change(changeset, _opts, _context) do
    title = Ash.Changeset.get_attribute(changeset, :source_title)
    source_listing_id = Ash.Changeset.get_attribute(changeset, :source_listing_id)
    direct_url = Ash.Changeset.get_attribute(changeset, :direct_url)
    gtin = Ash.Changeset.get_attribute(changeset, :gtin)

    changeset
    |> Ash.Changeset.change_attribute(:source_listing_id, trim(source_listing_id))
    |> Ash.Changeset.change_attribute(
      :source_title,
      if(is_binary(title), do: String.trim(title), else: title)
    )
    |> Ash.Changeset.change_attribute(:normalized_title, SearchText.normalize(trim(title)))
    |> Ash.Changeset.change_attribute(:direct_url, trim(direct_url))
    |> Ash.Changeset.change_attribute(
      :gtin,
      if(is_nil(gtin), do: nil, else: SealedIdentifier.normalize(:ean, gtin))
    )
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
