defmodule TcgCheap.Catalogue.Validations.SourceIdentity do
  @moduledoc "Validates optional source provenance pairs and required imported identities."
  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    source = Changeset.get_attribute(changeset, :source)
    source_id = Changeset.get_attribute(changeset, :source_id)
    required? = opts[:required?] == true

    validate_pair(source, source_id, required?)
  end

  defp validate_pair(source, _source_id, true) when is_nil(source),
    do: {:error, field: :source, message: "is required for imports"}

  defp validate_pair(_source, source_id, true) when is_nil(source_id),
    do: {:error, field: :source_id, message: "is required for imports"}

  defp validate_pair(nil, nil, false), do: :ok

  defp validate_pair(source, source_id, _required) do
    if blank?(source) or blank?(source_id),
      do: {:error, message: "source and source_id must be provided together"},
      else: :ok
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
