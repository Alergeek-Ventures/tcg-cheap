# Product

<!-- impeccable:product-schema 1 -->

> The facts in this record are collectively inferred from the explicit authoritative MVP plan and the current code/tests because a structured product interview was unavailable. They are not invented.

## Platform

web

## Users

- English-speaking Pokémon TCG players and collectors evaluating common in-shop singles trades.
- English-speaking Polish sealed-product buyers evaluating products and prices.
- The current public surface supports Singles and Sealed search/detail foundations plus local-only Home discovery. Public Sealed search/detail remains local-only; three development/manual private sealed adapters now provide LootQuest matched-product evidence plus CardzHouse and BoosterPoint LGS evidence, while external permission/republication remains a public-launch gate.

## Product Purpose

Provide locally searchable exact Pokémon TCG printings, honest aggregate Cardmarket estimates, and context for understanding trades and sealed-product prices. The Phase 3 trade/share batch is complete. Private sealed feasibility now covers three development/manual adapters: LootQuest matched-product evidence plus CardzHouse and BoosterPoint LGS evidence; the overall MVP remains incomplete and public launch rights remain external.

The product has exactly two top-level customer features: **sealed product price comparison** and **singles price comparison**. Singles includes composing a trade and calculating the difference; trade is not a third equal homepage product category.

## Positioning

Thesis-validation product built around local cached data and transparent uncertainty. It does not fabricate seller counts, shipping costs, or false precision.

## Operating Context

- Mobile-first checks while making an in-store trade.
- Desktop research for Pokémon TCG singles and sealed products.
- Public use does not require public accounts.

## Capabilities and Constraints

- Phoenix LiveView application using Elixir, Ash, and PostgreSQL.
- Singles are searched and identified by exact printing, including set and collector number plus distinguishing metadata. The exact TCGdex identity path covers observed punctuation IDs such as `exu-!` and literal `exu-%3F` without accepting malformed escapes, path/query delimiters, padded identity, or overlong segments.
- Singles estimates are in EUR and target seven-day freshness. Home discovery is deliberately bounded to the fixed preceding 30 UTC dates, at least two daily points spanning one day, and at least 2% absolute movement.
- Public Sealed search/detail reads local approved/projection data. Trade unit and row prices remain EUR; side totals and complete differences also show Decimal PLN using the latest locally cached NBP rate.
- Provider calls must happen outside normal request paths; public requests should primarily read local cached data.
- The public exact-printing search surface is the local-only Home LiveView over the cached catalogue. Home defaults to Singles and presents a compact wordmark with `Compare Pokémon prices`, a direct `Find a card` search, and one-column exact-printing price rows with image, name, set, collector number, optional rarity, price, update state, and one solid `View price` CTA. The shared external 250ms `CardAutocomplete` hook serves Home and Trade, preserving the focused input node, query, caret/selection, and focus through result updates; composition pauses search and searches once after compositionend, while Escape cancels a pending debounce.
- Home has an accessible Singles/Sealed mode switch. Sealed search/detail reads only local approved/projection data and honestly shows Limited data when evidence is sparse; it does not claim public live acquisition.
- The sealed foundation now includes canonical AshPostgres `SealedProduct` and reviewable `SealedProductAlias` resources, plus the current local public Sealed search/detail projection. One privately curated product and one confirmed local listing have been validated; this is not production data or public permission. A product is draft-only until an administrator approves released, official Polish/English completeness; discontinued approved products remain readable and archive is soft/unpublished. Source imports are pending-only and cannot overwrite reviewed rows.
- Search preloads the active `tcgdex_cardmarket_v1` valuation relationship with the printing, avoiding an N+1 valuation read. Estimates explicitly distinguish current/fresh, stale, and unpriced states.
- Home exposes full policy, methodology, and non-affiliation caveats in collapsed `How prices work` details, uses terse shipping language, 44px-class touch targets, keyboard semantics, and one reveal motion with a reduced-motion fallback. Local-only Market movers show up to 10 total rows, capped at 5 risers and 5 fallers; Singles require the current active policy and current Cardmarket mapping, while Sealed requires current recent ready mapping-confident aggregates and approved public products.
- When a mode has no qualified movers, Home shows up to 10 real local `Recently tracked` rows instead of blank mover lanes. Singles rows retain exact identity and current valuation/freshness where available, otherwise `Price unavailable`; sealed rows are approved public releases within a five-year window. Copy explains that direction appears only after observations on at least two dates. Rows use direct `View price` or `View offers` links. The separate cross-category zero-search-result fallback remains unchanged.
- The 2026-08-08 minimal Home correction remains the presentation baseline. It uses plain collector language: `€…` or `Price unavailable`, `Updated …` plus `May be outdated`, and no instructional filler on search idle; the discovery fallback instead gives the concise explanation that direction appears only after observations on two dates. Rows do not expose TCGdex, legality, policy, freshness, or local-data jargon. The completed autocomplete uses real combobox/listbox semantics, stable `card-option-UUID` stream IDs, bounded ten-option results, visible first/active options, wrapping ArrowUp/ArrowDown, exact active Enter selection, Escape close with query/focus retained, validated touch/click selection, and query-specific live status.
- The approved colors, fonts, and warm square visual direction remain; this correction targets density, copy, jargon, and CTA clarity rather than replacing the visual system.
- Public `/trade` is the completed Phase 3 surface inside Singles: a mobile-first warm square decision bench with deterministic URL-only card IDs/quantities, one local search, explicit add-left/add-right actions, merged quantity rows, local bulk valuation, EUR-plus-PLN totals/difference, stale/unpriced/incomplete states, bounded background acquisition, safe CardDetail return/pick flows, and explicit canonical share/copy. NBP evidence shows the exact rate, effective date, relative age, and pending/failed/no-cache states; cached conversion is retained while acquisition is pending or failed. Public Sealed search/detail exists as a local projection with no production data; private technical-feasibility acquisition is unblocked under the owner assumption, while public permission/republication remains gated.
- Missing or stale data is preferable to fabricated data or silently exceeding acquisition constraints.

