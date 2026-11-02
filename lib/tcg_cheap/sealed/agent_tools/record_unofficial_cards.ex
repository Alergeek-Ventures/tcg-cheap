defmodule TcgCheap.Sealed.AgentTools.RecordUnofficialCards do
  @moduledoc """
  Records the unofficial card list of an English set TCGdex does not list
  yet, so its booster pages show the cards from launch. Each card gets the id
  TCGdex will give it (`<set>-<number>`), and TCGdex's own cards replace the
  list once it has them. A set whose TCGdex cards are already copied is
  refused.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json

  @impl true
  def run(input, _opts, _context) do
    args = input.arguments

    with :ok <- not_on_tcgdex(args.set),
         {:ok, set} <-
           Sealed.record_unofficial_set_cards(%{
             tcgdex_id: args.set,
             name: args.name,
             cardmarket_expansion_id: args.expansion_id,
             released_on: args.released_on,
             cards_source_url: args.source_url,
             cards: Enum.map(args.cards, &Map.put(&1, :tcgdex_id, "#{args.set}-#{&1.number}"))
           }) do
      {:ok, set |> Json.tcgdex_set() |> Map.put(:cards, length(args.cards))}
    end
  end

  defp not_on_tcgdex(id) do
    if Enum.any?(
         Sealed.list_english_tcgdex_sets!(),
         &(&1.tcgdex_id == id and is_nil(&1.cards_source_url) and not is_nil(&1.cards_checked_at))
       ),
       do:
         {:error,
          InvalidArgument.exception(field: :set, message: "TCGdex's cards of this set are copied")},
       else: :ok
  end
end
