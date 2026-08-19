defmodule TcgCheap.Repo.Migrations.BackfillSinglesCollectionScope do
  use Ecto.Migration

  def up do
    execute """
    UPDATE card_printings
    SET collection_scopes = ARRAY['legacy_local']::text[],
        collection_scope_source = 'legacy',
        collection_scoped_at = (now() AT TIME ZONE 'utc')
    WHERE collection_scopes = '{}'::text[]
      AND collection_scope_source IS NULL
      AND collection_scoped_at IS NULL
      AND collection_expires_on IS NULL
    """
  end

  def down do
    execute """
    UPDATE card_printings
    SET collection_scopes = ARRAY[]::text[],
        collection_scope_source = NULL,
        collection_scoped_at = NULL,
        collection_expires_on = NULL
    WHERE collection_scopes = ARRAY['legacy_local']::text[]
      AND collection_scope_source = 'legacy'
    """
  end
end
