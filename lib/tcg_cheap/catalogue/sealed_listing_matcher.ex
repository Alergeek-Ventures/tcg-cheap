defmodule TcgCheap.Catalogue.SealedListingMatcher do
  @moduledoc "Conservative exact-GTIN matcher for retailer listings."
  alias TcgCheap.Catalogue.SealedIdentifier

  def match(%{gtin: gtin}, aliases) when is_binary(gtin) do
    normalized = SealedIdentifier.normalize(:ean, gtin)

    if SealedIdentifier.valid_ean?(normalized) do
      match_eligible(normalized, aliases)
    else
      review("listing GTIN is invalid", normalized)
    end
  end

  def match(_listing, _aliases),
    do: review("listing has no GTIN; name-only matching is disabled", nil)

  defp match_eligible(normalized, aliases) do
    matches =
      Enum.filter(aliases, fn alias ->
        Map.get(alias, :kind) in [:ean, "ean"] and
          Map.get(alias, :review_status) in [:approved, "approved"] and
          Map.get(alias, :normalized_value) == normalized and eligible_product?(alias)
      end)

    case matches do
      [%{sealed_product_id: product_id}] ->
        {:matched,
         %{
           confirmed_product_id: product_id,
           confidence: Decimal.new("1"),
           evidence: %{method: "exact_approved_gtin", gtin: normalized}
         }}

      [] ->
        review("no eligible approved exact GTIN alias", normalized)

      _ ->
        review("ambiguous eligible approved GTIN aliases", normalized)
    end
  end

  defp eligible_product?(alias) do
    product = Map.get(alias, :sealed_product)

    release_date = Map.get(product || %{}, :release_date)

    is_map(product) and Map.get(product, :publication_status) == "approved" and
      Map.get(product, :officially_distributed) == true and Map.get(product, :market) == "PL" and
      Map.get(product, :language) == "en" and
      is_struct(release_date, Date) and Date.compare(release_date, Date.utc_today()) != :gt
  end

  defp review(reason, gtin),
    do: {:review, %{reason: reason, evidence: %{method: "exact_approved_gtin", gtin: gtin}}}
end
