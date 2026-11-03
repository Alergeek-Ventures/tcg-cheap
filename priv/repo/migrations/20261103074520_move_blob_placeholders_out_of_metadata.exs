defmodule TcgCheap.Repo.Migrations.MoveBlobPlaceholdersOutOfMetadata do
  use Ecto.Migration

  def up do
    execute """
    UPDATE storage_blobs
    SET placeholder = metadata->>'placeholder', metadata = metadata - 'placeholder'
    WHERE metadata ? 'placeholder'
    """
  end

  def down do
    execute """
    UPDATE storage_blobs
    SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('placeholder', placeholder)
    WHERE placeholder IS NOT NULL
    """
  end
end
