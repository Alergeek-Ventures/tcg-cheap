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
      name does not say it), a single booster for "pack" ("Booster Pack") and
      a product also sold in a Jumbo version (Chinese sets) for "slim"; such
      a word does not count against the few title words a name may lack. A
      "Checklane" title is a "1-Pack Blister" unless it says "Premium" or
      counts packs, and must then name the blister's Pokémon and no other
      word; a "Blister Bundle" is the blister.
      A leading Chinese set code ("CBB3C:", "CSV9.5C:") is not part of the
      name: shops rarely write it, and when they do its words count as
      explained. Nor is a "Simplified Chinese" marker ("S-Ch" in
      "CSV10.5C: Black Bolt S-Ch Booster Box"), which shops leave out too;
      such a product has a namesake in another edition, so the title must
      say it is Chinese or name the set code instead. Nor need a title
      name the "ex" ending a Japanese set's name ("Terastal Festival
      Booster Box" for "Terastal Festival ex Booster Box") when the
      product's name holds that set name and no other "ex"; such a
      product then counts one token less (`set_ex/2`).

  Among matching products the most specific one (most tokens) wins; a tie is
  ambiguous and stays unmatched, because a wrong match would poison the price
  history. When nothing matches, a title may leave out what names a set's only
  product of its kind (a promo Pokémon, "Blister", "Collection"); a booster
  display is a booster box. Titles for multi-item bundles, empty, damaged,
  opened or used boxes, singles and accessories are excluded outright; a title naming a
  pre-order matches like any other (`preorder_title?/1` marks the offer). Otherwise a known
  EAN (`TcgCheap.Sealed.known_eans/0`) wins over the title, unless the title matches another
  product and contradicts the EAN's one (`contradicts?/4`): shops sell single boosters under
  their display's EAN and one Pokémon's tin under its sibling's.
  """

  alias TcgCheap.Sealed.Regions

  @stopwords ~w(pokemon tcg ptcg the and of s a z na i w edycja karty kart karta oryginal oryginalne
                oryginalny angielski angielska angielskie english en eng wersja nowy nowa prerelease)

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
    # A shop's tag line; "produkt" alone may still mean something ("produkt opóźniony").
    {"produkt kolekcjonerski", ""},
    # Smyk's tag line ("…, gra karciana w puszce, dodatek"); "dodatek" (expansion)
    # names no product either.
    {"gra karciana w puszce", ""},
    {"gra karciana", ""},
    {"dodatek", ""},
    # A display of boosters is what Cardmarket calls a booster box; other
    # displays ("Mini Tin Display", "Build & Battle Box Display") keep the word.
    {"booster box display", "booster box"},
    {"booster display", "booster box"},
    # A blister "bundle" is the blister itself (REBEL's "3-Pack Blister Bundle"
    # carries the 3-Pack Blister's EAN), unlike a Booster Bundle.
    {"blister bundle", "blister"},
    {"slim pack", "slim"},
    {"world championships deck", "wcd"},
    {"etb", "elite trainer box"},
    # A common misspelling of the Enhanced Booster Box.
    {"enchanced", "enhanced"},
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
    {"jap", "jp"},
    {"japonski", "jp"},
    {"japonska", "jp"},
    {"japonskie", "jp"},
    {"japonskich", "jp"},
    {"japonia", "jp"},
    {"koreanski", "korean"},
    {"koreanska", "korean"},
    {"koreanskie", "korean"},
    {"kor", "korean"},
    {"korea", "korean"},
    # Shops mark a Korean edition with a bare "KR" too ("Booster Box sv9a KR");
    # as a word of its own it never names anything else in a sealed title.
    {"kr", "korean"},
    {"chinski", "chinese"},
    {"chinska", "chinese"},
    {"chinskie", "chinese"},
    {"china", "chinese"},
    {"chiny", "chinese"},
    {"chn", "chinese"},
    # Like "KR": a bare "CN" marks a Chinese edition ("Booster (CN)").
    {"cn", "chinese"},
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
  # (`TcgCheap.Sealed.Regions`), for a single booster, "pack", for a 1-Pack
  # Blister, "checklane" (`checklane/1`) and, for a product sold in a Jumbo
  # version too, "slim" (`meet_slim/1`).
  @region_words %{ja: "jp", zh: "chinese", ko: "korean", id: "indonesian", th: "thai"}
  @kind_words %{booster: "pack"}

  # A count of two or more packs, as in "Booster Pack (36 boosterów)", "(36)",
  # "Booster 3 boostery" or "3-pack": a display, a lot or a blister, never a
  # single booster or 1-Pack Blister. A count of cards ("(10 kart)") is not one.
  @packs ~r/\(\s*(?:[2-9]|\d{2,3})\s*(?:booster(?:ów|ow|y|s)?|paczek|paczki|packs?|szt\.?|sztuk)?\s*\)|(?<![\w.,])(?:[2-9]|\d{2,3})[\s\p{Pd}]*(?:booster(?:ów|ow|y|s)|paczek|paczki|packs?)(?!\w)/iu

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
    # A pack opened live on stream for the buyer, not a sealed product.
    "booster break",
    "poke break",
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

  # Two or more pieces ("x3", "10x", "36 szt", "3 sztuki"); "1 szt" is still one item.
  @multiples ~r/(?:\A| )(?:x ?(?:[2-9]|[1-9]\d{1,2})|(?:[2-9]|[1-9]\d{1,2}) ?x|(?:[2-9]|[1-9]\d{1,2}) (?:sztuki|sztuk|szt|pcs))(?: |\z)/

  # Pack counts such as "(36)" or "(10 boosterów)" say nothing about identity
  # (but for 18, see `half_display/1`).
  @pack_count ~r/\(\s*\d{1,3}\s*[[:alpha:]]*\s*\)/u
  @case_units ~r/\A\d{1,2}\z/
  @digit_letter ~r/(\d)([a-z])/
  @letter_digit ~r/([a-z])(\d)/
  @diacritic ~r/\p{Mn}/u
  @non_word ~r/[^a-z0-9]+/

  defstruct entries: [],
            by_rare_token: %{},
            by_rare_pair: %{},
            by_token: %{},
            known_tokens: MapSet.new(),
            sets: [],
            eans: %{},
            by_id: %{}

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
          {code, name} = Regions.chinese_code(product.name) || {"", product.name},
          {sch, name_tokens} = name |> product_tokens() |> Enum.split_with(&(&1 == "sch")),
          tokens = MapSet.new(name_tokens),
          MapSet.size(tokens) >= 2,
          do: %{
            id: product.id,
            tokens: tokens,
            size: MapSet.size(tokens),
            omissible: set_ex(product, name_tokens),
            meets: meets(product, single_blister?(name_tokens), sch != []),
            sch?: sch != [],
            code_tokens: MapSet.new(tokens(code)),
            set_tokens: MapSet.new(tokens(Map.get(product, :set_name) || "")),
            single?: Map.get(product, :kind) == :booster or single_blister?(name_tokens)
          }

    entries = meet_slim(entries)

    frequency = entries |> Enum.flat_map(&MapSet.to_list(&1.tokens)) |> Enum.frequencies()

    # A token a title may leave out (`set_ex/2`) cannot be what reaches a product.
    rarest = fn entry ->
      entry.tokens
      |> MapSet.difference(entry.omissible)
      |> Enum.sort_by(&{Map.fetch!(frequency, &1), &1})
    end

    by_rare_token = Enum.group_by(entries, &hd(rarest.(&1)))

    # A title may lack one name token (see `unique_variant/4`), possibly the
    # rarest, so the second rarest reaches those products too.
    by_rare_pair =
      for entry <- entries, token <- Enum.take(rarest.(entry), 2), reduce: %{} do
        acc -> Map.update(acc, token, [entry], &[entry | &1])
      end

    # A set code's words are still words some product name uses (`unique_variant/4`).
    known_tokens =
      entries
      |> Enum.flat_map(&MapSet.to_list(MapSet.union(&1.tokens, &1.code_tokens)))
      |> MapSet.new()

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
      by_token: by_token(entries),
      known_tokens: known_tokens,
      sets: sets,
      eans: eans,
      by_id: Map.new(entries, &{&1.id, &1})
    }
  end

  @doc "Matches an offer (`:title`, optional `:ean`) against an index."
  @spec match(map(), t()) :: result()
  def match(%{title: title} = offer, %__MODULE__{} = index) when is_binary(title) do
    case exclusion(normalize(title)) do
      nil ->
        packs? = Regex.match?(@packs, title)
        offer_tokens = offer_tokens(title, index.sets, packs?)
        ean_id = Map.get(index.eans, Map.get(offer, :ean) || "")
        ean_or_title(ean_id, best(offer_tokens, index, packs?), offer_tokens, index, packs?)

      reason ->
        {:excluded, reason}
    end
  end

  # Shops reuse one product's EAN for another: a single booster under its
  # display's barcode ("Delta Reign – Booster pack" with the Booster Box's), a
  # tin, blister or box of one Pokémon under its sibling's ("Mega Charizard X ex
  # Tin" with the Mega Clefable ex Tin's). A known EAN wins over the title
  # unless the title matches another product and contradicts the EAN's one; a
  # title that matches nothing, or a product left out of the index, leaves the
  # EAN standing.
  defp ean_or_title(nil, by_title, _offer_tokens, _index, _packs?), do: by_title

  defp ean_or_title(ean_id, {:matched, title_id} = by_title, offer_tokens, index, packs?)
       when title_id != ean_id do
    case Map.fetch(index.by_id, ean_id) do
      {:ok, ean_entry} ->
        title_entry = Map.fetch!(index.by_id, title_id)

        if contradicts?(MapSet.new(offer_tokens), ean_entry, title_entry, packs?),
          do: by_title,
          else: {:matched, ean_id}

      :error ->
        {:matched, ean_id}
    end
  end

  defp ean_or_title(ean_id, _by_title, _offer_tokens, _index, _packs?), do: {:matched, ean_id}

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
      (it wins over the title when not excluded, unless the title matches
      another product and contradicts this one);
    * `:tokens` – the title tokens compared with product names, after pack
      counts and a leading series are removed and "1 Pack Blister" follows
      "Checklane" in a title that neither says "Premium" nor counts packs;
    * `:qualifiers` – the title tokens a matching product name must contain;
    * `:max_unexplained` – how many title tokens may be absent from the name;
    * `:candidates` – up to `limit` indexed products sharing the most tokens
      with the title, qualifying ones first (most specific first), each with
      `:id`, its name `:tokens`, `:missing` (name tokens absent from the
      title, but for its set's "ex" a title may leave out),
      `:missing_qualifiers` (title qualifiers absent from the name),
      `:unexplained` (title tokens absent from the name), `:code_tokens` (the
      words of its leading Chinese set code, which a title may name but need
      not), `:meets` (qualifiers it meets without naming them: its language,
      "pack" for a single booster, "checklane" for a 1-Pack Blister, "slim"
      for a product sold in a Jumbo version too, "sch" for one named
      "S-Ch"), `:edition_named?` (false when such a product's title says
      neither "Chinese" nor its set code) and `:qualifies?`.

  Products whose names reduce to fewer than two tokens are not indexed and
  never match.
  """
  @spec explain(map(), t(), pos_integer()) :: map()
  def explain(%{title: title} = offer, %__MODULE__{} = index, limit \\ 5) when is_binary(title) do
    packs? = Regex.match?(@packs, title)
    offer_tokens = offer_tokens(title, index.sets, packs?)
    offer_set = MapSet.new(offer_tokens)
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
          missing:
            entry.tokens
            |> MapSet.difference(offer_set)
            |> MapSet.difference(entry.omissible)
            |> Enum.sort(),
          missing_qualifiers:
            qualifiers
            |> MapSet.difference(MapSet.union(entry.tokens, entry.meets))
            |> Enum.sort(),
          unexplained: offer_set |> unexplained(entry) |> Enum.sort(),
          code_tokens: Enum.sort(entry.code_tokens),
          meets: Enum.sort(entry.meets),
          edition_named?: edition_named?(entry, offer_set),
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

    # A product counts the name tokens the title names, so one whose set's "ex"
    # the title leaves out (`set_ex/2`) yields to a product named in full.
    named = &MapSet.size(MapSet.intersection(&1.tokens, offer_set))

    case Enum.group_by(candidates, named) |> Enum.max_by(&elem(&1, 0), fn -> nil end) do
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
  # becomes the 151 one), a number (a year) nor "version", when every other title word the
  # name lacks is one no product name uses (so "Blister Spritzee" never becomes
  # the Seel blister) and no other product fits the same way. A title naming
  # none of the variant ("Obsidian Flames Checklane Blister") fits as well a
  # product whose variant takes several words or a number ("Paldean Wooper",
  # "Porygon2"), which leaves it ambiguous.
  defp unique_variant(offer_set, qualifiers, index, packs?) do
    offer_set
    |> Enum.flat_map(&Map.get(index.by_rare_pair, &1, []))
    |> Enum.uniq()
    |> Enum.filter(&fits?(&1, offer_set, qualifiers, index.known_tokens, packs?, :variant))
    |> case do
      [entry] ->
        if lookalike?(entry, offer_set, qualifiers, index, packs?),
          do: :ambiguous,
          else: {:matched, entry.id}

      [] ->
        :unmatched

      _several ->
        :ambiguous
    end
  end

  defp lookalike?(entry, offer_set, qualifiers, index, packs?) do
    names_variant? =
      entry.tokens |> MapSet.intersection(offer_set) |> Enum.any?(&variant_token?(&1, entry))

    not names_variant? and
      offer_set
      |> lookalike_candidates(index)
      |> Enum.any?(
        &(&1.id != entry.id and fits?(&1, offer_set, qualifiers, index.known_tokens, packs?, :any))
      )
  end

  # A product that fits a title names each of its words some product name
  # uses, but for the qualifiers it meets, so the rarest such word reaches it.
  defp lookalike_candidates(offer_set, index) do
    offer_set
    |> Enum.filter(
      &(MapSet.member?(index.known_tokens, &1) and not MapSet.member?(@qualifiers, &1))
    )
    |> Enum.map(&Map.fetch!(index.by_token, &1))
    |> Enum.min_by(&length/1, fn -> index.entries end)
  end

  defp fits?(entry, offer_set, qualifiers, known_tokens, packs?, omits) do
    unexplained = unexplained(offer_set, entry)

    omits?(omits, entry, MapSet.difference(entry.tokens, offer_set)) and
      not (packs? and entry.single?) and
      MapSet.subset?(qualifiers, MapSet.union(entry.tokens, entry.meets)) and
      MapSet.size(unexplained) <= @max_unexplained and
      MapSet.disjoint?(unexplained, known_tokens) and
      checklane_fits?(entry, offer_set, unexplained) and
      edition_named?(entry, offer_set)
  end

  # The name tokens a title lacks: omissible kind words and, for `:variant`,
  # at most one other token that is neither a kind word, a set word, a number
  # nor "version"; for `:any`, any others but kind and set words.
  defp omits?(:variant, entry, missing) do
    case missing |> MapSet.difference(@omissible) |> MapSet.to_list() do
      [] -> MapSet.size(missing) > 0
      [token] -> variant_token?(token, entry)
      _more -> false
    end
  end

  defp omits?(:any, entry, missing) do
    MapSet.size(missing) > 0 and
      missing
      |> MapSet.difference(@omissible)
      |> Enum.all?(
        &(not MapSet.member?(@qualifiers, &1) and not MapSet.member?(entry.set_tokens, &1))
      )
  end

  # "Version" tells printings of one product apart ("Zarude 2-Pack Blister
  # Version 1" and "Version 2"), so a title must name it.
  defp variant_token?(token, entry) do
    token != "version" and not MapSet.member?(@qualifiers, token) and
      not MapSet.member?(entry.set_tokens, token) and not String.match?(token, ~r/\A\d+\z/)
  end

  defp candidate?(entry, offer_set, qualifiers, packs?) do
    kind_fits?(entry, qualifiers, packs?) and
      entry.tokens |> MapSet.difference(entry.omissible) |> MapSet.subset?(offer_set) and
      MapSet.size(unexplained(offer_set, entry)) <= @max_unexplained and
      checklane_fits?(entry, offer_set, unexplained(offer_set, entry)) and
      edition_named?(entry, offer_set)
  end

  # The title contradicts the EAN's product when that product does not fit the
  # title's kind or language words or its pack count, or when the product the
  # title matches has a word the title names and the EAN's product lacks
  # (another Pokémon, set or edition). A title that only leaves words out, such
  # as "30th Celebration Booster (CHI)" for the Simplified Chinese booster,
  # does not contradict it.
  defp contradicts?(offer_set, ean_entry, title_entry, packs?) do
    qualifiers = MapSet.intersection(offer_set, @qualifiers)

    ean_words =
      ean_entry.tokens |> MapSet.union(ean_entry.meets) |> MapSet.union(ean_entry.code_tokens)

    not kind_fits?(ean_entry, qualifiers, packs?) or
      title_entry.tokens
      |> MapSet.intersection(offer_set)
      |> MapSet.difference(ean_words)
      |> Enum.any?()
  end

  # The title's kind and language words fit the product: it names or meets
  # every qualifier, and a title counting packs is not a single one.
  defp kind_fits?(entry, qualifiers, packs?) do
    not (packs? and entry.single?) and
      MapSet.subset?(qualifiers, MapSet.union(entry.tokens, entry.meets))
  end

  # A name's "S-Ch" (or "Simplified Chinese") is not a name token, but such a
  # product has a namesake in another edition ("CSV10.5C: Black Bolt S-Ch
  # Booster" and "Black Bolt Booster"), so the title must say it is Chinese
  # ("chiński", "S-Ch") or name the product's set code ("Black Bolt CSV10.5C").
  defp edition_named?(%{sch?: false}, _offer_set), do: true

  defp edition_named?(entry, offer_set) do
    MapSet.member?(offer_set, "sch") or MapSet.member?(offer_set, "chinese") or
      (MapSet.size(entry.code_tokens) > 0 and MapSet.subset?(entry.code_tokens, offer_set))
  end

  # A "Checklane" title (`checklane/1`) must name the blister's Pokémon and no
  # other word: shops also write "Checklane" for the Premium Checklane
  # Blisters' Pokémon ("Checklane Scorbunny") and for one of two blisters
  # ("Checklane Blister Eevee/Zarude", "Mix"), and the set's only 1-Pack
  # Blister must not take those.
  defp checklane_fits?(entry, offer_set, unexplained) do
    not MapSet.member?(offer_set, "checklane") or MapSet.member?(offer_set, "premium") or
      (entry.tokens |> MapSet.intersection(offer_set) |> Enum.any?(&variant_token?(&1, entry)) and
         not Enum.any?(unexplained, &String.match?(&1, ~r/[a-z]/)))
  end

  # Title tokens the product name does not account for. A qualifier the product
  # meets without naming it ("JP" for a Japanese product, "pack" for a booster)
  # is accounted for, so "Battle Partners Japoński Booster [sv9]" spends its
  # allowance on "sv 9" only; so is its set code ("[CSV9.5C]").
  defp unexplained(offer_set, entry) do
    offer_set
    |> MapSet.difference(entry.tokens)
    |> MapSet.difference(entry.meets)
    |> MapSet.difference(entry.code_tokens)
  end

  # Every word of a name or its set code, for `lookalike?/5`.
  defp by_token(entries) do
    for entry <- entries,
        token <- MapSet.union(entry.tokens, entry.code_tokens),
        reduce: %{} do
      acc -> Map.update(acc, token, [entry], &[entry | &1])
    end
  end

  # Chinese sets come as a regular product (5-card packs, 15 to a box) and a
  # Jumbo one (20-card packs, 6 to a box); shops call the regular one "slim".
  defp meet_slim(entries) do
    names = MapSet.new(entries, &{&1.tokens, &1.code_tokens})

    for entry <- entries do
      jumbo = {MapSet.put(entry.tokens, "jumbo"), entry.code_tokens}

      if not MapSet.member?(entry.tokens, "jumbo") and MapSet.member?(names, jumbo),
        do: %{entry | meets: MapSet.put(entry.meets, "slim")},
        else: entry
    end
  end

  # "1-Pack Blister" in a row: "Zarude 2-Pack Blister Version 1" is not one.
  defp single_blister?(name_tokens),
    do: String.contains?(" #{Enum.join(name_tokens, " ")} ", " 1 pack blister ")

  # Japanese sets end their names in "ex" ("Terastal Festival ex"), which shops
  # leave out ("Terastal Festival Booster Box Japoński"). A Japanese product's
  # name may lose that "ex" when it holds the whole set name and no other "ex"
  # (a Pokémon's, as in "Scarlet ex & Violet ex Special Set"); `best/3` then
  # counts it one token less, so a product the title names in full wins.
  defp set_ex(product, name_tokens) do
    set = tokens(Map.get(product, :set_name) || "")

    if Map.get(product, :region) == :ja and match?([_, _ | _], set) and List.last(set) == "ex" and
         Enum.count(name_tokens, &(&1 == "ex")) == 1 and
         String.contains?(" #{Enum.join(name_tokens, " ")} ", " #{Enum.join(set, " ")} "),
       do: MapSet.new(["ex"]),
       else: MapSet.new()
  end

  defp meets(product, single_blister?, sch?) do
    [
      Map.get(@region_words, Map.get(product, :region)),
      Map.get(@kind_words, Map.get(product, :kind)),
      if(single_blister?, do: "checklane"),
      if(sch?, do: "sch")
    ]
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp offer_tokens(title, sets, packs?) do
    tokens =
      title
      |> String.replace(@pack_count, &half_display/1)
      |> tokens()
      |> strip_series(sets)

    if packs? or "premium" in tokens, do: tokens, else: checklane(tokens)
  end

  # A pack count says nothing about identity, but for 18: Cardmarket names a
  # half display "Booster Box (18 Boosters)", and a title counting 18 is one.
  defp half_display(count),
    do: if(Regex.match?(~r/\A\(\s*18\D/, count), do: " 18 ", else: " ")

  # Shops call a single pack in a blister a "Checklane (Blister/Booster)",
  # Cardmarket a "1-Pack Blister", which meets "checklane" (`meets/2`). A
  # "Premium Checklane Blister" is another product, which Cardmarket names so,
  # and a title counting packs is not a single one, so both keep the word.
  defp checklane(["checklane", "booster" | rest]),
    do: ~w(checklane 1 pack blister) ++ checklane(rest)

  defp checklane(["checklane" | rest]), do: ~w(checklane 1 pack blister) ++ checklane(rest)
  defp checklane([token | rest]), do: [token | checklane(rest)]
  defp checklane([]), do: []

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
