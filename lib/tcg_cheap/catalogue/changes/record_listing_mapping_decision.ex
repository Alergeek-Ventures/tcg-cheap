defmodule TcgCheap.Catalogue.Changes.RecordListingMappingDecision do
  @moduledoc "Records one explicit mapping decision inside its parent transaction."
  use Ash.Resource.Change

  require Ash.Query

  alias TcgCheap.Catalogue.ListingProductMappingDecision
  alias TcgCheap.Core

  @events ~w(created baseline approved rejected reopened)

  @impl true
  def init(opts) when is_list(opts) do
    event = Keyword.get(opts, :event)
    only_if_missing? = Keyword.get(opts, :only_if_missing?, false)

    if event in @events and is_boolean(only_if_missing?) do
      {:ok, opts}
    else
      {:error, "mapping decision event or only_if_missing? option is invalid"}
    end
  end

  def init(_), do: {:error, "mapping decision options must be a keyword list"}

  @impl true
  def change(changeset, opts, context) do
    event = Keyword.fetch!(opts, :event)
    only_if_missing? = Keyword.get(opts, :only_if_missing?, false)

    Ash.Changeset.after_action(changeset, fn after_changeset, result ->
      attrs = decision_attrs(after_changeset, result, event, context.actor)

      with {:ok, true} <- record_decision?(result.id, only_if_missing?),
           {:ok, _decision} <- Core.record_listing_mapping_decision(attrs, authorize?: false) do
        {:ok, result}
      else
        {:ok, false} -> {:ok, result}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp decision_attrs(changeset, result, event, actor) do
    evidence = result.evidence || %{}
    evidence_method = evidence_method(evidence, result.status)

    %{
      mapping_id: result.id,
      event: event,
      from_status:
        if(event == "created", do: nil, else: Ash.Changeset.get_data(changeset, :status)),
      to_status: result.status,
      candidate_product_id: result.candidate_product_id,
      confirmed_product_id: result.confirmed_product_id,
      confidence: result.confidence,
      reason: result.reason,
      evidence_method: evidence_method,
      evidence_gtin: evidence_gtin(evidence, evidence_method),
      mapping_updated_at: result.updated_at,
      actor_type: actor_type(actor),
      actor_id: actor_id(actor),
      actor_email: actor_email(actor)
    }
  end

  defp actor_type(%TcgCheap.Accounts.Admin{}), do: "administrator"
  defp actor_type(_), do: "system"
  defp actor_id(%TcgCheap.Accounts.Admin{id: id}), do: id
  defp actor_id(_), do: nil
  defp actor_email(%TcgCheap.Accounts.Admin{email: email}), do: to_string(email)
  defp actor_email(_), do: nil

  defp evidence_method(evidence, status) do
    case Map.get(evidence, :method) || Map.get(evidence, "method") do
      nil when status == "matched" ->
        "unspecified"

      method when is_binary(method) and byte_size(method) <= 64 ->
        if String.valid?(method) and String.trim(method) != "",
          do: method,
          else: fallback_method(status)

      _method when status == "matched" ->
        "unspecified"

      _method ->
        nil
    end
  end

  defp fallback_method("matched"), do: "unspecified"
  defp fallback_method(_status), do: nil

  defp evidence_gtin(_evidence, nil), do: nil

  defp evidence_gtin(evidence, _method) do
    case Map.get(evidence, :gtin) || Map.get(evidence, "gtin") do
      gtin when is_binary(gtin) and byte_size(gtin) <= 14 ->
        if String.valid?(gtin) and String.trim(gtin) != "", do: gtin, else: nil

      _gtin ->
        nil
    end
  end

  defp record_decision?(_mapping_id, false), do: {:ok, true}

  defp record_decision?(mapping_id, true) do
    query = Ash.Query.filter(ListingProductMappingDecision, mapping_id: mapping_id)

    case Ash.exists(query, domain: Core, authorize?: false) do
      {:ok, exists?} -> {:ok, not exists?}
      {:error, error} -> {:error, error}
    end
  end
end
