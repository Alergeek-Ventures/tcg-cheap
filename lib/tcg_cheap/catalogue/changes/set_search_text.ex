defmodule TcgCheap.Catalogue.Changes.SetSearchText do
  @moduledoc "Derives private normalized search fields from printing identity fields."

  use Ash.Resource.Change

  alias Ash.Changeset
  alias TcgCheap.Catalogue.SearchText

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce(
      [
        {:name, :search_name},
        {:set_name, :search_set_name},
        {:collector_number, :search_collector_number},
        {:tcgdex_id, :search_tcgdex_id}
      ],
      changeset,
      fn {source, target}, changeset ->
        Changeset.change_attribute(
          changeset,
          target,
          SearchText.normalize(Changeset.get_attribute(changeset, source))
        )
      end
    )
  end
end
