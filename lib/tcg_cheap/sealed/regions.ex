defmodule TcgCheap.Sealed.Regions do
  @moduledoc """
  The language edition of a product, decided per Cardmarket expansion (every
  product of an expansion shares it), except for the few products Cardmarket
  files with another edition's (`for_product/2`).

  Cardmarket publishes no languages. In order:

    1. The product names, when at least a third of them say it: a language
       word ("JP", "Japanese", "Chinese", "ID/TH", …) or a Chinese set code
       such as "CBB3C:" or "CSVH1aC:". A third, not one: an English
       expansion may hold a single "JP Raging Bolt" deck. Names come first
       because TCGdex sometimes points a Japanese set at a Chinese expansion.
    2. TCGdex: an expansion holding the cards of a Japanese TCGdex set is
       Japanese, of an English one English (`TcgCheap.Sealed.TcgdexSet`).
       Asian editions other than Japanese point at the Japanese expansions
       there, so only English and Japanese sets are read.
    3. A few sealed-only Asian expansions TCGdex does not know, listed here.
    4. Otherwise English, the international edition sold in Poland.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  @regions [
    en: "Angielska",
    ja: "Japońska",
    zh: "Chińska",
    ko: "Koreańska",
    id: "Indonezyjska",
    th: "Tajska"
  ]

  # Sealed-only expansions without TCGdex data, checked by hand on 2026-11-01.
  @known %{
    # Eevee Heroes, Heat Wave Arena
    4239 => :ja,
    6037 => :ja,
    # Starter Set ex, MEGA Starter Sets
    6016 => :ja,
    6017 => :ja,
    6259 => :ja,
    6260 => :ja,
    6637 => :ja,
    6638 => :ja,
    6639 => :ja,
    # Gem Pack badges and the Mid-Autumn gift box
    5838 => :zh,
    # Checked against Polish shop listings ("CHI", "CHINA", "Chiński") or the
    # "CSM2.1C:" code on 2026-11-04: Eevee Evolution Advanced Gift Boxes, Card
    # Display Set Gift Boxes (Eevee, Charizard), Pikachu Legendary Celebration,
    # Golden Energy.
    6401 => :zh,
    6356 => :zh,
    6357 => :zh,
    6348 => :zh,
    6548 => :zh
  }

  # Products of another edition than their expansion's, by Cardmarket product
  # id, checked against Polish shop listings ("Japoński", "JPN") on 2026-11-04.
  @known_products %{
    # Ninja Spinner (M4) Booster, Booster Box and Booster Box Case, filed with
    # Traditional Chinese value sets
    873_179 => :ja,
    873_182 => :ja,
    873_183 => :ja,
    # Terastal Festival ex (sv8a) Booster, Booster Box and Booster Box Case:
    # Cardmarket lists Japanese and Korean copies as one product, in an
    # expansion whose two Korean accessories make it Korean; Polish shops sell
    # the Japanese edition. Checked on 2026-11-07.
    794_933 => :ja,
    794_934 => :ja,
    800_365 => :ja,
    # Pokémon Center Tohoku, Hiroshima and Fukuoka Special Boxes, filed with the
    # English Scarlet & Violet products
    830_070 => :ja,
    830_071 => :ja,
    830_072 => :ja
  }

  @words [
    {~w(jp japanese), :ja},
    {~w(chinese), :zh},
    {~w(korean), :ko},
    {~w(indonesian), :id},
    {~w(thai), :th}
  ]

  @chinese_code ~r/\A([A-Za-z0-9.]*\d[A-Za-z0-9.]*C):\s*(.*)\z/s
  @non_letter ~r/[^a-z]+/

  @spec all() :: [atom()]
  def all, do: Keyword.keys(@regions)

  @spec label(atom()) :: String.t()
  def label(region), do: translate_label(Keyword.fetch!(@regions, region))

  @spec labels() :: keyword(String.t())
  def labels, do: Enum.map(@regions, fn {key, label} -> {key, translate_label(label)} end)

  defp translate_label("Angielska"), do: gettext("Angielska")
  defp translate_label("Japońska"), do: gettext("Japońska")
  defp translate_label("Chińska"), do: gettext("Chińska")
  defp translate_label("Koreańska"), do: gettext("Koreańska")
  defp translate_label("Indonezyjska"), do: gettext("Indonezyjska")
  defp translate_label("Tajska"), do: gettext("Tajska")

  @doc ~S'A short tag for the edition: "JP", "CN", …'
  @spec tag(atom()) :: String.t()
  def tag(:ja), do: "JP"
  def tag(:zh), do: "CN"
  def tag(region), do: region |> Atom.to_string() |> String.upcase()

  @doc """
  The region of every expansion, given the product names per expansion and
  the TCGdex languages found for expansions (`%{expansion_id => "ja"}`).
  """
  @spec by_expansion(%{integer() => [String.t()]}, %{integer() => String.t()}) ::
          %{integer() => atom()}
  def by_expansion(names, tcgdex) do
    Map.new(names, fn {expansion, names} ->
      region =
        from_names(names) || from_tcgdex(Map.get(tcgdex, expansion)) ||
          Map.get(@known, expansion, :en)

      {expansion, region}
    end)
  end

  @doc ~S"""
  Splits a leading Chinese set code off a product name:
  "CBB3C: Gem Pack Vol. 3 Booster" → `{"CBB3C", "Gem Pack Vol. 3 Booster"}`;
  nil for a name without one.
  """
  @spec chinese_code(String.t()) :: {String.t(), String.t()} | nil
  def chinese_code(name) do
    case Regex.run(@chinese_code, name, capture: :all_but_first) do
      [code, rest] -> {code, rest}
      nil -> nil
    end
  end

  @doc "The region of a product, given its Cardmarket id and its expansion's region."
  @spec for_product(integer(), atom()) :: atom()
  def for_product(cardmarket_id, expansion_region),
    do: Map.get(@known_products, cardmarket_id, expansion_region)

  defp from_names(names) do
    case names |> Enum.map(&from_name/1) |> Enum.reject(&is_nil/1) |> Enum.frequencies() do
      counts when map_size(counts) == 0 ->
        nil

      counts ->
        {region, count} = Enum.max_by(counts, &elem(&1, 1))
        if count * 3 >= length(names), do: region
    end
  end

  defp from_tcgdex("ja"), do: :ja
  defp from_tcgdex("en"), do: :en
  defp from_tcgdex(_language), do: nil

  defp from_name(name) do
    words = name |> String.downcase() |> String.split(@non_letter, trim: true)

    cond do
      chinese_code(name) -> :zh
      String.contains?(name, "ID/TH") -> :id
      true -> Enum.find_value(@words, &from_words(&1, words))
    end
  end

  defp from_words({tags, region}, words), do: Enum.any?(tags, &(&1 in words)) && region
end
