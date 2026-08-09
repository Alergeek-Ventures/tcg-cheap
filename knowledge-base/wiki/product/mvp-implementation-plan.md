# Pokémon Market & Trade Platform — Detailed MVP Implementation Plan

- Updated: 2026-08-09
- Sources: Product specification supplied by project owner
- Raw: N/A — product specification

**Status:** **Current product north star.** Unless the product owner explicitly supersedes this article, every requirement, implementation phase, documentation deliverable, and acceptance criterion listed below is authoritative and must be completed in full. Phase 3 trade/share is complete. Phase 4 now has source-neutral product/alias/retailer/listing/mapping/observation foundations, an explicitly unconfigured fixture-backed LootQuest adapter and atomic unique refresh path, an authenticated administrator review desk, and a local-only public Sealed search/detail foundation. Phase 5 now has a local-only versioned daily aggregate foundation, the pure provisional `sealed_buying_model_v1`, and persisted versioned buying-guide snapshots/recomputation: one fresh offer per retailer, median/Tukey-IQR benchmark and range, retained history, deterministic fixed Decimal policy, explicit confidence/limited reasons, and four calculated buying intervals. Daily aggregate persistence atomically enqueues jobs identified by the exact current and preceding 30-day revisions, and historical corrections cascade through affected following guide dates; local snapshot reads retain model outputs and factors. Honest current/stale/cached public aggregate states are implemented, but public buying bands/explanations and the sealed graph are not. A fail-closed request-level acquisition-budget foundation covers every in-tree operational TCGdex catalogue, TCGdex Cardmarket, NBP, and sealed-retailer request with provider/global UTC counters, estimated-spend caps, and persisted provider kill switches. Written production source permission, real sealed data and model validation, actual-cost reconciliation, per-IP acquisition throttling, source health/operational admin, AshBackpex CRUD/operations, the sealed 30-day graph, and public buying-guide rendering remain incomplete. The overall MVP is not complete.
**Audience:** Long-running implementation agent

## Product-owner autocomplete quality correction — 2026-08-08 — Implemented

The owner-reported focus-loss blocker is corrected. The minimal plain collector UI, approved colors/fonts and warm square direction, exact-printing identity, pricing honesty, and clear CTA remain intact. The former form-level `phx-change`/form-reassignment path was replaced by a shared external 250ms input hook used by Home and Trade: the focused input is never server-value patched, so query, input node, focus, caret/selection survive result updates. IME composition blocks search and searches once after compositionend; Escape cancels pending debounce.

The implemented autocomplete uses real combobox/listbox semantics: `aria-expanded`, `aria-controls`, `aria-activedescendant`, direct streamed `role=option` children, stable `card-option-UUID` IDs, a bounded max-10 result set, and records retained only to reinsert prior/next stream items when the active assign changes. Exactly one active/`aria-selected` option is visible. ArrowUp/ArrowDown wrap, the first result is visibly active, Enter selects the exact active printing, Escape closes while retaining query/focus, and validated option click/touch follows the same navigation. Accessible option names reference visible name/set/rarity/price/update IDs; there is no nested interactive control. Query-specific live status changes even when the count is unchanged.

The active option is visibly ruled. The bounded listbox is `min(45svh, 32rem)` and scrolls internally; the hook keeps the active option in view without moving page scroll or the input away. Provider calls remain out of request paths and local/cached reads plus background acquisition boundaries remain intact.

Validation is complete: focused Home tests plus the canonical `direnv exec . mix check --verbose` passed with 222 tests, with 0 Dialyzer errors, no Credo issues, and Ash codegen, Sobelow, format, compile, xref, unused-dependency, assets, and static checks passing. Acquisition regression tests are included. Focused acquisition/trade/valuation/composition/bulk/Home/CardDetail coverage passed with 76 tests, and all web tests passed with 46 tests. Final read-only code review was clean to commit with no findings after deterministic search-error/live-region component coverage was added. Real desktop typing entered `Scrollcheck` one character at a time with 400ms/server updates after each character, preserving every prefix, the same input node, focus, caret, and mid-string insertion. Mobile preserved character-by-character focus/caret with no horizontal overflow. Browser composition-event simulation did not search during composition and searched once after compositionend while preserving focus/caret; this is not a claim about a native IME.

The ten-option Arrow navigation kept exactly one selection, input focus, internal listbox scrolling, page `scrollY` 0, and input visibility; Enter navigated the exact active ID. Escape canceled pending debounce, retained `ScrollcheckX`/focus, and stayed closed after 650ms. No console errors occurred. The detector found only the two known explicit-square 3px border false positives plus advisories; JSON/wiki lint passed. This does not add dead trade/sealed controls or narrow the remaining MVP work.

The correction is complete for this blocker. Phase 3 trade/share is now complete below; the NBP EUR/PLN backend/local cache and public conversion/share behavior are implemented. The overall MVP remains incomplete and sealed catalogue/acquisition is next.

## Phase 3 trade/share batch — Complete — 2026-08-08

Steps 1–3 and the EUR, stale/unvalued/incomplete, acquisition, and responsive foundations are implemented at public `/trade` inside Singles. State is URL-only and deterministic: stable TCGdex IDs and quantities in `left=id:qty,...&right=id:qty,...`, with no names, prices, internal UUIDs, or server trade records. Parsing is bounded and safe (validated IDs/quantities, duplicate merge/cap, deterministic sorting, malformed/truncated metadata); unknown valid IDs remain removable and unpriced. `handle_params` restores state, every mutation uses `push_patch`, selection requires one local search plus explicit add-left/add-right, and untrusted events cannot inject rows.

The surface uses one bulk Ash local read (maximum 100 IDs) with the card set and current `tcgdex_cardmarket_v1` valuation preloaded. Pure `TcgCheap.Trades.Valuation` calculates Decimal EUR unit/row/side/difference values, counts unknown/unvalued rows, includes stale values, and marks incomplete estimates. Missing/stale rows render first and use `ValuationAcquisition.subscribe_and_request_many` for bounded canonical bulk acquisition; subscription precedes unique Oban jobs, with no request-path HTTP. PubSub completion bulk-reloads/recalculates; failure retains stale estimates. Search/pick alone does not enqueue.

The shared external `CardAutocomplete` hook now serves Home and Trade while preserving query/node/focus/caret/composition behavior. CardDetail offers `Add to a trade` as a side-neutral pending pick and only accepts a reconstructed local `/trade` return target. Trade rows expose exact identity, current EUR, relative update labels, stale/outdated, fetching/failure, and incomplete `€x + ? (N unpriced)` evidence. Desktop sides are columns; mobile sides stack; controls are square and at least 44px with no 390px overflow.

The NBP EUR/PLN backend batch is implemented: an AshPostgres `ExchangeRate` stores one canonical NBP Table A EUR/PLN observation per effective date with positive Decimal rate, publication number, and fetched timestamp; same-date upserts refresh the observation and history is retained. `ExchangeRateProvider.Result` and strict `NbpExchangeRate` normalize the official HTTPS endpoint, Decimal JSON, future/shape validation, and tagged errors. `ExchangeRateWorker` runs with queue concurrency 1, active-state uniqueness, retry/cancel/PubSub behavior, and static `0 15 * * *` UTC scheduling; `ExchangeRateAcquisition` subscribes before enqueueing and limits freshness fetches to once per UTC day, carrying forward weekends/holidays. TradeLive reads the latest cached rate locally, subscribes once per connected LiveView before enqueue, consumes completion/failure, retains cached conversion while pending/failed, and rejects malformed/noncanonical/nonfinite/future/older messages. Generated migration/snapshot output was applied and reviewed. The live official adapter smoke observed 4.3010 on 2026-08-07, publication `152/A/NBP/2026`. No HTTP runs in public request paths.

Phase 3 is complete. Unit/row prices remain EUR; side totals show EUR plus Decimal PLN, incomplete known subtotals show both currencies plus `?`, and complete difference shows EUR plus PLN while incomplete difference remains explicit. Visible NBP evidence includes exact `1 EUR = … PLN`, effective date, relative age, and pending/failed/no-cache states. `TradeShare` copies an absolute URL from server-derived canonical `Composition.to_path`, with only stable IDs/quantities and no names, prices, UUIDs, pick/unknown parameters, fragments, or noncanonical ordering. Clipboard fallback cleans up, restores focus, protects overlapping/destroyed instances, and ignores stale/malformed async results. At this Phase 3 checkpoint Sealed remained unavailable; the later Phase 4 public foundation is recorded below. No public auth, server trade persistence, or snapshot pricing exists.

