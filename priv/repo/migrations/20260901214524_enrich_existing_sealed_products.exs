defmodule TcgCheap.Repo.Migrations.EnrichExistingSealedProducts do
  @moduledoc """
  Backfills sourced metadata for exactly the listed existing sealed products.

  The up migration fills only missing values and never overwrites reviewed
  metadata. The down migration removes only values that still exactly match
  this backfill, preserving edits made after the migration ran.
  """

  use Ecto.Migration

  @manifest """
  VALUES
    ('pokemon-tcg-pitch-black-3-pack-blister-binacle', 'This blister contains three booster packs and a Binacle foil promo card.', ARRAY['3 booster packs','1 Binacle foil promo card']::text[], 3, 10, 'https://www.pokemon.com/us/pokemon-news/pokemon-tcg-mega-evolution-pitch-black-product-showcase', NULL, NULL, NULL, NULL),
    ('pokemon-tcg-pitch-black-booster-box', 'This booster box contains 36 booster packs.', ARRAY['36 booster packs']::text[], 36, 10, 'https://www.pokemon.com/us/pokemon-news/pokemon-tcg-mega-evolution-pitch-black-product-showcase', 161.64, 'https://www.pokemoncenter.com/product/10-10425-120/pokemon-tcg-mega-evolution-pitch-black-booster-display-box-36-packs', 'https://mcdn.pokemon.com/pokemon-prod/image/upload/c_limit,w_1920/f_auto/v1/live/pcom-cms/static-assets/cms3/us/img/trading-card-game/tiles/me/me05/product-showcase/inline/booster-display-box-en.png', 'https://www.pokemon.com/us/news/pokemon-tcg-mega-evolution-pitch-black-product-showcase'),
    ('pokemon-tcg-pitch-black-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://tcg.pokemon.com/en-us/expansions/pitch-black/', NULL, NULL, 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/me_series/me05/me05-booster-packs-169-en.png', 'https://tcg.pokemon.com/en-us/expansions/pitch-black/'),
    ('pokemon-tcg-pitch-black-elite-trainer-box', 'This Elite Trainer Box contains nine booster packs, a Zarude full-art foil promo, and player accessories.', ARRAY['9 booster packs','Zarude full-art foil promo','65 sleeves','40 Energy','player''s guide','6 damage dice','competition coin-flip die','plastic coin','collector box with 6 dividers','1 Pokémon TCG Live code card']::text[], 9, 10, 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-pitch-black-elite-trainer-box', NULL, NULL, 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me05-elite-trainer-box/me05-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-pitch-black-elite-trainer-box'),
    ('pokemon-tcg-mega-evolution-chaos-rising-booster-box', 'This booster box contains 36 booster packs.', ARRAY['36 booster packs']::text[], 36, 10, 'https://www.pokemoncenter.com/product/10-10407-119/pokemon-tcg-mega-evolution-chaos-rising-booster-display-box-36-packs', 161.64, 'https://www.pokemoncenter.com/product/10-10407-119/pokemon-tcg-mega-evolution-chaos-rising-booster-display-box-36-packs', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/_tiles/me/me04/product-showcase/inline/booster-display-box-en.png', 'https://www.pokemon.com/us/pokemon-news/pokemon-tcg-mega-evolution-chaos-rising-product-showcase'),
    ('pokemon-tcg-mega-evolution-chaos-rising-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-chaos-rising-elite-trainer-box', NULL, NULL, 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/me_series/me04/me04-booster-packs-169-en.png', 'https://tcg.pokemon.com/en-us/expansions/chaos-rising/'),
    ('pokemon-tcg-mega-evolution-chaos-rising-elite-trainer-box', 'This Elite Trainer Box contains nine booster packs, a Fennekin full-art foil promo, and player accessories.', ARRAY['9 booster packs','Fennekin full-art foil promo','65 sleeves','40 Energy','player''s guide','6 damage dice','competition coin-flip die','plastic coin','collector box with 6 dividers','1 Pokémon TCG Live code card']::text[], 9, 10, 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-chaos-rising-elite-trainer-box', NULL, NULL, 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me04-elite-trainer-box/me04-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-chaos-rising-elite-trainer-box'),
    ('pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle', 'This booster bundle contains six booster packs.', ARRAY['6 booster packs']::text[], 6, 10, 'https://www.pokemoncenter.com/product/10-10311-114/pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle-6-packs', 26.94, 'https://www.pokemoncenter.com/product/10-10311-114/pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle-6-packs', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me2pt5-booster-bundle/me2pt5-booster-bundle-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-ascended-heroes-booster-bundle'),
    ('pokemon-tcg-mega-evolution-ascended-heroes-elite-trainer-box', 'This Elite Trainer Box contains nine booster packs, an N''s Zekrom full-art promo, and player accessories.', ARRAY['9 booster packs','N''s Zekrom full-art promo','65 sleeves','40 Energy','player''s guide','6 damage dice','competition die','plastic coin','collector box with 6 dividers','1 Pokémon TCG Live code card']::text[], 9, 10, 'https://www.pokemon.com/us/pokemon-news/pokemon-tcg-mega-evolution-ascended-heroes-product-showcase', NULL, NULL, 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/me2pt5-elite-trainer-box/me2pt5-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-ascended-heroes-elite-trainer-box'),
    ('pokemon-tcg-scarlet-violet-destined-rivals-booster-box', 'This booster box contains 36 booster packs.', ARRAY['36 booster packs']::text[], 36, 10, 'https://www.pokemoncenter.com/product/10-10157-101/pokemon-tcg-scarlet-and-violet-destined-rivals-booster-display-box-36-packs', 161.64, 'https://www.pokemoncenter.com/product/10-10157-101/pokemon-tcg-scarlet-and-violet-destined-rivals-booster-display-box-36-packs', 'https://mcdn.pokemon.com/pokemon-prod/image/upload/c_limit,w_1920/f_auto/v1/live/static-assets/content-assets/cms2/img/trading-card-game/_tiles/sv/sv10/product-showcase/inline/sv10-booster-display-box-en.png', 'https://www.pokemon.com/us/news/pokemon-tcg-scarlet-violet-destined-rivals-product-showcase'),
    ('pokemon-tcg-scarlet-violet-destined-rivals-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemoncenter.com/product/100-10623/pokemon-tcg-scarlet-and-violet-destined-rivals-sleeved-booster-pack-10-cards', 4.49, 'https://www.pokemoncenter.com/product/100-10623/pokemon-tcg-scarlet-and-violet-destined-rivals-sleeved-booster-pack-10-cards', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv10/sv10-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/100-10623/pokemon-tcg-scarlet-and-violet-destined-rivals-sleeved-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-destined-rivals-elite-trainer-box', 'This Elite Trainer Box contains nine booster packs, a Team Rocket''s Wobbuffet full-art promo, and player accessories.', ARRAY['9 booster packs','Team Rocket''s Wobbuffet full-art promo','65 sleeves','45 Energy','player''s guide','6 damage dice','competition die','2 condition markers','collector box with 4 dividers','1 Pokémon TCG Live code card']::text[], 9, 10, 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/scarlet-violet-destined-rivals-elite-trainer-box', 49.99, 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/scarlet-violet-destined-rivals-elite-trainer-box', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2025/sv10-elite-trainer-box/sv10-elite-trainer-box-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/scarlet-violet-destined-rivals-elite-trainer-box'),
    ('pokemon-tcg-scarlet-violet-151-booster-bundle', 'This booster bundle contains six booster packs.', ARRAY['6 booster packs']::text[], 6, 10, 'https://www.pokemoncenter.com/product/699-85322/pokemon-tcg-scarlet-and-violet-151-booster-bundle', 26.94, 'https://www.pokemoncenter.com/product/699-85322/pokemon-tcg-scarlet-and-violet-151-booster-bundle', NULL, NULL),
    ('pokemon-tcg-scarlet-violet-stellar-crown-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemoncenter.com/product/190-41279-BULK/pokemon-tcg-scarlet-and-violet-stellar-crown-booster-pack-10-cards', 4.49, 'https://www.pokemoncenter.com/product/190-41279-BULK/pokemon-tcg-scarlet-and-violet-stellar-crown-booster-pack-10-cards', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv07/sv07-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/190-41279-BULK/pokemon-tcg-scarlet-and-violet-stellar-crown-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-twilight-masquerade-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemoncenter.com/product/189-85340-BULK/pokemon-tcg-scarlet-and-violet-twilight-masquerade-booster-pack-10-cards', 4.49, 'https://www.pokemoncenter.com/product/189-85340-BULK/pokemon-tcg-scarlet-and-violet-twilight-masquerade-booster-pack-10-cards', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv06/sv06-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/189-85340-BULK/pokemon-tcg-scarlet-and-violet-twilight-masquerade-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-temporal-forces-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemoncenter.com/product/188-85981-BULK/pokemon-tcg-scarlet-and-violet-temporal-forces-booster-pack-10-cards', 4.49, 'https://www.pokemoncenter.com/product/188-85981-BULK/pokemon-tcg-scarlet-and-violet-temporal-forces-booster-pack-10-cards', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv05/sv05-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/188-85981-BULK/pokemon-tcg-scarlet-and-violet-temporal-forces-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-paradox-rift-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemoncenter.com/product/187-85399-BULK/pokemon-tcg-scarlet-and-violet-paradox-rift-booster-pack-10-cards', 4.49, 'https://www.pokemoncenter.com/product/187-85399-BULK/pokemon-tcg-scarlet-and-violet-paradox-rift-booster-pack-10-cards', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv04/sv04-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/187-85399-BULK/pokemon-tcg-scarlet-and-violet-paradox-rift-booster-pack-10-cards'),
    ('pokemon-tcg-scarlet-violet-obsidian-flames-booster-pack', 'Each booster pack contains 10 cards, one Basic Energy, and one Pokémon TCG Live code card.', ARRAY['1 booster pack','10 cards','1 Basic Energy','1 Pokémon TCG Live code card']::text[], 1, 10, 'https://www.pokemoncenter.com/product/186-85375/pokemon-tcg-scarlet-and-violet-obsidian-flames-sleeved-booster-pack-10-cards', 4.49, 'https://www.pokemoncenter.com/product/186-85375/pokemon-tcg-scarlet-and-violet-obsidian-flames-sleeved-booster-pack-10-cards', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/sv_series/sv03/sv03-booster-packs-169-en.png', 'https://www.pokemoncenter.com/product/186-85375/pokemon-tcg-scarlet-and-violet-obsidian-flames-sleeved-booster-pack-10-cards'),
    ('pokemon-tcg-pokemon-day-2026-collection', 'This collection contains a Pikachu stamped foil promo, a metallic 30th anniversary coin, and three booster packs from different expansions.', ARRAY['Pikachu stamped foil promo','metallic 30th anniversary coin','3 booster packs from different expansions']::text[], 3, 10, 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/pokemon-day-2026-collection', 14.99, 'https://www.pokemoncenter.com/product/10-10394-108/pokemon-tcg-pokemon-day-2026-collection', 'https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game/series/incrementals/2026/pokemon-day-2026-collection/pokemon-day-2026-collection-169-en.png', 'https://www.pokemon.com/us/pokemon-tcg/product-gallery/pokemon-day-2026-collection')
  """

  def up do
    execute("""
    CREATE TABLE sealed_product_enrichment_backfill_changes (
      slug text NOT NULL,
      field_name text NOT NULL,
      manifest_value jsonb NOT NULL,
      PRIMARY KEY (slug, field_name)
    )
    """)

    execute("""
    WITH manifest(slug, description, contents, pack_count, cards_per_pack, official_url, price, price_url, image_url, image_url_source) AS (#{@manifest}),
    enriched AS (SELECT m.*, 'The Pokémon Company International' AS source, 'Pokémon Center US' AS price_source FROM manifest m)
    INSERT INTO sealed_product_enrichment_backfill_changes (slug, field_name, manifest_value)
    SELECT e.slug, f.field_name, f.manifest_value
    FROM enriched e
    JOIN sealed_products p ON p.slug = e.slug AND p.publication_status = 'approved'
    CROSS JOIN LATERAL (VALUES
      ('description', to_jsonb(e.description), p.description IS NULL OR btrim(p.description) = ''),
      ('contents', to_jsonb(e.contents), p.contents = '{}'::text[]),
      ('pack_count', to_jsonb(e.pack_count), p.pack_count IS NULL),
      ('cards_per_pack', to_jsonb(e.cards_per_pack), p.cards_per_pack IS NULL),
      ('official_url', to_jsonb(e.official_url), p.official_url IS NULL OR btrim(p.official_url) = ''),
      ('details_source', to_jsonb(e.source), p.details_source IS NULL OR btrim(p.details_source) = ''),
      ('details_source_url', to_jsonb(e.official_url), p.details_source_url IS NULL OR btrim(p.details_source_url) = ''),
      ('official_price_amount', to_jsonb(e.price), e.price IS NOT NULL AND p.official_price_amount IS NULL),
      ('official_price_currency', to_jsonb('USD'::text), e.price IS NOT NULL AND (p.official_price_currency IS NULL OR btrim(p.official_price_currency) = '')),
      ('official_price_source', to_jsonb(e.price_source), e.price IS NOT NULL AND (p.official_price_source IS NULL OR btrim(p.official_price_source) = '')),
      ('official_price_source_url', to_jsonb(e.price_url), e.price IS NOT NULL AND (p.official_price_source_url IS NULL OR btrim(p.official_price_source_url) = '')),
      ('image_url', to_jsonb(e.image_url), e.image_url IS NOT NULL AND (p.image_url IS NULL OR btrim(p.image_url) = '')),
      ('image_source', to_jsonb(e.source), e.image_url IS NOT NULL AND (p.image_url IS NULL OR btrim(p.image_url) = '' OR p.image_url = e.image_url) AND (p.image_source IS NULL OR btrim(p.image_source) = '')),
      ('image_source_url', to_jsonb(e.image_url_source), e.image_url IS NOT NULL AND (p.image_url IS NULL OR btrim(p.image_url) = '' OR p.image_url = e.image_url) AND (p.image_source_url IS NULL OR btrim(p.image_source_url) = '') )
    ) AS f(field_name, manifest_value, should_fill)
    WHERE f.should_fill
    """)

    execute("""
    WITH manifest(slug, description, contents, pack_count, cards_per_pack, official_url, price, price_url, image_url, image_url_source) AS (#{@manifest}),
    enriched AS (
      SELECT m.*, 'The Pokémon Company International' AS source, 'Pokémon Center US' AS price_source
      FROM manifest m
    )
    UPDATE sealed_products p
    SET description = COALESCE(NULLIF(btrim(p.description), ''), e.description), contents = CASE WHEN p.contents = '{}'::text[] THEN e.contents ELSE p.contents END,
        pack_count = COALESCE(p.pack_count, e.pack_count), cards_per_pack = COALESCE(p.cards_per_pack, e.cards_per_pack), official_url = COALESCE(NULLIF(btrim(p.official_url), ''), e.official_url),
        details_source = COALESCE(NULLIF(btrim(p.details_source), ''), e.source), details_source_url = COALESCE(NULLIF(btrim(p.details_source_url), ''), e.official_url),
        official_price_amount = COALESCE(p.official_price_amount, e.price), official_price_currency = COALESCE(NULLIF(btrim(p.official_price_currency), ''), CASE WHEN e.price IS NULL THEN NULL ELSE 'USD' END),
        official_price_source = COALESCE(NULLIF(btrim(p.official_price_source), ''), CASE WHEN e.price IS NULL THEN NULL ELSE e.price_source END), official_price_source_url = COALESCE(NULLIF(btrim(p.official_price_source_url), ''), e.price_url),
        image_url = COALESCE(NULLIF(btrim(p.image_url), ''), e.image_url),
        image_source = CASE WHEN e.image_url IS NOT NULL AND (p.image_url IS NULL OR btrim(p.image_url) = '' OR p.image_url = e.image_url) THEN COALESCE(NULLIF(btrim(p.image_source), ''), e.source) ELSE p.image_source END,
         image_source_url = CASE WHEN e.image_url IS NOT NULL AND (p.image_url IS NULL OR btrim(p.image_url) = '' OR p.image_url = e.image_url) THEN COALESCE(NULLIF(btrim(p.image_source_url), ''), e.image_url_source) ELSE p.image_source_url END
    FROM enriched e
    WHERE p.slug = e.slug AND p.publication_status = 'approved' AND (p.description IS NULL OR btrim(p.description) = '' OR p.contents = '{}'::text[] OR p.pack_count IS NULL OR p.cards_per_pack IS NULL OR p.official_url IS NULL OR btrim(p.official_url) = '' OR p.details_source IS NULL OR btrim(p.details_source) = '' OR p.details_source_url IS NULL OR btrim(p.details_source_url) = '' OR e.price IS NOT NULL AND (p.official_price_amount IS NULL OR p.official_price_currency IS NULL OR btrim(p.official_price_currency) = '' OR p.official_price_source IS NULL OR btrim(p.official_price_source) = '' OR p.official_price_source_url IS NULL OR btrim(p.official_price_source_url) = '') OR e.image_url IS NOT NULL AND (p.image_url IS NULL OR btrim(p.image_url) = '' OR p.image_source IS NULL OR btrim(p.image_source) = '' OR p.image_source_url IS NULL OR btrim(p.image_source_url) = ''))
    """)
  end

  def down do
    execute("""
    WITH changes AS (SELECT * FROM sealed_product_enrichment_backfill_changes), eligible AS (
      SELECT p.slug FROM sealed_products p
      WHERE EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name IN ('description','contents','pack_count','cards_per_pack','official_url','details_source','details_source_url'))
        AND NOT EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name IN ('description','contents','pack_count','cards_per_pack','official_url','details_source','details_source_url') AND CASE c.field_name WHEN 'description' THEN to_jsonb(p.description) WHEN 'contents' THEN to_jsonb(p.contents) WHEN 'pack_count' THEN to_jsonb(p.pack_count) WHEN 'cards_per_pack' THEN to_jsonb(p.cards_per_pack) WHEN 'official_url' THEN to_jsonb(p.official_url) WHEN 'details_source' THEN to_jsonb(p.details_source) WHEN 'details_source_url' THEN to_jsonb(p.details_source_url) END IS DISTINCT FROM c.manifest_value)
        AND NOT EXISTS (SELECT 1 FROM (VALUES ('description', p.description IS NOT NULL AND btrim(p.description) <> ''), ('contents', p.contents <> '{}'::text[]), ('pack_count', p.pack_count IS NOT NULL), ('cards_per_pack', p.cards_per_pack IS NOT NULL), ('official_url', p.official_url IS NOT NULL AND btrim(p.official_url) <> ''), ('details_source', p.details_source IS NOT NULL AND btrim(p.details_source) <> ''), ('details_source_url', p.details_source_url IS NOT NULL AND btrim(p.details_source_url) <> '')) present(field_name, present) WHERE present AND NOT EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = present.field_name))
    )
    UPDATE sealed_products p
    SET description = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'description') THEN NULL ELSE p.description END,
        contents = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'contents') THEN '{}'::text[] ELSE p.contents END,
        pack_count = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'pack_count') THEN NULL ELSE p.pack_count END,
        cards_per_pack = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'cards_per_pack') THEN NULL ELSE p.cards_per_pack END,
        official_url = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'official_url') THEN NULL ELSE p.official_url END,
        details_source = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'details_source') THEN NULL ELSE p.details_source END,
        details_source_url = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'details_source_url') THEN NULL ELSE p.details_source_url END
    FROM eligible e WHERE p.slug = e.slug
    """)

    execute("""
    WITH changes AS (SELECT * FROM sealed_product_enrichment_backfill_changes), eligible AS (
      SELECT p.slug FROM sealed_products p
      WHERE EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name LIKE 'official_price_%')
        AND NOT EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name LIKE 'official_price_%' AND CASE c.field_name WHEN 'official_price_amount' THEN to_jsonb(p.official_price_amount) WHEN 'official_price_currency' THEN to_jsonb(p.official_price_currency) WHEN 'official_price_source' THEN to_jsonb(p.official_price_source) WHEN 'official_price_source_url' THEN to_jsonb(p.official_price_source_url) END IS DISTINCT FROM c.manifest_value)
        AND NOT EXISTS (SELECT 1 FROM (VALUES ('official_price_amount', p.official_price_amount IS NOT NULL), ('official_price_currency', p.official_price_currency IS NOT NULL), ('official_price_source', p.official_price_source IS NOT NULL), ('official_price_source_url', p.official_price_source_url IS NOT NULL)) present(field_name, present) WHERE present AND NOT EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = present.field_name))
    ) UPDATE sealed_products p SET official_price_amount = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'official_price_amount') THEN NULL ELSE p.official_price_amount END, official_price_currency = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'official_price_currency') THEN NULL ELSE p.official_price_currency END, official_price_source = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'official_price_source') THEN NULL ELSE p.official_price_source END, official_price_source_url = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'official_price_source_url') THEN NULL ELSE p.official_price_source_url END FROM eligible e WHERE p.slug = e.slug
    """)

    execute("""
    WITH changes AS (SELECT * FROM sealed_product_enrichment_backfill_changes), eligible AS (
      SELECT p.slug FROM sealed_products p
      WHERE EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name LIKE 'image_%')
        AND NOT EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name LIKE 'image_%' AND CASE c.field_name WHEN 'image_url' THEN to_jsonb(p.image_url) WHEN 'image_source' THEN to_jsonb(p.image_source) WHEN 'image_source_url' THEN to_jsonb(p.image_source_url) END IS DISTINCT FROM c.manifest_value)
        AND NOT EXISTS (SELECT 1 FROM (VALUES ('image_url', p.image_url IS NOT NULL), ('image_source', p.image_source IS NOT NULL), ('image_source_url', p.image_source_url IS NOT NULL)) present(field_name, present) WHERE present AND NOT EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = present.field_name))
    ) UPDATE sealed_products p SET image_url = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'image_url') THEN NULL ELSE p.image_url END, image_source = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'image_source') THEN NULL ELSE p.image_source END, image_source_url = CASE WHEN EXISTS (SELECT 1 FROM changes c WHERE c.slug = p.slug AND c.field_name = 'image_source_url') THEN NULL ELSE p.image_source_url END FROM eligible e WHERE p.slug = e.slug
    """)

    execute("DROP TABLE sealed_product_enrichment_backfill_changes")
  end
end
