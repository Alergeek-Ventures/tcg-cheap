defmodule TcgCheap.Cards.AgentTools do
  @moduledoc """
  Actions behind the MCP tools for the daily singles review (see the `tools`
  of `TcgCheap.Cards`): unmatched, matched and decided single-card offers,
  match explanations, card search and manual decisions, set pull rates and
  unofficial card lists. They store nothing themselves.
  """

  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Cards

  alias TcgCheap.Cards.AgentTools.{RecordUnofficialCards, Review, SetPullRates}

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
      run {Review, operation: :unmatched}
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
      run {Review, operation: :matched}
    end

    action :list_card_decisions, :map do
      description "Manual single-card assignments and exclusions, including aged offers with current=false. Review or undo with clear_card_decision. Filters combine and paging includes total."
      argument :shop, :string
      argument :title, :string
      argument :set, :string
      argument :limit, :integer, default: 50, constraints: [min: 1, max: 200]
      argument :offset, :integer, default: 0, constraints: [min: 0]
      run {Review, operation: :decisions}
    end

    action :explain_card_match, :map do
      description "Explain a single-card match by offer_id or title plus optional category: parsed language, condition, grading, variant, printed identity, set evidence and card candidates with name and variant agreement. Non-English cards are excluded; ambiguity is never guessed."
      argument :offer_id, :uuid
      argument :title, :string
      argument :category, :string
      run {Review, operation: :explain}
    end

    action :search_cards, :map do
      description "Search synced English cards by name words, set id/name/abbreviation and printed number. Returns rarity, variants, Cardmarket id and trend/trend_holo EUR plus delivered reference PLN. Reference does not include grading premiums."
      argument :name, :string
      argument :set, :string
      argument :number, :string
      argument :limit, :integer, default: 50, constraints: [min: 1, max: 200]
      argument :offset, :integer, default: 0, constraints: [min: 0]
      run {Review, operation: :search}
    end

    action :assign_card_offer, :map do
      description "Assign a single-card offer manually to its exact synced English card (TCGdex id or UUID) and variant normal/reverse/special. A patterned or stamped printing is special, with no reference price. Manual identities survive automatic matching. Atomic write under the singles lock; never recomputes sealed prices."
      argument :offer_id, :uuid, allow_nil?: false
      argument :card, :string, allow_nil?: false

      argument :variant, :atom,
        allow_nil?: false,
        constraints: [one_of: [:normal, :reverse, :special]]

      run {Review, operation: :assign}
    end

    action :exclude_card_offer, :map do
      description "Exclude a single-card offer manually, optionally recording why. Automatic matching will leave it excluded. Undo with clear_card_decision. Atomic write under the singles lock."
      argument :offer_id, :uuid, allow_nil?: false
      argument :note, :string, constraints: [max_length: 300]
      run {Review, operation: :exclude}
    end

    action :clear_card_decision, :map do
      description "Undo a manual single-card decision and immediately re-run automatic matching for that offer. Atomic under the singles lock; sealed prices are unaffected."
      argument :offer_id, :uuid, allow_nil?: false
      run {Review, operation: :clear}
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

      argument :pull_rates, TcgCheap.Cards.PullRates

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
      rarity as TCGdex spells it, and once Cardmarket lists the set's singles each card's
      Cardmarket product id, which gives it its Cardmarket page and price. Record only a list a
      source publishes, never guesses; the list is recorded whole, so send every card again.
      TCGdex's cards replace this list once TCGdex lists as many, or two weeks after release; a
      set whose TCGdex cards are copied is refused. Returns the set.
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
                        rarity: [type: :string],
                        cardmarket_id: [
                          type: :integer,
                          constraints: [min: 1],
                          description:
                            "The card's Cardmarket product id (its Cardmarket page and price), from Cardmarket's singles of the set's expansion; give it only when sure it is this printing (same number, name and rarity, e.g. its price matches Limitless TCG's for the card). Left out, the card has none until TCGdex lists the set."
                        ]
                      ]
                    ]
      end

      run RecordUnofficialCards
    end
  end
end