Validation for the completed batch: focused TradeLive coverage passed with 26 tests; assets build passed; canonical `direnv exec . mix check --verbose` passed 258 tests with Ash codegen, Sobelow, format, compile, unused, xref, Credo, and Dialyzer all clean (0 Dialyzer, no Credo). Detector findings were the two known explicit square 3px border false positives plus legacy/design-system advisories; new evidence typography is aligned to `.75rem`. Browser desktop 1008px and mobile 390px checks with long names/large totals showed no overflow, sampled controls were at least 44px, exact rate/PLN was visible, and Clipboard API/fallback behavior and failure feedback were correct with no console errors/warnings. Temporary browser records/rates/jobs were deleted and verified zero; final code review was clean.

## Product-owner course correction — 2026-08-08

The product owner has issued a newer authoritative correction to the public product direction. The product has exactly two top-level customer features: **(1) Sealed product price comparison** and **(2) Singles price comparison**, including the ability to compose a trade and calculate the difference. Trade is part of Singles, not a third equal homepage product category. The audience is ordinary, simple collectors, not market-data or technical users.

The current Home remains too wordy and too technical for simple collector tasks. Internal evidence, policy/provider, freshness, local-data, IDs, and long explanations must not dominate the primary path. Home must be minimal, use plain collector language, and present the fewest words needed for simple actions and states. Primary CTA hierarchy should help a collector search/select, compare a price, or add a single to a trade. Prefer states such as `Price unavailable` or `Updated …` over internal jargon. Preserve legal and methodology honesty, exact-printing correctness, accessibility, and required caveats, but move technical details and methodology into concise secondary disclosure wherever feasible instead of repeating them in the task path.

The current colors, fonts, and warm square visual direction are approved and should be retained. This correction targets information density, copy, jargon, and CTA clarity, not another visual-system replacement. Do not add dead controls or imply unavailable sealed/trade capability before implementation. The just-built Home remains a functional foundation but is not product-finished; its wording and density are historical/current-code evidence to simplify, not copy to preserve.

This correction supersedes only conflicting homepage wording, density, information-architecture, and CTA guidance below; it does not delete or narrow the original detailed requirements, domain scope, acceptance criteria, or implementation phases. All exact-printing, pricing honesty, methodology, legal, accessibility, sealed, and trade requirements remain authoritative and must still be completed in full.

## Product-owner course correction — 2026-08-07

The product owner has made two authoritative current decisions. First, TCGdex imagery is approved for the MVP. The owner accepts the pragmatic product risk because TCG Cheap is clearly unofficial/non-affiliated and is positioned as a review, comparison, and decision-support site. This is a product-risk decision, not a legal conclusion or a claim that the underlying artwork is independently licensed. Current code commit `52a9c0d` hotlinks only canonical `https://assets.tcgdex.net` URLs through a strict `CardImage` boundary, uses high WebP on detail and low WebP in search, sends no-referrer, allows the exact host in CSP, and provides no proxy/cache; missing or invalid images use an honest fallback. The visible disclaimer names Pokémon, Nintendo, TCGdex, Cardmarket, and listed companies. Third-party artwork rights are not independently proven, and broader reuse or self-hosting is not approved by this decision.

Second, correcting the homepage is the highest-priority active public-UI goal. The current `Printing Archive`, “Find the printing. Keep the name.”, “quiet local index”, oversized archive intro, and result-wall framing over-position the product as a catalogue/archival identifier. The actual promise is decision support: understand a singles estimate, judge trade fairness, and decide whether sealed product is a good buy in Poland. Exact-printing search is an enabling step, not the product thesis. The homepage should make Singles the default, offer a Sealed-products mode, provide a direct search/select action, show result identity with image, and make next actions clear (including the current estimate and adding to the completed trade/share flow). It must not add dead controls or imply unavailable sealed behavior; unsupported modes and states must remain honest while being built. Search/results and useful actions should win the first viewport, without preserving the oversized intro below which results sit. Preserve robust local search, exact identity, accessibility, and archive visual materials where they serve the task, but not archive metaphor/copy/layout merely because it is polished. Prioritize product promise, CTA clarity, and playable flows over ornamental polish. Subsequent roadmap agents should retain this correction while the current Home surface continues to evolve; the Phase 3 EUR/PLN trade/share batch is complete and Phase 4 sealed catalogue/acquisition is next.
**Primary market:** Poland
**Interface language:** English
**Working title:** Pokémon Market MVP

---

## 1. Mission

Build a new, production-capable MVP that helps Pokémon TCG buyers in Poland answer two questions:

1. **Is this sealed Pokémon product a good buy at the price I am seeing?**
2. **Is this trade of individual cards reasonably balanced?**

The implementation must be a single Phoenix application using Elixir, Phoenix LiveView, Ash Framework, PostgreSQL, and Oban. It must be inexpensive to operate on a single VPS and must keep external data-acquisition costs below a hard monthly budget of **US$50**, excluding hosting.

The implementation agent is expected to complete the application end to end: research data sources, scaffold the project, build the domain, implement background acquisition, create the public UI and admin UI, test it, document it, and leave it deployable.

Do not return ordinary implementation questions to the product owner when the answer can be derived from this specification, the reference projects, real data, or a bounded technical experiment. When an implementation choice remains intentionally open, investigate it, choose the best option within the stated constraints, and record the decision.

---

## 2. Reference projects and precedence

The agent will have access to two local Ash Framework projects:

- **Firmowid**
- **Onside**

Before writing application code, inspect both projects, including their READMEs, local agent instructions, skills, dependencies, libraries, conventions, test setup, deployment setup, and architectural patterns.

### 2.1 Precedence rules

1. **Firmowid is the primary reference** for:
   - Phoenix project structure
   - LiveView architecture
   - layouts and components
   - forms and validation
   - Ash usage
   - authentication and authorization conventions
   - styling and assets
   - testing
   - deployment and operations

2. **Onside is a secondary reference** for:
   - Ash resource design
   - reusable libraries
   - domain patterns
   - project documentation
   - skills and agent guidance
   - operational patterns not present in Firmowid

3. Onside contains SPA-oriented parts. **Do not copy its SPA architecture.** The public application must remain Phoenix LiveView-only.

4. Reuse conventions and abstractions, not business-specific code.

5. Prefer dependency versions and patterns already proven in Firmowid unless there is a documented compatibility, security, or maintenance reason to diverge. Pin compatible versions.

6. Create this platform as its own application. Do not modify Firmowid or Onside except when explicitly needed to inspect them.

---

## 3. Hard constraints

### 3.1 Technology

- Elixir
- Phoenix
- Phoenix LiveView for all public user-facing functionality
- Ash Framework for domain resources, actions, authorization, and persistence boundaries
- AshPostgres / PostgreSQL
- Oban for scheduled and on-demand background work
- AshBackpex for the main internal admin CRUD interface
- One deployable Phoenix application; no separate SPA or frontend repository
- Small JavaScript hooks are allowed only where LiveView alone is unsuitable, such as chart rendering or focused URL synchronization

### 3.2 Product and market

- Poland-only market for the MVP
- English-only interface for the MVP
- Public site; no public user accounts
- Mobile-first and responsive
- Desktop fully supported
- No native app
- No PWA or offline mode

### 3.3 Cost

- Hard monthly cap of **US$50 for external data acquisition**
- The cap includes paid APIs, scraping services, proxies, and similar acquisition costs
- The cap does not include the VPS, database, or normal application hosting
- Stale or missing data is preferable to silently exceeding the cap

### 3.4 Data integrity

- Public requests must primarily read from the platform’s own database
- External providers must not be called synchronously in the normal page-render path
- Never fabricate production data
- Keep all acquired observations and snapshots indefinitely
- Do not make a more expensive provider request solely to obtain extra raw detail when a cheaper aggregate request is sufficient for the MVP

---

## 4. Product scope

The product has two related but technically separate pricing domains.

### 4.1 Sealed products

A sealed product is an official Pokémon TCG SKU distributed in Poland, such as:

- booster packs
- sleeved boosters
- booster bundles
- booster boxes
- Elite Trainer Boxes
- tins
- collection boxes
- decks
- trainer toolkits
- other released official Pokémon TCG SKUs

The sealed-product feature provides Polish retail market context, price history, availability, current offers, and dynamic buying ranges.

### 4.2 Singles

A single is one exact Pokémon card printing, identified primarily by its set and collector number, with enough metadata to distinguish materially different printings.

