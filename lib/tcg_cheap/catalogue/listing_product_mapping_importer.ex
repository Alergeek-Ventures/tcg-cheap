defmodule TcgCheap.Catalogue.ListingProductMappingImporter do
  @moduledoc "Ensures an ingested retailer listing has one conservative mapping."

  alias TcgCheap.Catalogue.{SealedIdentifier, SealedListingMatcher}
  alias TcgCheap.Core

  @spec ensure(struct()) :: {:ok, struct(), list()} | {:error, term()}
  def ensure(listing) do
    case Core.get_listing_mapping(listing.id) do
      {:ok, nil} -> create_mapping(listing)
      {:ok, mapping} -> reconcile_mapping(listing, mapping)
      {:error, error} -> {:error, error}
    end
  end

  defp reconcile_mapping(_listing, %{status: status} = mapping)
       when status not in ["pending", "review"],
       do: {:ok, mapping, []}

  defp reconcile_mapping(listing, mapping) do
    with {:ok, aliases} <- approved_aliases(listing.gtin) do
      case SealedListingMatcher.match(listing, aliases) do
        {:review, attrs} ->
          Core.import_listing_mapping(
            Map.merge(attrs, %{retailer_listing_id: listing.id}),
            return_notifications?: true
          )

        {:matched, attrs} ->
          Core.approve_listing_mapping(
            mapping,
            Map.merge(attrs, %{expected_updated_at: mapping.updated_at}),
            authorize?: false,
            return_notifications?: true
          )
      end
    end
  end

  defp create_mapping(listing) do
    with {:ok, aliases} <- approved_aliases(listing.gtin) do
      case SealedListingMatcher.match(listing, aliases) do
        {:matched, attrs} ->
          Core.create_matched_listing_mapping(
            Map.merge(attrs, %{retailer_listing_id: listing.id}),
            return_notifications?: true
          )

        {:review, attrs} ->
          Core.create_review_listing_mapping(
            Map.merge(attrs, %{retailer_listing_id: listing.id}),
            return_notifications?: true
          )
      end
    end
  end

  defp approved_aliases(nil), do: {:ok, []}

  defp approved_aliases(gtin) do
    normalized = SealedIdentifier.normalize(:ean, gtin)
    Core.list_approved_ean_aliases(normalized, authorize?: false)
  end
end
