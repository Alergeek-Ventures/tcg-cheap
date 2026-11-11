defmodule TcgCheap.Repo.Migrations.RemoveDuplicateBladeAwakeningCoinSet do
  use Ecto.Migration

  # Cardmarket 873186 duplicates 862201 (TcgCheap.Sealed.Catalogue @duplicates);
  # the import keeps products that leave its rows, so the stored copy goes here.
  # Its daily prices are deleted and any offers unassigned by the foreign keys.
  def up do
    execute "DELETE FROM sealed_products WHERE cardmarket_id = 873186"
  end

  # The next catalogue import cannot bring it back, so there is nothing to restore.
  def down, do: :ok
end
