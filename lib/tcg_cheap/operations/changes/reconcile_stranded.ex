defmodule TcgCheap.Operations.Changes.ReconcileStranded do
  @moduledoc "Guards the internal stale-run transition with a row lock and cutoff."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      cutoff = Ash.Changeset.get_argument(changeset, :expected_cutoff)
      finished_at = Ash.Changeset.get_argument(changeset, :finished_at)
      id = Ash.Changeset.get_data(changeset, :id)

      eligible? =
        match?(%DateTime{time_zone: "Etc/UTC"}, cutoff) and
          match?(%DateTime{time_zone: "Etc/UTC"}, finished_at) and
          case TcgCheap.Repo.query(
                 "SELECT status, started_at FROM acquisition_runs WHERE id = $1 FOR UPDATE",
                 [Ecto.UUID.dump!(id)]
               ) do
            {:ok, %{rows: [["running", started_at]]}} ->
              DateTime.compare(to_utc_datetime(started_at), cutoff) != :gt

            _ ->
              false
          end

      if eligible? do
        changeset
        |> Ash.Changeset.force_change_attribute(:status, "failed")
        |> Ash.Changeset.force_change_attribute(:failure_category, "unknown")
        |> Ash.Changeset.force_change_attribute(:finished_at, finished_at)
      else
        Ash.Changeset.add_error(changeset,
          message: "acquisition run is not eligible for reconciliation"
        )
      end
    end)
  rescue
    _ ->
      Ash.Changeset.add_error(changeset,
        message: "acquisition run is not eligible for reconciliation"
      )
  end

  defp to_utc_datetime(%DateTime{} = value), do: value
  defp to_utc_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
