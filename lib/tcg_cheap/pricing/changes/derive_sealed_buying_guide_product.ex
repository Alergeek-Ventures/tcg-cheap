defmodule TcgCheap.Pricing.Changes.DeriveSealedBuyingGuideProduct do
  @moduledoc "Locks and verifies the exact source-aggregate revision used by a guide."
  use Ash.Resource.Change
  require Ash.Query

  alias Ash.Error.Changes.StaleRecord
  alias TcgCheap.Pricing.SealedDailyAggregate
  alias TcgCheap.Pricing.SealedDailyAggregateRevision

  @impl true
  def change(changeset, _opts, _context) do
    expected_date = Ash.Changeset.get_argument(changeset, :expected_source_aggregate_date)

    expected_calculated_at =
      Ash.Changeset.get_argument(changeset, :expected_source_aggregate_calculated_at)

    expected_fingerprint =
      Ash.Changeset.get_argument(changeset, :expected_source_aggregate_fingerprint)

    expected_history_fingerprint =
      Ash.Changeset.get_argument(changeset, :expected_source_history_fingerprint)

    changeset
    |> Ash.Changeset.force_change_attribute(:guide_date, expected_date)
    |> Ash.Changeset.force_change_attribute(
      :source_aggregate_calculated_at,
      expected_calculated_at
    )
    |> Ash.Changeset.force_change_attribute(:source_aggregate_fingerprint, expected_fingerprint)
    |> Ash.Changeset.force_change_attribute(
      :source_history_fingerprint,
      expected_history_fingerprint
    )
    |> Ash.Changeset.before_action(fn changeset ->
      aggregate_id = Ash.Changeset.get_attribute(changeset, :source_aggregate_id)

      query =
        TcgCheap.Pricing.SealedDailyAggregate
        |> Ash.Query.filter(id == ^aggregate_id)
        |> Ash.Query.lock(:for_update)

      case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
        {:ok, nil} ->
          Ash.Changeset.add_error(changeset,
            field: :source_aggregate_id,
            message: "source aggregate was not found"
          )

        {:ok, aggregate} ->
          derive_from_locked_aggregate(
            changeset,
            aggregate,
            expected_calculated_at,
            expected_fingerprint,
            expected_history_fingerprint
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset,
            field: :source_aggregate_id,
            message: Exception.message(error)
          )
      end
    end)
  end

  defp derive_from_locked_aggregate(
         changeset,
         aggregate,
         expected_calculated_at,
         expected_fingerprint,
         expected_history_fingerprint
       ) do
    with true <-
           is_struct(expected_calculated_at, DateTime) and is_binary(expected_fingerprint) and
             is_binary(expected_history_fingerprint),
         true <- aggregate.aggregate_date == Ash.Changeset.get_attribute(changeset, :guide_date),
         :eq <- DateTime.compare(aggregate.calculated_at, expected_calculated_at),
         {:ok, fingerprint} <- SealedDailyAggregateRevision.fingerprint(aggregate),
         true <- fingerprint == expected_fingerprint,
         {:ok, history} <- read_history(aggregate),
         {:ok, history_fingerprint} <-
           SealedDailyAggregateRevision.history_fingerprint(history),
         true <- history_fingerprint == expected_history_fingerprint do
      changeset
      |> Ash.Changeset.force_change_attribute(:sealed_product_id, aggregate.sealed_product_id)
      |> Ash.Changeset.force_change_attribute(:guide_date, aggregate.aggregate_date)
      |> Ash.Changeset.force_change_attribute(
        :source_aggregate_calculated_at,
        aggregate.calculated_at
      )
      |> Ash.Changeset.force_change_attribute(:source_aggregate_fingerprint, fingerprint)
      |> Ash.Changeset.force_change_attribute(:source_history_fingerprint, history_fingerprint)
    else
      _ ->
        Ash.Changeset.add_error(
          changeset,
          StaleRecord.exception(
            resource: TcgCheap.Pricing.SealedDailyAggregate,
            filter: %{id: aggregate.id}
          )
        )
    end
  end

  defp read_history(aggregate) do
    since = Date.add(aggregate.aggregate_date, -30)
    as_of = Date.add(aggregate.aggregate_date, -1)

    SealedDailyAggregate
    |> Ash.Query.filter(
      sealed_product_id == ^aggregate.sealed_product_id and
        calculation_version == ^aggregate.calculation_version and
        aggregate_date >= ^since and aggregate_date <= ^as_of
    )
    |> Ash.Query.sort(aggregate_date: :asc, calculated_at: :asc, id: :asc)
    |> Ash.Query.limit(30)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(domain: TcgCheap.Core, authorize?: false)
  end
end
