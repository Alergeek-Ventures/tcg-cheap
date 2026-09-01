defmodule TcgCheap.Repo.Migrations.EnablePgStatStatements do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_settings
        WHERE name = 'shared_preload_libraries'
          AND EXISTS (
            SELECT 1
            FROM regexp_split_to_table(setting, '\\s*,\\s*') AS preload(library)
            WHERE btrim(preload.library) = 'pg_stat_statements'
          )
      ) THEN
        RAISE EXCEPTION
          'pg_stat_statements must be present in shared_preload_libraries before running this migration';
      END IF;
    END
    $$;
    """)

    execute("CREATE EXTENSION IF NOT EXISTS pg_stat_statements")
  end

  def down do
    # pg_stat_statements may be shared by other applications using this database.
    :ok
  end
end