### Sealed catalogue foundation — Phase 4 begun, not complete

The current domain foundation is source-neutral and Polish-English official-SKU oriented. `SealedProduct` provides stable canonical slugs, normalized name/search text, an allowlisted product type, series/set and release date, optional finite positive PLN MSRP paired with provenance and source URL, image, language/official flags, draft/approved/archived publication state, current/discontinued distribution state, and source identity/provenance/private payload/timestamps. Draft-only imports use stable source plus source ID, may correct a draft slug, and cannot overwrite reviewed rows. Manual curation may omit source identity. Approval requires a released, non-future product with official Polish and English flags; discontinued approved products remain publicly readable, while archive is soft/unpublished.

`SealedProductAlias` supports name and EAN review, normalized aliases, original values and provenance, pending/approved/rejected queues, and approved-per-product reads. GTIN-8/12/13/14 ASCII normalization and GS1 checksum validation run in both application and database layers, with global uniqueness across canonical products. Imports are pending-only and idempotent and cannot overwrite reviewed aliases. Transaction-local row locks serialize product and alias review transitions and revalidate latest state and completeness under lock. Database constraints and indexes cover state/timestamp invariants, completeness, locale, source pairs, finite MSRP, canonical search fields, product type, GTIN/checksum, slugs, source identity, product foreign keys, and global EAN.

