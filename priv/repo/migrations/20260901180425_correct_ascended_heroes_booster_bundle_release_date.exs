defmodule TcgCheap.Repo.Migrations.CorrectAscendedHeroesBoosterBundleReleaseDate do
  use Ecto.Migration

  def change do
    execute(
      """
      UPDATE sealed_products
      SET release_date = '2026-04-24', updated_at = NOW()
      WHERE slug = 'pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle'
        AND id = 'e0875d62-fb46-4f5b-93b2-3216a64496b1'::uuid
        AND publication_status = 'approved'
        AND release_date = '2026-01-30'
      """,
      """
      UPDATE sealed_products
      SET release_date = '2026-01-30', updated_at = NOW()
      WHERE slug = 'pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle'
        AND id = 'e0875d62-fb46-4f5b-93b2-3216a64496b1'::uuid
        AND publication_status = 'approved'
        AND release_date = '2026-04-24'
      """
    )
  end
end
