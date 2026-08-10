defmodule TcgCheap.Catalogue.Changes.RecordCardPrintingMappingDecision do
  @moduledoc "Records an importer or administrator mapping decision atomically."
  use Ash.Resource.Change

  @events ~w(imported baseline provider_updated corrected reopened)

  @impl true
  def init(opts) when is_list(opts) do
    if Keyword.get(opts, :event) in @events,
      do: {:ok, opts},
      else: {:error, "invalid card mapping event"}
  end

  def init(_), do: {:error, "invalid card mapping options"}

  @impl true
  def change(changeset, opts, context) do
    event = Keyword.fetch!(opts, :event)

    Ash.Changeset.after_action(
      changeset,
      &record_after_action(&1, &2, event, context.actor)
    )
  end

  defp record_after_action(changeset, result, configured_event, actor) do
    event = effective_event(configured_event, Ash.Changeset.get_data(changeset, :mapping_status))

    if record?(changeset, result, event) do
      record_decision(decision_attrs(changeset, result, event, actor), result)
    else
      {:ok, result}
    end
  end

  defp effective_event("imported", old_status) when not is_nil(old_status),
    do: "provider_updated"

  defp effective_event(event, _old_status), do: event

  defp record?(_changeset, _result, event) when event in ["corrected", "reopened", "imported"],
    do: true

  defp record?(changeset, result, "provider_updated") do
    old_authority = Ash.Changeset.get_data(changeset, :mapping_authority) || "provider"
    old_authority == "provider" and mapping_changed?(changeset, result)
  end

  defp record?(_changeset, _result, _event), do: false

  defp mapping_changed?(changeset, result) do
    Ash.Changeset.get_data(changeset, :mapping_status) != result.mapping_status or
      Ash.Changeset.get_data(changeset, :cardmarket_product_id) != result.cardmarket_product_id or
      Ash.Changeset.get_data(changeset, :mapping_review_reason) != result.mapping_review_reason
  end

  defp decision_attrs(changeset, result, event, actor) do
    imported? = event == "imported"

    %{
      card_printing_id: result.id,
      event: event,
      from_status: unless(imported?, do: Ash.Changeset.get_data(changeset, :mapping_status)),
      to_status: result.mapping_status,
      from_cardmarket_product_id:
        unless(imported?, do: Ash.Changeset.get_data(changeset, :cardmarket_product_id)),
      cardmarket_product_id: result.cardmarket_product_id,
      mapping_authority: result.mapping_authority,
      reason: decision_reason(changeset, result, event),
      source_mapping_evidence_at: result.mapping_updated_at,
      printing_version_at: result.updated_at,
      actor_type: actor_type(actor),
      actor_id: actor_id(actor),
      actor_email: actor_email(actor)
    }
  end

  defp decision_reason(changeset, _result, event) when event in ["corrected", "reopened"],
    do: Ash.Changeset.get_argument(changeset, :reason)

  defp decision_reason(_changeset, result, _event), do: result.mapping_review_reason

  defp record_decision(attrs, result) do
    case TcgCheap.Core.record_card_printing_mapping_decision(attrs, authorize?: false) do
      {:ok, _decision} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp actor_type(%TcgCheap.Accounts.Admin{}), do: "administrator"
  defp actor_type(_), do: "system"
  defp actor_id(%TcgCheap.Accounts.Admin{id: id}), do: id
  defp actor_id(_), do: nil
  defp actor_email(%TcgCheap.Accounts.Admin{email: email}), do: to_string(email)
  defp actor_email(_), do: nil
end
