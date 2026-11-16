defmodule TcgCheap.Cards.SetCards do
  @moduledoc """
  An expansion's English cards by rarity with its set's pull rates, as the
  product page of a single booster, the odds of a box and the expansion's
  page show them.
  """

  alias TcgCheap.Cards
  alias TcgCheap.Cards.{Guide, Rarities, Set, SinglesBanner}
  alias TcgCheap.Cards.PullRates.Rate
  alias TcgCheap.Sealed.ExpansionLogo

  @card_number ~r/\A(\D*)(\d+)(.*)\z/

  @doc """
  The expansion's pull rates and cards by rarity (`pull_rates` and `rarities`,
  see `odds/1`), with the cards per standard pack, its logo and the day the
  newest card price is from.
  """
  @spec read(integer() | nil) :: map()
  def read(id) do
    {pull_rates, set} = id |> sets_with_cards() |> read_sets()

    Map.merge(set, %{
      standard_pack_size: pull_rates && pull_rates.cards_per_pack,
      logo_url: id && Map.get(ExpansionLogo.mirrored_urls(), id)
    })
  end

  @doc """
  The expansion's pull rates (nil when none are known), its cards by rarity
  with their prices, the page the cards were listed on and the day the
  newest price is from.
  """
  @spec odds(integer() | nil) :: map()
  def odds(id) do
    {_pull_rates, set} = id |> sets_with_cards() |> read_sets()
    set
  end

  @doc """
  The expansion's set as the expansion page shows it, with the card count,
  the most valuable cards (`top_cards`, with the packs and the booster's
  price to pull one) and the singles banner, `nil` when we have neither pull
  rates nor cards. `booster` is the expansion's single booster summary or nil.
  """
  @spec with_singles(map(), map() | nil) :: map() | nil
  def with_singles(set, booster) do
    cards = Enum.flat_map(set.rarities, & &1.cards)

    top_cards =
      cards
      |> Enum.filter(&Guide.price/1)
      |> Enum.sort_by(&Guide.price/1, {:desc, Decimal})
      |> Enum.take(4)

    deal = SinglesBanner.best_deal(cards)
    images = Guide.images(Enum.uniq_by(List.wrap(deal) ++ top_cards, & &1.id))

    top_cards =
      Enum.map(top_cards, fn card ->
        packs = packs(card, set)
        cheapest = booster && !booster.preorder? && booster.verdict.cheapest

        %{
          card: card,
          price: Guide.price(card),
          source: Guide.price_source(card),
          image: Map.fetch!(images, card.id),
          path: card.public_path,
          packs: packs,
          cost: if(packs && cheapest, do: Decimal.mult(cheapest.price, packs))
        }
      end)

    set =
      Map.merge(set, %{
        card_count: length(cards),
        top_cards: top_cards,
        singles: SinglesBanner.of_set(cards, deal, images)
      })

    if set.pull_rates || cards != [], do: set
  end

  @doc "Average packs for this printing, using only the set's own observed rates."
  @spec packs(map(), map()) :: pos_integer() | nil
  def packs(%{rarity: nil}, _set), do: nil
  def packs(_card, %{pull_rates: nil}), do: nil

  def packs(_card, %{pull_rates: %{borrowed_from: borrowed}}) when not is_nil(borrowed),
    do: nil

  def packs(card, set) do
    # Rates name rarities and cards ignoring case, as `set_pull_rates` checks
    # them; each rate already points at its rarity's group in the card list.
    rarity = card.rarity |> Rarities.label() |> String.downcase()
    group = Enum.find_index(set.rarities, &(&1.rarity && String.downcase(&1.rarity) == rarity))
    name = String.downcase(card.name)
    rows = if group, do: Enum.filter(set.pull_rates.rates, &(&1.group == group)), else: []

    row =
      Enum.find(rows, &(&1.rate.card && String.downcase(&1.rate.card) == name)) ||
        Enum.find(rows, &is_nil(&1.rate.card))

    if row do
      count = if row.rate.card, do: 1, else: length(Enum.at(set.rarities, group).cards)

      Decimal.new(100)
      |> Decimal.div(Rate.percent(row.rate))
      |> Decimal.mult(count)
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> max(1)
    end
  end

  defp read_sets(sets) do
    pull_rates = set_pull_rates(sets)
    cards = sets |> Enum.flat_map(& &1.cards) |> Guide.enrich(sets)
    rarities = by_rarity(cards)

    {pull_rates,
     %{
       pull_rates: pull_rates(pull_rates, rarities),
       rarities: rarities,
       cards_source_url: Enum.find_value(sets, & &1.cards_source_url),
       priced_on: priced_on(cards)
     }}
  end

  # An expansion's English sets, a set and its gallery subsets, with their cards.
  defp sets_with_cards(nil), do: []

  defp sets_with_cards(expansion_id),
    do: Cards.list_english_sets_of_expansion!(expansion_id, load: [cards: :cardmarket_price])

  # The main set's pull rates, else a subset's.
  defp set_pull_rates(sets) do
    main = Set.by_expansion(sets) |> Map.values() |> List.first()
    Enum.find_value([main | sets], &(&1 && &1.pull_rates))
  end

  defp priced_on(cards) do
    cards
    |> Enum.map(&(&1.cardmarket_price && &1.cardmarket_price.priced_on))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(Date, fn -> nil end)
  end

  defp pull_rates(nil, _rarities), do: nil

  # Each rate with its rarity as the card list spells it and the index of
  # that list's group, if any (`set_pull_rates` checks the two agree).
  defp pull_rates(pull_rates, rarities) do
    groups =
      rarities
      |> Enum.with_index()
      |> Map.new(fn {group, index} -> {group.rarity && String.downcase(group.rarity), index} end)

    rates =
      pull_rates.rates
      |> Enum.sort_by(&Rate.percent/1, Decimal)
      |> Enum.map(fn rate ->
        rarity = Rarities.label(rate.rarity)
        %{rate: rate, rarity: rarity, group: groups[String.downcase(rarity)]}
      end)

    %{
      rates: rates,
      sources: pull_rates.sources,
      borrowed_from: pull_rates.borrowed_from,
      checked_on: pull_rates.checked_on
    }
  end

  defp by_rarity(cards) do
    cards
    |> Enum.group_by(&(&1.rarity && Rarities.label(&1.rarity)))
    |> Enum.sort_by(fn {rarity, _cards} -> {Rarities.rank(rarity), rarity || ""} end)
    |> Enum.map(fn {rarity, cards} ->
      %{rarity: rarity, cards: Enum.sort_by(cards, &number_order(&1.number))}
    end)
  end

  # "TG05" after "TG04", "010" after "9": a letter prefix, then the number.
  defp number_order(number) do
    case Regex.run(@card_number, number) do
      [_, prefix, digits, rest] -> {prefix, String.to_integer(digits), rest}
      nil -> {number, 0, ""}
    end
  end
end
