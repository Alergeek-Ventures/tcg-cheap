defmodule TcgCheap.Sealed.Changes.RecordCards do
  @moduledoc """
  Replaces a TCGdex set's cards with the `cards` argument in the action's
  transaction: listed cards are upserted with `TcgCheap.Sealed.TcgdexCard`'s
  `action` (`:record` by default), the others removed.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.TcgdexCard

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, set ->
      cards = Ash.Changeset.get_argument(changeset, :cards)
      ids = Enum.map(cards, & &1.tcgdex_id)

      %Ash.BulkResult{status: :success} =
        cards
        |> Enum.map(&Map.put(&1, :tcgdex_set_id, set.id))
        |> Ash.bulk_create!(TcgdexCard, Keyword.get(opts, :action, :record),
          domain: Sealed,
          return_errors?: true,
          stop_on_error?: true
        )

      %Ash.BulkResult{status: :success} =
        TcgdexCard
        |> Ash.Query.filter(tcgdex_set_id == ^set.id and tcgdex_id not in ^ids)
        |> Ash.bulk_destroy!(:prune, %{}, domain: Sealed, return_errors?: true)

      {:ok, set}
    end)
  end

  # The hook runs after the update, so the action stays atomic.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
