defmodule TcgCheap.Sealed.Regions do
  @moduledoc """
  The language edition of a product, decided per Cardmarket expansion (every
  product of an expansion shares it).

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
    5838 => :zh
  }

  @words [
    {~w(jp japanese), :ja},
    {~w(chinese), :zh},
    {~w(korean), :ko},
    {~w(indonesian), :id},
    {~w(thai), :th}
  ]

  @chinese_code ~r/^[A-Za-z0-9.]*\d[A-Za-z0-9.]*C:/

  @spec all() :: [atom()]
  def all, do: Keyword.keys(@regions)

  @spec label(atom()) :: String.t()
  def label(region), do: Keyword.fetch!(@regions, region)

  @spec labels() :: keyword(String.t())
  def labels, do: @regions

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
    words = name |> String.downcase() |> String.split(~r/[^a-z]+/, trim: true)

    cond do
      Regex.match?(@chinese_code, name) -> :zh
      String.contains?(name, "ID/TH") -> :id
      true -> Enum.find_value(@words, &from_words(&1, words))
    end
  end

  defp from_words({tags, region}, words), do: Enum.any?(tags, &(&1 in words)) && region
end
