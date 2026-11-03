defmodule TcgCheap.Sealed.AgentTools.SetPullRates do
  @moduledoc """
  Sets or clears the pull rates of an English TCGdex set, found by its
  TCGdex id or its name (case and accents ignored). Keys the pull rates do
  not know are rejected rather than dropped, and so are rarities and cards
  the copied cards of the set's expansion do not have. Rates wait until the
  cards of every English set of the expansion are copied.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.{Json, KnownKeys}
  alias TcgCheap.Sealed.Rarities

  @pull_rates ~w(cards_per_pack rates sources borrowed_from checked_on)
  @rate ~w(rarity per_pack percent card)
  @source ~w(url sample_packs data_from)
  @diacritic ~r/\p{Mn}/u

  @impl true
  def run(input, _opts, _context) do
    with :ok <-
           KnownKeys.check(
             input.params["pull_rates"] || input.params[:pull_rates],
             :pull_rates,
             @pull_rates,
             %{"rates" => @rate, "sources" => @source}
           ),
         {:ok, set} <- set(input.arguments.set),
         :ok <- matches_cards(input.arguments[:pull_rates], set),
         {:ok, set} <- Sealed.set_tcgdex_set_pull_rates(set, input.arguments[:pull_rates]) do
      {:ok, Json.tcgdex_set(set)}
    end
  end

  defp set(wanted) do
    key = normalize(wanted)

    case Enum.filter(
           Sealed.list_english_tcgdex_sets!(),
           &(&1.tcgdex_id == wanted or normalize(&1.name || "") == key)
         ) do
      [set] ->
        {:ok, set}

      [] ->
        invalid("no English TCGdex set has this id or name")

      sets ->
        invalid(
          "several English sets have this name, give one id: " <>
            Enum.map_join(sets, ", ", & &1.tcgdex_id)
        )
    end
  end

  # A rarity TCGdex uses must be one the cards of the set's expansion (the
  # sets the booster page draws its card list from) have, and a named card
  # one of that rarity, so the rates and the card list agree. Other rows
  # ("Reverse Rare", "Energy") pass. Card sync never re-checks stored rates,
  # so they are refused until all those sets' cards are copied.
  defp matches_cards(nil, _set), do: :ok

  defp matches_cards(pull_rates, set) do
    with {:ok, cards} <- cards_of_expansion(set), do: rates_match_cards(pull_rates, cards)
  end

  defp rates_match_cards(pull_rates, cards) do
    rarities = cards |> Enum.map(&label(&1.rarity)) |> Enum.uniq()
    known = Enum.map(Rarities.rarest_first(), &label/1)

    pull_rates.rates
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {rate, index} ->
      rarity = label(rate.rarity)

      cond do
        rate.card &&
            not Enum.any?(
              cards,
              &(label(&1.name) == label(rate.card) and label(&1.rarity) == rarity)
            ) ->
          invalid(
            :pull_rates,
            "rates[#{index}].card: no #{rate.rarity} card of this set is named #{rate.card}"
          )

        rarity in known and rarity not in rarities ->
          invalid(
            :pull_rates,
            "rates[#{index}].rarity: this set's cards have no #{rate.rarity}; they have " <>
              (cards
               |> Enum.map(& &1.rarity)
               |> Enum.reject(&is_nil/1)
               |> Enum.uniq()
               |> Enum.join(", "))
          )

        true ->
          nil
      end
    end)
  end

  defp cards_of_expansion(%{cardmarket_expansion_id: nil}),
    do: invalid("this set has no Cardmarket expansion, so no booster page shows its pull rates")

  defp cards_of_expansion(set) do
    sets = Sealed.list_english_sets_of_expansion!(set.cardmarket_expansion_id, load: [:cards])

    case Enum.filter(sets, &is_nil(&1.cards_checked_at)) do
      [] ->
        {:ok, Enum.flat_map(sets, & &1.cards)}

      unsynced ->
        invalid(
          "the cards of " <>
            Enum.map_join(unsynced, ", ", & &1.tcgdex_id) <>
            " are not synced yet; run the card sync first"
        )
    end
  end

  defp label(nil), do: nil
  defp label(name), do: name |> Rarities.label() |> String.downcase()

  defp normalize(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(@diacritic, "")
    |> String.downcase()
    |> String.trim()
  end

  defp invalid(message), do: invalid(:set, message)

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
