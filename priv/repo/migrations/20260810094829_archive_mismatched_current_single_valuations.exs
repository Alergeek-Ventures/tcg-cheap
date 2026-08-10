defmodule TcgCheap.Repo.Migrations.ArchiveMismatchedCurrentSingleValuations do
  use Ecto.Migration

  def up do
    execute """
    UPDATE single_valuation_snapshots AS snapshot
    SET "current?" = FALSE
    FROM card_printings AS card
    WHERE snapshot.card_printing_id = card.id
      AND snapshot.policy_version = 'tcgdex_cardmarket_v1'
      AND snapshot."current?" = TRUE
      AND (
        card.mapping_status <> 'matched'
        OR card.cardmarket_product_id IS NULL
        OR snapshot.cardmarket_product_id IS DISTINCT FROM card.cardmarket_product_id
      )
    """
  end

  # A former current snapshot cannot safely be restored after its mapping binding
  # has been found invalid. Retained history remains untouched.
  def down, do: :ok
end
