defmodule TcgCheap.Catalogue.MaterialVariant do
  @moduledoc "Conservative material-variant semantics shared by importing and crosswalking."
  @record_keys ~w(type subtype stamp stamps size firstEdition wPromo jumbo preRelease foil)

  @spec descriptors(map() | list(), map() | list()) :: map()
  def descriptors(variants, detailed) do
    detailed_records = records(detailed)
    variants = if is_map(variants), do: variants, else: %{}

    %{
      first_edition:
        Map.get(variants, "firstEdition") == true or
          Enum.any?(detailed_records, &(Map.get(&1, "firstEdition") == true)),
      w_promo:
        Map.get(variants, "wPromo") == true or
          Enum.any?(detailed_records, &(Map.get(&1, "wPromo") == true)),
      stamps: detailed_records |> Enum.flat_map(&stamp_values/1) |> Enum.uniq() |> Enum.sort(),
      jumbo:
        Map.get(variants, "jumbo") == true or
          Enum.any?(detailed_records, &(Map.get(&1, "jumbo") == true)),
      pre_release:
        Map.get(variants, "preRelease") == true or
          Enum.any?(detailed_records, &(Map.get(&1, "preRelease") == true)),
      identities:
        detailed_records
        |> Enum.map(&material_identity/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()
    }
  end

  @doc "Evaluates Cardmarket-filtered details while retaining top-level variant flags."
  def cardmarket_descriptors(variants, detailed), do: descriptors(variants, detailed)

  def conflict?(%{first_edition: _} = material),
    do:
      material.first_edition or material.w_promo or material.stamps != [] or material.jumbo or
        material.pre_release or material.identities != []

  def conflict?(variant_data) when is_map(variant_data), do: conflict?(variant_data, %{})
  def conflict?(_), do: false

  def conflict?(variants, detailed) do
    material = descriptors(variants || %{}, detailed || %{})

    material.first_edition or material.w_promo or material.stamps != [] or material.jumbo or
      material.pre_release or material.identities != []
  end

  def reason(material) when is_map(material) do
    cond do
      material.first_edition -> "firstEdition variant"
      material.w_promo -> "wPromo variant"
      material.stamps != [] -> "stamped variant: " <> Enum.join(material.stamps, ",")
      material.jumbo -> "jumbo variant"
      material.pre_release -> "preRelease variant"
      material.identities != [] -> "material descriptor: " <> hd(material.identities)
      true -> nil
    end
  end

  def obvious_cardmarket_marker?(name) when is_binary(name),
    do:
      Regex.match?(
        ~r/\b(first|1st)\s*edition\b|\bpromo\b|\bstamp(?:ed)?\b|\bjumbo\b|\bpre[- ]?release\b/i,
        name
      )

  def obvious_cardmarket_marker?(_), do: false

  defp records(value) when is_list(value), do: Enum.flat_map(value, &records/1)

  defp records(%{} = value) do
    own = if Enum.any?(Map.keys(value), &(&1 in @record_keys)), do: [value], else: []
    own ++ Enum.flat_map(Map.values(value), &records/1)
  end

  defp records(_), do: []

  defp stamp_values(record) do
    [Map.get(record, "stamp"), Map.get(record, "stamps")]
    |> List.flatten()
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&String.trim/1)
  end

  defp material_identity(record) do
    values =
      %{
        "subtype" => non_default(Map.get(record, "subtype"), "unlimited"),
        "size" => non_default(Map.get(record, "size"), "standard"),
        "foil" => nonblank(Map.get(record, "foil"))
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if values == [], do: nil, else: inspect(values, pretty: false)
  end

  defp non_default(value, default) when is_binary(value) do
    value = String.trim(value)
    if value == "" or value == default, do: nil, else: value
  end

  defp non_default(_, _), do: nil

  defp nonblank(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp nonblank(_), do: nil
end
