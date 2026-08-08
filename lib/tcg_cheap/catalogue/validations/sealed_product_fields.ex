defmodule TcgCheap.Catalogue.Validations.SealedProductFields do
  @moduledoc "Validates the paired optional MSRP amount and provenance source."
  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    validate_values(
      Changeset.get_attribute(changeset, :msrp_pln),
      Changeset.get_attribute(changeset, :msrp_source)
    )
  end

  def validate_values(amount, source) do
    cond do
      is_nil(amount) and is_nil(source) ->
        :ok

      valid_amount?(amount) and is_binary(source) and String.trim(source) != "" ->
        :ok

      not is_nil(amount) and not valid_amount?(amount) ->
        {:error, field: :msrp_pln, message: "must be a finite positive amount"}

      true ->
        {:error,
         field: :msrp_source,
         message: "is required when MSRP is present and cannot exist without MSRP"}
    end
  end

  defp valid_amount?(%Decimal{} = amount) do
    not Decimal.nan?(amount) and not Decimal.inf?(amount) and
      Decimal.compare(amount, Decimal.new(0)) == :gt
  end

  defp valid_amount?(_), do: false
end
