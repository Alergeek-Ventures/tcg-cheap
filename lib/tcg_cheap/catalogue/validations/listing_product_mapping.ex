defmodule TcgCheap.Catalogue.Validations.ListingProductMapping do
  @moduledoc "Validates the persisted mapping state matrix, including finite Decimal confidence."
  use Ash.Resource.Validation

  @impl true
  def init(opts) when is_list(opts) do
    if Keyword.get(opts, :state) in [:pending, :review, :matched, :rejected],
      do: {:ok, opts},
      else: {:error, "state must be pending, review, matched, or rejected"}
  end

  def init(_), do: {:error, "state must be pending, review, matched, or rejected"}

  @impl true
  # This is intentionally a visible state matrix: each branch mirrors a database invariant.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, opts, _context) do
    state = opts[:state]
    candidate = Ash.Changeset.get_attribute(changeset, :candidate_product_id)
    confirmed = Ash.Changeset.get_attribute(changeset, :confirmed_product_id)
    confidence = Ash.Changeset.get_attribute(changeset, :confidence)
    evidence = Ash.Changeset.get_attribute(changeset, :evidence)
    reason = Ash.Changeset.get_attribute(changeset, :reason)

    valid? =
      case state do
        :pending ->
          is_nil(candidate) and is_nil(confirmed) and is_nil(confidence) and is_nil(evidence) and
            is_nil(reason)

        :matched ->
          is_nil(candidate) and is_binary(confirmed) and valid_confidence?(confidence) and
            is_map(evidence) and map_size(evidence) > 0 and is_nil(reason)

        :review ->
          is_nil(confirmed) and nonblank?(reason) and optional_confidence?(confidence)

        :rejected ->
          is_nil(candidate) and is_nil(confirmed) and is_nil(confidence) and is_nil(evidence) and
            nonblank?(reason)
      end

    if valid?, do: :ok, else: {:error, field: :status, message: "has inconsistent mapping fields"}
  end

  defp optional_confidence?(nil), do: true
  defp optional_confidence?(value), do: valid_confidence?(value)

  defp valid_confidence?(%Decimal{coef: coef} = value) when is_integer(coef) do
    Decimal.compare(value, Decimal.new(0)) == :gt and
      Decimal.compare(value, Decimal.new(1)) != :gt
  end

  defp valid_confidence?(_), do: false
  defp nonblank?(value), do: is_binary(value) and String.trim(value) != ""
end
