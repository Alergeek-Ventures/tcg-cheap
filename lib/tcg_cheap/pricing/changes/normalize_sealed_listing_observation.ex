defmodule TcgCheap.Pricing.Changes.NormalizeSealedListingObservation do
  @moduledoc "Trims the preserved source title before recording an observation."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    title = Ash.Changeset.get_attribute(changeset, :source_title)

    if is_binary(title) do
      Ash.Changeset.change_attribute(changeset, :source_title, String.trim(title))
    else
      changeset
    end
  end
end
