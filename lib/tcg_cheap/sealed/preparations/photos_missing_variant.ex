defmodule TcgCheap.Sealed.Preparations.PhotosMissingVariant do
  @moduledoc """
  Products whose stored photo lacks the current version (name and digest) of
  the `:variant` option's variant, in random order: a photo that keeps failing
  cannot hold up the others.

  Attachments are polymorphic (a text `record_id`), so this is SQL rather than
  `exists(photo.blob.variants, ...)`, which compares it with the uuid key.
  """

  use Ash.Resource.Preparation

  require Ash.Query
  require Ash.Sort

  alias AshStorage.VariantDefinition

  @impl true
  def prepare(query, opts, _context) do
    {:ok, attachment} = AshStorage.Info.attachment(query.resource, :photo)
    variant = Enum.find(attachment.variants, &(&1.name == opts[:variant]))
    record_type = to_string(query.resource)
    name = to_string(variant.name)
    digest = VariantDefinition.digest(variant)

    query
    |> Ash.Query.filter(
      fragment(
        """
        EXISTS (
          SELECT 1 FROM storage_attachments a
          WHERE a.record_type = ? AND a.name = 'photo' AND a.record_id = ?::text
            AND NOT EXISTS (
              SELECT 1 FROM storage_blobs v
              WHERE v.variant_of_blob_id = a.blob_id
                AND v.variant_name = ? AND v.variant_digest = ?
            )
        )
        """,
        ^record_type,
        id,
        ^name,
        ^digest
      )
    )
    |> Ash.Query.sort(Ash.Sort.expr_sort(fragment("random()"), :float))
  end
end
