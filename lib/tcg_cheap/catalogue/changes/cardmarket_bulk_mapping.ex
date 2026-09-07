defmodule TcgCheap.Catalogue.Changes.CardmarketBulkMapping do
  @moduledoc "Locks and validates a system-owned Cardmarket bulk mapping transition."
  use Ash.Resource.Change
  require Ash.Query
  import Ash.Expr

  @prefix "cardmarket_bulk_v1:"

  @impl true
  def init(opts) when is_list(opts) do
    if Keyword.get(opts, :mode) in [:match, :review],
      do: {:ok, opts},
      else: {:error, "invalid Cardmarket bulk mapping mode"}
  end

  def init(_), do: {:error, "Cardmarket bulk mapping options must be a keyword list"}

  @impl true
  def change(changeset, opts, context) do
    mode = Keyword.fetch!(opts, :mode)

    Ash.Changeset.before_action(changeset, fn cs ->
      if is_nil(context.actor) do
        validate_and_change(cs, mode)
      else
        Ash.Changeset.add_error(cs, message: "Cardmarket bulk mappings are system-only")
      end
    end)
  end

  defp validate_and_change(cs, mode) do
    expected = Ash.Changeset.get_argument(cs, :expected_updated_at)
    query = lock_query(cs)

    case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, latest} ->
        with {:ok, evidence} <- superseded_evidence(cs, latest),
             :ok <- validate_locked(cs, latest, expected, evidence) do
          apply_transition(cs, latest, mode)
        else
          {:error, message} -> Ash.Changeset.add_error(cs, message: message)
        end

      _ ->
        Ash.Changeset.add_error(cs, message: "mapping could not be locked")
    end
  end

  defp lock_query(cs) do
    id = Ash.Changeset.get_data(cs, :id)
    Ash.Query.for_read(TcgCheap.Catalogue.CardPrinting, :lock_for_update_by_id, %{id: id})
  end

  defp validate_locked(cs, latest, expected, evidence) do
    cond do
      not current_and_expected?(cs, latest, expected) ->
        {:error, "mapping is stale or not eligible for Cardmarket bulk"}

      eligible?(latest) ->
        :ok

      latest.mapping_status == "matched" and latest.mapping_authority == "provider" and
          valid_superseded_evidence?(evidence, latest) ->
        :ok

      true ->
        {:error, "mapping is stale or not eligible for Cardmarket bulk"}
    end
  end

  defp current_and_expected?(cs, latest, expected),
    do: latest.updated_at == expected and Ash.Changeset.get_data(cs, :updated_at) == expected

  defp eligible?(latest), do: provider_pending?(latest) or provider_bulk_review?(latest)

  defp superseded_evidence(cs, _latest) do
    case Ash.Changeset.get_argument(cs, :superseded_evidence_id) do
      nil ->
        {:ok, nil}

      id ->
        query =
          TcgCheap.Catalogue.CardmarketCardMappingEvidence
          |> Ash.Query.for_read(:read, %{})
          |> Ash.Query.filter(expr(id == ^id))

        case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
          {:ok, evidence} when not is_nil(evidence) -> {:ok, evidence}
          _ -> {:error, "mapping evidence is invalid for Cardmarket bulk"}
        end
    end
  end

  defp valid_superseded_evidence?(
         %{
           decision: "auto_matched",
           card_printing_id: card_id,
           cardmarket_product_id: product_id
         },
         latest
       ) do
    card_id == latest.id and product_id == latest.cardmarket_product_id
  end

  defp valid_superseded_evidence?(_, _), do: false

  defp provider_pending?(latest),
    do:
      latest.mapping_authority == "provider" and latest.mapping_status in ["pending", "unmatched"]

  defp provider_bulk_review?(latest) do
    latest.mapping_status == "review" and latest.mapping_authority == "provider" and
      is_binary(latest.mapping_review_reason) and
      String.starts_with?(latest.mapping_review_reason, @prefix)
  end

  defp apply_transition(cs, latest, mode) do
    target_reason = target_reason(cs, mode)

    if already_applied?(cs, latest, mode, target_reason) do
      cs
    else
      force_transition(cs, mode, target_reason)
    end
  end

  defp target_reason(_cs, :match), do: nil
  defp target_reason(cs, :review), do: prefix_reason(Ash.Changeset.get_argument(cs, :reason))

  defp already_applied?(cs, latest, mode, target_reason) do
    latest.mapping_status == target_status(mode) and
      latest.mapping_review_reason == target_reason and latest.mapping_authority == "provider" and
      product_matches?(cs, latest, mode)
  end

  defp target_status(:match), do: "matched"
  defp target_status(:review), do: "review"

  defp product_matches?(_cs, _latest, :review), do: true

  defp product_matches?(cs, latest, :match),
    do: latest.cardmarket_product_id == Ash.Changeset.get_argument(cs, :cardmarket_product_id)

  defp force_transition(cs, mode, target_reason) do
    cs
    |> Ash.Changeset.force_change_attribute(:mapping_status, target_status(mode))
    |> Ash.Changeset.force_change_attribute(:cardmarket_product_id, target_product(cs, mode))
    |> Ash.Changeset.force_change_attribute(:mapping_review_reason, target_reason)
    |> Ash.Changeset.force_change_attribute(:mapping_authority, "provider")
    |> Ash.Changeset.force_change_attribute(
      :mapping_updated_at,
      Ash.Changeset.get_argument(cs, :evidence_timestamp)
    )
  end

  defp target_product(cs, :match), do: Ash.Changeset.get_argument(cs, :cardmarket_product_id)
  defp target_product(_cs, :review), do: nil

  defp prefix_reason(reason) do
    reason = String.trim(reason)
    if String.starts_with?(reason, @prefix), do: reason, else: @prefix <> reason
  end
end
