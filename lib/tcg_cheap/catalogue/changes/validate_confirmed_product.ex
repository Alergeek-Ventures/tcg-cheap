defmodule TcgCheap.Catalogue.Changes.ValidateConfirmedProduct do
  @moduledoc "Locks and verifies that a mapping target is currently public and released."
  use Ash.Resource.Change

  @impl true
  def init(opts) do
    if opts == [], do: {:ok, opts}, else: {:error, "no options are supported"}
  end

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      product_id = Ash.Changeset.get_attribute(changeset, :confirmed_product_id)

      query =
        TcgCheap.Catalogue.SealedProduct
        |> Ash.Query.for_read(:public_by_id, %{id: product_id})
        |> Ash.Query.lock(:for_update)

      case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
        {:ok, nil} ->
          Ash.Changeset.add_error(changeset,
            field: :confirmed_product_id,
            message: "must be an approved released public product"
          )

        {:ok, _product} ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, message: Exception.message(error))
      end
    end)
  end
end
