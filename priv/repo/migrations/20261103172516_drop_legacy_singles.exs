defmodule TcgCheap.Repo.Migrations.DropLegacySingles do
  use Ecto.Migration

  def up do
    drop table(:card_printing_mapping_decisions)
    drop table(:card_set_cardmarket_mapping_decisions)
    drop table(:cardmarket_card_mapping_evidence)
    drop table(:acquisition_runs)
    drop table(:acquisition_budget_usages)
    drop table(:catalogue_set_issue_resolutions)
    drop table(:catalogue_sync_runs)
    drop table(:import_issues)
    drop table(:acquisition_source_health)
    drop table(:single_valuation_snapshots)
    drop table(:cardmarket_bulk_prices)
    drop table(:cardmarket_bulk_products)
    drop table(:cardmarket_bulk_raw_responses)
    drop table(:card_printings)
    drop table(:cardmarket_expansion_mappings)
    drop table(:acquisition_data_providers)
    drop table(:card_sets)
    drop table(:cardmarket_bulk_batches)
  end

  def down do
    raise "Dropping legacy singles data is irreversible; restore a database backup to recover it"
  end
end
