defmodule TcgCheap.Operations.Changes.AdvanceCatalogueSyncRun do
  @moduledoc "Serializes and validates one catalogue progress transition."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &lock_and_advance/1)
  end

  defp lock_and_advance(changeset) do
    id = Ash.Changeset.get_data(changeset, :id)

    case lock_run(id) do
      {:ok, run} -> advance_locked(changeset, run)
      {:error, message} -> reject(changeset, message)
    end
  end

  defp lock_run(id) do
    case TcgCheap.Repo.query(
           "SELECT set_ids, next_index, synced_sets, failed_sets, excluded_sets, status, started_at FROM catalogue_sync_runs WHERE id = $1 FOR UPDATE",
           [Ecto.UUID.dump!(id)]
         ) do
      {:ok, %{rows: [[set_ids, index, synced, failed, excluded, "running", started_at]]}} ->
        {:ok,
         %{
           set_ids: set_ids,
           index: index,
           counters: %{synced_sets: synced, failed_sets: failed, excluded_sets: excluded},
           started_at: started_at
         }}

      {:ok, %{rows: [[_set_ids, _index, _synced, _failed, _excluded, _status, _started_at]]}} ->
        {:error, "catalogue sync run is not running"}

      _other ->
        {:error, "catalogue sync run could not be locked"}
    end
  end

  defp advance_locked(changeset, run) do
    transition = transition(changeset, run)

    case validate_transition(transition) do
      :ok -> apply_transition(changeset, run, transition)
      {:error, message} -> reject(changeset, message)
    end
  end

  defp transition(changeset, run) do
    %{
      expected_index: Ash.Changeset.get_argument(changeset, :expected_index),
      current_set_id: Enum.at(run.set_ids, run.index),
      index: run.index,
      set_id: Ash.Changeset.get_argument(changeset, :set_id),
      outcome: Ash.Changeset.get_argument(changeset, :outcome),
      completed_at: Ash.Changeset.get_argument(changeset, :completed_at),
      started_at: run.started_at,
      final?: run.index + 1 == length(run.set_ids)
    }
  end

  defp validate_transition(transition) do
    with :ok <- validate_position(transition),
         :ok <- validate_outcome(transition),
         :ok <- validate_completion_shape(transition) do
      validate_completion_time(transition)
    end
  end

  defp validate_position(%{expected_index: expected, index: index}) when expected != index,
    do: {:error, "expected_index is stale"}

  defp validate_position(%{current_set_id: current, set_id: set_id}) when current != set_id,
    do: {:error, "set_id does not match the current set"}

  defp validate_position(_transition), do: :ok

  defp validate_outcome(%{outcome: outcome}) when outcome in ["synced", "failed", "excluded"],
    do: :ok

  defp validate_outcome(_transition), do: {:error, "outcome is invalid"}

  defp validate_completion_shape(%{final?: true, completed_at: %DateTime{}}), do: :ok

  defp validate_completion_shape(%{final?: true}),
    do: {:error, "completed_at is required for the final set"}

  defp validate_completion_shape(%{final?: false, completed_at: nil}), do: :ok

  defp validate_completion_shape(_transition),
    do: {:error, "completed_at is only allowed for the final set"}

  defp validate_completion_time(transition) do
    if completion_before_start?(transition),
      do: {:error, "completed_at cannot be before started_at"},
      else: :ok
  end

  defp apply_transition(changeset, run, transition) do
    counter = counter_for(transition.outcome)

    changeset
    |> Ash.Changeset.force_change_attribute(:next_index, run.index + 1)
    |> Ash.Changeset.force_change_attribute(counter, Map.fetch!(run.counters, counter) + 1)
    |> Ash.Changeset.force_change_attribute(
      :status,
      if(transition.final?, do: "completed", else: "running")
    )
    |> Ash.Changeset.force_change_attribute(
      :completed_at,
      if(transition.final?, do: transition.completed_at, else: nil)
    )
  end

  defp completion_before_start?(%{
         final?: true,
         completed_at: %DateTime{} = completed_at,
         started_at: started_at
       }) do
    NaiveDateTime.compare(DateTime.to_naive(completed_at), naive_datetime(started_at)) == :lt
  end

  defp completion_before_start?(_transition), do: false

  defp reject(changeset, message), do: Ash.Changeset.add_error(changeset, message: message)

  defp counter_for("synced"), do: :synced_sets
  defp counter_for("failed"), do: :failed_sets
  defp counter_for("excluded"), do: :excluded_sets

  defp naive_datetime(%DateTime{} = value), do: DateTime.to_naive(value)
  defp naive_datetime(%NaiveDateTime{} = value), do: value
end
