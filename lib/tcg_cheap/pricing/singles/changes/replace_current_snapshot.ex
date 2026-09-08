defmodule TcgCheap.Pricing.Singles.Changes.ReplaceCurrentSnapshot do
  @moduledoc "Serializes replacement of the current Cardmarket bulk valuation."

  use Ash.Resource.Change

  alias TcgCheap.Core

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &replace_current_snapshot/1)
  end

  defp replace_current_snapshot(changeset) do
    card_printing_id = Ash.Changeset.get_attribute(changeset, :card_printing_id)

    with {:ok, card_printing} <- Core.lock_card_printing_for_update(card_printing_id),
         :ok <- validate_current_bulk_mapping(changeset, card_printing),
         {:ok, current} <-
           Core.get_current_single_valuation(card_printing_id, "cardmarket_bulk_v1"),
         :ok <- archive_current(current) do
      changeset
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp validate_current_bulk_mapping(changeset, card_printing) do
    snapshot_product_id = Ash.Changeset.get_attribute(changeset, :cardmarket_product_id)

    if card_printing.mapping_status == "matched" and
         is_integer(card_printing.cardmarket_product_id) and
         card_printing.cardmarket_product_id > 0 and
         snapshot_product_id == card_printing.cardmarket_product_id do
      :ok
    else
      {:error,
       "Cardmarket bulk valuation must match the currently matched positive Cardmarket product"}
    end
  end

  defp archive_current(nil), do: :ok

  defp archive_current(snapshot) do
    case Core.archive_single_valuation(snapshot) do
      {:ok, _archived} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
