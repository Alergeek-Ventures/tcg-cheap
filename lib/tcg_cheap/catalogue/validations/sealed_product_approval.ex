defmodule TcgCheap.Catalogue.Validations.SealedProductApproval do
  @moduledoc "Validates the completeness and distribution requirements for approval."
  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    validate_record(%{
      name: Changeset.get_attribute(changeset, :name),
      slug: Changeset.get_attribute(changeset, :slug),
      product_type: Changeset.get_attribute(changeset, :product_type),
      release_date: Changeset.get_attribute(changeset, :release_date),
      market: Changeset.get_attribute(changeset, :market),
      language: Changeset.get_attribute(changeset, :language),
      officially_distributed: Changeset.get_attribute(changeset, :officially_distributed)
    })
  end

  def validate_record(record) do
    name = record.name
    slug = record.slug
    type = record.product_type
    release_date = record.release_date
    market = record.market
    language = record.language
    official = record.officially_distributed

    with :ok <- validate_identity(name, slug, type),
         :ok <- validate_distribution(market, language, official),
         do: validate_release(release_date)
  end

  defp validate_identity(name, slug, type) do
    if blank?(name) or blank?(slug) or blank?(type),
      do: {:error, message: "name, slug, and product type are required"},
      else: :ok
  end

  defp validate_distribution("PL", "en", true), do: :ok

  defp validate_distribution(_market, _language, _official),
    do: {:error, message: "must be officially distributed in PL/en"}

  defp validate_release(nil),
    do: {:error, field: :release_date, message: "is required for approval"}

  defp validate_release(date) do
    if Date.compare(date, Date.utc_today()) == :gt,
      do: {:error, field: :release_date, message: "cannot be in the future"},
      else: :ok
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