The singles feature provides an honest, aggregate Cardmarket-derived estimate for common in-shop Pokémon trades, a 30-day valuation graph when observations accumulate, and the values used by the trade calculator. This is thesis validation, not seller-level market intelligence.

### 4.3 Important boundary

Sealed products and singles may share UI primitives and historical-data conventions, but they must not share pricing logic or source-specific storage models. Retailer prices for sealed products and marketplace valuations for individual cards are different domains.

---

## 5. Explicit MVP non-goals

Do not include the following in the MVP:

- public accounts
- watchlists
- alerts or notifications
- saved server-side trade sessions
- price snapshots frozen into shared trade links
- editable singles pricing presets
- user-selectable pricing settings
- per-card language or condition overrides
- shipping-cost calculations
- barcode scanning
- retailer URL parsing
- native mobile applications
- PWA or offline behavior
- preorders
- Japanese sealed products or fringe imports not officially distributed in Poland
- collector-grade precision for every minor finish variant
- a separate public JSON API unless an integration truly requires it
- an external search engine unless PostgreSQL search proves inadequate with the real catalogue

The design may preserve extension points for these features, but they must not add visible MVP complexity.

---

## 6. Core users and journeys

### 6.1 Sealed-product buyer

The user is standing in a card shop or looking at an online listing. They know the product name and want to determine whether the observed price is sensible.

MVP journey:

1. Open the site on a phone or desktop.
2. Switch search mode to **Sealed products**.
3. Type the product name.
4. Select the canonical product from autocomplete.
5. View:
   - MSRP / recommended retail price when known
   - current market benchmark
   - dynamic buying ranges
   - 30-day trend graph
   - typical market range
   - availability context
   - current shop offers and links
   - explanation of why the ranges are what they are
6. Compare the shop or listing price mentally with the displayed ranges.

The MVP does **not** require the user to type the candidate price into a separate evaluator.

### 6.2 Single-card lookup

1. Open the site.
2. Use the default **Singles** search mode.
3. Type a card name.
4. Select the exact printing using image, set, collector number, and other distinguishing metadata.
5. View the current estimate, 30-day history when available, price methodology, data age, and stale/limited state.
6. Add the card to a trade.

### 6.3 Trade calculator

1. Open the trade calculator or start it from a card page.
2. Search for an exact card printing in one shared search bar.
3. Select the card.
4. Confirm using one of two buttons:
   - add to the left side
   - add to the right side
5. Repeat for all cards.
6. Adjust quantities.
7. Review both side totals and the difference.
8. Copy the URL and share it.

On mobile, the two sides are stacked vertically. On desktop, they are side by side.

---

## 7. Information architecture and public pages

### 7.1 Homepage

The homepage should feel like a focused search surface rather than a marketing landing page.

**Superseding 2026-08-08 homepage guidance:** Make the first path minimal and collector-readable. Keep only the words and controls needed to search/select and take the next available action. Singles is the default; sealed comparison is the other top-level customer feature. Trade entry belongs inside Singles and must not be presented as a third equal homepage category. Use clear CTAs and plain states such as `Price unavailable` and `Updated …`; put policy/provider, freshness, local-data, IDs, and longer methodology explanations behind concise secondary disclosure where feasible. Preserve the detailed identity, evidence, caveat, accessibility, and exactness requirements below, but do not let their technical labels dominate the task path. The approved warm square visual direction, colors, and fonts remain in force. The autocomplete must also preserve typing focus, caret/selection, and IME composition while results update; its complete keyboard, touch, stable-ID, visible-active-option, and screen-reader behavior is a release blocker, not optional polish.

Required structure:

1. Large central search field
2. Mode switch directly below or adjacent to the search field:
   - **Singles**
   - **Sealed products**
3. Singles is the default mode
4. Fast autocomplete as the user types
5. Primary results come only from the selected category
6. If there are no strong matches in the selected category, show clearly separated suggestions from the other category
7. Do not casually mix weak singles and sealed-product matches in one undifferentiated list

Secondary homepage content:

- biggest recent price changes
- recent released sealed products
- optionally recently updated or active items when the data is meaningful

Keep homepage discovery concise. A single fixed recent-change window is sufficient; do not add filters or date controls in the MVP.

### 7.2 Search result identity

Singles results should display enough information to distinguish exact printings:

- card image thumbnail
- card name
- set name or code
- collector number
- rarity when useful
- material variant badge when required

Sealed results should display:

- product image when available
- canonical product name
- product type
- series/set
- release date when useful

### 7.3 Single-card page

Required content:

- card image
- canonical name
- set
- collector number
- rarity and legality metadata when available
- current valuation in EUR
- data freshness or stale status
- source and selected metric/methodology; seller/offer count is unavailable from the active aggregate source and must not be fabricated
- exact methodology explanation
- fixed 30-day price graph
- action to start or continue a trade with this card

If pricing is missing or stale, the page renders immediately and initiates the background behavior described later.

### 7.4 Sealed-product page

Required content:

- product image
- canonical product name
- product type
- release date
- MSRP/RRP in PLN when known
- current market benchmark
- one of:
  - four buying bands, or
  - **Limited data**
- concise human-readable explanation
- fixed 30-day graph
- current offer list
- recently sold-out context
- last-updated information
- visible note that shipping is excluded in the MVP

### 7.5 Trade calculator page

Required behavior:

- one global card autocomplete field
- after selecting a card, two explicit add buttons for left and right
- identical cards on the same side merge into one row
- re-adding a card increments quantity
- quantity controls are available on each row
- row value equals unit valuation multiplied by quantity
- each row can open the corresponding card’s detailed valuation without losing the trade state
- mobile layout is vertical
- desktop layout is horizontal / two-column
- clear stale and unvalued states
- copyable share URL

Recommended neutral labels are **Left side** and **Right side** unless Firmowid conventions suggest clearer copy. Avoid assuming which side belongs to the current user in a shared URL.

---

## 8. Canonical catalogues

### 8.1 Card catalogue

The long-term target is every card that can be matched reliably to Cardmarket or the chosen Cardmarket-derived source.

MVP requirements:

- import the full available catalogue from the selected metadata provider when affordable and practical
- support all legality values provided by the source
- do not limit public search to Standard-only cards
- current or Standard-legal cards may receive a ranking boost, but older cards remain searchable
- treat each exact printing as a distinct catalogue entity
- preserve external source identifiers
- preserve set, collector number, rarity, legalities, regulation mark, images, and other matching metadata
- retain cards after rotation

Use TCGdex for the MVP metadata/catalogue and embedded Cardmarket aggregate pricing where available. Pokémon TCG API may remain a fallback/cross-check. Verify coverage, licensing, exact-printing fidelity, image reliability, and mapping suitability; unresolved material mappings go to review.

### 8.2 Card variants

Use set plus collector number as the primary human identity of a printing.

- materially different printings or high-impact variants must remain separate
- first edition, materially different promos, stamped variants, or otherwise meaningfully different products must not be collapsed
- low-impact finish differences such as normal versus reverse holo may be simplified in the MVP when the source groups them or the price difference is immaterial
- do not force collector-grade variant selection for low-value cards
- uncertain or materially ambiguous mappings must enter an admin review queue rather than being guessed

### 8.3 Sealed-product catalogue

Include all released official Pokémon TCG SKUs distributed in Poland.

Each canonical product should support:

- internal ID
- stable slug
- canonical name
- aliases used by Polish shops
- product type
- set or series
- release date
- MSRP/RRP and source
- EAN/barcode when known
- official or approved image
- publication status
- distribution status

Exclude from the MVP public catalogue:

- preorders
- Japanese products
- fringe imports not officially distributed in Poland

Discontinued products remain searchable indefinitely.

### 8.4 Sealed-product publication workflow

Newly discovered sealed products begin as drafts.

An administrator must approve:

- canonical identity
- aliases
- product type
- release date
- MSRP
- retailer-listing mappings

Only approved products appear in public search. Ambiguous or unmatched listings remain in an admin review queue.

---

## 9. Singles valuation rules

### 9.1 Aggregate MVP policy

The active MVP uses the free, unauthenticated TCGdex embedded Cardmarket aggregate pricing source. The versioned policy is `tcgdex_cardmarket_v1`. It is intentionally an estimate for thesis validation: it does not claim English/Near Mint filtering, Poland shipping eligibility, or seller-level precision. Low-impact finish differences may be simplified; ambiguous or materially different variants remain missing/review rather than guessed.

