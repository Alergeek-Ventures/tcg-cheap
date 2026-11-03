defmodule TcgCheap.Sealed.Preparations.PhotosMissingVariant do
  @moduledoc """
  Products whose stored photo lacks the current version (name and digest) of
  any of its variants, in random order: a photo that keeps failing cannot
  hold up the others.

  Attachments are polymorphic (a text `record_id`), so this is SQL rather than
  `exists(photo.blob.variants, ...)`, which compares it with the uuid key.
  """

  use Ash.Resource.Preparation

  require Ash.Query
  require Ash.Sort

  alias AshStorage.VariantDefinition

  @impl true
  def prepare(query, _opts, _context) do
    {:ok, attachment} = AshStorage.Info.attachment(query.resource, :photo)
    record_type = to_string(query.resource)
    names = Enum.map(attachment.variants, &to_string(&1.name))
    digests = Enum.map(attachment.variants, &VariantDefinition.digest/1)

    query
    |> Ash.Query.filter(
      fragment(
        """
        EXISTS (
          SELECT 1 FROM storage_attachments a
          CROSS JOIN unnest(?::text[], ?::text[]) AS d(name, digest)
          WHERE a.record_type = ? AND a.name = 'photo' AND a.record_id = ?::text
            AND NOT EXISTS (
              SELECT 1 FROM storage_blobs v
              WHERE v.variant_of_blob_id = a.blob_id
                AND v.variant_name = d.name AND v.variant_digest = d.digest
            )
        )
        """,
        ^names,
        ^digests,
        ^record_type,
        id
      )
    )
    |> Ash.Query.sort(Ash.Sort.expr_sort(fragment("random()"), :float))
  end
end