This is the source-neutral/domain foundation plus current public Sealed search/detail projection for Phase 4. LootQuest, CardzHouse, and BoosterPoint are registered only in development for explicit manual private testing; no sealed Cron or public schedule exists. Latest private LootQuest refresh job 81 succeeded in one attempt with 5 admitted requests. Retained LootQuest state remains 154 listings, 154 immutable observations, 153 review mappings, 1 matched mapping, and 155 decisions, confirming unchanged refreshes do not append fake history. CardzHouse and BoosterPoint add private LGS evidence, but no mappings are approved; no ready sealed bands, directional history, or public rights are claimed. External source permission and public republication scope remain launch gates.

The curated `Pokémon TCG: Scarlet & Violet—151 Booster Bundle` is approved and listing source ID 104164 is manually confirmed. Its local daily aggregate is `limited / too_few_regular_retailers` with one regular retailer; its guide is `limited / limited_market_aggregate`, confidence `0.19`, with no fabricated bands. Browser search/detail showed one 899.99 PLN LootQuest offer and honest Limited-data messages. The historical private TCGdex run exhausted all 218 set IDs at 192 synced, 15 excluded, 11 permanent failed, and 20,561 printings. A later live failed-set repair converted those 11 hard failures to partial, and the punctuation-ID correction plus one budget-admitted `exu` sync imported that set 28/28. Current private state is 203 sets, 20,964 printings, and 10 unresolved provider-partial sets. This is not a fully successful production import. Public permission and long-term reliability remain open.

Detailed private enrichment now covers exactly `sv01-001` through `sv01-011`: all 11 matched Cardmarket IDs 702298–702308 and all 11 have current `tcgdex_cardmarket_v1` valuations. These real local observations range from EUR 0.03 to EUR 5.04; Pineco remains EUR 5.04. This is not representative coverage of the 20,964-printing catalogue; the two restored `exu` rows are pending and unpriced. Every successful listing ingest ensures a mapping in the same transaction: missing/invalid/ambiguous evidence creates or refreshes review; one eligible approved exact EAN may create or promote a mutable pending/review mapping to matched through the locked/product-validated Ash action and immutable decision history; terminal matched/rejected decisions are protected from source overwrite; failures roll back the batch.

## Current deployment checkpoint — 2026-08-19

Production is online at <https://tcg-cheap.d.alergeek.me>. The product owner
confirms that the pinned ParadeDB production setup is complete, automatic
release migrations are configured, and the first administrator is provisioned.
Independently verified: the public HTTPS root, `/health`, `/health/live`, a
connected LiveView search event, zero browser console warnings/errors, and the
successful GitHub CI run at
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32250558751>.
`/health` reported database ready, 7 Oban queues, and 3 acquisition providers.
Production currently has no catalogue data, so empty Recently tracked/search
results are expected. Future deploys, migration gating, administrator
provisioning, ParadeDB upgrades/preload, backups, rollback, and incident
handling remain governed by the deployment runbook; no secrets or administrator
identity are recorded here.

The deployment is complete, but the broader MVP remains incomplete. Backup and
restore drill, external monitoring/alerts, production catalogue/data
validation, public source/republication rights, representative evidence,
broader pilot/MVP work, and PostgreSQL 18.4-versus-18.6 update risk remain open.

## Current implementation checkpoint — 2026-08-10

Private sealed retailer adapters now include reusable `TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI` request, pagination, and normalization mechanics; LootQuest uses it without intended behavior change. CardzHouse (fixed endpoint/category `742`) and BoosterPoint (fixed endpoint/category `61`) are new development/private-test-only adapters. All three remain manual and development-only: there is no sealed Cron or public schedule, and each source has an independent zero-cost budget of 50/hour, 100/day, and 500/month. Their exact host/path/category/field policies enforce per-page admission, disabled redirects/retries, bounded pages/listings/body/time, strict PLN minor-unit conversion, conservative English sealed filtering, and exact direct-URL validation. Public recurring acquisition/republication permission remains unresolved.

