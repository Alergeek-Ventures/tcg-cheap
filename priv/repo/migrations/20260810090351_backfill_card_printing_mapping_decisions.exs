defmodule TcgCheap.Repo.Migrations.BackfillCardPrintingMappingDecisions do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO card_printing_mapping_decisions
      (id, card_printing_id, event, from_status, to_status, from_cardmarket_product_id,
       cardmarket_product_id, mapping_authority, reason, source_mapping_evidence_at,
       printing_version_at, actor_type, actor_id, actor_email, inserted_at)
    SELECT md5('card-printing-mapping-baseline:' || id::text)::uuid,
      id, 'baseline', NULL, mapping_status, NULL, cardmarket_product_id,
      mapping_authority, mapping_review_reason, mapping_updated_at, updated_at,
      'system', NULL, NULL, updated_at
    FROM card_printings AS card
    WHERE NOT EXISTS (
      SELECT 1
      FROM card_printing_mapping_decisions AS decision
      WHERE decision.card_printing_id = card.id
    )
    """
  end

  def down do
    execute """
    DELETE FROM card_printing_mapping_decisions AS decision
    USING card_printings AS card
    WHERE decision.id = md5('card-printing-mapping-baseline:' || card.id::text)::uuid
      AND decision.card_printing_id = card.id
      AND decision.event = 'baseline'
      AND decision.actor_type = 'system'
    """
  end
end
