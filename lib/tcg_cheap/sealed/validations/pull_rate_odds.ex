defmodule TcgCheap.Sealed.Validations.PullRateOdds do
  @moduledoc """
  A pull rate's `per_pack` names a possible chance: one in at least one
  pack, at least one card per pack, or at least one hit in no more packs
  than were opened, at a percent above 0 and at most 100.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias TcgCheap.Sealed.PullRates.Rate

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :per_pack) do
      nil -> :ok
      per_pack -> per_pack |> Rate.odds() |> check()
    end
  end

  # A `per_pack` with none of the forms fails its own match constraint.
  defp check(nil), do: :ok

  defp check({:one_in, packs, _about?}),
    do: at_least_one(packs, "must be 1 in at least 1 pack")

  defp check({:per_pack, cards}), do: at_least_one(cards, "must be at least 1 per pack")

  defp check({:hits, percent, hits, packs}) do
    if Decimal.gt?(percent, 0) and not Decimal.gt?(percent, 100) and
         not Decimal.lt?(hits, 1) and not Decimal.gt?(hits, packs),
       do: :ok,
       else: error("must have a percent above 0 and at most 100, and 1 to all packs as hits")
  end

  defp at_least_one(number, message),
    do: if(Decimal.lt?(Decimal.new(number), 1), do: error(message), else: :ok)

  # An exception, as a keyword error turns unknown inside a nested embed.
  defp error(message),
    do: {:error, InvalidAttribute.exception(field: :per_pack, message: message)}
end