The two real local shops are deliberately registered as `lgs`; they are not representative `regular_retailer` evidence. CardzHouse job 88 completed in one attempt with 2 admitted requests and retained 96 listings, 96 immutable observations, 96 review mappings, and 96 decisions: 13 in stock and 83 sold out, priced PLN 22.95–1899.99. BoosterPoint job 89 completed in one attempt with 4 admitted requests and retained 232 listings, observations, review mappings, and decisions; all 232 source rows currently report sold out, priced PLN 3.99–990.00. Unchanged reruns jobs 90 and 91 used 2 and 4 admitted requests and retained exactly 96 and 232 rows, proving no duplicate observations or decisions.

No Woo response supplied reliable GTINs, so every new mapping remains `review`; no title-based auto-match was added. Manually inspectable 151 candidates are CardzHouse ID 8393, `Pokémon TCG: 151 – Booster Bundle`, 599.99 PLN sold out, and BoosterPoint ID 5423, `Pokémon TCG: Scarlet and Violet 151 – Booster Bundle (dodruk)`, 187.50 PLN sold out. Neither is approved because no authenticated administrator actor exists, leaving current aggregate, guide, and public-offer behavior unchanged. The focused concrete adapter suite passed 20 tests; the combined adapter/worker/refresh suite passed 45 after review hardening. Canonical `direnv exec . mix check --verbose` passed every static gate and 771 tests. Final review corrected a trailing-newline URL-anchor weakness with `\A...\z`, rejected same-host newline-suffixed URLs for all adapters, and added proof of one admission/one HTTP request on 503; no actionable finding remains.

Home’s local-only Market movers use the fixed preceding 30 UTC dates, at least two distinct daily points spanning at least one day, and at least 2% absolute movement. This deliberate 1-day/2% discovery threshold surfaces more bounded local evidence than the superseded 7-day/5% rule, while excluding single-point and zero-change rows and remaining subject to real-history tuning. With no qualified movers, `Recently tracked` shows up to 10 real local rows per active mode rather than blank riser/faller lanes. No real riser/faller can exist until a second daily observation; one matched regular retailer and one approved matched product currently mean Limited/no ready sealed movement, while the two additional LGS sources remain review evidence.

Final local validation: canonical `direnv exec . mix check --verbose` passed all static gates and 771 tests. Home-specific focused coverage passed 32 tests, and Home-specific browser validation with real rows passed at 1000px desktop and 390px mobile: 10 singles rows and 1 sealed row, direct routes, 44.8px actions, no horizontal overflow, and zero console warnings/errors. Impeccable retained two known square-border false positives plus existing/design-token advisories and no new structural blocker. A final code-review warning about zero-observation wording was corrected. Migration rollback and production-scale query-plan validation remain residual risks. Public source/republication permission, representative Polish multi-retailer validation, recurring history, production deployment/monitoring, and restore drill remain incomplete.

## Evidence on Hand

- The authoritative MVP implementation plan: `knowledge-base/wiki/product/mvp-implementation-plan.md`.
- Current application code and tests in `lib/` and `test/`.
- No testimonials or customer proof are available.
- This thesis-validation product displays canonical TCGdex-hosted card images for exact-printing identification. Missing images retain an honest fallback. The site is explicitly unofficial and non-affiliated; it makes no claim that Pokémon art is independently licensed.

## Product Principles

- Exact identity over approximate matching.
- Honest uncertainty over fabricated precision.
- Fast, local-first reads over synchronous provider dependence.
- Stale data over a blank result when the data is clearly labeled.
- Operational restraint over unnecessary acquisition cost or complexity.

## Accessibility & Inclusion

- English-only MVP.
- Mobile-first and responsive, with desktop support.
- Keyboard-accessible controls and semantic markup.
- LiveView state changes must be communicated accessibly.
- Regression coverage and real browser validation type one character at a time, verify focus after every update, exercise keyboard selection/Escape and composition-event behavior, and cover mobile/desktop with no console errors or horizontal overflow. The completed pass also keeps the bounded listbox internally scrollable without moving the page or input.
