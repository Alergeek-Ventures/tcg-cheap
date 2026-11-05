defmodule TcgCheap.Repo.Migrations.BackfillCardImagesUrl do
  @moduledoc """
  Card images were found next to the set logo, which TCGdex lacks for some
  sets (Temporal Forces, SVP and 30th Celebration among them). Sets with a
  logo keep that directory; the others are copied again once by
  `TcgCheap.Sealed.CardSync`, which takes the directory from TCGdex's cards.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE sealed_tcgdex_sets
       SET card_images_url = regexp_replace(logo_url, '/logo(\\.(png|webp|jpg))?$', '')
     WHERE language = 'en' AND logo_url ~ '/logo(\\.(png|webp|jpg))?$'
    """)

    # A set without an official card count is due for copying again.
    execute("""
    UPDATE sealed_tcgdex_sets
       SET official_card_count = NULL
     WHERE language = 'en' AND card_images_url IS NULL
       AND cardmarket_expansion_id IS NOT NULL AND cards_source_url IS NULL
    """)
  end

  def down, do: :ok
end
