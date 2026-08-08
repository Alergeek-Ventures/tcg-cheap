defmodule TcgCheap.Catalogue.Changes.LockRetailerListingIngest do
  @moduledoc "Serializes concurrent ingests for one retailer/source listing identity."
  use Ash.Resource.Change

  alias TcgCheap.Repo

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &lock_listing/1)
  end

  defp lock_listing(changeset) do
    retailer_id = Ash.Changeset.get_attribute(changeset, :retailer_id)
    source_listing_id = Ash.Changeset.get_attribute(changeset, :source_listing_id)

    key = "retailer-listing:" <> String.downcase(retailer_id) <> ":" <> source_listing_id

    case Repo.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key]) do
      {:ok, _result} -> changeset
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end
end
