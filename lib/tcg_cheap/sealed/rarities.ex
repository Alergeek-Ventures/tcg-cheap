defmodule TcgCheap.Sealed.Rarities do
  @moduledoc """
  Card rarities as TCGdex names them, rarest first, covering the Sword &
  Shield, Scarlet & Violet and Mega Evolution eras (with the 30th
  Celebration's own) and the older holo names.
  A set uses one era's names, so the order only has to hold within an era.
  TCGdex spells some in lower case ("Double rare"); they are compared
  ignoring case and shown as written here. Unknown rarities come last.
  """

  @rarest_first [
    "Mega Hyper Rare",
    "Black White Rare",
    "Hyper Rare",
    "Futuristic Rare",
    "RGB Rare",
    "Special Illustration Rare",
    "Mega Attack Rare",
    "Illustration Rare",
    "Secret Rare",
    "Shiny Ultra Rare",
    "Ultra Rare",
    "Double Rare",
    "ACE SPEC Rare",
    "Shiny Rare VMAX",
    "Shiny Rare V",
    "Shiny Rare",
    "Amazing Rare",
    "Radiant Rare",
    "Holo Rare VSTAR",
    "Holo Rare VMAX",
    "Holo Rare V",
    "Rare Holo LV.X",
    "Rare PRIME",
    "LEGEND",
    "Full Art Trainer",
    "Holo Rare",
    "Rare Holo",
    "Classic Collection",
    "Pikachu Rare",
    "Rare",
    "Uncommon",
    "Common"
  ]

  @ranks @rarest_first
         |> Enum.with_index()
         |> Map.new(fn {name, i} -> {String.downcase(name), i} end)
  @labels Map.new(@rarest_first, &{String.downcase(&1), &1})

  @doc "Every known rarity, rarest first."
  @spec rarest_first() :: [String.t()]
  def rarest_first, do: @rarest_first

  @doc "The sort position of a rarity: rarest first, unknown (or none) last."
  @spec rank(String.t() | nil) :: non_neg_integer()
  def rank(nil), do: map_size(@ranks)
  def rank(rarity), do: Map.get(@ranks, String.downcase(rarity), map_size(@ranks))

  @doc ~S'A rarity as shown: "Double rare" is "Double Rare"; unknown ones as given.'
  @spec label(String.t()) :: String.t()
  def label(rarity), do: Map.get(@labels, String.downcase(rarity), rarity)
end
