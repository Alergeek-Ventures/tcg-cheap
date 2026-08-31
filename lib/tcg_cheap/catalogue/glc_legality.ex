defmodule TcgCheap.Catalogue.GlcLegality do
  @moduledoc """
  Local Gym Leader Challenge eligibility policy for exact card printings.

  This policy is based on the official community ban list at
  https://gymleaderchallenge.com/ban-list, effective 2026-04-20 through
  Dimension Valley. Policy version: `glc_local_2026-04-20`.

  A Trainer, or a Pokémon that is not a rule-box Pokémon, is eligible when its
  exact printing is not banned. Other card categories are not eligible. This
  is a conservative local policy: it uses only persisted card identity fields
  and does not claim to replace the community rules or future ban-list review.
  """

  @policy_version "glc_local_2026-04-20"

  # Exact TCGdex printings and the all-printings Double Colorless Energy group
  # from the current GLC community ban list. IDs are grouped by source entry:
  # Lysandre's Trump Card (xy4-99, xy4-118), Oranguru (sm5-114), Forest of
  # Giant Plants (xy7-74), Chip-Chip Ice Axe (sm10-165), Hiker (sm7-133,
  # sma-SV85), Kyogre (swsh4.5-21), Pokémon Research Lab (sm11-205), Raikou
  # (swsh4-50), Marshadow (sm3.5-45, smp-SM85), Duskull (sm12-83), Twin Energy
  # (swsh2-174, swsh2-209), and Dimension Valley (xy4-93).
  @banned_tcgdex_ids MapSet.new([
                       "xy4-99",
                       "xy4-118",
                       "sm5-114",
                       "xy7-74",
                       "sm10-165",
                       "sm7-133",
                       "sma-SV85",
                       "swsh4.5-21",
                       "sm11-205",
                       "swsh4-50",
                       "sm3.5-45",
                       "smp-SM85",
                       "sm12-83",
                       "swsh2-174",
                       "swsh2-209",
                       "xy4-93"
                     ])

  @doc "Returns whether the persisted card is eligible for Gym Leader Challenge."
  @spec legal?(map() | struct()) :: boolean()
  def legal?(%{category: "Trainer"} = card), do: not banned?(card)

  def legal?(%{category: "Pokemon", name: name} = card) when is_binary(name),
    do: not rule_box_pokemon?(name) and not banned?(card)

  def legal?(_card), do: false

  @doc "Returns the version of the local Gym Leader Challenge policy."
  @spec policy_version() :: String.t()
  def policy_version, do: @policy_version

  defp banned?(%{name: "Double Colorless Energy"}), do: true

  defp banned?(%{tcgdex_id: id}), do: MapSet.member?(@banned_tcgdex_ids, id)
  defp banned?(_), do: false

  # Rule-box suffixes are tokens, not arbitrary substrings (for example,
  # "Vileplume" and "Gengar" must remain ordinary Pokémon names).
  defp rule_box_pokemon?(name) do
    normalized = String.trim(name)

    String.starts_with?(String.downcase(normalized), "radiant ") or
      String.contains?(normalized, "◇") or
      Regex.match?(~r/(?:^|[\s-])(?:ex|gx|vmax|vstar|v-union|v|break)$/iu, normalized)
  end
end
