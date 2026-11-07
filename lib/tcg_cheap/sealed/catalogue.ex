defmodule TcgCheap.Sealed.Catalogue do
  @moduledoc """
  Turns Cardmarket's sealed product list and price guide into catalogue rows.

  Cardmarket publishes no expansion names. An expansion holding an English
  TCGdex set takes that set's name; otherwise the name is derived per
  `idExpansion` from the product names that share it: the longest leading
  word sequence (up to eight words, without kind words such as "Booster" or
  "Elite") that at least 40% of them start with, and two thirds as many as
  start with the most shared one. A colon bounds a variant when an unqualified
  product confirms that boundary. A lone product uses the text before a colon
  in its name. When nothing is convincing the set name stays empty. The
  language edition comes from `TcgCheap.Sealed.Regions`. The few product and
  set names Cardmarket's data gets wrong are corrected here; the slug keeps
  Cardmarket's name.
  """

  alias TcgCheap.Pricing.CardmarketBulk.Adapter
  alias TcgCheap.Sealed.{Kinds, Matcher, Regions}

  @kind_words ~w(booster boosters box boxes bundle elite trainer mini tin tins premium collection
                 display case sleeved jumbo blister pack checklane deck decks battle theme
                 starter set kit pokemon center league build special illustration)

  # Single words too generic to name a set on their own.
  @generic_words ~w(mega pokemon chinese japanese korean special gift)

  # Cardmarket names that are wrong, by product id, checked on 2026-11-06.
  @names %{
    # The tin is Mega Latias: Pokémon Center, TCGplayer and the Polish shops.
    834_807 => "Mega Heroes: Mega Latias Mini Tin"
  }

  # Derived set names that are wrong, by expansion id, checked on 2026-11-07.
  @set_names %{
    # Two Korean accessories (Binder Set, Playmat Set) share the expansion with
    # the Terastal Festival ex booster, box and case, which Cardmarket lists
    # once for Japanese and Korean copies.
    5928 => "Terastal Festival ex"
  }

  @parenthesized ~r/\s*\([^)]*\)/u
  @unit_count ~r/\A\d{1,2}\z/

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
          _ -> {expansion, Map.get_lazy(@set_names, expansion, fn -> set_name(names) end)}
        end
      end)

    regions = Regions.by_expansion(names, Map.new(tcgdex, fn {id, set} -> {id, set.language} end))

    Enum.map(products, fn product ->
      name = Map.get(@names, product.id_product, product.name)
      kind = Kinds.from_cardmarket(product.category_id, name)
      set_name = Map.get(set_names, product.id_expansion)
      price = Map.get(prices, product.id_product)

      %{
        cardmarket_id: product.id_product,
        name: name,
        kind: kind,
        region:
          Regions.for_product(product.id_product, Map.fetch!(regions, product.id_expansion)),
        cardmarket_category_id: product.category_id,
        cardmarket_expansion_id: product.id_expansion,
        set_name: set_name,
        cardmarket_added_on: added_on(product.date_added),
        slug: slug(product.name, product.id_product),
        search_text: search_text(name, set_name, kind),
        cardmarket_trend: price && price.trend,
        cardmarket_low: price && price.low,
        cardmarket_avg: price && price.avg,
        cardmarket_price_updated_on: price && priced_on
      }
    end)
  end

  defp set_name([name]), do: colon_prefix(name)

  # A longer prefix must keep two thirds of the names the most shared one
  # covers: "EX Team Magma vs Team Aqua: Team Magma Theme Deck" and "...: Team
  # Aqua Theme Deck" do not make the set "EX Team Magma vs Team Aqua Team".
  defp set_name(names) do
    needed = max(2, div(length(names) * 2 + 4, 5))

    boundaries = variant_boundaries(names)

    candidates =
      names
      |> Enum.flat_map(&(&1 |> words() |> prefixes()))
      |> Enum.frequencies()
      |> Enum.filter(fn {prefix, count} ->
        count >= needed and
          not Enum.any?(
            boundaries,
            &(length(prefix) > length(&1) and List.starts_with?(prefix, &1))
          )
      end)

    most = candidates |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)

    candidates
    |> Enum.filter(fn {_prefix, count} -> count * 3 >= most * 2 end)
    |> Enum.max_by(fn {prefix, count} -> {length(prefix), count} end, fn -> nil end)
    |> case do
      nil -> nil
      {prefix, _count} -> Enum.join(prefix, " ")
    end
  end

  # "Double Crisis: Team Magma ..." describes a variant of "Double Crisis
  # Booster". Do not cross that colon. A colon alone is not enough: names
  # such as "151C: Collect 151" use it within the expansion's own title.
  defp variant_boundaries(names) do
    unqualified = names |> Enum.reject(&String.contains?(&1, ":")) |> Enum.map(&words/1)

    for name <- names,
        prefix = colon_prefix(name),
        prefix,
        prefix = words(prefix),
        Enum.any?(unqualified, &kind_follows?(&1, prefix)),
        uniq: true,
        do: prefix
  end

  defp kind_follows?(words, prefix) do
    case Enum.split(words, length(prefix)) do
      {^prefix, [next | _]} -> kind_word?(next)
      _ -> false
    end
  end

  # Leading word sequences (up to eight words) that end on a non-kind word.
  defp prefixes(words) do
    for length <- 1..min(8, length(words)),
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
    |> String.replace(@parenthesized, "")
    |> String.split(" ", trim: true)
    |> Enum.map(&String.trim_trailing(&1, ":"))
  end

  defp kind_word?(word) do
    normalized = Matcher.normalize(word)
    normalized in @kind_words or normalized == "" or String.match?(normalized, @unit_count)
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
