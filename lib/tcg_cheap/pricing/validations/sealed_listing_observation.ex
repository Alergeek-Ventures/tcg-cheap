defmodule TcgCheap.Pricing.Validations.SealedListingObservation do
  @moduledoc "Validates sealed listing observation persistence invariants."
  use Ash.Resource.Validation

  alias TcgCheap.Catalogue.{SealedIdentifier, SearchText}

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, _opts, _context) do
    title = Ash.Changeset.get_attribute(changeset, :source_title)
    normalized_title = Ash.Changeset.get_attribute(changeset, :normalized_title)
    url = Ash.Changeset.get_attribute(changeset, :direct_url)
    gtin = Ash.Changeset.get_attribute(changeset, :gtin)
    status = Ash.Changeset.get_attribute(changeset, :stock_status)
    price = Ash.Changeset.get_attribute(changeset, :price_pln)
    observed_at = Ash.Changeset.get_attribute(changeset, :observed_at)

    cond do
      not is_binary(title) or String.trim(title) == "" ->
        {:error, field: :source_title, message: "must not be blank"}

      title != String.trim(title) ->
        {:error, field: :source_title, message: "must be trimmed"}

      not is_binary(normalized_title) or String.trim(normalized_title) == "" ->
        {:error, field: :normalized_title, message: "must not be blank"}

      normalized_title != SearchText.normalize(title) ->
        {:error, field: :normalized_title, message: "does not match source title"}

      not https_url?(url) ->
        {:error, field: :direct_url, message: "must be HTTPS with a host"}

      not is_nil(gtin) and not SealedIdentifier.valid_ean?(gtin) ->
        {:error, field: :gtin, message: "must be a valid GTIN"}

      not is_nil(price) and not positive_decimal?(price) ->
        {:error, field: :price_pln, message: "must be finite and positive"}

      status == "in_stock" and (is_nil(price) or not positive_decimal?(price)) ->
        {:error, field: :price_pln, message: "is required for in-stock observations"}

      not is_struct(observed_at, DateTime) ->
        {:error, field: :observed_at, message: "is required"}

      true ->
        :ok
    end
  end

  defp https_url?(value) when is_binary(value) do
    uri = URI.parse(String.trim(value))
    uri.scheme == "https" and is_binary(uri.host) and String.trim(uri.host) != ""
  end

  defp https_url?(_), do: false

  defp positive_decimal?(%Decimal{coef: coef} = value) when is_integer(coef),
    do: Decimal.compare(value, Decimal.new(0)) == :gt

  defp positive_decimal?(_), do: false
end
