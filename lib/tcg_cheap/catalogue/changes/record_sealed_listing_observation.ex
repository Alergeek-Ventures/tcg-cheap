defmodule TcgCheap.Catalogue.Changes.RecordSealedListingObservation do
  @moduledoc "Appends a changed sealed listing projection after a successful ingest."
  use Ash.Resource.Change

  alias TcgCheap.Core

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &after_ingest/2)
  end

  defp after_ingest(changeset, result) do
    case persisted_by_this_ingest?(changeset, result) do
      true -> record_observation(result)
      false -> {:ok, result}
    end
  end

  defp record_observation(result) do
    case record_if_changed(result) do
      :ok -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp record_if_changed(result) do
    attrs = observation_attrs(result)

    case Core.get_latest_sealed_listing_observation(result.id) do
      {:ok, latest} -> record_when_changed(latest, attrs)
      {:error, error} -> {:error, error}
    end
  end

  defp record_when_changed(latest, attrs) do
    if changed?(latest, attrs) do
      case Core.record_sealed_listing_observation(attrs) do
        {:ok, _observation} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      :ok
    end
  end

  defp persisted_by_this_ingest?(changeset, result) do
    result.status == "active" and
      Enum.all?([:last_seen_at, :last_checked_at], fn field ->
        Ash.Changeset.get_attribute(changeset, field) == Map.get(result, field)
      end)
  end

  defp observation_attrs(result) do
    %{
      retailer_listing_id: result.id,
      source_title: result.source_title,
      normalized_title: result.normalized_title,
      direct_url: result.direct_url,
      gtin: result.gtin,
      price_pln: result.current_price_pln,
      currency: result.currency,
      stock_status: result.stock_status,
      observed_at: result.last_checked_at,
      source_payload: result.source_payload
    }
  end

  defp changed?(nil, _attrs), do: true

  defp changed?(latest, attrs) do
    latest.source_title != attrs.source_title or
      latest.normalized_title != attrs.normalized_title or
      latest.direct_url != attrs.direct_url or
      latest.gtin != attrs.gtin or
      not decimal_equal?(latest.price_pln, attrs.price_pln) or
      latest.currency != attrs.currency or
      latest.stock_status != attrs.stock_status or
      latest.source_payload != attrs.source_payload
  end

  defp decimal_equal?(nil, nil), do: true
  defp decimal_equal?(nil, _decimal), do: false
  defp decimal_equal?(_decimal, nil), do: false
  defp decimal_equal?(left, right), do: Decimal.compare(left, right) == :eq
end
