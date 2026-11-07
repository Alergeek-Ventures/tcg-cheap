defmodule TcgCheap.Sealed.AgentTools do
  @moduledoc """
  Actions behind the MCP tools for AI agents (see the `tools` of
  `TcgCheap.Sealed`): shop status, offer lists, product detail, match
  explanations, manual decisions, product barcodes, contents and photos, set
  pull rates and unofficial card lists, expansion logos, REBEL suggested prices and fetch/import jobs.
  They do what the admin buying-guide desk
  (`TcgCheapWeb.Admin.BuyingGuideLive`) does and store nothing themselves.
  """

  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Sealed

  alias TcgCheap.Sealed.AgentTools.{
    Decide,
    Enqueue,
    ExplainMatch,
    OfferList,
    ProductDetail,
    RecordUnofficialCards,
    SetContents,
    SetEans,
    SetExpansionLogo,
    SetPhoto,
    SetPullRates,
    ShopStatus,
    SuggestedPrices
  }

  alias TcgCheap.Sealed.Shops

  @shops Enum.join(Shops.keys(), ", ")
  @current "An offer is current while it was in its shop's latest fetch and that fetch is at most 3 days old."
  @recomputes "Manual decisions are never overwritten by automatic matching. Prices, availability and today's daily prices are recomputed in the same transaction, which can take a few seconds."

  actions do
    action :list_unmatched_card_offers, :map do
      description "Current single-card offers without an automatic identity or manual decision. Exclusions are hidden by default, counted by reason. Returns evidence and up to 3 candidates per row. Filters combine; pages return total, limit, offset and items."
      argument :shop, :string
      argument :title, :string
      argument :set, :string
      argument :reason, :string
      argument :include_excluded, :boolean, default: false
      argument :limit, :integer, default: 50, constraints: [min: 1, max: 200]
      argument :offset, :integer, default: 0, constraints: [min: 0]
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :unmatched}
    end

    action :list_matched_card_offers, :map do
      description "Audit current automatic English single-card matches, variant, condition and grading. Raw Cardmarket trend plus delivery in PLN is the reference (trend_holo for reverse). Special patterns have no reference. suspicious selects price_ratio < 0.3 or > 3, or an impossible reverse variant. Graded prices include a premium: review grading before changing identity."
      argument :shop, :string
      argument :title, :string
      argument :set, :string
      argument :card, :string
      argument :suspicious, :boolean, default: false
      argument :limit, :integer, default: 50, constraints: [min: 1, max: 200]
      argument :offset, :integer, default: 0, constraints: [min: 0]
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :matched}
    end

    action :list_card_decisions, :map do
      description "Manual single-card assignments and exclusions, including aged offers with current=false. Review or undo with clear_card_decision. Filters combine and paging includes total."
      argument :shop, :string
      argument :title, :string
      argument :set, :string
      argument :limit, :integer, default: 50, constraints: [min: 1, max: 200]
      argument :offset, :integer, default: 0, constraints: [min: 0]
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :decisions}
    end

    action :explain_card_match, :map do
      description "Explain a single-card match by offer_id or title plus optional category: parsed language, condition, grading, variant, printed identity, set evidence and card candidates with name and variant agreement. Non-English cards are excluded; ambiguity is never guessed."
      argument :offer_id, :uuid
      argument :title, :string
      argument :category, :string
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :explain}
    end

    action :search_cards, :map do
      description "Search synced English cards by name words, set id/name/abbreviation and printed number. Returns rarity, variants, Cardmarket id and trend/trend_holo EUR plus delivered reference PLN. Reference does not include grading premiums."
      argument :name, :string
      argument :set, :string
      argument :number, :string
      argument :limit, :integer, default: 50, constraints: [min: 1, max: 200]
      argument :offset, :integer, default: 0, constraints: [min: 0]
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :search}
    end

    action :assign_card_offer, :map do
      description "Assign a single-card offer manually to its exact synced English card (TCGdex id or UUID) and variant normal/reverse/special. A patterned or stamped printing is special, with no reference price. Manual identities survive automatic matching. Atomic write under the singles lock; never recomputes sealed prices."
      argument :offer_id, :uuid, allow_nil?: false
      argument :card, :string, allow_nil?: false

      argument :variant, :atom,
        allow_nil?: false,
        constraints: [one_of: [:normal, :reverse, :special]]

      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :assign}
    end

    action :exclude_card_offer, :map do
      description "Exclude a single-card offer manually, optionally recording why. Automatic matching will leave it excluded. Undo with clear_card_decision. Atomic write under the singles lock."
      argument :offer_id, :uuid, allow_nil?: false
      argument :note, :string, constraints: [max_length: 300]
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :exclude}
    end

    action :clear_card_decision, :map do
      description "Undo a manual single-card decision and immediately re-run automatic matching for that offer. Atomic under the singles lock; sealed prices are unaffected."
      argument :offer_id, :uuid, allow_nil?: false
      run {TcgCheap.Sealed.AgentTools.CardTools, operation: :clear}
    end

    action :shop_status, {:array, :map} do
      description """
      Per configured shop: `last_fetch` (UTC time of the latest successful fetch, null if never),
      `seen` (offers in that fetch), `matched` (of those, assigned to a catalogue product) and
      `matched_in_stock` (current matched offers in stock). #{@current} Start here to see whether
      fetching works and how well each shop matches. Singles have independent singles_seen,
      singles_matched, singles_matched_in_stock and singles_last_fetch fields.
      """

      run ShopStatus
    end

    action :unmatched_offers, :map do
      description """
      Current offers matched to no catalogue product and without a manual decision, sorted by shop
      and title. Each offer has `matcher`: `unmatched` (no product name fits the title),
      `ambiguous` (two equally specific products fit) or `excluded` with the `reason`
      (preorder, bundle of many, damaged, accessory, …; excluded offers are only listed with
      `include_excluded`). `matched` there means the catalogue changed since the last fetch and
      the next recomputation will match it. Returns `total`, `excluded_total`, `limit`, `offset`
      and `offers`. Use explain_match to see why a title does not match, then assign_offer or
      exclude_offer. #{@current}
      """

      argument :shop, :string, description: "Only offers of this shop key (#{@shops})."

      argument :title, :string,
        description: "Only offers whose title contains this text (case and accents ignored)."

      argument :include_excluded, :boolean,
        default: false,
        description:
          "Also list offers whose titles the matcher excludes outright (false by default)."

      argument :limit, :integer,
        default: 50,
        constraints: [min: 1, max: 200],
        description: "Page size, 50 by default."

      argument :offset, :integer,
        default: 0,
        constraints: [min: 0],
        description: "Offers to skip, for the next page."

      run {OfferList, list: :unmatched}
    end

    action :matched_offers, :map do
      description """
      Current offers matched to a catalogue product automatically (manual decisions are listed by
      list_manual_decisions), sorted by shop and title, each with its `product`. Use it to audit
      automatic matches; a wrong one is fixed with assign_offer (right product) or exclude_offer
      (never match). Returns `total`, `limit`, `offset` and `offers`. #{@current}
      """

      argument :shop, :string, description: "Only offers of this shop key (#{@shops})."

      argument :title, :string,
        description: "Only offers whose title contains this text (case and accents ignored)."

      argument :product_id, :uuid, description: "Only offers matched to this product."

      argument :limit, :integer,
        default: 50,
        constraints: [min: 1, max: 200],
        description: "Page size, 50 by default."

      argument :offset, :integer,
        default: 0,
        constraints: [min: 0],
        description: "Offers to skip, for the next page."

      run {OfferList, list: :matched}
    end

    action :manual_decisions, :map do
      description """
      Every offer with a manual decision, current or not, sorted by shop and title: assigned to a
      `product`, or kept unmatched for good when `product` is null. `current` says whether the
      offer is still listed by its shop. Undo a decision with clear_manual_decision. Returns
      `total`, `limit`, `offset` and `offers`.
      """

      argument :shop, :string, description: "Only offers of this shop key (#{@shops})."

      argument :title, :string,
        description: "Only offers whose title contains this text (case and accents ignored)."

      argument :product_id, :uuid, description: "Only offers assigned to this product."

      argument :limit, :integer,
        default: 50,
        constraints: [min: 1, max: 200],
        description: "Page size, 50 by default."

      argument :offset, :integer,
        default: 0,
        constraints: [min: 0],
        description: "Offers to skip, for the next page."

      run {OfferList, list: :manual}
    end

    action :product, :map do
      description """
      One catalogue product by `slug` or `id`: its catalogue data, the public verdict on today's
      market (`status` good/normal/expensive against the median of each in-stock shop's lowest
      price, cardmarket (only compared with the Cardmarket trend when fewer than 3 shops have
      stock, no limits), insufficient_data or out_of_stock; cheapest in-stock offer,
      `shop_prices`, typical price and its source, price limits; good also needs the price at most
      95% of the 30-day usual price and of the Cardmarket trend with shipping when known,
      `good_limits` has each limit), `past`: the same cheapest price against the 30-day history
      (`status` low/usual/high, insufficient_data before 7 days with stock, or out_of_stock; usual
      price, limits, last known price), `preorder` (true when nothing is in stock and the verdict
      rates the pre-order offers instead; `premiere`, the expansion's release day when still to
      come, is when shops ship them), the Cardmarket trend in PLN without and with shipping to
      Poland, every current offer assigned to it, with offer ids, the REBEL `suggested_price`
      matched to it (null when none) and its `contents` (null when unknown).
      """

      argument :slug, :string, description: "The product slug, as in /produkty/{slug}."
      argument :id, :uuid, description: "The product id."

      run ProductDetail
    end

    action :explain_match, :map do
      description """
      Explains how automatic matching decides an offer, given an `offer_id` or a raw `title` (and
      optional `ean`). Returns the `result` (matched/unmatched/ambiguous/excluded) with a
      `summary`, the normalized title, the `tokens` compared with product names, the
      `qualifiers` (kind and language words every matching name must contain) and the closest
      `candidates`, each saying why it does or does not qualify. Rules: every name token must be
      in the title, every title qualifier in the name, at most `max_unexplained` title tokens may
      be absent from the name, the most specific qualifying product wins and a tie stays
      unmatched; a leading Chinese set code in a name ("CBB3C:") is not a name token, and a title
      may name it without it counting as absent (`set_code_tokens`); a product meets some title
      qualifiers without naming them (`met_qualifiers`: its language, "pack" for a single
      booster, "checklane" for a 1-Pack Blister, "slim" for the non-Jumbo product of a set sold
      in both); a "Checklane" title without "Premium" or a pack count must name the blister's
      Pokémon and no other word; a known EAN (product barcode or manual assignment) wins over
      the title; excluded titles never match. It changes nothing.
      """

      argument :offer_id, :uuid, description: "A stored offer to explain."
      argument :title, :string, description: "A raw offer title to explain instead of an offer."
      argument :ean, :string, description: "The EAN that goes with `title`, if any."

      argument :candidates, :integer,
        default: 5,
        constraints: [min: 1, max: 20],
        description: "How many candidate products to explain, 5 by default."

      run ExplainMatch
    end

    action :assign_offer, :map do
      description """
      Manually assigns an offer to a catalogue product (find it with search_products), also
      correcting a wrong automatic match. Its EAN then identifies that product for other shops.
      #{@recomputes} Returns the updated offer.
      """

      argument :offer_id, :uuid, allow_nil?: false
      argument :product_id, :uuid, allow_nil?: false

      run {Decide, decision: :assign}
    end

    action :exclude_offer, :map do
      description """
      Keeps an offer unmatched for good, e.g. after a wrong automatic match or for an item that is
      not in the catalogue. #{@recomputes} Returns the updated offer.
      """

      argument :offer_id, :uuid, allow_nil?: false

      run {Decide, decision: :exclude}
    end

    action :clear_manual_decision, :map do
      description """
      Removes an offer's manual assignment or exclusion and hands it back to automatic matching,
      which decides it again right away. #{@recomputes} Returns the updated offer.
      """

      argument :offer_id, :uuid, allow_nil?: false

      run {Decide, decision: :clear}
    end

    action :set_product_eans, :map do
      description """
      Replaces a product's complete barcode list with verified EAN-13 or UPC-A codes. Read its
      current eans with get_product first and retain any codes you want to keep; [] clears the
      list. Only use codes confirmed for this exact product. Invalid check digits are rejected;
      UPC-A is normalized to EAN-13. Codes claimed by different products identify neither.
      Re-matches offers and recomputes prices in the same transaction. Returns the product.
      """

      argument :product_id, :uuid, allow_nil?: false
      argument :eans, {:array, :string}, allow_nil?: false

      run SetEans
    end

    action :set_product_contents, :map do
      description """
      Replaces what a product holds, shown on its public page: items (boosters with their set,
      every named card such as promo and oversize cards, accessories by type), the https sources
      read and the day they were checked. Record only facts that a publisher page or at least two
      shops agree on, never guesses; omit what you could not confirm. Give each card its TCGdex
      id (tcgdex_id, e.g. svp-085) when you are sure of the exact card: its set, number, picture
      and Cardmarket link are filled in from TCGdex, and an unknown id is rejected. A fixed deck
      (type deck), or a row of fixed cards that is not a ready deck (type card, e.g. a
      deck-building box's cards), may carry its full list in cards: every card with its copies
      and TCGdex id, checked the same way. A random deck (type deck) instead has variants:
      [{name: "Enamorus", cards: [...]}, ...], one per possible deck, with English featured
      Pokémon names. Its quantity is the number of random decks (1 in a Build & Battle Box,
      10 in a Display of 10 boxes), not the number of variants. cards and variants are mutually
      exclusive. Variant cards get the same TCGdex validation and enrichment as fixed cards.
      When TCGdex has no picture of a card (image null, e.g. basic Energy), give it a photo
      checked by eye to show that printing, on an allowed image host.
      Record only known cards even if the publisher's list is incomplete (e.g. 39 cards).
      Read the current contents with get_product first. contents null removes them. Returns the product
      with its contents.
      """

      argument :product_id, :uuid, allow_nil?: false
      argument :contents, TcgCheap.Sealed.ProductContents

      run SetContents
    end

    action :set_product_photo, :map do
      description """
      Sets or clears a product's photo, shown on its page, in search results and in link previews,
      for a product whose shop photos are missing, tiny or wrong. Give only a photo you checked by
      eye shows this exact product in its edition (language, version), large and sharp, ideally
      the publisher's or a retailer's packshot, as an https url on an allowed image host. The
      photo is copied to our storage in the background (within 10 minutes) and then replaces the
      shops' photos. url null goes back to the shops' photos. Returns the product.
      """

      argument :product_id, :uuid, allow_nil?: false
      argument :url, :string, description: "The https photo; null goes back to the shops' photos."

      run SetPhoto
    end

    action :set_pull_rates, :map do
      description """
      Replaces a set's pull rates, shown on the page of its English single booster: how often a
      pack holds each rarity, as estimated by people who opened many packs (never official
      numbers). Find the set by its English TCGdex id or name. Give cards_per_pack when a source
      says it; one rate per rarity, named as TCGdex names the set's cards (a TCGdex rarity the
      set's cards lack is rejected; other rows such as "Reverse Rare" pass), its per_pack in one
      of the forms "1 in 5", "about 1 in 12", "1 in 1,081", "3 per pack" or "5.39% (20 of 371
      packs)", optionally the percent per pack, and card (its TCGdex name) when the rate is for
      that one card rather than the whole rarity; every https source read, with sample_packs
      (packs opened) when it says and data_from when it cites someone else's data (e.g.
      TCGplayer); and the day they were checked. Until a new set's own estimates are out, the
      estimates of the previous comparable set may stand in, with borrowed_from naming that set;
      the page then says they are unverified for this set. Record only estimates a source states, never
      guesses. Unknown keys are rejected. pull_rates null removes them. Rates are refused for a
      set without cardmarket_expansion_id (it has no booster page) and until the cards of every
      English set of its expansion are synced. Returns the set with its pull rates.
      """

      argument :set, :string,
        allow_nil?: false,
        description: "The English TCGdex set id (e.g. sv09) or name (e.g. Journey Together)."

      argument :pull_rates, TcgCheap.Sealed.PullRates

      run SetPullRates
    end

    action :record_unofficial_set_cards, :map do
      description """
      Records the card list of a new English set TCGdex does not list yet (before or right after
      its release), shown on its booster pages as unofficial and possibly changing, from a
      published full set list such as a fan wiki's (source_url, the page read). Give the set id
      TCGdex will use (e.g. me06 after me05; check TCGdex's open pull requests), the name its
      boosters carry, the Cardmarket expansion id of its sealed products, the release day and
      every card with its collector number as TCGdex writes it ("001"), English name and
      rarity as TCGdex spells it. Record only a list a source publishes, never guesses. TCGdex's
      cards replace this list once TCGdex lists as many, or two weeks after release; a set
      whose TCGdex cards are copied is refused. Returns the set.
      """

      argument :set, :string, allow_nil?: false, description: "The TCGdex set id, e.g. me06."
      argument :name, :string, allow_nil?: false, description: "The set's English name."

      argument :abbreviation, :string,
        constraints: [match: ~r/\A[A-Z0-9]+\z/],
        description:
          "The set's official code as printed on its cards (e.g. DLR), which Limitless TCG names its card scans by; without it the cards show no pictures until TCGdex lists them. Give it only when the list's numbers are the printed ones and the code is this set's own (check limitlesstcg.com/cards/<code>); left out, a code recorded before stays."

      argument :expansion_id, :integer,
        allow_nil?: false,
        constraints: [min: 1],
        description: "The Cardmarket expansion id of the set's sealed products."

      argument :released_on, :date, allow_nil?: false, description: "The release day."
      argument :source_url, :string, allow_nil?: false, description: "The https page read."

      argument :cards, {:array, :map} do
        allow_nil? false

        constraints min_length: 1,
                    items: [
                      fields: [
                        number: [type: :string, allow_nil?: false],
                        name: [type: :string, allow_nil?: false],
                        rarity: [type: :string]
                      ]
                    ]
      end

      run RecordUnofficialCards
    end

    action :set_expansion_logo, :map do
      description """
      Sets or clears the logo of a Cardmarket expansion (the cardmarket_expansion_id of its
      products, from search_products or get_product), shown on its tile in the public expansion
      filter. Give only a logo you checked by eye is this expansion's, in its edition (a Japanese
      set's own logo, not its English counterpart's): `url` the image, on an allowed image host,
      `page` the https page it was found on and `checked_on` the day. An English TCGdex logo,
      when there is one, is shown instead. The image is copied to our storage in the background
      and shown once copied. url null clears the logo. Returns the expansion's logo.
      """

      argument :expansion_id, :integer,
        allow_nil?: false,
        constraints: [min: 1],
        description: "The Cardmarket expansion id."

      argument :url, :string, description: "The https logo image; null clears the logo."
      argument :page, :string, description: "The https page the logo was found on."
      argument :checked_on, :date, description: "The day the logo was checked."

      run SetExpansionLogo
    end

    action :enqueue_shop_fetch, :map do
      description """
      Queues a background fetch of one shop's product feed; it upserts the offers, re-matches every
      offer and recomputes prices. Returns the job; `already_queued` is true when a fetch of that
      shop was already waiting or running. Check shop_status afterwards.
      """

      argument :shop, :string, allow_nil?: false, description: "The shop key (#{@shops})."

      run {Enqueue, job: :shop_fetch}
    end

    action :enqueue_catalogue_import, :map do
      description """
      Queues a background import of the Cardmarket sealed catalogue and prices (also run daily). New
      products are matched at the next shop fetch. Returns the job; `already_queued` is true when an
      import was already waiting or running.
      """

      run {Enqueue, job: :catalogue_import}
    end

    action :enqueue_card_sync, :map do
      description """
      Queues a background copy of the TCGdex set cards (also run daily), needed by singles
      matching and set_pull_rates, then looks up the Cardmarket product ids of cards
      without one (about a thousand per run), which link booster pages' cards to Cardmarket and
      their prices. One run stops after five minutes; queue another while sets remain unsynced or
      cards lack ids. Returns the job; `already_queued` is true when a copy was already waiting or
      running.
      """

      run {Enqueue, job: :card_sync}
    end

    action :suggested_prices, :map do
      description """
      Suggested retail prices (SCD, gross PLN) collected from the REBEL wholesaler's public
      catalogue, every item ever seen, sorted by title, each with its matched `product` (null when
      none), `manual` (a manual decision; with no product it never matches) and `last_seen_at`
      (REBEL lists only its current range). The SCD is shown on the matched product's page.
      Automatic matching only matches English products, and items of several units only when
      named a display. Returns `total`, `limit`, `offset` and `items`.
      """

      argument :title, :string,
        description: "Only items whose title contains this text (case and accents ignored)."

      argument :unmatched, :boolean,
        default: false,
        description: "Only items with no product and no manual decision (false by default)."

      argument :limit, :integer,
        default: 50,
        constraints: [min: 1, max: 200],
        description: "Page size, 50 by default."

      argument :offset, :integer,
        default: 0,
        constraints: [min: 0],
        description: "Items to skip, for the next page."

      run {SuggestedPrices, action: :list}
    end

    action :decide_suggested_price, :map do
      description """
      Manually assigns a REBEL suggested price item to the catalogue product it is (find it with
      search_products), also correcting a wrong automatic match; without `product_id` the item
      never matches. Only assign the exact product: a display of several units belongs to a
      Cardmarket product of that many units. An assigned item's EAN then identifies the product
      for shops' offers. #{@recomputes} Returns the updated item.
      """

      argument :suggested_price_id, :uuid, allow_nil?: false
      argument :product_id, :uuid, description: "The product; null keeps the item unmatched."

      run {SuggestedPrices, action: :decide}
    end

    action :enqueue_suggested_price_fetch, :map do
      description """
      Queues a background collection of REBEL's suggested retail prices (also run daily); it stores
      the listed items and matches them again. Returns the job; `already_queued` is true when one
      was already waiting or running.
      """

      run {Enqueue, job: :suggested_prices}
    end
  end
end
