defmodule TcgCheap.Repo do
  use AshPostgres.Repo,
    otp_app: :tcg_cheap

  @impl true
  def installed_extensions do
    ["ash-functions", "citext", "pg_trgm", "pg_search"]
  end

  # Reads and single writes do not need a wrapping transaction.
  @impl true
  def prefer_transaction? do
    false
  end

  @impl true
  def min_pg_version do
    %Version{major: 18, minor: 4, patch: 0}
  end
end