For one exact card printing, select the first finite positive EUR value in this exact order: `avg7`, `avg30`, `trend`, `avg`, `low`. Use Decimal arithmetic and display the selected value to two decimal places. Store the selected source metric/method, source/provider, card identity, fetched timestamp, provider pricing update timestamp when parseable, and current/archive status. The active source does not provide a seller/offer count; it is unavailable and must never be fabricated. Any future shared storage field for that count may be nullable/optional.

The UI and methodology copy must say that this is an aggregate Cardmarket estimate. It cannot prove language, condition, seller identity, finish-specific exactness, or shipping to Poland. Shipping is not calculated. Quantity still multiplies the unit estimate, but does not imply availability of multiple copies.

The previously implemented `default_v1` five-lowest-distinct-seller offer algorithm remains historical/post-MVP capability and must not be the active MVP methodology. Preserve its code and history for a future seller-level source; do not expose its promises in the MVP.

### 9.2 Missing aggregate value

When none of `avg7`, `avg30`, `trend`, `avg`, or `low` is a finite positive EUR value, show the card as unavailable/unpriced and exclude it from numeric trade totals. Do not invent a fallback or claim that no current offers exist: this aggregate source does not provide qualifying-offer evidence.

### 9.3 Never-valued card

When a card has no current or historical valuation:

- show `?` as its price
- exclude it from the numeric side total
- mark the side total as incomplete
- do not present the trade difference as definitive
- show the number of unvalued cards

Example presentation:

```text
Left side:   €32.50 + 1 unvalued card
Right side:  €35.10
Difference:  Cannot be determined precisely
```

### 9.4 Provider request shape

Use the free TCGdex embedded aggregate; do not scrape Cardmarket or pay for listing-level data for the active singles MVP. Every stored valuation snapshot must still include:
  - card printing
  - policy version (`tcgdex_cardmarket_v1`)
  - calculated EUR value
  - source/provider
  - calculation method
  - selected source metric/method
  - seller/offer count only when a future source provides it; otherwise leave any shared field nullable/optional and do not fabricate it
  - fetch timestamp
  - provider pricing update timestamp when parseable
  - current versus archival status

---

## 10. Singles freshness, on-demand acquisition, and history

### 10.1 Freshness

A singles valuation is fresh for **7 days**.

### 10.2 Missing data

When a card has never been priced:

- render the card page or trade row immediately
- show a fetching or unavailable state
- enqueue one unique Oban refresh job
- update the LiveView automatically when the job completes
- never block the page on the external provider request

### 10.3 Stale data

When the latest valuation is older than 7 days:

- show the stale value immediately
- show when it was last updated
- enqueue one deduplicated refresh job
- update the LiveView automatically after completion
- keep the stale value if the refresh fails

### 10.4 Deduplication

Concurrent public requests for the same card and preset must reuse one in-flight job. Use Oban uniqueness and a database-backed freshness check.

### 10.5 History

- each successful fetch creates a timestamped valuation snapshot
- retain snapshots indefinitely
- the public graph shows the last 30 days only
- no date-range switcher
- do not interpolate missing periods
- when multiple snapshots occur on one day, the displayed daily point should use the last successful valuation of that day unless the chosen charting convention has a documented superior reason

---

## 11. Trade calculator rules

### 11.1 Composition

Each side contains rows of:

- canonical card-printing ID
- quantity

No prices are serialized into the shared link.

### 11.2 Shared URL

The trade is entirely URL-backed for the MVP.

Requirements:

- no server-side trade record
- no private or non-guessable token requirement
- deterministic, shareable URL
- encode left-side card IDs and quantities
- encode right-side card IDs and quantities
- do not encode price snapshots
- opening the link always uses the latest available cached valuation and current `tcgdex_cardmarket_v1` policy
- card names may change without breaking the URL because stable IDs are authoritative
- update the URL as the trade changes without full-page reloads

The exact query-string or fragment encoding is an implementation choice. Prefer readable encoding unless trade size or browser limits make compact encoding necessary.

Illustrative shape:

```text
/trade?left=JTG-123:1,JTG-321:2&right=JTG-444:1
```

### 11.3 Totals and currencies

- individual card unit prices: EUR only
- row totals: EUR only
- each side total: EUR plus PLN conversion
- trade difference: EUR plus PLN conversion
- if either side has an unvalued card, mark the comparison incomplete
- stale archival prices count in the total but are visibly marked

### 11.4 EUR/PLN conversion

Use the latest published NBP average EUR exchange rate.

- refresh daily
- on weekends and holidays, use the most recent available rate
- cache and retain rates
- display rate age in the trade explanation or details
- use decimal arithmetic

---

## 12. Sealed-product market data

### 12.1 Source categories

Represent retailer categories explicitly:

1. **Regular retailers** — representative Polish non-LGS retailers
2. **LGSes** — local game stores and specialist card shops

The MVP should target approximately 5–10 representative regular retailers plus a useful sample of LGSes, subject to source reliability and the acquisition budget.

Marketplaces are not required for the MVP. If researched, keep them separate and do not include them in the primary benchmark without evidence that they improve the buying decision.

### 12.2 MSRP

MSRP/RRP should come from the most authoritative Polish source available, preferably the official distributor or another first-party source.

The agent must research the main official Pokémon TCG distributor or distribution source for Poland and document the selected source and limitations.

### 12.3 Listing eligibility

For the main current-offer dataset:

- include only offers marked in stock
- ignore shipping costs
- use one data point per shop, choosing its cheapest qualifying listing when duplicates exist
- preserve shop category
- preserve direct URL
- preserve current stock state
- preserve last successful check time

### 12.4 Current offer display

Show:

- shop name
- category: regular retailer or LGS
- current price in PLN
- stock status
- last checked time
- direct link
- shipping-excluded note

Sort current in-stock offers by price. Show recently sold-out offers separately so they are not mistaken for purchasable listings.

---

## 13. Sealed-product buying intelligence

### 13.1 Product purpose

The sealed-product page is a buying guide. It must help a user decide whether an observed shop or listing price is good without requiring the user to enter the price into the application.

### 13.2 Buying bands

When confidence is sufficient, display four dynamic, product-specific bands:

1. **Great price**
2. **Fair price**
3. **Expensive**
4. **Avoid**

Example only:

```text
Below 200 PLN     Great price
200–250 PLN       Fair price
250–300 PLN       Expensive
Above 300 PLN     Avoid
```

The values must be calculated per product and change with the market. Never hardcode global monetary thresholds.

### 13.3 Inputs to the model

The explainable scoring/range model should combine:

- MSRP/RRP
- current in-stock regular-retailer prices
- current in-stock LGS prices
- recently sold-out prices
- 30-day price trend
- current availability
- availability trend
- source freshness
- data coverage and confidence

MSRP is the first reference point. The average or robust center of 5–10 regular retailers is the primary live-market reference. LGS prices are a separate market signal and may receive a different weight.

The final benchmark may be a weighted calculation. Exact weights are intentionally not fixed here because they must be validated with real Polish-market cases.

### 13.4 Sold-out relevance

- sold out 0–14 days ago: strong current-market evidence
- sold out 15–30 days ago: secondary context
- older than 30 days: graph/history only; it should not materially influence the current verdict

A long-gone promotional offer must not make every current price look bad indefinitely.

### 13.5 Trend-aware explanation

The result must explain the strongest reasons in plain English.

Example:

> Fair price. The product was recently available for less, but those offers sold out. The cheapest current offers are higher, availability is falling, and the market benchmark has risen during the last two weeks.

Do not expose a mysterious opaque score without explanation.

### 13.6 Model implementation requirements

Implement the buying model as a pure, testable, versioned module with configuration for:

- retailer-category weights
- robust center calculation
- typical-range calculation
- outlier handling
- sold-out recency weights
- trend thresholds
- availability thresholds
- confidence thresholds
- band boundaries

Store the model version with derived snapshots so later model changes do not silently rewrite the meaning of previously stored results.

Before finalizing initial weights, test the model against representative cases:

- widely available below MSRP
- widely available around MSRP
- scarce and rising after lower offers sold out
- one cheap outlier among expensive shops
- one expensive outlier among normal shops
- reprint causing falling prices
- new release with little history
- product with only one active shop
- discontinued product with sporadic stock

Document the selected initial weights and trade-offs in an ADR.

### 13.7 Limited-data state

When confidence is insufficient, show **Limited data** instead of the four bands.

Reasons may include:

- too few shops
- missing MSRP
- insufficient history
- stale sources
- uncertain product mapping

Still show all trustworthy current offers and available history. Explain what is missing. Never manufacture confident ranges from weak evidence.

