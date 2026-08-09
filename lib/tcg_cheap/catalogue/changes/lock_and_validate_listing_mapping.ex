defmodule TcgCheap.Catalogue.Changes.LockAndValidateListingMapping do
  @moduledoc "Serializes mapping review transitions with a transaction-local row lock."
  use Ash.Resource.Change

  @impl true
  def init(opts) when is_list(opts), do: {:ok, opts}
  def init(_), do: {:error, "mapping lock options must be a keyword list"}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      id = Ash.Changeset.get_data(changeset, :id)

      query =
        TcgCheap.Catalogue.ListingProductMapping
        |> Ash.Query.for_read(:lock_for_update_by_id, %{id: id})
        |> Ash.Query.lock(:for_update)

      expected_updated_at = Ash.Changeset.get_argument(changeset, :expected_updated_at)

      case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
        {:ok, %{status: status, updated_at: ^expected_updated_at}}
        when status in ["pending", "review"] ->
          changeset

        {:ok, %{status: status}} when status in ["pending", "review"] ->
          Ash.Changeset.add_error(changeset, message: "mapping changed after it was loaded")

        {:ok, _} ->
          Ash.Changeset.add_error(changeset,
            message: "mapping is no longer pending or under review"
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, message: Exception.message(error))
      end
    end)
  end
end
