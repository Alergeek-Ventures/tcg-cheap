defmodule TcgCheap.Catalogue.Validations.SealedIdentifier do
  @moduledoc "Validates normalized name aliases and GS1 EAN/GTIN identifiers."
  use Ash.Resource.Validation

  alias Ash.Changeset
  alias TcgCheap.Catalogue.SealedIdentifier

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Changeset.get_attribute(changeset, :kind)
    value = Changeset.get_attribute(changeset, :normalized_value)

    cond do
      kind == "name" and is_binary(value) and byte_size(value) > 0 -> :ok
      kind == "ean" and SealedIdentifier.valid_ean?(value) -> :ok
      kind == "ean" -> {:error, field: :original_value, message: "must be a valid EAN/GTIN"}
      true -> {:error, field: :normalized_value, message: "must not be blank"}
    end
  end
end