---

## 14. Sealed-product graph

The MVP graph has a fixed 30-day range and no date controls.

Required presentation:

- one central line representing the daily market benchmark
- one shaded background band representing the typical observed market range
- the band must exclude obvious outliers
- missing periods remain gaps
- MSRP may be shown as a static reference if visually useful and not confusing

Regular retailers and LGSes remain separate in the underlying data and offer list, but do not need separate graph lines.

The typical-range method must be robust and configurable, such as a trimmed range or percentile-based band. Choose the approach after testing against real source counts. When data is too sparse, use the limited-data state rather than a misleading band.

---

## 15. Data-source research phase

Data sources will make or break the product. Treat source selection as an explicit implementation phase.

### 15.1 Singles research

For the active MVP, document and fixture-test TCGdex embedded Cardmarket aggregate pricing. Seller-level alternatives are post-MVP research only. Evaluate current options for:

- exact printing matching
- aggregate metric availability and field semantics
- data freshness and provider update timestamps
- historic data availability
- API stability
- pricing and rate limits
- licensing and terms
- known inability to verify language, condition, seller identity, finish-specific exactness, or shipping-to-Poland eligibility

### 15.2 Card metadata research

Evaluate candidate catalogue providers for:

- complete set and printing coverage
- exact IDs
- images
- legalities
- collector numbers
- variants
- release metadata
- licensing
- Cardmarket matching suitability

### 15.3 Sealed-product research

Identify:

- authoritative Polish MSRP/distribution source
- representative regular retailers
- representative LGSes
- accessible APIs, feeds, structured pages, or lawful scraping paths
- reliability of stock status
- product-name and EAN consistency
- anti-bot and operational cost

### 15.4 Required research deliverable

Create a concise decision record before locking integrations. It must contain:

- sources evaluated
- primary and fallback choices
- real aggregate request tests (and bounded scrape experiments only when relevant to later sealed/post-MVP research)
- coverage examples
- matching accuracy examples
- pricing and quota table
- estimated monthly cost at MVP usage
- worst-case cost-control behavior
- licensing and terms notes
- known gaps

### 15.5 Aggregate-first/no-scraping MVP policy

The active singles MVP selects free, unauthenticated TCGdex embedded Cardmarket aggregates and avoids scraping where practical. The selected singles source has **$0 acquisition cost** and requires no credentials. This does not decide every broader sealed-product source: sealed distributor and retailer research remains open and must be evaluated separately.

Use canonical identifiers and known source URLs only; never accept arbitrary user-supplied URLs. Keep any future credentials out of git and provider-specific secrets server-side. Do not bypass authentication, payment, or CAPTCHA controls. Scraping or paid providers may be researched for post-MVP seller-level capability, but are not part of the active singles methodology.

Keep the global **US$50/month** cap across all external acquisition. Use backoff, bounded concurrency, kill switches, cost tracking, and stale/`?` fallback for any future paid or scraped source.

---

## 16. Acquisition budget and protection

### 16.1 Hard cap

The application must track estimated and actual external acquisition cost and enforce a hard monthly cap of US$50.

### 16.2 Protection mechanisms

Implement:

- canonical card IDs only for on-demand fetches
- no arbitrary user-supplied URLs or provider queries
- 7-day card TTL
- unique Oban jobs
- per-IP request limiting
- global hourly on-demand budget
- global daily on-demand budget
- monthly provider budget
- provider quota tracking
- circuit breakers / kill switches
- graceful fallback to stale data or `?`

The concrete hourly and daily numbers should be derived from the selected provider’s price model and made configurable.

### 16.3 Prioritization

When budget is constrained, prioritize:

1. user-requested uncached singles
2. stale popular singles
3. newly released or highly active sealed products
4. current sealed products with changing availability
5. older or unavailable sealed products

Never silently spend beyond the cap to improve freshness.

### 16.4 Implemented request-admission foundation — 2026-08-09

Every in-tree operational outbound request now enters one fail-closed PostgreSQL admission transaction immediately before HTTP. This covers TCGdex catalogue requests made by `Importer`, `Sync`, and `Enrichment`; TCGdex Cardmarket valuation requests; NBP exchange-rate requests; and every page of a configured sealed-retailer refresh. Metered adapters disable internal Req retries, so an HTTP attempt cannot hide additional uncounted retries; later Oban or caller retries require a new admission. Adapter contracts require the injected zero-arity request admitter to run before each outbound request. Budget rejection prevents the request, while budget-persistence failure is retryable in workers and otherwise returns an explicit error.

`DataProvider` persists provider status, estimated per-request cost, provider hourly/daily/monthly request limits, and provider monthly estimated-spend limits. `BudgetUsage` retains one UTC hour/day/month row per provider with request and estimated-spend counters. One global advisory lock serializes provider upsert/status locking, provider and global checks, and all three atomic increments, preventing concurrent admissions from exceeding provider/global limits. Global hourly/daily request limits and the global monthly estimated-spend limit are configurable, bounded at US$50, and shared across catalogue, singles, exchange-rate, and future configured sealed acquisition. Config synchronization intentionally does not re-enable a disabled persisted provider. UTC windows zero subsecond precision so requests in the same hour/day cannot split counters by microsecond.

This is a strong foundation, not completion of all Section 16 requirements. Active sources currently have zero acquisition cost, and estimated cost is conservatively reserved before HTTP. Actual-cost reconciliation for future paid responses, public per-IP acquisition throttling, acquisition priority classes, source health/circuit-breaker automation beyond the persisted kill switch, and admin usage/failure visibility remain required.

---

## 17. Own data bank and retention

The platform is its own historical data bank.

- store acquired observations in PostgreSQL
- public pages read from the local database
- retain all acquired raw observations and normalized snapshots indefinitely
- retain all daily aggregates indefinitely
- retain NBP exchange rates indefinitely
- retain source/fetch metadata indefinitely
- retain stock transitions
- avoid inserting identical full duplicates when nothing changed
- still preserve `first_seen_at`, `last_seen_at`, and `last_checked_at` semantics so unchanged listings remain auditable

For singles, “retain raw observations” means retain whatever granularity the chosen cost-efficient request returns. Do not pay extra just to make the raw record richer.

---

## 18. Technical architecture

### 18.1 Application shape

Use one Phoenix application containing:

- public LiveViews
- Ash domains and resources
- Oban workers
- provider adapters
- AshBackpex admin
- custom internal operational LiveViews when AshBackpex is insufficient

Use one PostgreSQL database for application data and Oban.

### 18.2 Request-path rule

Normal public page rendering must not make blocking external provider calls.

The allowed pattern is:

1. read cached/local state
2. render immediately
3. enqueue a unique job when data is missing or stale
4. subscribe through Phoenix PubSub
5. update the LiveView when the job completes

### 18.3 Provider adapters

Create explicit boundaries equivalent to:

- `CardCatalogProvider`
- `SinglesPricingProvider`
- `SealedCatalogProvider` or distributor importer
- one `SealedRetailerAdapter` per retailer/source
- `ExchangeRateProvider`

Provider-specific payloads and identifiers must not leak into public LiveViews or core pricing calculations.

Each adapter should normalize into internal structs/resources and provide fixture-backed contract tests.

### 18.4 Search

Prefer PostgreSQL-backed search:

- normalized search text
- aliases
- trigram indexes
- full-text search where helpful
- weighted ranking by exact name, prefix, set, collector number, alias, and current relevance

Seed both catalogues before final ranking work. Test realistic collision cases with actual data. Add a separate search service only if measured PostgreSQL performance or relevance is inadequate.

### 18.5 Caching

Use hard caching at the data level:

- normalized current records
- derived latest valuations
- daily aggregates
- data freshness timestamps
- cached homepage sections

An additional in-memory cache is optional, but PostgreSQL remains the source of truth. Avoid a cache architecture that makes a single-VPS deployment fragile.

### 18.6 Money and time

- use decimal or integer-minor-unit money handling; never floats
- store source currency explicitly
- store timestamps in UTC
- present relevant times in Europe/Warsaw
- display sealed prices in PLN
- display singles in EUR, with PLN only for trade totals and differences

---

## 19. Suggested Ash domain model

Follow Firmowid conventions even when names differ. The following is a conceptual minimum, not permission to create unnecessary abstractions.

### 19.1 Catalogue domain

