defmodule TcgCheap.Sealed.Kinds do
  @moduledoc """
  The small fixed set of product kinds, their Polish labels, and how
  Cardmarket's sealed categories map onto them.

  Cardmarket "Pokémon Coins" (1017) and "Pokémon Lot" (1064) are not
  products a buyer compares between shops and are left out.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  @kinds [
    booster: "Booster",
    booster_bundle: "Booster Bundle",
    booster_box: "Booster Box",
    elite_trainer_box: "Elite Trainer Box",
    blister: "Blister",
    collection: "Kolekcja",
    tin: "Puszka",
    deck: "Talia",
    card_set: "Zestaw kart",
    case: "Karton zbiorczy"
  ]

  # What a buyer picks first: a handful of shelves, each one or more kinds
  # (owner decision, 2026-11-04). The list filter takes a shelf or an exact kind.
  @shelves [
    boosters: [:booster, :booster_bundle, :blister],
    boxes: [:booster_box, :case],
    elite_trainer_box: [:elite_trainer_box],
    collections: [:collection, :tin],
    decks: [:deck, :card_set]
  ]

  @booster 52
  @display 53
  @theme_deck 54
  @trainer_kit 1013
  @tin 1014
  @box_set 1015
  @coins 1017
  @elite_trainer_box 1016
  @lot 1064
  @blister 1083
  @card_set 1654

  @excluded_categories [@coins, @lot]
  @non_word ~r/[^a-z0-9]+/u

  @spec all() :: [atom()]
  def all, do: Keyword.keys(@kinds)

  @doc "The shelves in the order the list offers them."
  @spec shelves() :: [atom()]
  def shelves, do: Keyword.keys(@shelves)

  @doc "Every value the list's kind filter takes: a shelf or an exact kind."
  @spec choices() :: [atom()]
  def choices, do: Enum.uniq(shelves() ++ all())

  @doc "The kinds a shelf holds, or the kind itself."
  @spec members(atom()) :: [atom()]
  def members(choice), do: Keyword.get(@shelves, choice, [choice])

  @doc "The shelf a kind stands on."
  @spec shelf(atom()) :: atom()
  def shelf(kind), do: Enum.find_value(@shelves, fn {shelf, kinds} -> kind in kinds && shelf end)

  @spec label(atom()) :: String.t()
  def label(:boosters), do: gettext("Boostery")
  def label(:boxes), do: gettext("Booster Boxy")
  def label(:collections), do: gettext("Kolekcje i puszki")
  def label(:decks), do: gettext("Talie")
  def label(kind), do: translate_label(Keyword.fetch!(@kinds, kind))

  @spec labels() :: keyword(String.t())
  def labels, do: Enum.map(@kinds, fn {key, label} -> {key, translate_label(label)} end)

  defp translate_label("Booster"), do: gettext("Booster")
  defp translate_label("Booster Bundle"), do: gettext("Booster Bundle")
  defp translate_label("Booster Box"), do: gettext("Booster Box")
  defp translate_label("Elite Trainer Box"), do: gettext("Elite Trainer Box")
  defp translate_label("Blister"), do: gettext("Blister")
  defp translate_label("Kolekcja"), do: gettext("Kolekcja")
  defp translate_label("Puszka"), do: gettext("Puszka")
  defp translate_label("Talia"), do: gettext("Talia")
  defp translate_label("Zestaw kart"), do: gettext("Zestaw kart")
  defp translate_label("Karton zbiorczy"), do: gettext("Karton zbiorczy")

  @doc "Whether a Cardmarket category belongs in the buying guide."
  @spec included_category?(integer()) :: boolean()
  def included_category?(category_id), do: category_id not in @excluded_categories

  @doc """
  The kind of a Cardmarket product. Multi-unit cases and displays of tins or
  blisters become `:case`, whatever their category; a "Display Set" or a
  "… Display Gift Box" is one box with a stand that shows a card off, not a
  display of many.
  """
  @spec from_cardmarket(integer(), String.t()) :: atom()
  def from_cardmarket(category_id, name) do
    words = name |> String.downcase() |> String.split(@non_word, trim: true)

    cond do
      "case" in words -> :case
      category_id != @display and display_of_units?(words) -> :case
      true -> category_kind(category_id, words)
    end
  end

  defp display_of_units?(words) do
    pairs = Enum.chunk_every(words, 2, 1)
    "display" in words and ["display", "set"] not in pairs and ["gift", "box"] not in pairs
  end

  defp category_kind(@booster, _words), do: :booster

  defp category_kind(@display, words),
    do: if("bundle" in words, do: :booster_bundle, else: :booster_box)

  defp category_kind(@elite_trainer_box, _words), do: :elite_trainer_box
  defp category_kind(@blister, _words), do: :blister
  defp category_kind(@tin, _words), do: :tin
  defp category_kind(@theme_deck, _words), do: :deck
  defp category_kind(@trainer_kit, _words), do: :deck
  defp category_kind(@card_set, _words), do: :card_set
  defp category_kind(@box_set, _words), do: :collection
  defp category_kind(_other, _words), do: :collection
end
