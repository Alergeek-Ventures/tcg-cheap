defmodule TcgCheap.Catalogue.Validations.RetailerListing do
  @moduledoc "Validates normalized retailer listing projections and observation times."
  use Ash.Resource.Validation
  alias TcgCheap.Catalogue.SealedIdentifier
  @impl true
  # The validation deliberately enumerates independent persistence invariants.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, _opts, _context) do
    title = Ash.Changeset.get_attribute(changeset, :source_title)
    source_listing_id = Ash.Changeset.get_attribute(changeset, :source_listing_id)
    url = Ash.Changeset.get_attribute(changeset, :direct_url)
    gtin = Ash.Changeset.get_attribute(changeset, :gtin)
    status = Ash.Changeset.get_attribute(changeset, :stock_status)
    price = Ash.Changeset.get_attribute(changeset, :current_price_pln)
    first = Ash.Changeset.get_attribute(changeset, :first_seen_at)
    last = Ash.Changeset.get_attribute(changeset, :last_seen_at)
    checked = Ash.Changeset.get_attribute(changeset, :last_checked_at)

    cond do
      not is_binary(source_listing_id) or String.trim(source_listing_id) == "" ->
        {:error, field: :source_listing_id, message: "must not be blank"}

      not is_binary(title) or String.trim(title) == "" ->
        {:error, field: :source_title, message: "must not be blank"}

      not https_url?(url) ->
        {:error, field: :direct_url, message: "must be HTTPS with a host"}

      not is_nil(gtin) and not SealedIdentifier.valid_ean?(gtin) ->
        {:error, field: :gtin, message: "must be a valid GTIN"}

      status not in ~w(in_stock sold_out unknown) ->
        {:error, field: :stock_status, message: "is invalid"}

      not is_nil(price) and not positive_decimal?(price) ->
        {:error, field: :current_price_pln, message: "must be finite and positive"}

      status == "in_stock" and (is_nil(price) or not positive_decimal?(price)) ->
        {:error, field: :current_price_pln, message: "is required for in-stock listings"}

      not (is_struct(first, DateTime) and is_struct(last, DateTime) and
               is_struct(checked, DateTime)) ->
        {:error, field: :last_checked_at, message: "timestamps are required"}

      DateTime.compare(first, last) == :gt or DateTime.compare(last, checked) == :gt ->
        {:error, field: :last_checked_at, message: "timestamps must be ordered"}

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
