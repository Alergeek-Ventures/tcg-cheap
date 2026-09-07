defmodule TcgCheap.Catalogue.Changes.RecordCardSetCardmarketMappingDecision do
  @moduledoc "Records immutable administrator history after a CardSet mapping approval."
  use Ash.Resource.Change
  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Catalogue.CardmarketExpansionMapping
  alias TcgCheap.Pricing.CardmarketBulk.MappingReplayWorker
  alias TcgCheap.Pricing.Singles.ValuationPolicyCache

  def change(changeset, _opts, context),
    do:
      changeset
      |> Ash.Changeset.after_action(&record(&1, &2, context.actor))
      |> Ash.Changeset.after_transaction(&invalidate_after_commit/2)

  defp invalidate_after_commit(_changeset, {:ok, _result} = outcome) do
    ValuationPolicyCache.invalidate()
    outcome
  end

  defp invalidate_after_commit(_changeset, {:error, _} = outcome), do: outcome

  defp record(changeset, result, %Admin{} = actor) do
    mapping_id = Ash.Changeset.get_argument(changeset, :source_mapping_id)

    mapping =
      CardmarketExpansionMapping
      |> Ash.Query.for_read(:by_id, %{id: mapping_id})
      |> Ash.read_one!(domain: TcgCheap.Core, authorize?: false)

    attrs = %{
      card_set_id: result.id,
      source_mapping_id: mapping.id,
      source_batch_id: mapping.source_batch_id,
      event:
        if(
          result.cardmarket_mapping_authority == "administrator" and
            not is_nil(Ash.Changeset.get_data(changeset, :cardmarket_expansion_id)),
          do: "corrected",
          else: "approved"
        ),
      from_expansion_id: Ash.Changeset.get_data(changeset, :cardmarket_expansion_id),
      to_expansion_id: result.cardmarket_expansion_id,
      reason: Ash.Changeset.get_argument(changeset, :reason),
      card_set_version_at: result.updated_at,
      actor_id: actor.id,
      actor_email: to_string(actor.email)
    }

    case TcgCheap.Core.record_card_set_cardmarket_mapping_decision(attrs, authorize?: false) do
      {:ok, decision} ->
        case MappingReplayWorker.enqueue(mapping.source_batch_id, decision.id) do
          {:ok, _job} -> {:ok, result}
          error -> error
        end

      error ->
        error
    end
  end
end
