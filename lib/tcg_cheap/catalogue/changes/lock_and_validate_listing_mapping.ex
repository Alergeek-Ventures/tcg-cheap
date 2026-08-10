defmodule TcgCheap.Catalogue.Changes.LockAndValidateListingMapping do
  @moduledoc "Serializes mapping review transitions with a transaction-local row lock."
  use Ash.Resource.Change

  @impl true
  def init(opts) when is_list(opts) do
    allowed = Keyword.get(opts, :allowed_statuses, ["pending", "review"])

    if is_list(allowed) and allowed != [] and
         Enum.all?(allowed, &(&1 in ["pending", "review", "matched", "rejected"])) do
      {:ok, opts}
    else
      {:error, "mapping lock allowed_statuses must be a non-empty list of valid statuses"}
    end
  end

  def init(_), do: {:error, "mapping lock options must be a keyword list"}

  @impl true
  def change(changeset, opts, _context) do
    allowed_statuses = Keyword.get(opts, :allowed_statuses, ["pending", "review"])
    copy_confirmed? = Keyword.get(opts, :copy_confirmed_to_candidate?, false)

    Ash.Changeset.before_action(changeset, fn changeset ->
      id = Ash.Changeset.get_data(changeset, :id)

      query =
        TcgCheap.Catalogue.ListingProductMapping
        |> Ash.Query.for_read(:lock_for_update_by_id, %{id: id})
        |> Ash.Query.lock(:for_update)

      expected_updated_at = Ash.Changeset.get_argument(changeset, :expected_updated_at)

      case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
        {:ok, latest = %{status: status}} ->
          transition_changeset(
            changeset,
            latest,
            status,
            expected_updated_at,
            allowed_statuses,
            copy_confirmed?
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, message: Exception.message(error))
      end
    end)
  end

  defp transition_changeset(
         changeset,
         latest,
         status,
         expected_updated_at,
         allowed_statuses,
         copy_confirmed?
       ) do
    cond do
      status not in allowed_statuses ->
        Ash.Changeset.add_error(changeset,
          message: "mapping is no longer in an allowed transition state"
        )

      latest.updated_at != expected_updated_at or
          Ash.Changeset.get_data(changeset, :updated_at) != expected_updated_at ->
        Ash.Changeset.add_error(changeset, message: "mapping changed after it was loaded")

      copy_confirmed? ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :candidate_product_id,
          latest.confirmed_product_id
        )

      true ->
        changeset
    end
  end
end
