defmodule TcgCheap.Repo.Migrations.BackfillListingProductMappingDecisions do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO listing_product_mapping_decisions (
      id,
      event,
      from_status,
      to_status,
      candidate_product_id,
      confirmed_product_id,
      confidence,
      reason,
      evidence_method,
      evidence_gtin,
      actor_type,
      actor_id,
      actor_email,
      mapping_updated_at,
      inserted_at,
      mapping_id
    )
    SELECT
      gen_random_uuid(),
      'baseline',
      NULL,
      mapping.status,
      CASE WHEN mapping.status = 'review' THEN mapping.candidate_product_id END,
      CASE WHEN mapping.status = 'matched' THEN mapping.confirmed_product_id END,
      CASE WHEN mapping.status IN ('review', 'matched') THEN mapping.confidence END,
      CASE WHEN mapping.status IN ('review', 'rejected') THEN mapping.reason END,
      CASE
        WHEN mapping.status IN ('review', 'matched')
          AND jsonb_typeof(mapping.evidence -> 'method') = 'string'
          AND char_length(btrim(mapping.evidence ->> 'method')) BETWEEN 1 AND 64
          THEN mapping.evidence ->> 'method'
        WHEN mapping.status = 'matched' THEN 'unspecified'
      END,
      CASE
        WHEN mapping.status IN ('review', 'matched')
          AND jsonb_typeof(mapping.evidence -> 'gtin') = 'string'
          AND char_length(btrim(mapping.evidence ->> 'gtin')) BETWEEN 1 AND 14
          AND (
            mapping.status = 'matched'
            OR (
              jsonb_typeof(mapping.evidence -> 'method') = 'string'
              AND char_length(btrim(mapping.evidence ->> 'method')) BETWEEN 1 AND 64
            )
          )
          THEN mapping.evidence ->> 'gtin'
      END,
      'system',
      NULL,
      NULL,
      mapping.updated_at,
      mapping.updated_at,
      mapping.id
    FROM listing_product_mappings AS mapping
    WHERE NOT EXISTS (
      SELECT 1
      FROM listing_product_mapping_decisions AS decision
      WHERE decision.mapping_id = mapping.id
    )
    """)
  end

  def down do
    execute("DELETE FROM listing_product_mapping_decisions WHERE event = 'baseline'")
  end
end
