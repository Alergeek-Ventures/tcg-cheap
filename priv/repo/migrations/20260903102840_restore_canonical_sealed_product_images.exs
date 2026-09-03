defmodule TcgCheap.Repo.Migrations.RestoreCanonicalSealedProductImages do
  @moduledoc """
  Restores canonical images removed by the legacy unsourced-image cleanup.
  """

  use Ecto.Migration

  @manifest """
  VALUES
    ('pokemon-tcg-pitch-black-booster-box', 'https://mcdn.pokemon.com/pokemon-prod/image/upload/c_limit,w_1920/f_auto/v1/live/pcom-cms/static-assets/cms3/us/img/trading-card-game/tiles/me/me05/product-showcase/inline/booster-display-box-en.png', 'https://www.pokemon.com/us/news/pokemon-tcg-mega-evolution-pitch-black-product-showcase'),
    ('pokemon-tcg-pitch-black-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/me_series/me05/me05-booster-packs-169-en.png', 'https://tcg.pokemon.com/en-us/expansions/pitch-black/'),
    ('pokemon-tcg-pitch-black-elite-trainer-box', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me05-elite-trainer-box/me05-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-pitch-black-elite-trainer-box'),
    ('pokemon-tcg-mega-evolution-chaos-rising-booster-box', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/_tiles/me/me04/product-showcase/inline/booster-display-box-en.png', 'https://www.pokemon.com/us/pokemon-news/pokemon-tcg-mega-evolution-chaos-rising-product-showcase'),
    ('pokemon-tcg-mega-evolution-chaos-rising-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/me_series/me04/me04-booster-packs-169-en.png', 'https://tcg.pokemon.com/en-us/expansions/chaos-rising/'),
    ('pokemon-tcg-mega-evolution-chaos-rising-elite-trainer-box', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me04-elite-trainer-box/me04-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-chaos-rising-elite-trainer-box'),
    ('pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me2pt5-booster-bundle/me2pt5-booster-bundle-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-ascended-heroes-booster-bundle'),
    ('pokemon-tcg-mega-evolution-ascended-heroes-elite-trainer-box', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me2pt5-elite-trainer-box/me2pt5-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-ascended-heroes-elite-trainer-box'),
    ('pokemon-tcg-scarlet-violet-destined-rivals-booster-box', 'https://mcdn.pokemon.com/pokemon-prod/image/upload/c_limit,w_1920/f_auto/v1/live/static-assets/content-assets/cms2/img/trading-card-game/_tiles/sv/sv10/product-showcase/inline/sv10-booster-display-box-en.png', 'https://www.pokemon.com/us/news/pokemon-tcg-scarlet-violet-destined-rivals-product-showcase'),
    ('pokemon-tcg-scarlet-violet-destined-rivals-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv10/sv10-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/100-10623/pokemon-tcg-scarlet-and-violet-destined-rivals-sleeved-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-destined-rivals-elite-trainer-box', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2025/sv10-elite-trainer-box/sv10-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/scarlet-violet-destined-rivals-elite-trainer-box'),
    ('pokemon-tcg-scarlet-violet-stellar-crown-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv07/sv07-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/190-41279-BULK/pokemon-tcg-scarlet-and-violet-stellar-crown-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-twilight-masquerade-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv06/sv06-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/189-85340-BULK/pokemon-tcg-scarlet-and-violet-twilight-masquerade-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-temporal-forces-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv05/sv05-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/188-85981-BULK/pokemon-tcg-scarlet-and-violet-temporal-forces-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-paradox-rift-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv04/sv04-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/187-85399-BULK/pokemon-tcg-scarlet-and-violet-paradox-rift-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-obsidian-flames-booster-pack', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv03/sv03-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/186-85375/pokemon-tcg-scarlet-and-violet-obsidian-flames-sleeved-booster-pack-10-cards'),
    ('pokemon-tcg-pokemon-day-2026-collection', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/pokemon-day-2026-collection/pokemon-day-2026-collection-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/pokemon-day-2026-collection')
  """

  def up do
    execute("""
    WITH manifest(slug, image_url, image_source_url) AS (#{@manifest})
    UPDATE sealed_products AS p
    SET image_url = m.image_url,
        image_source = 'The Pokémon Company International',
        image_source_url = m.image_source_url
    FROM manifest AS m
    WHERE p.slug = m.slug
      AND p.publication_status = 'approved'
      AND p.image_url IS NULL
      AND p.image_source IS NULL
      AND p.image_source_url IS NULL
    """)
  end

  def down do
    raise "forward-only migration"
  end
end
