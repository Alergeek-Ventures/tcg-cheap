defmodule TcgCheap.Sealed.Changes.SetEans do
  @moduledoc """
  Replaces a product's EANs with the `:eans` argument, normalized to EAN-13;
  any code that is not a valid barcode rejects the whole change.
  """

  use Ash.Resource.Change

  alias TcgCheap.Sealed.Ean

  @impl true
  def change(changeset, _opts, _context) do
    codes = Ash.Changeset.get_argument(changeset, :eans) || []

    case Enum.reject(codes, &Ean.normalize/1) do
      [] ->
        eans = codes |> Enum.map(&Ean.normalize/1) |> Enum.uniq()
        Ash.Changeset.force_change_attribute(changeset, :eans, eans)

      invalid ->
        Ash.Changeset.add_error(changeset,
          field: :eans,
          message: "not valid EAN-13/UPC-A barcodes: %{codes}",
          vars: [codes: Enum.join(invalid, ", ")]
        )
    end
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
