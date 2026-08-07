defmodule TcgCheap.Pricing.Singles.Changes.ReplaceCurrentSnapshot do
  @moduledoc """
  Serializes replacement of the current valuation for one card and policy.

  The parent-card lock is held by the surrounding create transaction, so a
  concurrent first write or replacement cannot observe the same current row.
  """

  use Ash.Resource.Change

  alias TcgCheap.Core

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &replace_current_snapshot/1)
  end

  defp replace_current_snapshot(changeset) do
    card_printing_id = Ash.Changeset.get_attribute(changeset, :card_printing_id)
    policy_version = Ash.Changeset.get_attribute(changeset, :policy_version)

    with {:ok, _card_printing} <- lock_card_printing(card_printing_id),
         {:ok, current} <- current_snapshot(card_printing_id, policy_version),
         :ok <- archive_current(current) do
      changeset
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp lock_card_printing(card_printing_id) do
    Core.lock_card_printing_for_update(card_printing_id)
  end

  defp current_snapshot(card_printing_id, policy_version) do
    Core.get_current_single_valuation(card_printing_id, policy_version)
  end

  defp archive_current(nil), do: :ok

  defp archive_current(snapshot) do
    case Core.archive_single_valuation(snapshot) do
      {:ok, _archived} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
