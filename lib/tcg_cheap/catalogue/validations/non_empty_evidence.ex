defmodule TcgCheap.Catalogue.Validations.NonEmptyEvidence do
  @moduledoc "Validates that mapping evidence contains at least one entry."

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :evidence) do
      value when is_map(value) and map_size(value) > 0 -> :ok
      _ -> {:error, field: :evidence, message: "must contain evidence"}
    end
  end
end
