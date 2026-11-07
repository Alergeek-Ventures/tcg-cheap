defmodule TcgCheap.Sealed.CardMatcher do
  @moduledoc """
  Pure, conservative identity matching of English singles. Conflicting set
  evidence blocks matching; the longest named set wins over its parent. A printed
  denominator can suggest sets, but never resolves two cards on its own.
  A name must corroborate the number. Manual decisions belong to CardOffer,
  not this parser. No shop title or category is executable input.
  """
  alias TcgCheap.Sealed.Matcher

  @languages [
    {"ja", ~r/\b(jp|jap|jpn|japanese|japonsk\w*|japonia)\b/u},
    {"zh", ~r/\b(cn|chn|chinese|chinsk\w*)\b/u},
    {"ko", ~r/\b(kr|kor|korean|koreansk\w*)\b/u},
    {"pl", ~r/\b(polska|polski|polskie|polskiej|polska wersja)\b|\bpl\s*$/u},
    {"de", ~r/\b(ger|german|niemieck\w*)\b/u},
    {"fr", ~r/\b(french|francusk\w*)\b/u},
    {"it", ~r/\b(italian|wlosk\w*)\b/u},
    {"es", ~r/\b(spanish|hiszpansk\w*)\b/u},
    {"pt", ~r/\b(portuguese|portugalsk\w*)\b/u},
    {"en", ~r/\b(eng|english|angielsk\w*)\b/u}
  ]
  @conditions [
    {:near_mint, ~r/\b(nm|near mint)\b/},
    {:light_played, ~r/\b(lp|light played|lightly played)\b/},
    {:excellent, ~r/\b(excellent|exc)\b/},
    {:good, ~r/\b(gd|good)\b/},
    {:played, ~r/\b(played|heavily played|hp)\b/},
    {:poor, ~r/\b(po|poor|damaged)\b/},
    {:mint, ~r/\bmint\b/}
  ]
  @grading ~r/\b(PSA|CGC|BGS|Beckett|ACE|TAG)\s*(10|[1-9](?:[.,]5)?)\b/i
  @not_card ~r/\b(deck|talia|lot|bundle|zestaw|koszulki|sleeves|booster|box|display|jumbo|oversize|proxy|replika|random|losow\w*|portfolio|binder|album|toploader|playmat|komplet|pakiet)\b/u
  @special ~r/\b((poke|master|quick|dusk)\s*ball|ball pattern|energy\s*(symbol|pattern)|stamped|stamp|cosmos|cosmic holo|galaxy holo|galactic holo|holo energy pattern|rocket reverse)\b/
  # 30th Classic Collection reprints print their original number (Charizard
  # 4/102), which shops quote; TCGdex numbers them 001–030 in order of it.
  # Three cards print 106 and two print 11, so the name still has to agree.
  @classic_collection_printed %{
    "001" => "4",
    "002" => "5",
    "003" => "11",
    "004" => "11",
    "005" => "18",
    "006" => "19",
    "007" => "25",
    "008" => "33",
    "009" => "41",
    "010" => "43",
    "011" => "47",
    "012" => "50",
    "013" => "57",
    "014" => "58",
    "015" => "69",
    "016" => "85",
    "017" => "89",
    "018" => "94",
    "019" => "99",
    "020" => "100",
    "021" => "101",
    "022" => "106",
    "023" => "106",
    "024" => "106",
    "025" => "108",
    "026" => "114",
    "027" => "123",
    "028" => "138",
    "029" => "149",
    "030" => "203"
  }

  # Black Star Promo numbers carry the era prefix instead of a set code. "XY"
  # alone is also the XY base set's abbreviation, so a promo prefix names its
  # promo set explicitly, and only when no total is printed.
  @promo_sets %{"svp" => "svp", "swsh" => "swshp", "sm" => "smp", "xy" => "xyp", "mep" => "mep"}
  # English promo set labels. A bare "SvP Promo" is left out: it also labels
  # Japanese "053/SV-P" numbering.
  @promo_labels [
    {"svp", ~r/\b(?:scarlet (?:and )?violet(?: black star)?|svp? black star) promos?\b/},
    {"swshp", ~r/\b(?:sword (?:and )?shield(?: black star)?|swsh black star) promos?\b/},
    {"smp", ~r/\b(?:sun (?:and )?moon(?: black star)?|sm black star) promos?\b/},
    {"xyp", ~r/\bxy(?: black star)? promos?\b/},
    {"mep", ~r/\b(?:mega evolution|mep)(?: black star)? promos?\b/}
  ]

  @doc "Build once per batch from English synced sets with their loaded cards."
  def index(sets) do
    sets = Enum.filter(sets, &(&1.language == "en" and is_list(&1.cards) and &1.cards != []))

    %{
      sets: Enum.map(sets, &set_index/1),
      name_extensions: name_extensions(sets),
      cards_by_number: sets |> Enum.flat_map(& &1.cards) |> Enum.group_by(&number(&1.number)),
      set_words:
        sets
        |> Enum.map(&Matcher.normalize(&1.name))
        |> Enum.filter(&String.contains?(&1, " "))
        |> Enum.flat_map(&String.split/1)
        |> MapSet.new(),
      cards: Map.new(for set <- sets, card <- set.cards, do: {card.id, card})
    }
  end

  defp set_index(set) do
    %{
      id: set.tcgdex_id,
      name: set.name,
      normalized: compact(set.name || ""),
      title_pattern:
        Regex.compile!(
          "(?:^| )" <>
            Regex.escape(Matcher.normalize(set.name || "")) <>
            "(?= |$)(?! (?:s|promo|promos|black star)(?: |$))"
        ),
      base_abbreviation:
        set.abbreviation && set.abbreviation |> String.downcase() |> String.split(":") |> hd(),
      abbreviation: set.abbreviation && String.downcase(set.abbreviation),
      total: set.official_card_count,
      cards: Enum.group_by(set.cards, &set_number(set.tcgdex_id, &1.number))
    }
  end

  # A Classic Collection card TCGdex adds later stays unreachable (nil) until
  # its printed number is known, rather than answering to TCGdex's number.
  defp set_number("30th-c", tcgdex_number),
    do: Map.get(@classic_collection_printed, tcgdex_number)

  # TCGdex numbers SWSH, SM and XY promos "SWSH001"; the offer's promo prefix
  # already chose the set, so look its cards up by the digits alone.
  defp set_number(set_id, value) do
    if set_id in Map.values(@promo_sets),
      do: String.replace(number(value), ~r/^[a-z]+(?=\d)/, ""),
      else: number(value)
  end

  @doc "Identity result; explain/2 includes the evidence and rejected candidates."
  def match(offer, index), do: offer |> explain(index) |> Map.fetch!(:result)

  def explain(offer, index) do
    parsed = parse(offer)

    set_title = set_title(parsed, index)

    set_parse = %{
      parsed
      | normalized_title: set_title,
        compact_title: String.replace(set_title, " ", "")
    }

    promo_labels = promo_label_sets(parsed, index.sets)
    sets = candidates(set_parse, index.sets, promo_labels)
    named = Enum.filter(index.sets, &named_in_title?(&1, set_parse))
    # Keep independent set evidence, even when a different set has a longer name.
    # A parent label inside a subset name is redundant, not a second identity.
    named = most_specific_sets(named)
    category = category_sets(parsed.category, index.sets)
    evidence = Enum.uniq_by(named ++ category ++ promo_labels, & &1.id)

    identity =
      Enum.reduce(named, identity_title(parsed), fn set, text ->
        Regex.replace(
          Regex.compile!(
            "(?:^| )" <>
              Regex.escape(Matcher.normalize(set.name)) <>
              "(?= [0-9]|$| (?:poor|good|nm|reverse|holo|ex|gd|lp)(?: |$))"
          ),
          text,
          " "
        )
      end)

    parsed = Map.put(parsed, :identity_title, identity)
    cards = card_candidates(sets, parsed, index.name_extensions)
    agreed = Enum.filter(cards, & &1.name_agrees)

    # Check every independent label against the final identity, not the union
    # of candidates: two contradictory labels cannot validate each other.
    possible_sets =
      if agreed == [],
        do: Enum.map(sets, fn {set, _} -> set.id end),
        else: Enum.map(agreed, & &1.set)

    conflict =
      possible_sets != [] and
        not Enum.any?(possible_sets, fn id ->
          Enum.all?(named ++ promo_labels, &related_set?(id, &1.id)) and
            category_agrees?(id, category)
        end)

    parsed = Map.put(parsed, :set_conflict, conflict)

    parsed =
      case agreed do
        [card] ->
          residual = String.replace(parsed.normalized_title, Matcher.normalize(card.name), " ")

          Map.merge(parsed, %{
            not_a_card: Regex.match?(@not_card, residual),
            variant: variant_without_name(parsed, residual)
          })

        _ ->
          parsed
      end

    result = result(parsed, sets, cards)

    Map.merge(parsed, %{
      set_evidence: Enum.map(evidence, &Map.take(&1, [:id, :name])),
      sets: Enum.map(sets, fn {set, why} -> %{id: set.id, name: set.name, why: why} end),
      candidates: Enum.map(cards, &Map.drop(&1, [:card])),
      result: result
    })
  end

  defp identity_title(%{code: nil} = parsed), do: parsed.normalized_title

  defp identity_title(parsed) do
    code_number = parsed.number_evidence.code |> String.downcase() |> Regex.escape()
    pattern = Regex.compile!("\\b" <> Regex.escape(parsed.code) <> "\\s*" <> code_number <> "\\b")
    Regex.replace(pattern, parsed.normalized_title, " ")
  end

  defp set_title(parsed, index) do
    coded =
      Enum.uniq(
        promo_code_sets(parsed, index.sets) ++ Enum.filter(index.sets, &code_matches?(&1, parsed))
      )

    cards =
      if coded == [],
        do:
          Enum.filter(
            Map.get(index.cards_by_number, parsed.number, []),
            &(not MapSet.member?(index.set_words, Matcher.normalize(&1.name)))
          ),
        else: Enum.flat_map(coded, &Map.get(&1.cards, parsed.number, []))

    title =
      Enum.reduce(cards, parsed.normalized_title, fn card, text ->
        String.replace(" " <> text <> " ", " " <> Matcher.normalize(card.name) <> " ", " ")
      end)

    # These phrases describe a printing/era rather than independent set labels.
    title =
      if String.contains?(parsed.title, ["δ", "Δ"]),
        do: String.replace(title, "delta species", " "),
        else: title

    title |> without_base_set_description() |> classic_collection_label()
  end

  defp without_base_set_description(text) do
    Regex.replace(
      ~r/\b(sword and shield|scarlet and violet|sun and moon) base set\b/,
      text,
      "\\1"
    )
  end

  # Shops name the subset "30th Celebration: Classic Collection", TCGdex
  # "30th Classic Collection"; otherwise the parent set's name would win.
  defp classic_collection_label(text),
    do: String.replace(text, "30th celebration classic collection", "30th classic collection")

  @doc "Parsed offer attributes, independent of the catalogue."
  def parse(offer) do
    title = offer.title
    category = Map.get(offer, :category) || ""
    text = Matcher.normalize(title <> " " <> category)
    normalized_title = Matcher.normalize(title)
    # A slab grade is not a collector number, even when it happens to name
    # an existing card in the set (e.g. Alakazam PSA 1, Base Set).
    identity_title = Regex.replace(@grading, title, " ")
    fraction = Regex.run(~r/\b([a-z]{0,5}\d{1,4})\s*\/\s*([a-z]{0,5}\d{1,4})\b/i, identity_title)
    {code, code_number} = code_number(identity_title, fraction)
    fraction = if pikachu_place?(code, code_number, fraction), do: nil, else: fraction
    {num, total} = printed_number(fraction, code_number, identity_title)

    %{
      language: language(title, category),
      condition: condition(title),
      grading: grading(title),
      variant: variant(title, category, text),
      code: code,
      number_evidence: %{code: code_number, fraction: fraction && Enum.at(fraction, 1)},
      number_conflict:
        not is_nil(code_number) and not is_nil(fraction) and
          number(code_number) != number(Enum.at(fraction, 1)),
      # Several promo numbers are several cards ("MEP023 & MEP024"), not one.
      number: if(num && not several_promos?(identity_title), do: number(num)),
      total: total,
      title: title,
      category: category,
      normalized_title: normalized_title,
      text: text,
      compact_text: String.replace(text, " ", ""),
      compact_title: String.replace(normalized_title, " ", ""),
      category_tokens: MapSet.new(String.split(Matcher.normalize(category))),
      category_segments:
        MapSet.new(Enum.map(String.split(category, ">"), &String.downcase(String.trim(&1)))),
      not_a_card: Regex.match?(@not_card, normalized_title)
    }
  end

  defp language(title, category) do
    # Short language codes are evidence only as labels or terminal markers.
    languages =
      Enum.flat_map([title, category], fn value ->
        explicit =
          Regex.scan(
            ~r/(?:\[|\(|(?:language|jezyk|wersja)\s*:?\s*)(PL|DE|FR|IT|ES|PT|EN)(?:\]|\)|\b)|\b(PL|DE|FR|IT|ES|PT|EN)\s*$/i,
            value
          )
          |> Enum.map(fn captures ->
            captures |> tl() |> Enum.find(&(&1 != "")) |> String.downcase()
          end)

        normalized = Matcher.normalize(value)

        marked =
          @languages
          |> Enum.filter(fn {_lang, regex} -> Regex.match?(regex, normalized) end)
          |> Enum.map(fn {lang, _regex} -> lang end)

        explicit ++ marked
      end)

    Enum.find(languages, &(&1 != "en")) || Enum.find(languages, &(&1 == "en"))
  end

  defp condition(title) do
    title =
      title
      |> then(&Regex.replace(@grading, &1, ""))
      |> then(
        &Regex.replace(
          ~r/[\[(](?:PL|JP|JAP|CN|KOR|DE|FR|IT|ES|PT|EN)[\])]|\b(?:PL|JP|JAP|CN|KOR|DE|FR|IT|ES|PT|EN)\s*$/i,
          &1,
          ""
        )
      )
      |> String.trim()
      |> String.trim_trailing("-")
      |> String.trim()

    # A condition must be explicitly labelled or form a separated suffix.
    case Regex.run(
           ~r/(?:\b(?:stan|condition)\s*:?\s*|\s+-\s+|[\[(])((?:NM|Near Mint|LP|Light(?:ly)? Played|EX|Excellent|Exc|GD|Good|HP|Heavily Played|Played|PO|Poor|Damaged|Mint)(?:\s*\/\s*(?:EX|NM|GD))?)(?:[\])]|\s*$)/i,
           title
         ) do
      [_, value] ->
        if value == "EX", do: :excellent, else: named_condition(Matcher.normalize(value))

      nil ->
        nil
    end
  end

  defp named_condition(normalized) do
    Enum.find_value(@conditions, fn {condition, regex} ->
      if Regex.match?(regex, normalized), do: condition
    end)
  end

  defp grading(title) do
    case Regex.run(@grading, title) do
      [_, grader, grade] -> String.upcase(grader) <> " " <> String.replace(grade, ",", ".")
      nil -> nil
    end
  end

  defp variant_without_name(parsed, residual) do
    # Only the remaining print description may identify Energy/Rocket reverse;
    # "Luminous Energy Reverse Holo" must retain its ordinary reverse finish.
    if Regex.match?(~r/\b(energy reverse|team rocket s reverse)\b/, residual),
      do: :special,
      else:
        variant(residual, parsed.category, Matcher.normalize(residual <> " " <> parsed.category))
  end

  defp energy_pattern?(title),
    do: Regex.match?(~r/(?:\(|-\s*)energy reverse(?:\)|\s*-|$)/i, title)

  defp variant(title, category, text) do
    normalized = Matcher.normalize(title)
    energy_pattern = energy_pattern?(title)

    cond do
      energy_pattern or Regex.match?(@special, text) -> :special
      reverse?(normalized) -> :reverse
      Regex.match?(~r/\b(holo|normal|non holo|zwykla)\b/, normalized) -> :normal
      Regex.match?(~r/holo\s*\/\s*reverse/i, category) -> :normal
      reverse?(Matcher.normalize(category)) -> :reverse
      true -> :normal
    end
  end

  defp reverse?(text), do: Regex.match?(~r/\b(reverse|rev holo|rh)\b/, text)

  # A Classic Collection reprint is labelled "30C BS 4": the subset's code, the
  # original set's and the original number, which the reprint still prints.
  defp code_number(title, fraction) do
    case Regex.run(~r/\b30C\s+[A-Z]{2,4}\s+(\d{1,3})\b/, title) do
      [_, number] -> {"30c", number}
      nil -> set_code_number(title, fraction)
    end
  end

  # Promo cards print no total, so next to a printed fraction a compact
  # "SWSH06" is the set's label ("SWSH06: Chilling Reign"), not a promo number.
  # A card's mechanic is not a set code ("Armarouge EX 125 SVP").
  defp set_code_number(title, fraction) do
    case Regex.run(
           ~r/\b(?!(?:EX|GX)\b)((?=[A-Z0-9]{0,4}[A-Z])[A-Z0-9]{2,5})\s+((?:TG|GG|SV)?\d{1,4})\b/,
           title
         ) do
      [_, code, number] -> {String.downcase(code), number}
      nil when is_nil(fraction) -> compact_promo(title)
      nil -> {nil, nil}
    end
  end

  # "SVP-EN-144" is an English promo number too; "XY67a" an alternate print.
  # A following number makes it a set code instead ("sm9 013").
  defp compact_promo(title) do
    case Regex.run(~r/\b(SVP|SWSH|SM|XY|MEP)(?:-EN-)?(\d{1,3}a?)\b(?!\s*\d)/i, title) do
      [_, code, num] -> {String.downcase(code), num}
      nil -> number_code(title)
    end
  end

  # Some shops write the number first: "Charizard ex 228 OBF". The code still
  # has to be a set's abbreviation and the name has to agree.
  defp number_code(title) do
    case Regex.run(~r/\b((?:TG|GG|SV)?\d{1,4})\s+([A-Z][A-Z0-9]{1,4})\b(?!\s*\d)/, title) do
      [_, number, code] -> {String.downcase(code), number}
      nil -> {nil, nil}
    end
  end

  # 30th Celebration's Pikachu 023–052 are also counted 1/30–30/30 by their
  # place in that run: "Pikachu 30C 042 20/30" names one card twice.
  defp pikachu_place?("30c", code_number, [_, place, "30"]) do
    with {code_number, ""} <- Integer.parse(code_number),
         {place, ""} <- Integer.parse(place) do
      place in 1..30 and code_number == place + 22
    else
      _ -> false
    end
  end

  defp pikachu_place?(_code, _code_number, _fraction), do: false

  defp several_promos?(title) do
    ~r/\b(?:SVP|SWSH|SM|XY|MEP)(?:\s*|-EN-)\d{1,3}a?\b/i
    |> Regex.scan(title)
    |> Enum.uniq()
    |> length() > 1
  end

  defp printed_number([_, num, total], _code, _title), do: {num, number(total)}

  defp printed_number(nil, code_number, title) do
    num =
      code_number ||
        List.first(Regex.run(~r/\b(?:TG|GG|SV|SVP|SWSH|SM|XY)\d{1,3}\b/i, title) || []) ||
        List.first(Regex.run(~r/\b\d{1,3}\b/, title) || [])

    case num && Regex.run(~r/^(SVP|SWSH|SM|XY)(\d+)$/i, num) do
      [_, _prefix, digits] -> {digits, nil}
      _ -> {num, nil}
    end
  end

  @doc "Ignore numeric zero padding while retaining gallery prefixes."
  def number(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\b0+(?=\d)/, "")
    |> String.replace(~r/([a-z])0+(?=\d)/, "\\1")
  end

  defp candidates(parsed, sets, promo_labels) do
    promo = promo_code_sets(parsed, sets)
    coded = Enum.filter(sets, &code_matches?(&1, parsed))

    named = if coded == [], do: named_sets(parsed, sets), else: []

    cond do
      # "XY 146" may still be the XY base set's card; the name decides.
      promo != [] or coded != [] ->
        Enum.map(promo, &{&1, :promo}) ++
          Enum.map(coded -- promo, &{&1, :abbreviation})

      Map.has_key?(@promo_sets, parsed.code) ->
        []

      named != [] ->
        named |> most_specific_sets() |> Enum.map(&{&1, :name})

      promo_labels != [] ->
        Enum.map(promo_labels, &{&1, :promo_label})

      true ->
        total_sets(parsed.total, sets)
    end
  end

  defp total_sets(nil, _sets), do: []

  # Black Star Promos print no total.
  defp total_sets(total, sets) do
    sets
    |> Enum.filter(&(&1.total && number(to_string(&1.total)) == total))
    |> Enum.reject(&(&1.id in Map.values(@promo_sets)))
    |> Enum.map(&{&1, :total})
  end

  defp promo_code_sets(%{code: code, total: nil}, sets),
    do: Enum.filter(sets, &(&1.id == Map.get(@promo_sets, code)))

  defp promo_code_sets(_parsed, _sets), do: []

  # Shops also label set-numbered blister promos ("Iron Moth 028/182 - Scarlet &
  # Violet Promo"); only a lone number without a total is a Black Star Promo
  # number ("Eevee 101a/149" is not promo 149).
  defp promo_label_sets(%{total: nil} = parsed, sets) do
    ids = for {id, regex} <- @promo_labels, Regex.match?(regex, parsed.text), do: id

    if length(Regex.scan(~r/\d+/, parsed.title)) == 1,
      do: Enum.filter(sets, &(&1.id in ids)),
      else: []
  end

  defp promo_label_sets(_parsed, _sets), do: []

  defp named_sets(parsed, sets) do
    in_title =
      Enum.filter(
        sets,
        &named_in_title?(&1, parsed)
      )

    if in_title == [], do: category_sets(parsed.category, sets), else: in_title
  end

  # Google feeds separate a category path with ">", Shoper's Ceneo feed with " / ".
  defp category_sets(category, sets) do
    category
    |> String.split(~r/>| \/ /)
    |> Enum.reverse()
    |> Enum.find_value([], &category_segment(&1, sets))
    |> then(fn result -> if result == :no_set, do: [], else: result end)
  end

  defp most_specific_sets(sets) do
    Enum.reject(sets, fn set ->
      Enum.any?(sets, fn other ->
        other.id != set.id and String.contains?(other.normalized, set.normalized)
      end)
    end)
  end

  # Gallery and Classic Collection numbers live under their parent set label.
  defp related_set?(id, evidence) do
    id == evidence or
      Enum.any?(["tg", "gg", "sv", "-c"], &String.starts_with?(id, evidence <> &1))
  end

  # This known combined category means either release, not two conflicting
  # identities. A specific leaf category and independent title labels still bind.
  defp category_agrees?(id, category) do
    if Enum.sort(Enum.map(category, & &1.id)) == ["sv10.5b", "sv10.5w"],
      do: Enum.any?(category, &related_set?(id, &1.id)),
      else: Enum.all?(category, &related_set?(id, &1.id))
  end

  defp category_segment(segment, sets) do
    # Era/promo labels do not identify a same-named base set or its parent.
    if Regex.match?(~r/\bera\b|promos?/i, segment) do
      :no_set
    else
      segment =
        segment
        |> Matcher.normalize()
        |> without_base_set_description()
        |> classic_collection_label()
        |> compact()

      sets |> Enum.filter(&named_in_category?(&1, segment)) |> category_candidates()
    end
  end

  defp category_candidates([]), do: nil

  defp category_candidates(found), do: most_specific_sets(found)

  # A numeric set name is evidence only as a set label, never as the card's
  # numerator. In particular [151] must beat the Scarlet & Violet era category.
  defp named_in_title?(%{normalized: "151"}, parsed),
    do: Regex.match?(~r/\[151\]|pokemon\s+151(?!\d|\s*\/)/i, parsed.title)

  defp named_in_title?(set, parsed),
    do:
      String.length(set.normalized) > 3 and
        String.contains?(parsed.compact_title, set.normalized) and
        Regex.match?(set.title_pattern, parsed.normalized_title)

  defp named_in_category?(%{normalized: "151"}, segment),
    do:
      segment == "151" or String.contains?(segment, "pokemon151") or
        String.starts_with?(segment, "single151")

  defp named_in_category?(%{id: "30th-c"}, "classiccollection"), do: true

  defp named_in_category?(set, segment),
    do: String.length(set.normalized) > 3 and String.contains?(segment, set.normalized)

  defp code_matches?(%{abbreviation: nil}, _parsed), do: false

  defp code_matches?(set, parsed) do
    # Match complete tokens, so MEW never matches Mew as a card's name alone.
    set.base_abbreviation == parsed.code or
      MapSet.member?(parsed.category_segments, set.base_abbreviation)
  end

  defp card_candidates(sets, parsed, extensions) do
    for {set, why} <- sets,
        card <- Map.get(set.cards, parsed.number, []) do
      %{
        id: card.id,
        tcgdex_id: card.tcgdex_id,
        name: card.name,
        number: card.number,
        set: set.id,
        variants: Map.get(card, :variants) || [],
        why: why,
        name_agrees: name_agrees?(card.name, parsed, extensions),
        variant_agrees:
          parsed.variant != :reverse or Map.get(card, :variants, []) in [nil, []] or
            "reverse" in card.variants,
        card: card
      }
    end
  end

  defp name_agrees?(name, parsed, name_extensions) do
    normalized = identity_name(name)
    title = normalize_identity(parsed.identity_title)
    extensions = Map.get(name_extensions, normalized, [])

    normalized != "" and contains_name?(title, normalized) and
      not Enum.any?(extensions, &contains_name?(title, &1)) and
      not Regex.match?(
        Regex.compile!(
          "(?:\\b\\w+ s " <>
            Regex.escape(normalized) <>
            "\\b|\\b" <>
            Regex.escape(normalized) <>
            " and \\w+\\b|\\b\\w+ and " <>
            Regex.escape(normalized) <> "\\b)"
        ),
        title
      )
  end

  defp contains_name?(title, name),
    do: String.contains?(" " <> title <> " ", " " <> name <> " ")

  defp identity_name(name) do
    name
    |> String.replace(~r/\s*\([^)]*\)/, "")
    |> normalize_identity()
  end

  defp normalize_identity(name) do
    name
    |> Matcher.normalize()
    |> String.replace(~r/\b(basic|ex|gx|v|vmax|vstar|delta|species)\b/, " ")
    |> String.split()
    |> Enum.join(" ")
  end

  # Index catalogue names containing a shorter complete identity. This catches
  # owners, tag teams and distinguishing suffixes without scanning all cards
  # for each offer; mechanic spelling is normalized on both sides.
  defp name_extensions(sets) do
    names = for set <- sets, card <- set.cards, into: MapSet.new(), do: identity_name(card.name)

    Enum.reduce(names, %{}, fn name, acc ->
      tokens = String.split(name)

      for start <- 0..(length(tokens) - 1),
          count <- 1..length(tokens),
          start + count <= length(tokens),
          count < length(tokens),
          shorter = tokens |> Enum.slice(start, count) |> Enum.join(" "),
          MapSet.member?(names, shorter),
          reduce: acc do
        result -> Map.update(result, shorter, [name], &[name | &1])
      end
    end)
  end

  defp result(%{language: lang}, _sets, _cards) when lang not in [nil, "en"],
    do: {:excluded, {:language, lang}}

  defp result(%{number_conflict: true}, _sets, _cards), do: {:unmatched, :number_conflict}
  defp result(%{set_conflict: true}, _sets, _cards), do: {:unmatched, :set_conflict}
  defp result(%{not_a_card: true}, _sets, _cards), do: {:excluded, :not_a_card}
  defp result(%{number: nil}, _sets, _cards), do: {:unmatched, :no_number}
  defp result(_parsed, [], _cards), do: {:unmatched, :unknown_set}
  defp result(_parsed, _sets, []), do: {:unmatched, :no_card}

  defp result(parsed, _sets, cards) do
    case Enum.filter(cards, & &1.name_agrees) do
      [] -> {:unmatched, :name_mismatch}
      [card] -> {:matched, card.id, parsed.variant}
      cards -> {:ambiguous, cards |> Enum.map(& &1.id) |> Enum.uniq()}
    end
  end

  defp compact(value), do: value |> Matcher.normalize() |> String.replace(" ", "")
end
