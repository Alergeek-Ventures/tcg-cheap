defmodule TcgCheap.Catalogue.Changes.LockAndValidateCardmarketExpansion do
  @moduledoc "Locks a CardSet and validates immutable successful-batch review evidence."
  use Ash.Resource.Change
  alias TcgCheap.Accounts.AdminActor
  alias TcgCheap.Catalogue.CardmarketExpansionMapping
  alias TcgCheap.Pricing.CardmarketBulk.Batch
  require Ash.Query

  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &validate(&1, context.actor))

  defp validate(changeset, actor) do
    with :ok <- AdminActor.validate(actor),
         {:ok, latest} <- lock_set(changeset),
         {:ok, {mapping, batch}} <- source(changeset, latest),
         :ok <- validate_reason(Ash.Changeset.get_argument(changeset, :reason)),
         false <-
           latest.cardmarket_expansion_id == mapping.expansion_id and
             latest.cardmarket_mapping_authority == "administrator" do
      Ash.Changeset.force_change_attributes(changeset, %{
        cardmarket_expansion_id: mapping.expansion_id,
        cardmarket_mapping_status: "matched",
        cardmarket_mapping_authority: "administrator",
        cardmarket_mapping_evidence_at: batch.completed_at,
        cardmarket_mapping_reason: Ash.Changeset.get_argument(changeset, :reason)
      })
    else
      true -> Ash.Changeset.add_error(changeset, message: "mapping approval is a no-op")
      _ -> Ash.Changeset.add_error(changeset, message: "mapping approval is not available")
    end
  end

  defp lock_set(changeset) do
    id = Ash.Changeset.get_data(changeset, :id)
    query = Ash.Query.for_read(TcgCheap.Catalogue.CardSet, :lock_for_update_by_id, %{id: id})

    case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, nil} ->
        {:error, :missing_set}

      {:ok, latest} ->
        expected = Ash.Changeset.get_argument(changeset, :expected_updated_at)

        if latest.updated_at == expected and
             Ash.Changeset.get_data(changeset, :updated_at) == expected,
           do: {:ok, latest},
           else: {:error, :stale}

      error ->
        error
    end
  end

  defp source(changeset, latest) do
    id = Ash.Changeset.get_argument(changeset, :source_mapping_id)

    query =
      Ash.Query.for_read(CardmarketExpansionMapping, :read, %{})
      |> Ash.Query.filter(expr(id == ^id))

    with {:ok, mapping} when not is_nil(mapping) <-
           Ash.read_one(query, domain: TcgCheap.Core, authorize?: false),
         {:ok, %Batch{} = batch} <- load_batch(mapping.source_batch_id),
         {:ok, %Batch{} = latest_batch} <- load_latest_batch(),
         %Batch{status: "succeeded"} <- batch do
      if mapping.card_set_id == latest.id and mapping.status == "review" and
           batch.id == latest_batch.id,
         do: {:ok, {mapping, batch}},
         else: {:error, :wrong_source}
    else
      _ -> {:error, :wrong_source}
    end
  end

  defp load_latest_batch do
    Batch
    |> Ash.Query.for_read(:latest_successful, %{})
    |> Ash.read_one(domain: TcgCheap.Core, authorize?: false)
  end

  defp load_batch(id) do
    Batch
    |> Ash.Query.for_read(:read, %{})
    |> Ash.Query.filter(expr(id == ^id))
    |> Ash.read_one(domain: TcgCheap.Core, authorize?: false)
  end

  defp validate_reason(reason) when is_binary(reason),
    do: if(String.trim(reason) == "", do: {:error, :blank}, else: :ok)

  defp validate_reason(_), do: {:error, :blank}
end