| Resource | Purpose |
|---|---|
| `CardSet` | Set metadata and external mappings |
| `CardPrinting` | Exact searchable card printing |
| `CardExternalMapping` | Mapping between catalogue and pricing-provider identities |
| `SealedProduct` | Canonical official Polish sealed SKU |
| `SealedProductAlias` | Retailer/distributor naming aliases |
| `Retailer` | Shop identity, category, and status |
| `RetailerListing` | Current canonical retailer listing |
| `ListingProductMapping` | Mapping and review state between raw listing and product |

### 19.2 Pricing domain

| Resource | Purpose |
|---|---|
| `PricingPreset` | Internal versioned singles policy; MVP uses `tcgdex_cardmarket_v1` |
| `SingleValuationSnapshot` | Timestamped EUR valuation and methodology |
| `SingleOfferObservation` | Optional seller-level observations when returned at no extra cost |
| `SealedListingObservation` | Timestamped PLN price and stock observation |
| `SealedDailyAggregate` | Daily benchmark, range, availability, and source counts |
| `SealedBuyingGuideSnapshot` | Model version, confidence, bands, and explanation factors |
| `ExchangeRate` | NBP EUR/PLN rate history |

### 19.3 Acquisition/operations domain

| Resource | Purpose |
|---|---|
| `DataProvider` | Provider status, cost model, and capability metadata |
| `AcquisitionRun` | Fetch/import attempt, status, cost, and diagnostics |
| `BudgetUsage` | Hourly, daily, and monthly usage/accounting |
| `ImportIssue` | Unmatched, ambiguous, malformed, or failed imports |
| `SourceHealth` | Last success, failure streak, freshness, and circuit-breaker state |

### 19.4 Identity/admin

Use the authentication and admin-user approach established in Firmowid. There are no public users. At minimum, support a restricted administrator identity for `/admin`.

Prefer soft-disable/archive actions over destructive bulk deletion for operational data.

---

## 20. Oban jobs

Implement jobs equivalent to:

- card catalogue synchronization
- card-to-pricing-provider mapping/backfill
- on-demand single valuation refresh
- scheduled popular-single refresh
- sealed distributor catalogue import
- per-retailer sealed listing refresh
- sealed listing matching
- daily sealed aggregates
- buying-guide recomputation
- NBP exchange-rate refresh
- homepage aggregate refresh
- provider quota/cost reconciliation
- source-health checks
- stale/failure alert generation for admin

Requirements:

- idempotent
- unique where appropriate
- retry with provider-specific backoff
- budget-aware before external work
- safe to resume after deployment/restart
- observable in admin
- testable with recorded fixtures

---

## 21. Admin interface

Use AshBackpex for the main internal CRUD interface.

Required admin capabilities:

- manage sealed products
- manage aliases
- approve drafts
- edit MSRP and release metadata
- manage retailers and categories
- inspect retailer listings
- approve or correct listing mappings
- inspect cards and external mappings
- inspect valuation snapshots
- inspect import issues
- inspect failed jobs and source health
- inspect stale sources
- inspect provider quota and cost usage
- enable/disable a provider or retailer adapter
- trigger a safe manual refresh
- inspect the current buying-model configuration/version

AshBackpex is an evolving integration. Pin compatible versions. Where an operational workflow cannot be expressed safely or clearly in AshBackpex, add a focused custom authenticated LiveView rather than forcing it into generic CRUD.

Do not expose the admin publicly without authentication and authorization.

---

## 22. UX and presentation requirements

### 22.1 Mobile-first

Design for phone use first, especially:

- in-store sealed-product lookup
- quick single-card search
- in-person trade entry

Support narrow screens without horizontal page scrolling.

### 22.2 Loading and freshness states

Every price surface must distinguish:

- fresh
- stale but usable
- fetching
- limited data
- unavailable / never valued
- provider failure with cached fallback

Do not replace stale data with a blank screen.

### 22.3 Explanations

Show concise methodology text, for example:

**Superseding presentation guidance:** Keep the primary task path to plain collector language and the fewest words needed for the action or state. Technical methodology, provider/policy labels, local-data wording, freshness detail, IDs, and required caveats may remain available in a concise disclosure, but should not be repeated across the main search and comparison path. Legal and methodological honesty remains mandatory.

> Aggregate Cardmarket estimate from TCGdex (`tcgdex_cardmarket_v1`); language, condition, seller identity, finish, and Poland shipping are not verified.

For an unavailable aggregate:

> No positive aggregate metric is available; this card is currently unpriced rather than treated as evidence of no offers.

### 22.4 Accessibility

Follow Firmowid accessibility patterns and standard LiveView semantics:

- keyboard-accessible autocomplete
- visible focus states
- semantic controls
- non-color-only status indicators
- chart text summaries or accessible labels
- adequate touch targets

### 22.5 Disclaimer

Clearly state that:

- prices are estimates based on collected market data
- shipping is excluded in the MVP
- the application is unofficial and not affiliated with Pokémon, Cardmarket, or listed retailers

Do not imply guaranteed resale value or investment advice.

---

## 23. Homepage aggregates

The homepage may show concise discovery sections after search:

### 23.1 Biggest changes

- use a single fixed recent window
- include only items with enough history to make the change meaningful
- exclude low-confidence or single-point changes
- separate singles and sealed items visually when necessary

### 23.2 Recent releases

- released sealed products only
- no preorders
- link directly to product pages

### 23.3 Recently updated / active

Optional if it improves the page and has trustworthy data. Do not add filler content.

---

## 24. Data-quality and matching rules

- never guess an ambiguous card-to-Cardmarket mapping
- never guess an ambiguous sealed listing-to-product mapping
- use EAN when available
- use aliases and normalized names as supporting evidence
- record confidence and evidence
- auto-match only above a tested confidence threshold
- route the rest to admin review
- keep source identifiers and provenance
- make imports idempotent
- do not publish draft sealed products

Provide an admin-visible unmatched/ambiguous queue from the first implementation phase.

---

## 25. Performance and scalability targets

The MVP should run comfortably on one modest VPS.

Targets:

- search autocomplete should feel immediate and normally return from local PostgreSQL in well under one second
- cached product and card pages should not depend on provider latency
- trade recalculation should be local and effectively instant
- background work must not starve web requests
- job concurrency must be configurable per provider
- homepage aggregates should be precomputed or cached
- indexes must support catalogue size without a separate search service

Do not prematurely introduce distributed infrastructure.

---

## 26. Testing requirements

### 26.1 Domain/unit tests

Cover:

- aggregate metric-priority selection
- non-finite/non-positive aggregate values
- exact priority order and Decimal two-decimal formatting
- provenance fields, parseable provider update timestamp, and current/archive status
- seller/offer count remains unavailable for the active aggregate adapter and is not fabricated
- missing aggregate value and unavailable state
- never-valued card
- quantity multiplication
- incomplete trade totals
- EUR/PLN conversion
- URL encode/decode round trips
- duplicate card merge
- stale/fresh TTL behavior
- budget rejection
- job uniqueness
- sealed outlier handling
- sold-out recency weighting
- limited-data confidence
- buying-band boundary behavior

### 26.2 Provider contract tests

For every provider/retailer adapter:

- use recorded fixtures or stable local fixtures
- test normalization
- test missing fields
- test changed markup/payload failure behavior
- test rate-limit responses
- test retry/backoff classification
- test cost accounting

Do not make the default test suite depend on live external services.

### 26.3 LiveView tests

Cover:

- homepage mode switch
- autocomplete result identity
- autocomplete regression: typing retains input focus, query, caret/selection, and IME/composition state across every update; result updates do not replace the input or steal focus
- autocomplete combobox/listbox semantics, stable option IDs, visible active option, ArrowUp/ArrowDown, Enter exact-printing selection, Escape close, touch/click selection, and screen-reader status
- cross-category fallback suggestions
- single page missing-price refresh state
- stale single refresh state
- trade add-left/add-right flow
- quantity changes
- share URL restoration
- unvalued card state
- sealed page buying bands
- sealed limited-data state
- current and sold-out offer sections
- mobile-responsive component behavior where practical

### 26.4 Import and job tests

- catalogue sync is idempotent
- retailer refresh updates existing listings instead of duplicating them
- stock transitions are retained
- failed jobs preserve prior public data
- budget limits prevent provider calls
- PubSub updates waiting LiveViews after successful refresh

---

## 27. Real-data validation before MVP completion

The MVP must prove both core features with real, non-fabricated data.

Before declaring completion:

