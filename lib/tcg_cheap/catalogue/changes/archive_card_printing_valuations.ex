defmodule TcgCheap.Catalogue.Changes.ArchiveCardPrintingValuations do
  @moduledoc "Archives current valuation snapshots before a mapping transition."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &archive_current_valuations/1)
  end

  defp archive_current_valuations(changeset) do
    card_printing_id = Ash.Changeset.get_data(changeset, :id)

    case TcgCheap.Core.list_current_single_valuations(card_printing_id, authorize?: false) do
      {:ok, snapshots} -> Enum.reduce_while(snapshots, changeset, &archive_snapshot/2)
      {:error, error} -> add_archival_error(changeset, error)
    end
  end

  defp archive_snapshot(snapshot, changeset) do
    case TcgCheap.Core.archive_single_valuation(snapshot, authorize?: false) do
      {:ok, _archived} -> {:cont, changeset}
      {:error, error} -> {:halt, add_archival_error(changeset, error)}
    end
  end

  defp add_archival_error(changeset, _error) do
    Ash.Changeset.add_error(changeset,
      message: "current card valuations could not be archived"
    )
  end
end
