defmodule TcgCheap.Catalogue.Normalizer do
  @moduledoc false

  def canonical_local_id(value) when is_integer(value), do: Integer.to_string(value)
  def canonical_local_id(value) when is_binary(value), do: String.trim(value)

  def asset_url(nil, _kind), do: nil
  def asset_url(value, _kind) when not is_binary(value), do: nil

  def asset_url(value, kind) do
    value = String.trim(value)

    cond do
      value == "" -> nil
      String.match?(value, ~r/\.[A-Za-z0-9]+(?:[?#].*)?$/) -> value
      kind == :card -> value <> "/high.webp"
      true -> value <> ".webp"
    end
  end

  def set_attributes(set, synced_at) do
    counts = Map.get(set, "cardCount", %{})
    legalities = Map.get(set, "legal", %{})

    %{
      tcgdex_id: trim(Map.get(set, "id")),
      name: trim(Map.get(set, "name")),
      series_id: trim(get_in(set, ["serie", "id"]) || get_in(set, ["series", "id"])),
      series_name: trim(get_in(set, ["serie", "name"]) || get_in(set, ["series", "name"])),
      release_date: parse_date(Map.get(set, "releaseDate")),
      logo_url: asset_url(Map.get(set, "logo"), :set),
      symbol_url: asset_url(Map.get(set, "symbol"), :set),
      official_count: nonnegative_int(Map.get(counts, "official")),
      total_count: nonnegative_int(Map.get(counts, "total")),
      standard_legal: legal?(legalities, "standard"),
      expanded_legal: legal?(legalities, "expanded"),
      source_payload: set,
      last_synced_at: synced_at
    }
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_), do: nil
  defp nonnegative_int(value) when is_integer(value) and value >= 0, do: value
  defp nonnegative_int(_), do: nil

  defp legal?(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp legal?(_, _), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil
end