- import the available card catalogue
- demonstrate reliable exact-printing search
- match and price a representative subset of singles
- retain multiple real valuation snapshots for enough singles to demonstrate the 30-day-history UI
- import all currently distributed official Polish sealed SKUs and as much released historical catalogue as the authoritative source allows
- collect multiple real observations for a representative set of sealed products
- demonstrate stock transitions or recent sold-out context for at least some products
- validate the buying model against real Polish-market examples
- demonstrate a complete shareable trade with current, stale, and unvalued examples

If a source does not expose historical data, allow the collector to accumulate real observations; do not seed fake production history. Until history is sufficient, use **Limited data** or an honest “history is being collected” state.

---

## 28. Implementation sequence

### Phase 0 — Inspect and decide

1. Inspect Firmowid and Onside.
2. Record relevant conventions.
3. Research card metadata, singles pricing, Polish distributor, retailers, and LGS sources.
4. Run real source experiments.
5. Produce provider/cost ADRs.
6. Confirm a feasible acquisition plan under US$50/month.

### Phase 1 — Foundation

1. Create the Phoenix/Ash application using Firmowid conventions.
2. Configure PostgreSQL, Oban, authentication, and AshBackpex.
3. Create core domains/resources.
4. Add provider adapter behaviours.
5. Add cost tracking, rate limiting, source health, and kill switches.
6. Add initial admin screens.

### Phase 2 — Card catalogue and singles

1. Import card sets and printings.
2. Implement search and exact-printing result display.
3. Implement Cardmarket/provider mapping.
4. Implement `tcgdex_cardmarket_v1` aggregate valuation; preserve `default_v1` as historical/post-MVP code.
5. Implement snapshots and 7-day TTL.
6. Implement on-demand refresh and PubSub updates.
7. Implement single-card page and 30-day graph.

### Phase 3 — Trade calculator

1. **Complete:** Implement URL-backed composition.
2. **Complete:** Implement one search bar and two add buttons.
3. **Complete:** Implement quantities and row merging.
4. **Complete:** Implement EUR totals and NBP PLN conversion.
5. **Complete:** Implement stale/unvalued/incomplete states.
6. **Complete:** Implement responsive vertical/horizontal layout.
7. **Complete:** Implement share/copy behavior.

### Phase 4 — Sealed catalogue and acquisition

1. **Foundation begun, not complete:** Added source-neutral AshPostgres `SealedProduct` canonical official Polish-English SKU modeling. It supports stable slugs/search text, allowlisted types, series/set/release, optional finite positive PLN MSRP with paired provenance/source URL, image, PL/en/official flags, draft/approved/archived and current/discontinued states, source identity/provenance/private payload/timestamps. Draft-only source imports use stable source+source ID, allow slug corrections, and cannot overwrite reviewed rows; manual curation may omit source. Approval requires released/non-future and official PL/en; discontinued approved products remain readable and archive is soft/unpublished. No production SKUs are imported or curated, so this step is not complete.
2. **Foundation advanced, not complete:** Added `SealedProductAlias` name/EAN review queues with normalized aliases, original values/provenance, pending/approved/rejected states, approved-per-product reads, and app/DB GTIN-8/12/13/14 ASCII normalization plus GS1 checksum enforcement and global canonical-product uniqueness. Imports are pending-only/idempotent and cannot overwrite reviewed aliases. The authenticated review desk can approve or reject pending aliases with canonical-product evidence and stale-row protection. No production aliases/EANs/MSRP curation exists, so this step is not complete.
3. **Foundation advanced, not complete:** Added source-neutral regular-retailer/LGS identity, current listing projection, and a normalized `SealedRetailerAdapter` contract. A fixture-backed LootQuest WooCommerce Store API adapter now proves one strict fixed-endpoint source shape: bounded `_fields` acquisition, response bytes, per-request/whole-job execution, deterministic pagination, Decimal PLN minor-unit conversion, canonical product URLs, explicit sealed-category/import/preorder/backorder filtering, source-order retention, and Retry-After classification. A canonical retailer acquisition boundary and unique `sealed_retailers` Oban worker validate all rows and duplicate IDs before one atomic ingest transaction, lock/revalidate the active retailer after fetch, defer Ash notifications until commit, retain missing rows without sold-out inference, and retry only explicit transient source/database failures. Every page now requires request-level budget admission immediately before HTTP; a mid-pagination rejection stops before the next request and writes nothing. Req-level retries are disabled so Oban owns whole-batch retry and transient page-count drift restarts from page one with a new admission per requested page; unexpected adapter callbacks cancel permanently. The adapter registry is empty by default and there is no sealed Cron, production retailer row, live schedule, or claim of reuse permission. Broad category evidence cannot positively prove released English official Polish distribution, so canonical product review remains mandatory and this step is not complete.
4. **Foundation advanced, not complete:** Added conservative exact-approved-GTIN matching and one human-reviewable listing-to-product mapping projection with pending/review/matched/rejected transitions, locked review decisions, approved-product validation, and import protection. The authenticated review desk now exposes one-row-at-a-time approval/correction or reasoned rejection with retailer/listing/candidate/evidence context. Every product, alias, and mapping review submits the displayed `updated_at` version and revalidates it under the transaction-local row lock, so stale forms cannot silently overwrite or approve newer evidence. No real production mappings exist.
5. **Foundation begun, not complete:** Every successful current-listing ingest now appends an immutable PLN price/stock/source observation only when content changes. Transaction-local per-listing advisory locks serialize first insert and update, stale source timestamps cannot regress the current projection, identical later checks update audit timestamps without duplicate observations, and stock/price transitions are retained. A unique listing/check-time boundary rejects ambiguous same-timestamp changes and the observation foreign key restricts hard deletion. No real production observations or source-driven stock transitions have been collected.
6. **Public foundation implemented, not complete:** Current listing rows retain direct URL, price, stock state, first/last-seen and last-checked audit timestamps, while immutable history feeds the daily aggregate path. Public reads require an approved released official PL/en product, a matched mapping, and active listing/retailer. `/` searches local approved canonical names plus approved name aliases with bounded deterministic PostgreSQL ranking and stable accessible options; `/sealed/:slug` shows canonical identity, release/status, optional provenance-backed MSRP, one cheapest in-stock listing per shop sorted by PLN price, and one most recently checked sold-out listing per shop within 30 days in a separate section. When a valid current-version daily aggregate exists, the detail also shows its benchmark, typical range, source counts, aggregate/evidence times, and concise methodology. A newest limited result remains explicit while the latest older ready snapshot is retained as clearly cached/outdated; corrupt or unreadable aggregates fail closed. Direct HTTPS links, shop category, stock, exact UTC check time, shipping exclusion, not-found/read-error states, and explicit **Limited data** labels are visible. No provider runs in public paths, no price, graph, confidence band, or buying verdict is fabricated, and stale Enter events cannot select prior autocomplete options. The pure buying model now feeds persisted local `SealedBuyingGuideSnapshot` records through an exact-revision Oban job, but this public step remains incomplete because no approved production catalogue/retailer data exists and public guide consumption, the required 30-day graph, plain-English explanation, and real-market validation are not implemented.

Generated Ash migration/snapshot sets `20260808160842_sealed_catalogue_foundation`, `20260808204902_sealed_retailer_listing_foundation`, `20260808213452_sealed_listing_observations`, the `20260808231641`/`20260808231642` administrator-authentication pair, `20260809003932_public_sealed_lookup`, `20260809140042`–`20260809145258` for sealed daily aggregates, and `20260809163539`–`20260809185311` for persisted buying guides/source evidence/current-plus-history revision hardening were applied and reviewed. The public lookup migration adds concurrent GIN trigram indexes for canonical sealed names and aliases. The generated authentication-extension rollback was narrowly corrected because dropping shared pre-existing Ash functions was demonstrably unsafe. Product/alias/mapping review transitions use transaction-local row locks plus displayed-version checks; listing ingest uses a stable per-listing transaction advisory lock. Aggregate and guide app/database constraints cover version/currency/state, canonical limited reasons, finite ordered money, nonnegative/coherent coverage counts, evidence/calculation time, exact current/history source fingerprints, restrictive parent references, and one product/date/version row. Other app/database constraints continue covering review state, identity, timestamp, locale, source, finite-money, stock/price, GTIN/checksum, URL, foreign-key, and unique observation-boundary invariants.

