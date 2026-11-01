defmodule TcgCheap.Sealed.Catalogue do
  @moduledoc """
  Turns Cardmarket's sealed product list and price guide into catalogue rows.

  Cardmarket publishes no expansion names. An expansion holding an English
  TCGdex set takes that set's name; otherwise the name is derived per
  `idExpansion` from the product names that share it: the longest leading
  word sequence (without kind words such as "Booster" or "Elite") that at
  least 40% of them start with. A lone product uses the text before a colon
  in its name. When nothing is convincing the set name stays empty. The
  language edition comes from `TcgCheap.Sealed.Regions`.
  """

  alias TcgCheap.Pricing.CardmarketBulk.Adapter
  alias TcgCheap.Sealed.{Kinds, Matcher, Regions}

  @kind_words ~w(booster boosters box boxes bundle elite trainer mini tin tins premium collection
                 display case sleeved jumbo blister pack checklane deck decks battle theme
                 starter set kit pokemon center league build special illustration)

  # Single words too generic to name a set on their own.
  @generic_words ~w(mega pokemon chinese japanese korean special gift)

  @search_words %{
    booster: "booster pack saszetka",
    booster_bundle: "bundle",
    booster_box: "display box",
    elite_trainer_box: "etb",
    blister: "blister",
    collection: "collection box",
    tin: "tin",
    deck: "deck",
    card_set: "set",
    case: "case display karton"
  }

  @doc """
  Catalogue rows ready for `Product.import`, one per included product, given
  the TCGdex set found for expansions (`%{expansion_id => %{language: "en",
  name: "Surging Sparks"}}`).
  """
  @spec rows([Adapter.Product.t()], [Adapter.Price.t()], Date.t(), %{integer() => map()}) ::
          [map()]
  def rows(products, prices, %Date{} = priced_on, tcgdex) do
    products = Enum.filter(products, &Kinds.included_category?(&1.category_id))
    prices = Map.new(prices, &{&1.id_product, &1})
    names = Enum.group_by(products, & &1.id_expansion, & &1.name)

    set_names =
      Map.new(names, fn {expansion, names} ->
        case tcgdex do
          %{^expansion => %{language: "en", name: name}} when is_binary(name) -> {expansion, name}
          _ -> {expansion, set_name(names)}
        end
      end)

    regions = Regions.by_expansion(names, Map.new(tcgdex, fn {id, set} -> {id, set.language} end))

    Enum.map(products, fn product ->
      kind = Kinds.from_cardmarket(product.category_id, product.name)
      set_name = Map.get(set_names, product.id_expansion)
      price = Map.get(prices, product.id_product)

      %{
        cardmarket_id: product.id_product,
        name: product.name,
        kind: kind,
        region: Map.fetch!(regions, product.id_expansion),
        cardmarket_category_id: product.category_id,
        cardmarket_expansion_id: product.id_expansion,
        set_name: set_name,
        cardmarket_added_on: added_on(product.date_added),
        slug: slug(product.name, product.id_product),
        search_text: search_text(product.name, set_name, kind),
        cardmarket_trend: price && price.trend,
        cardmarket_low: price && price.low,
        cardmarket_avg: price && price.avg,
        cardmarket_price_updated_on: price && priced_on
      }
    end)
  end

  defp set_name([name]), do: colon_prefix(name)

  defp set_name(names) do
    needed = max(2, div(length(names) * 2 + 4, 5))

    names
    |> Enum.flat_map(&(&1 |> words() |> prefixes()))
    |> Enum.frequencies()
    |> Enum.filter(fn {_prefix, count} -> count >= needed end)
    |> Enum.max_by(fn {prefix, count} -> {length(prefix), count} end, fn -> nil end)
    |> case do
      nil -> nil
      {prefix, _count} -> Enum.join(prefix, " ")
    end
  end

  # Leading word sequences (up to five words) that end on a non-kind word.
  defp prefixes(words) do
    for length <- 1..min(5, length(words)),
        prefix = Enum.take(words, length),
        not kind_word?(List.last(prefix)),
        not Enum.any?(prefix, &kind_word?/1),
        not generic_prefix?(prefix),
        uniq: true,
        do: prefix
  end

  defp colon_prefix(name) do
    case String.split(name, ":", parts: 2) do
      [prefix, _rest] -> if String.trim(prefix) == "", do: nil, else: String.trim(prefix)
      _ -> nil
    end
  end

  defp words(name) do
    name
    |> String.replace(~r/\s*\([^)]*\)/u, "")
    |> String.split(" ", trim: true)
    |> Enum.map(&String.trim_trailing(&1, ":"))
  end

  defp kind_word?(word) do
    normalized = Matcher.normalize(word)
    normalized in @kind_words or normalized == "" or String.match?(normalized, ~r/\A\d{1,2}\z/)
  end

  defp generic_prefix?([word]), do: Matcher.normalize(word) in @generic_words
  defp generic_prefix?(_prefix), do: false

  @doc "A readable, unique slug: the name plus the Cardmarket id."
  @spec slug(String.t(), integer()) :: String.t()
  def slug(name, cardmarket_id) do
    base =
      name
      |> Matcher.normalize()
      |> String.replace(" ", "-")
      |> String.slice(0, 160)
      |> String.trim("-")

    if base == "", do: "produkt-#{cardmarket_id}", else: "#{base}-#{cardmarket_id}"
  end

  @doc "Lower-case ASCII text searched by the public list."
  @spec search_text(String.t(), String.t() | nil, atom()) :: String.t()
  def search_text(name, set_name, kind) do
    # The leading space lets every word be found as a prefix with " " <> word.
    " " <>
      ([name, set_name || "", Kinds.label(kind), Map.fetch!(@search_words, kind)]
       |> Enum.join(" ")
       |> Matcher.normalize())
  end

  defp added_on(<<date::binary-size(10), _rest::binary>>) do
    case Date.from_iso8601(date) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp added_on(_value), do: nil
end
