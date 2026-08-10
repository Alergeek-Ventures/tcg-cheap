defmodule TcgCheap.Operations.Changes.StaleStatusTransition do
  @moduledoc """
  Locks a provider and applies a status transition only when its displayed version
  still matches. The update actions require `require_atomic? false` because the
  lock-and-compare must run inside the transaction immediately before the update.
  """

  use Ash.Resource.Change
  alias TcgCheap.Operations.ProviderSourceHealthLock

  @impl true
  def init(opts) do
    case Keyword.get(opts, :status) do
      status when status in ["active", "disabled"] -> {:ok, opts}
      _ -> {:error, "status must be active or disabled"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    status = Keyword.fetch!(opts, :status)

    Ash.Changeset.before_action(changeset, fn changeset ->
      expected =
        Ash.Changeset.get_argument(changeset, :expected_updated_at) ||
          Map.get(changeset.arguments, :expected_updated_at) ||
          Map.get(changeset.arguments, "expected_updated_at")

      id = Ash.Changeset.get_data(changeset, :id)
      provider_key = Ash.Changeset.get_data(changeset, :provider_key)

      ProviderSourceHealthLock.lock_source!(provider_key)

      case TcgCheap.Repo.query(
             "SELECT status, updated_at FROM acquisition_data_providers WHERE id = $1 FOR UPDATE",
             [Ecto.UUID.dump!(id)]
           ) do
        {:ok, %{rows: [[current_status, updated_at]]}} ->
          validate_transition(changeset, status, current_status, updated_at, expected)

        _ ->
          stale(changeset)
      end
    end)
    |> Ash.Changeset.after_action(fn changeset, result ->
      if status == "active" do
        provider_key = Ash.Changeset.get_data(changeset, :provider_key)

        TcgCheap.Repo.query!(
          "UPDATE acquisition_source_health SET circuit_failure_streak = 0, circuit_opened_at = NULL, updated_at = now() WHERE provider_key = $1",
          [provider_key]
        )
      end

      {:ok, result}
    end)
  end

  defp validate_transition(changeset, status, current_status, updated_at, expected) do
    if current_status == opposite_status(status) and same_version?(updated_at, expected),
      do: Ash.Changeset.force_change_attribute(changeset, :status, status),
      else: stale(changeset)
  end

  defp stale(changeset),
    do: Ash.Changeset.add_error(changeset, message: "expected_updated_at is stale")

  defp opposite_status("disabled"), do: "active"
  defp opposite_status("active"), do: "disabled"

  defp same_version?(%DateTime{} = actual, %DateTime{} = expected),
    do: DateTime.compare(actual, expected) == :eq

  defp same_version?(%NaiveDateTime{} = actual, %DateTime{} = expected),
    do: same_version?(DateTime.from_naive!(actual, "Etc/UTC"), expected)

  defp same_version?(_, _), do: false
end
