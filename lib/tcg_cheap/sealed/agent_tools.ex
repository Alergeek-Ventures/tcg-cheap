defmodule TcgCheap.Sealed.AgentTools do
  @moduledoc """
  Actions behind the MCP tools for AI agents (see the `tools` of
  `TcgCheap.Sealed`): shop status, offer lists, product detail, match
  explanations, manual decisions, product barcodes and contents, REBEL
  suggested prices and fetch/import jobs.
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
    SetContents,
    SetEans,
    ShopStatus,
    SuggestedPrices
  }

  alias TcgCheap.Sealed.Shops

  @shops Enum.join(Shops.keys(), ", ")
  @current "An offer is current while it was in its shop's latest fetch and that fetch is at most 3 days old."
  @recomputes "Manual decisions are never overwritten by automatic matching. Prices, availability and today's daily prices are recomputed in the same transaction, which can take a few seconds."

  actions do
    action :shop_status, {:array, :map} do
      description """
      Per configured shop: `last_fetch` (UTC time of the latest successful fetch, null if never),
      `seen` (offers in that fetch), `matched` (of those, assigned to a catalogue product) and
      `matched_in_stock` (current matched offers in stock). #{@current} Start here to see whether
      fetching works and how well each shop matches.
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
      One catalogue product by `slug` or `id`: its catalogue data, the public verdict (`status`
      good/normal/expensive, cardmarket (only compared with the Cardmarket trend before 7 days of shop prices, no limits), insufficient_data or out_of_stock, cheapest in-stock offer, typical price
      and its source, price limits), every current offer assigned to it, with offer ids, the
      REBEL `suggested_price` matched to it (null when none) and its `contents` (null when unknown).
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
      unmatched; a known EAN (product barcode or manual assignment) wins over the title; excluded titles never
      match. It changes nothing.
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
      promo and oversize cards by name, accessories), for a fixed deck its full card list, the
      https sources read and the day they were checked. Record only facts that a publisher page
      or at least two shops agree on, never guesses; omit a field you could not confirm and leave
      deck [] unless every card is known. Look up cards in TCGdex for tcgdex_id and image. Read
      the current contents with get_product first. contents null removes them. Returns the
      product with its contents.
      """

      argument :product_id, :uuid, allow_nil?: false
      argument :contents, TcgCheap.Sealed.ProductContents

      run SetContents
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
      for shops' offers and the public scanner (automatic matches only serve the scanner).
      #{@recomputes} Returns the updated item.
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
