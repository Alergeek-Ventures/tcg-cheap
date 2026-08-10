defmodule TcgCheap.Operations.Changes.StartCatalogueSyncRun do
  @moduledoc false
  use Ash.Resource.Change

  @pattern ~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

  @impl true
  def change(changeset, _opts, _context) do
    set_ids = Ash.Changeset.get_argument(changeset, :set_ids)

    if canonical?(set_ids) do
      changeset
      |> Ash.Changeset.change_attribute(:provider_key, "tcgdex_catalogue")
      |> Ash.Changeset.change_attribute(:set_ids, set_ids)
      |> Ash.Changeset.change_attribute(
        :started_at,
        Ash.Changeset.get_argument(changeset, :started_at)
      )
    else
      Ash.Changeset.add_error(changeset,
        field: :set_ids,
        message: "must be sorted, unique, and match TCGdex IDs"
      )
    end
  end

  defp canonical?(set_ids) when is_list(set_ids),
    do:
      set_ids != [] and length(set_ids) <= 1000 and Enum.sort(set_ids) == set_ids and
        MapSet.size(MapSet.new(set_ids)) == length(set_ids) and Enum.all?(set_ids, &is_binary/1) and
        Enum.all?(set_ids, &Regex.match?(@pattern, &1))

  defp canonical?(_), do: false
end
