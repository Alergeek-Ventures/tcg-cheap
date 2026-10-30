defmodule TcgCheap.Sealed.Catalogue do
  @moduledoc """
  The curated list of English-language sealed Pokémon TCG products.

  The catalogue is code, not a table: adding a product means adding an entry
  below and deploying. Each entry names its set (shared name, release date and
  title terms), its kind (shared title terms and exclusions) and optional
  product-specific terms. Match terms are normalized phrases (see
  `TcgCheap.Sealed.Matcher.normalize/1`); every term group must appear in an
  offer title, and one phrase from each group is enough.

  Release dates come from the Bulbapedia set and merchandise pages (the
  official pokemon.com pages refuse automated requests); dates the sources
  disagree on are left empty.
  """

  alias TcgCheap.Sealed.{Matcher, Product}

  @kinds [
    booster: "Booster",
    blister: "Blister",
    booster_bundle: "Booster Bundle",
    booster_box: "Booster Box",
    elite_trainer_box: "Elite Trainer Box",
    collection: "Kolekcja",
    tin: "Puszka",
    deck: "Talia"
  ]

  # Extra words a shopper may search for, besides the name, set and label.
  @kind_search_words %{
    booster: "booster pack saszetka",
    blister: "blister",
    booster_bundle: "bundle",
    booster_box: "display box",
    elite_trainer_box: "etb",
    collection: "collection box",
    tin: "tin",
    deck: "deck"
  }

  # Title rules shared by every product of a kind: {terms, exclusions}.
  @kind_rules %{
    booster:
      {[["booster"]],
       ~w(bundle box display blister case tin collection half checklane build prerelease) ++
         ["pack blister"]},
    blister: {[], ["checklane", "tech sticker"]},
    booster_bundle: {[["booster bundle"]], ["display"]},
    booster_box:
      {[["booster box", "booster display", "display box"]], ["half", "bundle", "pokemon center"]},
    elite_trainer_box: {[["elite trainer box", "etb"]], ["pokemon center", "plus"]},
    collection: {[], []},
    tin: {[], ["display"]},
    deck: {[], []}
  }

  @mega_evolution_expansions [
    "phantasmal flames",
    "ascended heroes",
    "perfect order",
    "chaos rising",
    "pitch black",
    "30th celebration",
    "delta reign"
  ]

  # name, title terms and exclusions, release date of the main expansion.
  @sets %{
    celebration_30th: {"30th Celebration", [["30th celebration"]], [], ~D[2026-09-16]},
    pitch_black: {"Pitch Black", [["pitch black"]], [], ~D[2026-07-17]},
    chaos_rising: {"Chaos Rising", [["chaos rising"]], [], ~D[2026-05-22]},
    perfect_order: {"Perfect Order", [["perfect order"]], [], ~D[2026-03-27]},
    ascended_heroes: {"Ascended Heroes", [["ascended heroes"]], [], ~D[2026-01-30]},
    phantasmal_flames: {"Phantasmal Flames", [["phantasmal flames"]], [], ~D[2025-11-14]},
    mega_evolution:
      {"Mega Evolution", [["mega evolution"]], @mega_evolution_expansions, ~D[2025-09-26]},
    black_bolt: {"Black Bolt", [["black bolt"]], ["white flare"], ~D[2025-07-18]},
    white_flare: {"White Flare", [["white flare"]], ["black bolt"], ~D[2025-07-18]},
    destined_rivals: {"Destined Rivals", [["destined rivals"]], [], ~D[2025-05-30]},
    journey_together: {"Journey Together", [["journey together"]], [], ~D[2025-03-28]},
    prismatic_evolutions:
      {"Prismatic Evolutions", [["prismatic evolutions"]], [], ~D[2025-01-17]},
    surging_sparks: {"Surging Sparks", [["surging sparks"]], [], ~D[2024-11-08]},
    stellar_crown: {"Stellar Crown", [["stellar crown"]], [], ~D[2024-09-13]},
    twilight_masquerade: {"Twilight Masquerade", [["twilight masquerade"]], [], ~D[2024-05-24]},
    temporal_forces: {"Temporal Forces", [["temporal forces"]], [], ~D[2024-03-22]},
    paldean_fates: {"Paldean Fates", [["paldean fates"]], [], ~D[2024-01-26]},
    paradox_rift: {"Paradox Rift", [["paradox rift"]], [], ~D[2023-11-03]},
    scarlet_violet_151: {"151", [["151"]], [], ~D[2023-09-22]},
    obsidian_flames: {"Obsidian Flames", [["obsidian flames"]], [], ~D[2023-08-11]},
    paldea_evolved: {"Paldea Evolved", [["paldea evolved"]], [], ~D[2023-06-09]}
  }

  @image_base "https://www.pokemon.com/static-assets/content-assets/cms2/img/trading-card-game"
  @mcdn_base "https://mcdn.pokemon.com/pokemon-prod/image/upload/c_limit,w_1920/f_auto/v1/live"

  # {slug, set, kind, name, options}. Options: :terms, :exclude, :release_date
  # (when it differs from the set's), :image_url, :eans.
  @entries [
    # 30th Celebration
    {"pokemon-tcg-30th-celebration-booster-pack", :celebration_30th, :booster,
     "30th Celebration Booster", []},
    {"pokemon-tcg-30th-celebration-elite-trainer-box", :celebration_30th, :elite_trainer_box,
     "30th Celebration Elite Trainer Box", []},
    {"pokemon-tcg-30th-celebration-booster-bundle", :celebration_30th, :booster_bundle,
     "30th Celebration Booster Bundle", release_date: ~D[2026-10-02]},
    {"pokemon-tcg-30th-celebration-greninja-ex-box", :celebration_30th, :collection,
     "30th Celebration Greninja ex Box",
     terms: [["greninja"], ["box"]], exclude: ["tin", "mini"]},
    {"pokemon-tcg-30th-celebration-sylveon-ex-box", :celebration_30th, :collection,
     "30th Celebration Sylveon ex Box", terms: [["sylveon"], ["box"]], exclude: ["tin", "mini"]},
    {"pokemon-tcg-30th-celebration-greninja-ex-tin", :celebration_30th, :tin,
     "30th Celebration Greninja ex Tin",
     terms: [["greninja"], ["tin"]], exclude: ["mini", "box"], release_date: nil},
    {"pokemon-tcg-30th-celebration-sylveon-ex-tin", :celebration_30th, :tin,
     "30th Celebration Sylveon ex Tin",
     terms: [["sylveon"], ["tin"]], exclude: ["mini", "box"], release_date: nil},
    {"pokemon-tcg-30th-celebration-mini-tin", :celebration_30th, :tin,
     "30th Celebration Mini Tin (dowolny wzór)",
     terms: [["mini tin"]], release_date: ~D[2026-10-02]},
    {"pokemon-tcg-30th-celebration-poster-collection", :celebration_30th, :collection,
     "30th Celebration Poster Collection", terms: [["poster collection"]], exclude: ["premium"]},
    {"pokemon-tcg-30th-celebration-binder-collection", :celebration_30th, :collection,
     "30th Celebration Binder Collection", terms: [["binder collection"]], release_date: nil},
    {"pokemon-tcg-30th-celebration-two-pack-blister", :celebration_30th, :blister,
     "30th Celebration 2-Pack Blister", terms: [["2 pack", "two pack"]]},
    {"pokemon-tcg-30th-celebration-battle-deck-espeon-ex", :celebration_30th, :deck,
     "30th Celebration Battle Deck Espeon ex",
     terms: [["battle deck"], ["espeon"]], release_date: ~D[2026-10-30]},
    {"pokemon-tcg-30th-celebration-battle-deck-umbreon-ex", :celebration_30th, :deck,
     "30th Celebration Battle Deck Umbreon ex",
     terms: [["battle deck"], ["umbreon"]], release_date: ~D[2026-10-30]},

    # Pitch Black
    {"pokemon-tcg-pitch-black-booster-pack", :pitch_black, :booster, "Pitch Black Booster",
     image_url: "#{@image_base}/series/me_series/me05/me05-booster-packs-169-en.png"},
    {"pokemon-tcg-pitch-black-elite-trainer-box", :pitch_black, :elite_trainer_box,
     "Pitch Black Elite Trainer Box",
     image_url:
       "#{@image_base}/series/incrementals/2026/me05-elite-trainer-box/me05-elite-trainer-box-169-en.png"},
    {"pokemon-tcg-pitch-black-booster-box", :pitch_black, :booster_box, "Pitch Black Booster Box",
     image_url:
       "#{@mcdn_base}/pcom-cms/static-assets/cms3/us/img/trading-card-game/tiles/me/me05/product-showcase/inline/booster-display-box-en.png"},
    {"pokemon-tcg-pitch-black-3-pack-blister-binacle", :pitch_black, :blister,
     "Pitch Black 3-Pack Blister", terms: [["3 pack", "3pack", "three pack"]]},

    # Chaos Rising
    {"pokemon-tcg-mega-evolution-chaos-rising-booster-pack", :chaos_rising, :booster,
     "Chaos Rising Booster",
     image_url: "#{@image_base}/series/me_series/me04/me04-booster-packs-169-en.png"},
    {"pokemon-tcg-mega-evolution-chaos-rising-elite-trainer-box", :chaos_rising,
     :elite_trainer_box, "Chaos Rising Elite Trainer Box",
     image_url:
       "#{@image_base}/series/incrementals/2026/me04-elite-trainer-box/me04-elite-trainer-box-169-en.png"},
    {"pokemon-tcg-mega-evolution-chaos-rising-booster-box", :chaos_rising, :booster_box,
     "Chaos Rising Booster Box",
     image_url: "#{@image_base}/_tiles/me/me04/product-showcase/inline/booster-display-box-en.png"},
    {"pokemon-tcg-mega-evolution-chaos-rising-booster-bundle", :chaos_rising, :booster_bundle,
     "Chaos Rising Booster Bundle", []},
    {"pokemon-tcg-mega-evolution-chaos-rising-3-pack-blister", :chaos_rising, :blister,
     "Chaos Rising 3-Pack Blister", terms: [["3 pack", "3pack", "three pack"]]},

    # Perfect Order
    {"pokemon-tcg-mega-evolution-perfect-order-booster-pack", :perfect_order, :booster,
     "Perfect Order Booster", []},
    {"pokemon-tcg-mega-evolution-perfect-order-elite-trainer-box", :perfect_order,
     :elite_trainer_box, "Perfect Order Elite Trainer Box", []},
    {"pokemon-tcg-mega-evolution-perfect-order-booster-box", :perfect_order, :booster_box,
     "Perfect Order Booster Box", []},
    {"pokemon-tcg-mega-evolution-perfect-order-3-pack-blister", :perfect_order, :blister,
     "Perfect Order 3-Pack Blister", terms: [["3 pack", "3pack", "three pack"]]},

    # Ascended Heroes
    {"pokemon-tcg-mega-evolution-ascended-heroes-elite-trainer-box", :ascended_heroes,
     :elite_trainer_box, "Ascended Heroes Elite Trainer Box",
     release_date: ~D[2026-02-20],
     image_url:
       "#{@image_base}/series/incrementals/2026/me2pt5-elite-trainer-box/me2pt5-elite-trainer-box-169-en.png"},
    {"pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle", :ascended_heroes,
     :booster_bundle, "Ascended Heroes Booster Bundle",
     release_date: ~D[2026-04-24],
     image_url:
       "#{@image_base}/series/incrementals/2026/me2pt5-booster-bundle/me2pt5-booster-bundle-169-en.png"},
    {"pokemon-tcg-mega-evolution-ascended-heroes-mega-meganium-ex-box", :ascended_heroes,
     :collection, "Ascended Heroes Mega Meganium ex Box",
     terms: [["meganium"]],
     exclude: ["feraligatr", "emboar", "tin", "mini tin"],
     release_date: ~D[2026-04-24]},
    {"pokemon-tcg-mega-evolution-ascended-heroes-mega-emboar-ex-box", :ascended_heroes,
     :collection, "Ascended Heroes Mega Emboar ex Box",
     terms: [["emboar"]],
     exclude: ["feraligatr", "meganium", "tin", "mini tin"],
     release_date: ~D[2026-04-24]},
    {"pokemon-tcg-mega-evolution-ascended-heroes-mega-feraligatr-ex-box", :ascended_heroes,
     :collection, "Ascended Heroes Mega Feraligatr ex Box",
     terms: [["feraligatr"]],
     exclude: ["meganium", "emboar", "tin", "mini tin"],
     release_date: ~D[2026-04-24]},
    {"pokemon-tcg-mega-evolution-ascended-heroes-booster-pack", :ascended_heroes, :booster,
     "Ascended Heroes Booster", []},

    # Phantasmal Flames
    {"pokemon-tcg-mega-evolution-phantasmal-flames-booster-pack", :phantasmal_flames, :booster,
     "Phantasmal Flames Booster", []},
    {"pokemon-tcg-mega-evolution-phantasmal-flames-elite-trainer-box", :phantasmal_flames,
     :elite_trainer_box, "Phantasmal Flames Elite Trainer Box", []},
    {"pokemon-tcg-mega-evolution-phantasmal-flames-booster-box", :phantasmal_flames, :booster_box,
     "Phantasmal Flames Booster Box", []},

    # Mega Evolution
    {"pokemon-tcg-mega-evolution-booster-pack", :mega_evolution, :booster,
     "Mega Evolution Booster", []},
    {"pokemon-tcg-mega-evolution-booster-box", :mega_evolution, :booster_box,
     "Mega Evolution Booster Box", []},

    # Mega Evolution era collections and tins without a single expansion.
    {"pokemon-tcg-mega-charizard-x-ex-ultra-premium-collection", nil, :collection,
     "Mega Charizard X ex Ultra-Premium Collection",
     terms: [["charizard x"], ["ultra premium collection"]],
     exclude: ["tin"],
     release_date: ~D[2025-11-14]},
    {"pokemon-tcg-mega-venusaur-ex-premium-collection", nil, :collection,
     "Mega Venusaur ex Premium Collection", terms: [["mega venusaur"], ["premium collection"]]},
    {"pokemon-tcg-mega-zygarde-ex-premium-collection", nil, :collection,
     "Mega Zygarde ex Premium Collection", terms: [["mega zygarde"], ["premium collection"]]},
    {"pokemon-tcg-mega-greninja-ex-premium-collection", nil, :collection,
     "Mega Greninja ex Premium Collection",
     terms: [["mega greninja"], ["premium collection"]],
     exclude: ["30th celebration", "battle deck"],
     release_date: ~D[2026-07-03]},
    {"pokemon-tcg-mega-charizard-x-ex-tin", nil, :tin, "Mega Charizard Tin – Mega Charizard X ex",
     terms: [["mega charizard tin"], ["charizard x"]], release_date: ~D[2026-02-20]},
    {"pokemon-tcg-mega-charizard-y-ex-tin", nil, :tin, "Mega Charizard Tin – Mega Charizard Y ex",
     terms: [["mega charizard tin"], ["charizard y"]], release_date: ~D[2026-02-20]},
    {"pokemon-tcg-lumiose-city-mini-tin", nil, :tin, "Lumiose City Mini Tin (dowolny wzór)",
     terms: [["lumiose city"], ["mini tin", "min tin"]]},
    {"pokemon-tcg-first-partner-illustration-collection-series-1", nil, :collection,
     "First Partner Illustration Collection – Series 1",
     terms: [["first partner"], ["illustration collection"], ["series 1", "seria 1"]],
     release_date: ~D[2026-03-20]},
    {"pokemon-tcg-first-partner-illustration-collection-series-2", nil, :collection,
     "First Partner Illustration Collection – Series 2",
     terms: [["first partner"], ["illustration collection"], ["series 2", "seria 2"]],
     release_date: ~D[2026-06-19]},
    {"pokemon-tcg-first-partner-illustration-collection-series-3", nil, :collection,
     "First Partner Illustration Collection – Series 3",
     terms: [["first partner"], ["illustration collection"], ["series 3", "seria 3"]],
     release_date: ~D[2026-08-07]},
    {"pokemon-tcg-pokemon-day-2026-collection", nil, :collection, "Pokémon Day 2026 Collection",
     terms: [["pokemon day"], ["2026"]],
     release_date: ~D[2026-01-30],
     image_url:
       "#{@image_base}/series/incrementals/2026/pokemon-day-2026-collection/pokemon-day-2026-collection-169-en.png"},

    # Scarlet & Violet
    {"pokemon-tcg-scarlet-violet-black-bolt-elite-trainer-box", :black_bolt, :elite_trainer_box,
     "Black Bolt Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-black-bolt-binder-collection", :black_bolt, :collection,
     "Black Bolt Binder Collection", terms: [["binder collection"]]},
    {"pokemon-tcg-scarlet-violet-white-flare-elite-trainer-box", :white_flare, :elite_trainer_box,
     "White Flare Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-white-flare-binder-collection", :white_flare, :collection,
     "White Flare Binder Collection", terms: [["binder collection"]]},
    {"pokemon-tcg-scarlet-violet-destined-rivals-booster-pack", :destined_rivals, :booster,
     "Destined Rivals Booster",
     image_url: "#{@image_base}/series/sv_series/sv10/sv10-booster-packs-169-en.png"},
    {"pokemon-tcg-scarlet-violet-destined-rivals-elite-trainer-box", :destined_rivals,
     :elite_trainer_box, "Destined Rivals Elite Trainer Box",
     image_url:
       "#{@image_base}/series/incrementals/2025/sv10-elite-trainer-box/sv10-elite-trainer-box-169-en.png"},
    {"pokemon-tcg-scarlet-violet-destined-rivals-booster-box", :destined_rivals, :booster_box,
     "Destined Rivals Booster Box",
     image_url:
       "#{@mcdn_base}/static-assets/content-assets/cms2/img/trading-card-game/_tiles/sv/sv10/product-showcase/inline/sv10-booster-display-box-en.png"},
    {"pokemon-tcg-scarlet-violet-journey-together-booster-pack", :journey_together, :booster,
     "Journey Together Booster", []},
    {"pokemon-tcg-scarlet-violet-journey-together-elite-trainer-box", :journey_together,
     :elite_trainer_box, "Journey Together Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-journey-together-booster-box", :journey_together, :booster_box,
     "Journey Together Booster Box", []},
    {"pokemon-tcg-scarlet-violet-prismatic-evolutions-elite-trainer-box", :prismatic_evolutions,
     :elite_trainer_box, "Prismatic Evolutions Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-prismatic-evolutions-booster-pack", :prismatic_evolutions,
     :booster, "Prismatic Evolutions Booster", []},
    {"pokemon-tcg-scarlet-violet-prismatic-evolutions-booster-bundle", :prismatic_evolutions,
     :booster_bundle, "Prismatic Evolutions Booster Bundle", release_date: ~D[2025-03-07]},
    {"pokemon-tcg-scarlet-violet-prismatic-evolutions-super-premium-collection",
     :prismatic_evolutions, :collection, "Prismatic Evolutions Super-Premium Collection",
     terms: [["super premium collection"]], release_date: ~D[2025-05-16]},
    {"pokemon-tcg-scarlet-violet-surging-sparks-elite-trainer-box", :surging_sparks,
     :elite_trainer_box, "Surging Sparks Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-stellar-crown-booster-pack", :stellar_crown, :booster,
     "Stellar Crown Booster",
     image_url: "#{@image_base}/series/sv_series/sv07/sv07-booster-packs-169-en.png"},
    {"pokemon-tcg-scarlet-violet-twilight-masquerade-booster-pack", :twilight_masquerade,
     :booster, "Twilight Masquerade Booster",
     image_url: "#{@image_base}/series/sv_series/sv06/sv06-booster-packs-169-en.png"},
    {"pokemon-tcg-scarlet-violet-temporal-forces-booster-pack", :temporal_forces, :booster,
     "Temporal Forces Booster",
     image_url: "#{@image_base}/series/sv_series/sv05/sv05-booster-packs-169-en.png"},
    {"pokemon-tcg-scarlet-violet-paldean-fates-booster-pack", :paldean_fates, :booster,
     "Paldean Fates Booster", []},
    {"pokemon-tcg-scarlet-violet-paldean-fates-elite-trainer-box", :paldean_fates,
     :elite_trainer_box, "Paldean Fates Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-paldean-fates-booster-bundle", :paldean_fates, :booster_bundle,
     "Paldean Fates Booster Bundle", release_date: ~D[2024-02-23]},
    {"pokemon-tcg-scarlet-violet-paradox-rift-booster-pack", :paradox_rift, :booster,
     "Paradox Rift Booster",
     image_url: "#{@image_base}/series/sv_series/sv04/sv04-booster-packs-169-en.png"},
    {"pokemon-tcg-scarlet-violet-151-booster-pack", :scarlet_violet_151, :booster, "151 Booster",
     []},
    {"pokemon-tcg-scarlet-violet-151-booster-bundle", :scarlet_violet_151, :booster_bundle,
     "151 Booster Bundle", []},
    {"pokemon-tcg-scarlet-violet-151-elite-trainer-box", :scarlet_violet_151, :elite_trainer_box,
     "151 Elite Trainer Box", []},
    {"pokemon-tcg-scarlet-violet-obsidian-flames-booster-pack", :obsidian_flames, :booster,
     "Obsidian Flames Booster",
     image_url: "#{@image_base}/series/sv_series/sv03/sv03-booster-packs-169-en.png"},
    {"pokemon-tcg-scarlet-violet-paldea-evolved-elite-trainer-box", :paldea_evolved,
     :elite_trainer_box, "Paldea Evolved Elite Trainer Box", []}
  ]

  @products (for {slug, set_key, kind, name, opts} <- @entries do
               {set_name, set_terms, set_exclude, set_date} =
                 if set_key, do: Map.fetch!(@sets, set_key), else: {nil, [], [], nil}

               {kind_terms, kind_exclude} = Map.fetch!(@kind_rules, kind)

               %Product{
                 slug: slug,
                 name: name,
                 kind: kind,
                 set_name: set_name,
                 release_date: Keyword.get(opts, :release_date, set_date),
                 image_url: Keyword.get(opts, :image_url),
                 eans: Keyword.get(opts, :eans, []),
                 terms: set_terms ++ kind_terms ++ Keyword.get(opts, :terms, []),
                 exclude:
                   Enum.uniq(set_exclude ++ kind_exclude ++ Keyword.get(opts, :exclude, []))
               }
             end)

  @by_slug Map.new(@products, &{&1.slug, &1})

  @doc "Every catalogue product, newest release first (undated products last)."
  @spec all() :: [Product.t()]
  def all, do: sorted(@products)

  @spec get(String.t()) :: {:ok, Product.t()} | :error
  def get(slug) when is_binary(slug), do: Map.fetch(@by_slug, slug)
  def get(_slug), do: :error

  @doc "Products whose name, set or kind contains every word of the query."
  @spec search(String.t() | nil) :: [Product.t()]
  def search(query) when is_binary(query) do
    case query |> Matcher.normalize() |> String.split(" ", trim: true) do
      [] -> all()
      words -> Enum.filter(all(), &search_match?(&1, words))
    end
  end

  def search(_query), do: all()

  @spec kind_label(atom()) :: String.t()
  def kind_label(kind), do: Keyword.fetch!(@kinds, kind)

  @spec kinds() :: [atom()]
  def kinds, do: Keyword.keys(@kinds)

  defp search_match?(product, words) do
    haystack =
      [
        product.name,
        product.set_name || "",
        kind_label(product.kind),
        @kind_search_words[product.kind]
      ]
      |> Enum.join(" ")
      |> Matcher.normalize()

    padded = " " <> haystack <> " "
    Enum.all?(words, &String.contains?(padded, " " <> &1))
  end

  defp sorted(products) do
    {dated, undated} = Enum.split_with(products, & &1.release_date)
    Enum.sort_by(dated, & &1.release_date, {:desc, Date}) ++ undated
  end
end
