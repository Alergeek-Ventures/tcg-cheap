defmodule TcgCheap.Catalogue.Validations.MappingInvariant do
  @moduledoc "Ensures a card mapping status and its mapping fields agree."

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    status = Ash.Changeset.get_attribute(changeset, :mapping_status)
    product_id = Ash.Changeset.get_attribute(changeset, :cardmarket_product_id)
    reason = Ash.Changeset.get_attribute(changeset, :mapping_review_reason)

    valid? = valid_mapping?(status, product_id, reason)

    if valid?,
      do: :ok,
      else: {:error, field: :mapping_status, message: "has inconsistent mapping fields"}
  end

  defp valid_mapping?(status, product_id, reason) when status in ["pending", "unmatched"],
    do: is_nil(product_id) and is_nil(reason)

  defp valid_mapping?("matched", product_id, reason),
    do: is_integer(product_id) and product_id > 0 and is_nil(reason)

  defp valid_mapping?("review", product_id, reason),
    do: is_nil(product_id) and is_binary(reason) and String.trim(reason) != ""

  defp valid_mapping?(_, _, _), do: true
end
