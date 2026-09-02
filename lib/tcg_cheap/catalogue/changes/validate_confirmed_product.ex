defmodule TcgCheap.Catalogue.Changes.ValidateConfirmedProduct do
  @moduledoc "Locks and verifies a mapping target's original publication eligibility.

  This intentionally does not require factual completeness or an image. Those
  are public-read concerns, and applying them here would prevent a retailer
  image from completing an otherwise valid approved product.
  "
  use Ash.Resource.Change
  import Ash.Expr
  require Ash.Query

  @impl true
  def init(opts) do
    if opts == [], do: {:ok, opts}, else: {:error, "no options are supported"}
  end

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      product_id = Ash.Changeset.get_attribute(changeset, :confirmed_product_id)

      query = validation_query(product_id)

      case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
        {:ok, nil} ->
          Ash.Changeset.add_error(changeset,
            field: :confirmed_product_id,
            message: "must be an approved, released, officially distributed PL/en product"
          )

        {:ok, _product} ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, message: Exception.message(error))
      end
    end)
  end

  defp validation_query(product_id) do
    TcgCheap.Catalogue.SealedProduct
    |> Ash.Query.filter(
      expr(
        id == ^product_id and publication_status == "approved" and
          release_date <= today() and officially_distributed == true and
          market == "PL" and language == "en" and
          distribution_status in ["current", "discontinued"]
      )
    )
    |> Ash.Query.lock(:for_update)
  end
end
