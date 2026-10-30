defmodule TcgCheap.Sealed.Matcher do
  @moduledoc """
  Decides which catalogue product a shop offer is, automatically.

  Titles and product names are reduced to word tokens: lower case, no
  diacritics, punctuation as spaces, "Pokémon TCG" and filler words removed,
  shop synonyms unified ("ETB", "japoński" → "jp", …) and a leading series
  ("Scarlet & Violet –", "Mega Evolution –") dropped when the title names a
  set after it. An offer matches a product when

    * every token of the product name appears in the title, and
    * every *qualifier* in the title (kind words such as "box", "case",
      "half", "center", "mini", and edition languages) appears in the
      product name — so "Half Booster Box" never matches "Booster Box" and a
      Japanese offer never matches an English product.

  Among matching products the most specific one (most tokens) wins; a tie is
  ambiguous and stays unmatched, because a wrong match would poison the price
  history. Titles for preorders, multi-item bundles, empty boxes, singles and
  accessories are excluded outright. An EAN seen on a manually assigned offer
  wins over the title.
  """

  @stopwords ~w(pokemon tcg the and of s a z na i w edycja karty kart karta oryginalne oryginalny
                angielski angielska angielskie english en eng wersja nowy nowa prerelease)

  @plurals %{
    "boosters" => "booster",
    "boxes" => "box",
    "tins" => "tin",
    "decks" => "deck",
    "blisters" => "blister",
    "collections" => "collection",
    "bundles" => "bundle"
  }

  # Unexplained title words allowed beyond the product name (a Pokémon, "Day", …).
  @max_unexplained 2

  @synonyms [
    {"eu version", ""},
    {"world championships deck", "wcd"},
    {"etb", "elite trainer box"},
    {"min tin", "mini tin"},
    {"puszka", "tin"},
    {"seria", "series"},
    {"ultra premium", "ultra premium"},
    {"simplified chinese", "sch"},
    {"traditional chinese", "tch"},
    {"s ch", "sch"},
    {"t ch", "tch"},
    {"japanese", "jp"},
    {"japan", "jp"},
    {"jpn", "jp"},
    {"japonski", "jp"},
    {"japonska", "jp"},
    {"japonskie", "jp"},
    {"japonskich", "jp"},
    {"koreanski", "korean"},
    {"koreanska", "korean"},
    {"koreanskie", "korean"},
    {"kor", "korean"},
    {"chinski", "chinese"},
    {"chinska", "chinese"},
    {"chinskie", "chinese"},
    {"indonezyjski", "indonesian"},
    {"tajski", "thai"},
    {"niemiecki", "german"},
    {"francuski", "french"}
  ]

  @series [
    "mega evolution",
    "scarlet violet",
    "sword shield",
    "sun moon",
    "black white",
    "me",
    "sv",
    "swsh"
  ]

  @qualifiers MapSet.new(
                ~w(booster box bundle display case half mini tin elite trainer center premium collection
                   checklane blister pack sleeved jumbo build battle prerelease deck league figure poster
                   binder pin sticker tech ultra super special illustration deluxe toolkit chest kit stadium
                   enhanced surprise pouch portfolio starter gift calendar jp korean chinese sch tch thai
                   indonesian german french italian spanish)
              )

  @exclusions [
    "preorder",
    "pre order",
    "przedsprzedaz",
    "przedpremiera",
    "przedpremierowy",
    "przedpremierowa",
    "zestaw",
    "wzorow",
    "komplet",
    "empty",
    "pusty",
    "pusta",
    "puste",
    "single",
    "singles",
    "pojedyncza",
    "pojedyncze",
    "sleeves",
    "koszulki",
    "playmat",
    "mata",
    "album",
    "binder only",
    "toploader",
    "code card",
    "kod"
  ]

  @multiples ~r/(?:\A| )(?:x ?\d{1,3}|\d{1,3} ?x|\d{1,3} (?:sztuk|szt|pcs))(?: |\z)/

  defstruct entries: [], by_rare_token: %{}, sets: [], eans: %{}

  @type t :: %__MODULE__{}
  @type product :: %{
          required(:id) => term(),
          required(:name) => String.t(),
          optional(:set_name) => String.t() | nil
        }
  @type result :: {:matched, term()} | :unmatched | :ambiguous | {:excluded, String.t()}

  @doc """
  Builds a match index over products. `eans` maps an EAN to the product id of
  a manually assigned offer that carried it.
  """
  @spec index([product()], %{String.t() => term()}) :: t()
  def index(products, eans \\ %{}) do
    entries =
      for product <- products,
          tokens = MapSet.new(product_tokens(product.name)),
          MapSet.size(tokens) >= 2,
          do: %{id: product.id, tokens: tokens, size: MapSet.size(tokens)}

    frequency = entries |> Enum.flat_map(&MapSet.to_list(&1.tokens)) |> Enum.frequencies()

    by_rare_token =
      Enum.group_by(entries, fn entry ->
        Enum.min_by(entry.tokens, &{Map.fetch!(frequency, &1), &1})
      end)

    sets =
      products
      |> Enum.map(&Map.get(&1, :set_name))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(&1 |> tokens() |> Enum.join(" ")))
      |> Enum.reject(&(&1 == "" or &1 in @series))
      |> Enum.uniq()

    %__MODULE__{entries: entries, by_rare_token: by_rare_token, sets: sets, eans: eans}
  end

  @doc "Matches an offer (`:title`, optional `:ean`) against an index."
  @spec match(map(), t()) :: result()
  def match(%{title: title} = offer, %__MODULE__{} = index) when is_binary(title) do
    case Map.fetch(index.eans, Map.get(offer, :ean) || "") do
      {:ok, id} -> {:matched, id}
      :error -> match_title(title, index)
    end
  end

  @doc "The matched product id, or nil."
  @spec product_id(map(), t()) :: term() | nil
  def product_id(offer, index) do
    case match(offer, index) do
      {:matched, id} -> id
      _ -> nil
    end
  end

  @doc "Whether a title is excluded outright (preorder, bundle of many, accessory…)."
  @spec excluded?(String.t()) :: boolean()
  def excluded?(title), do: exclusion(normalize(title)) != nil

  defp match_title(title, index) do
    normalized = normalize(title)

    case exclusion(normalized) do
      nil -> title |> offer_tokens(index.sets) |> best(index)
      reason -> {:excluded, reason}
    end
  end

  defp best(offer_tokens, index) do
    offer_set = MapSet.new(offer_tokens)
    qualifiers = MapSet.intersection(offer_set, @qualifiers)

    candidates =
      offer_set
      |> Enum.flat_map(&Map.get(index.by_rare_token, &1, []))
      |> Enum.uniq()
      |> Enum.filter(&candidate?(&1, offer_set, qualifiers))

    case Enum.group_by(candidates, & &1.size) |> Enum.max_by(&elem(&1, 0), fn -> nil end) do
      nil -> :unmatched
      {_size, [entry]} -> {:matched, entry.id}
      {_size, _tie} -> :ambiguous
    end
  end

  defp candidate?(entry, offer_set, qualifiers) do
    MapSet.subset?(entry.tokens, offer_set) and MapSet.subset?(qualifiers, entry.tokens) and
      MapSet.size(MapSet.difference(offer_set, entry.tokens)) <= @max_unexplained
  end

  # Pack counts such as "(36)" or "(18 boosterów)" say nothing about identity.
  defp offer_tokens(title, sets) do
    title
    |> String.replace(~r/\(\s*\d{1,3}\s*[[:alpha:]]*\s*\)/u, " ")
    |> tokens()
    |> strip_series(sets)
  end

  # Drops a leading series name when a set name follows it.
  defp strip_series(tokens, sets) do
    text = Enum.join(tokens, " ")

    Enum.find_value(@series, tokens, fn series ->
      padded = " " <> text <> " "

      with true <- String.contains?(padded, " " <> series <> " "),
           rest =
             padded |> String.replace(" " <> series <> " ", " ", global: false) |> String.trim(),
           true <- Enum.any?(sets, &String.contains?(" " <> rest <> " ", " " <> &1 <> " ")) do
        String.split(rest, " ", trim: true)
      else
        _ -> nil
      end
    end)
  end

  # Cardmarket names cases by unit count ("6 Booster Box Case"); shops rarely do.
  defp product_tokens(name) do
    tokens = tokens(name)

    if "case" in tokens,
      do: Enum.reject(tokens, &String.match?(&1, ~r/\A\d{1,2}\z/)),
      else: tokens
  end

  @doc "The significant word tokens of a title or product name."
  @spec tokens(String.t()) :: [String.t()]
  def tokens(text) do
    normalized =
      text
      |> normalize()
      |> String.replace(~r/(\d)([a-z])/, "\\1 \\2")
      |> String.replace(~r/([a-z])(\d)/, "\\1 \\2")

    @synonyms
    |> Enum.reduce(" " <> normalized <> " ", fn {from, to}, acc ->
      String.replace(acc, " " <> from <> " ", " " <> to <> " ")
    end)
    |> String.split(" ", trim: true)
    |> Enum.map(&Map.get(@plurals, &1, &1))
    |> Enum.reject(&(&1 in @stopwords))
  end

  @doc "Normalizes text for word-wise comparison: lower case ASCII words separated by spaces."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace("ł", "l")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("&", " and ")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp exclusion(normalized) do
    padded = " " <> normalized <> " "

    cond do
      phrase = Enum.find(@exclusions, &String.contains?(padded, " " <> &1 <> " ")) -> phrase
      Regex.match?(@multiples, normalized) -> "multiple items"
      true -> nil
    end
  end
end
