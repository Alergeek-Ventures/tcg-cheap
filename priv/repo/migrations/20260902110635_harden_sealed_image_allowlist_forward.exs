defmodule TcgCheap.Repo.Migrations.HardenSealedImageAllowlistForward do
  @moduledoc "Forward-only cleanup for legacy sealed image evidence."
  use Ecto.Migration

  @image_pattern "^https://((assets\\.tcgdex\\.net|assets\\.pokemon\\.com|www\\.pokemon\\.com|mcdn\\.pokemon\\.com)|([a-z0-9-]+\\.)*(lootquest\\.pl|cardzhouse\\.pl|boosterpoint\\.pl|pokebooster\\.pl|boosterland\\.pl|colligere\\.pl))(:443)?(/|[/?#][^[:space:][:cntrl:]]*)?$"

  def up do
    drop_if_exists constraint(:sealed_products, :sealed_products_image_provenance_invariant)

    execute("""
    UPDATE sealed_products
    SET source_payload = jsonb_set(COALESCE(source_payload, '{}'::jsonb), '{legacy_image_url}', to_jsonb(image_url), true),
        image_url = NULL, image_source = NULL, image_source_url = NULL
    WHERE image_url IS NOT NULL
      AND (image_source = 'Existing product record' OR image_url !~* '#{@image_pattern}'
           OR image_source IS NULL OR btrim(image_source) = ''
           OR image_source_url IS NULL OR btrim(image_source_url) = '')
    """)

    create constraint(:sealed_products, :sealed_products_image_provenance_invariant,
             check:
               "((image_url IS NULL AND image_source IS NULL AND image_source_url IS NULL) OR (image_url IS NOT NULL AND image_source IS NOT NULL AND image_source_url IS NOT NULL AND image_url ~* '#{@image_pattern}' AND btrim(image_source) <> '' AND image_source_url ~ '^https://[^/@/?#[:space:]]+(/|[/?#].*)?$'))"
           )
  end

  def down, do: raise("forward-only migration")
end
