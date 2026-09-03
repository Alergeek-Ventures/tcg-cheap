defmodule TcgCheap.Repo.Migrations.CorrectPitchBlackEliteTrainerBoxProductType do
  @moduledoc "Corrects the approved Pitch Black Elite Trainer Box product type."
  use Ecto.Migration

  def up do
    execute("""
    UPDATE sealed_products
    SET product_type = 'elite_trainer_box'
    WHERE slug = 'pokemon-tcg-pitch-black-elite-trainer-box'
      AND publication_status = 'approved'
      AND product_type = 'booster_pack'
    """)
  end

  def down, do: raise("forward-only migration")
end
