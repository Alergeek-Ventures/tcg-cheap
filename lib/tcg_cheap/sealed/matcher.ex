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
      Japanese offer never matches an English product. A product's language
      edition answers for its language word ("JP" for a Japanese product whose
      name does not say it), and a single booster for "pack" ("Booster Pack").

  Among matching products the most specific one (most tokens) wins; a tie is
  ambiguous and stays unmatched, because a wrong match would poison the price
  history. When nothing matches, a title may leave out what names a set's only
  product of its kind (a promo Pokémon, "Blister", "Collection"); a booster
  display is a booster box. Titles for multi-item bundles, empty, damaged,
  opened or used boxes, singles and accessories are excluded outright; a title naming a
  pre-order matches like any other (`preorder_title?/1` marks the offer). Otherwise a known
  EAN (`TcgCheap.Sealed.known_eans/0`) wins over the title.
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
    # A display of boosters is what Cardmarket calls a booster box; other
    # displays ("Mini Tin Display", "Build & Battle Box Display") keep the word.
    {"booster box display", "booster box"},
    {"booster display", "booster box"},
    {"world championships deck", "wcd"},
    {"etb", "elite trainer box"},
    {"min tin", "mini tin"},
    {"puszka", "tin"},
    {"seria", "series"},
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
    {"korea", "korean"},
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
                   enhanced surprise pouch portfolio starter gift calendar slim jp korean chinese sch tch thai
                   indonesian german french italian spanish)
              )

  # Kind words a title may leave out of its set's only product of that kind.
  @omissible MapSet.new(~w(blister collection))

  # Title qualifiers a product meets without naming them: its language edition
  # (`TcgCheap.Sealed.Regions`) and, for a single booster, "pack".
  @region_words %{ja: "jp", zh: "chinese", ko: "korean", id: "indonesian", th: "thai"}
  @kind_words %{booster: "pack"}

  # A count of two or more packs, as in "Booster Pack (36 boosterów)" or "(36)":
  # a display, never a single booster. A count of cards ("(10 kart)") is not one.
  @packs ~r/\(\s*(?:[2-9]|\d{2,3})\s*(?:booster(?:ów|ow|y|s)?|paczek|paczki|packs?|szt\.?|sztuk)?\s*\)/iu

  # Words naming a kind of sealed product, as in Cardmarket's sealed product
  # names. A title with none of them is a single card or an accessory.
  @sealed_words ~w(booster box bundle display case tin collection blister deck pack set starter
                   kit toolkit chest wcd academy showcase calendar classic stadium sticker
                   checklane portfolio album)

  # Words of a title that sells a pre-order ("Przedsprzedaż", "przedpremierowy"…).
  @preorder ~r/(?:\A| )(?:przedsprzedaz|przedpremier|preorder|pre order)/

  @exclusions [
    "zestaw",
    "wzorow",
    "komplet",
    "empty",
    "pusty",
    "pusta",
    "puste",
    "damaged",
    "opened",
    "used",
    "bez folii",
    "bez boosterow",
    "z zestawu",
    "repack",
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

  # Polish word stems for damaged, opened or used items ("uszkodzone", "otwarty", "używany"…).
  @damaged ~r/(?:\A| )(?:uszkodz|naruszon|otwart|otwier|uzywan)/

  # Two or more pieces ("x3", "10x", "36 szt"); "1 szt" is still one item.
  @multiples ~r/(?:\A| )(?:x ?(?:[2-9]|[1-9]\d{1,2})|(?:[2-9]|[1-9]\d{1,2}) ?x|(?:[2-9]|[1-9]\d{1,2}) (?:sztuk|szt|pcs))(?: |\z)/

  # Pack counts such as "(36)" or "(18 boosterów)" say nothing about identity.
  @pack_count ~r/\(\s*\d{1,3}\s*[[:alpha:]]*\s*\)/u
  @case_units ~r/\A\d{1,2}\z/
  @digit_letter ~r/(\d)([a-z])/
  @letter_digit ~r/([a-z])(\d)/
  @diacritic ~r/\p{Mn}/u
  @non_word ~r/[^a-z0-9]+/

  defstruct entries: [],
            by_rare_token: %{},
            by_rare_pair: %{},
            known_tokens: MapSet.new(),
            sets: [],
            eans: %{}

  @type t :: %__MODULE__{}
  @type product :: %{
          required(:id) => term(),
          required(:name) => String.t(),
          optional(:set_name) => String.t() | nil,
          optional(:region) => atom(),
          optional(:kind) => atom()
        }
  @type result :: {:matched, term()} | :unmatched | :ambiguous | {:excluded, String.t()}

  @doc """
  Builds a match index over products. `eans` maps a known EAN to its
  product id.
  """
  @spec index([product()], %{String.t() => term()}) :: t()
  def index(products, eans \\ %{}) do
    entries =
      for product <- products,
          tokens = MapSet.new(product_tokens(product.name)),
          MapSet.size(tokens) >= 2,
          do: %{
            id: product.id,
            tokens: tokens,
            size: MapSet.size(tokens),
            meets: meets(product),
            set_tokens: MapSet.new(tokens(Map.get(product, :set_name) || "")),
            booster?: Map.get(product, :kind) == :booster
          }

    frequency = entries |> Enum.flat_map(&MapSet.to_list(&1.tokens)) |> Enum.frequencies()

    rarest = fn entry -> Enum.sort_by(entry.tokens, &{Map.fetch!(frequency, &1), &1}) end

    by_rare_token = Enum.group_by(entries, &hd(rarest.(&1)))

    # A title may lack one name token (see `unique_variant/4`), possibly the
    # rarest, so the second rarest reaches those products too.
    by_rare_pair =
      for entry <- entries, token <- Enum.take(rarest.(entry), 2), reduce: %{} do
        acc -> Map.update(acc, token, [entry], &[entry | &1])
      end

    sets =
      products
      |> Enum.map(&Map.get(&1, :set_name))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(&1 |> tokens() |> Enum.join(" ")))
      |> Enum.reject(&(&1 == "" or &1 in @series))
      |> Enum.uniq()

    %__MODULE__{
      entries: entries,
      by_rare_token: by_rare_token,
      by_rare_pair: by_rare_pair,
      known_tokens: frequency |> Map.keys() |> MapSet.new(),
      sets: sets,
      eans: eans
    }
  end

  @doc "Matches an offer (`:title`, optional `:ean`) against an index."
  @spec match(map(), t()) :: result()
  def match(%{title: title} = offer, %__MODULE__{} = index) when is_binary(title) do
    normalized = normalize(title)

    with nil <- exclusion(normalized),
         :error <- Map.fetch(index.eans, Map.get(offer, :ean) || "") do
      title |> offer_tokens(index.sets) |> best(index, Regex.match?(@packs, title))
    else
      {:ok, id} -> {:matched, id}
      reason -> {:excluded, reason}
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

  @doc ~s{Whether a title sells a pre-order ("Przedsprzedaż", "Preorder"…).}
  @spec preorder_title?(String.t()) :: boolean()
  def preorder_title?(title), do: Regex.match?(@preorder, normalize(title))

  @doc "Whether a title is excluded outright (bundle of many, accessory…)."
  @spec excluded?(String.t()) :: boolean()
  def excluded?(title), do: exclusion(normalize(title)) != nil

  @doc """
  Whether a title names a kind of sealed product (booster, box, tin, ETB,
  collection, …). Feeds without curated sealed categories use it to keep
  singles and accessories out; matching still decides what the offer is.
  """
  @spec sealed_title?(String.t()) :: boolean()
  def sealed_title?(title), do: title |> tokens() |> Enum.any?(&(&1 in @sealed_words))

  @doc """
  Why `match/2` decides what it does for an offer (`:title`, optional `:ean`),
  without changing it. Returns

    * `:result` – exactly what `match/2` returns;
    * `:normalized` – the normalized title;
    * `:exclusion` – the exclusion phrase or rule that rejects the title, or nil;
    * `:ean_product_id` – the product identified by the known EAN, or nil
      (it wins over the title when not excluded);
    * `:tokens` – the title tokens compared with product names, after pack
      counts and a leading series are removed;
    * `:qualifiers` – the title tokens a matching product name must contain;
    * `:max_unexplained` – how many title tokens may be absent from the name;
    * `:candidates` – up to `limit` indexed products sharing the most tokens
      with the title, qualifying ones first (most specific first), each with
      `:id`, its name `:tokens`, `:missing` (name tokens absent from the
      title), `:missing_qualifiers` (title qualifiers absent from the name),
      `:unexplained` (title tokens absent from the name) and `:qualifies?`.

  Products whose names reduce to fewer than two tokens are not indexed and
  never match.
  """
  @spec explain(map(), t(), pos_integer()) :: map()
  def explain(%{title: title} = offer, %__MODULE__{} = index, limit \\ 5) when is_binary(title) do
    offer_tokens = offer_tokens(title, index.sets)
    offer_set = MapSet.new(offer_tokens)
    packs? = Regex.match?(@packs, title)
    qualifiers = MapSet.intersection(offer_set, @qualifiers)

    candidates =
      for entry <- index.entries,
          shared = MapSet.size(MapSet.intersection(entry.tokens, offer_set)),
          shared > 0 do
        {candidate?(entry, offer_set, qualifiers, packs?), shared, entry}
      end
      |> Enum.sort_by(fn {qualifies?, shared, entry} ->
        {not qualifies?, -shared, entry.size - shared}
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {qualifies?, _shared, entry} ->
        %{
          id: entry.id,
          tokens: Enum.sort(entry.tokens),
          missing: entry.tokens |> MapSet.difference(offer_set) |> Enum.sort(),
          missing_qualifiers:
            qualifiers
            |> MapSet.difference(MapSet.union(entry.tokens, entry.meets))
            |> Enum.sort(),
          unexplained: offer_set |> MapSet.difference(entry.tokens) |> Enum.sort(),
          qualifies?: qualifies?
        }
      end)

    normalized = normalize(title)

    %{
      result: match(offer, index),
      normalized: normalized,
      exclusion: exclusion(normalized),
      ean_product_id: Map.get(index.eans, Map.get(offer, :ean) || ""),
      tokens: Enum.uniq(offer_tokens),
      qualifiers: Enum.sort(qualifiers),
      max_unexplained: @max_unexplained,
      candidates: candidates
    }
  end

  defp best(offer_tokens, index, packs?) do
    offer_set = MapSet.new(offer_tokens)
    qualifiers = MapSet.intersection(offer_set, @qualifiers)

    candidates =
      offer_set
      |> Enum.flat_map(&Map.get(index.by_rare_token, &1, []))
      |> Enum.uniq()
      |> Enum.filter(&candidate?(&1, offer_set, qualifiers, packs?))

    case Enum.group_by(candidates, & &1.size) |> Enum.max_by(&elem(&1, 0), fn -> nil end) do
      nil -> unique_variant(offer_set, qualifiers, index, packs?)
      {_size, [entry]} -> {:matched, entry.id}
      {_size, _tie} -> :ambiguous
    end
  end

  # Shops often leave out what tells a set's only product of its kind from
  # others: "Delta Reign 3-Pack Blister" for "Delta Reign: Seel 3-Pack Blister",
  # "30th Celebration 2-Pack" for "30th Celebration: Eevee 2-Pack Blister",
  # "Tech Sticker Lucario" for the "Lucario Tech Sticker Collection". A title
  # matches a product whose name has at most one token more, besides "blister"
  # and "collection", that is neither a kind word (so "Mini Tin" never becomes
  # "Mini Tin Display"), a word of the product's set ("Booster Bundle" never
  # becomes the 151 one) nor a number (a year), when every other title word the
  # name lacks is one no product name uses (so "Blister Spritzee" never becomes
  # the Seel blister) and no other product fits the same way.
  defp unique_variant(offer_set, qualifiers, index, packs?) do
    offer_set
    |> Enum.flat_map(&Map.get(index.by_rare_pair, &1, []))
    |> Enum.uniq()
    |> Enum.filter(&variant?(&1, offer_set, qualifiers, index.known_tokens, packs?))
    |> case do
      [entry] -> {:matched, entry.id}
      [] -> :unmatched
      _several -> :ambiguous
    end
  end

  defp variant?(entry, offer_set, qualifiers, known_tokens, packs?) do
    unexplained = MapSet.difference(offer_set, entry.tokens)

    omits_variant_only?(entry, MapSet.difference(entry.tokens, offer_set)) and
      not (packs? and entry.booster?) and
      MapSet.subset?(qualifiers, MapSet.union(entry.tokens, entry.meets)) and
      MapSet.size(unexplained) <= @max_unexplained and
      MapSet.disjoint?(unexplained, known_tokens)
  end

  # The name tokens a title lacks: omissible kind words and at most one other
  # token that is neither a kind word, a set word nor a number.
  defp omits_variant_only?(entry, missing) do
    case missing |> MapSet.difference(@omissible) |> MapSet.to_list() do
      [] -> MapSet.size(missing) > 0
      [token] -> variant_token?(token, entry)
      _more -> false
    end
  end

  defp variant_token?(token, entry) do
    not MapSet.member?(@qualifiers, token) and not MapSet.member?(entry.set_tokens, token) and
      not String.match?(token, ~r/\A\d+\z/)
  end

  defp candidate?(entry, offer_set, qualifiers, packs?) do
    not (packs? and entry.booster?) and MapSet.subset?(entry.tokens, offer_set) and
      MapSet.subset?(qualifiers, MapSet.union(entry.tokens, entry.meets)) and
      MapSet.size(MapSet.difference(offer_set, entry.tokens)) <= @max_unexplained
  end

  defp meets(product) do
    [
      Map.get(@region_words, Map.get(product, :region)),
      Map.get(@kind_words, Map.get(product, :kind))
    ]
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp offer_tokens(title, sets) do
    title
    |> String.replace(@pack_count, " ")
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
      do: Enum.reject(tokens, &String.match?(&1, @case_units)),
      else: tokens
  end

  @doc "The significant word tokens of a title or product name."
  @spec tokens(String.t()) :: [String.t()]
  def tokens(text) do
    normalized =
      text
      |> normalize()
      |> String.replace(@digit_letter, "\\1 \\2")
      |> String.replace(@letter_digit, "\\1 \\2")

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
    |> String.replace(@diacritic, "")
    |> String.replace("&", " and ")
    |> String.replace(@non_word, " ")
    |> String.trim()
  end

  defp exclusion(normalized) do
    padded = " " <> normalized <> " "

    cond do
      phrase = Enum.find(@exclusions, &String.contains?(padded, " " <> &1 <> " ")) -> phrase
      Regex.match?(@damaged, normalized) -> "damaged or used"
      Regex.match?(@multiples, normalized) -> "multiple items"
      true -> nil
    end
  end
end