Latest sealed validation includes the prior observation/retailer/listing/mapping/concurrency, LootQuest contract, bounded worker, administrator authentication/authorization, dual-key throttling, stale-review coverage, daily aggregate calculator/resource/worker/public-snapshot suite, pure buying-model suite, and persisted-guide input/resource/worker integration. Canonical `direnv exec . mix check --verbose` passes 503 tests with format, Ash codegen, Sobelow, warnings-as-errors compile, unused dependencies, xref, Credo, and Dialyzer clean. Buying-model coverage remains 37 focused tests, focused guide/aggregate integration passes 35 tests, and all pricing coverage passes 209 tests. Existing desktop 1008px and mobile 390px browser evidence still covers the current benchmark/range/count/evidence snapshot, methodology disclosure, at least 44px summary control, and no horizontal overflow; this persistence batch makes no public UI change or new browser claim. No production SKU, retailer, listing, observation, configured live retailer adapter, production market benchmark/guide record, public graph/band, or fabricated history was added. Written source permission and real SKU/alias/MSRP curation remain production blockers; AshBackpex operations, public buying guides, the graph, plain-English explanations, and real-data validation remain incomplete.

### Phase 5 — Buying intelligence

1. **Implemented in code, awaiting production data:** A unique daily local-only Oban worker reads approved products and every matched active listing, skips products with no mapped evidence rather than fabricating history, and upserts one retained product/date/version aggregate. The 16:00 UTC schedule follows NBP but performs no external request. Same-day newer calculations replace older ones; stale writes fail; historical corrections atomically enqueue every persisted following guide date whose 30-day input window changes.
2. **Initial v1 implementation complete, real-market validation outstanding:** `sealed_market_daily_v1` chooses one cheapest fresh (maximum seven-day age) in-stock listing per retailer, requires five regular retailers, keeps LGS separate, deduplicates the latest eligible sold-out listing per retailer into 0–14/15–30-day buckets, removes Tukey 1.5-IQR outliers, and stores the half-up two-decimal median plus inlier min/max range. Canonical limited reasons cover no fresh current evidence, too few regular retailers, and insufficient inliers. App/database invariants and public defensive validation fail closed on inconsistent state/count/time/money.
3. **Initial implementation and local persistence complete; public integration outstanding:** `sealed_buying_model_v1` is a deterministic, fixed-Decimal, versioned module with inspectable component/confidence weights, sold-out recency weights, trend/availability thresholds, hard requirements, limited-reason precedence, and two-decimal rounding. It defensively validates aggregate/history/LGS/sold-out evidence and does not call providers. A current-plus-history exact-revision worker now persists its result separately. The [Sealed Buying Model v1 ADR](../architecture/sealed-buying-model-v1.md) records the decision and trade-offs.
4. **Synthetic cases complete; real cases blocked:** Required representative policy fixtures cover below/around MSRP, scarcity plus rising/sold-out evidence, cheap/expensive upstream outliers, a falling reprint, new-release history, one-shop evidence, and sporadic stock. Initial weights remain provisional until written source access supplies real Polish-market cases.
5. **Persistence/recomputation implemented; public behavior outstanding:** The model returns explicit Great/Fair/Expensive/Avoid intervals or deterministic Limited data, including fail-closed rounded-boundary handling. `SealedBuyingGuideSnapshot` retains one model-versioned product/date result, current aggregate plus preceding-history revision fingerprints, confidence, component centers, trend/availability states, ceilings, and explanation factors. Daily aggregate persistence atomically enqueues unique exact-revision recomputation for every affected guide date; source rows are locked and rechecked before write, stale jobs enqueue the latest successor, transient reads retry, and local latest/ready/history reads are available. Public rendering is not implemented.
6. Implement 30-day sealed graph and plain-English explanations from persisted model factors.

### Phase 6 — Homepage, hardening, and deployment

1. Implement homepage discovery sections.
2. Tune search using real collision cases.
3. **Foundation advanced, not complete:** request-level provider/global UTC limits, estimated-spend caps, and persisted provider kill switches are implemented; actual-cost reconciliation, public per-IP acquisition throttling, priority classes, circuit-breaker/source-health automation, and admin usage visibility remain.
4. Complete admin operational views.
5. Add observability and health checks.
6. Run full tests and real-data validation.
7. Produce deployment and operations documentation.

---

## 29. Acceptance criteria

The MVP is complete only when all of the following are true.

### 29.1 Public application

**Superseding product-structure and copy guidance:** The public product presents exactly two top-level customer features: sealed product price comparison and singles price comparison. Singles includes composing a trade and calculating the difference; trade is not a third equal homepage category. Homepage CTAs and states must remain minimal, plain-language, accessible, and honest about unimplemented capability. This supplements, and does not narrow, the detailed acceptance criteria below.

- English-only public site works without accounts
- mobile-first responsive UI
- homepage search supports Singles and Sealed products
- selected-category results are primary
- cross-category suggestions appear only when appropriate
- public pages read from local stored data

### 29.2 Singles

- exact card printings are searchable
- card page shows image and identity metadata
- card page shows current or stale EUR aggregate valuation under `tcgdex_cardmarket_v1`
- aggregate source, selected metric, and methodology are visible; no seller/offer-count widget is required because the active source does not provide that field
- 7-day TTL works
- missing/stale data triggers one deduplicated Oban job
- page updates through LiveView when the job completes
- 30-day valuation history works with real data

### 29.3 Trade calculator

- one search bar adds selected cards to either side using two buttons
- identical rows merge and quantities work
- mobile sides are vertical
- desktop sides are horizontal
- rows show EUR values
- totals and difference show EUR plus PLN
- NBP rate is current or honestly dated
- stale prices count and are marked
- never-valued cards show `?` and are excluded
- incomplete totals are clearly identified
- shared URL restores cards and quantities
- URL contains no prices

### 29.4 Sealed products

- all currently distributed official Polish SKUs are represented
- released products only; no preorders
- discontinued products remain searchable
- product page shows MSRP when known
- product page shows current in-stock offers and direct links
- sold-out offers are separate
- shipping-excluded note is visible
- 30-day graph shows benchmark plus typical-range band
- confident products show four buying bands
- weak-data products show Limited data
- explanations reflect MSRP, current market, sold-out recency, trend, and availability

### 29.5 Operations

- AshBackpex admin is authenticated
- admin can review drafts and mappings
- admin can inspect source failures and cost usage
- external acquisition cannot silently exceed US$50/month
- per-IP, hourly, daily, and monthly controls exist
- source outages leave cached public data usable
- all jobs are observable and retry safely
- production deployment instructions work

### 29.6 Quality

- test suite passes
- no live external dependency in the normal test suite
- no fabricated production history
- provider choices and scoring weights are documented
- code follows Firmowid conventions unless an ADR explains otherwise

---

## 30. Required documentation and handoff

Leave the repository with:

- root README with setup and development instructions
- `.env.example` without secrets
- architecture overview
- Ash domain/resource map
- provider research ADR
- provider adapter documentation
- acquisition budget model
- sealed buying-model ADR
- operations/admin runbook
- data-import and matching runbook
- deployment guide
- test guide
- known limitations and post-MVP roadmap

Also document the exact local paths or commit references of Firmowid and Onside used as architectural references.

---

## 31. Intentionally open implementation decisions

The agent must decide these through research and testing, not by asking the product owner unless access is genuinely blocked:

- exact card metadata provider
- exact Cardmarket data provider or direct access method
- exact Polish distributor/MSRP source
- exact regular retailers and LGS sources
- exact sealed refresh cadences
- exact hourly/daily on-demand quotas
- exact chart library or LiveView hook
- exact robust range calculation
- initial sealed-model weights and confidence thresholds
- exact compact URL encoding format
- exact Ash resource/module names consistent with Firmowid

Each decision must stay within the product rules and budget above and be recorded in an ADR where material.

---

## 32. Superseded decisions — do not implement in the MVP

Earlier exploration considered a broader preset and settings system. The final MVP deliberately simplifies it.

Do **not** expose:

- preset switching
- custom language filters
- custom condition filters
- seller-country filters
- per-card overrides
- shipping normalization
- separate fetches for arbitrary settings combinations

The internal model should remain versionable so these can be added later, but the MVP uses one fixed aggregate policy, `tcgdex_cardmarket_v1`.

Earlier exploration also considered server-persisted trade links and frozen prices. The final MVP uses URL-only trade composition and always evaluates against the latest locally cached data.

---

## 33. Post-MVP extension points

Preserve clean extension points, without implementing the UI now, for:

- multiple singles pricing presets
- per-card overrides
- shipping-aware valuation
- marketplace benchmarks
- barcode scanning
- retailer URL recognition
- watchlists and alerts
- Polish localization
- historical range controls
- saved trades or price snapshots
- additional countries
- Japanese and imported sealed products

Do not allow these extension points to complicate the MVP experience.
