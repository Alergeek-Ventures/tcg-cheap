# Product

<!-- impeccable:product-schema 1 -->

> The facts in this record are collectively inferred from the explicit authoritative MVP plan and the current code/tests because a structured product interview was unavailable. They are not invented.

## Platform

web

## Users

- English-speaking Pokémon TCG players and collectors evaluating common in-shop singles trades.
- English-speaking Polish sealed-product buyers evaluating products and prices.
- The current public surface supports Singles and Sealed search/detail foundations plus local-only Home discovery. Three centrally configured sealed sources provide recurring internal MVP acquisition: LootQuest plus CardzHouse and BoosterPoint LGS evidence; the exact registry and weekly schedule are deployed through Coolify.

## Product Purpose

Provide locally searchable exact Pokémon TCG printings, honest aggregate Cardmarket estimates, and context for understanding trades and sealed-product prices. The Phase 3 trade/share batch is complete. Sealed recurring acquisition now covers three centrally configured sources, with the exact registry and schedule deployed; the overall MVP remains incomplete.

The product has exactly two top-level customer features: **sealed product price comparison** and **singles price comparison**. Singles includes composing a trade and calculating the difference; trade is not a third equal homepage product category.

## Current owner direction — 2026-08-20

All interested parties were included in a group email and agreed that recurring
source pulls are permitted for internal MVP validation. The internal recurring
acquisition/retention blocker is therefore closed for sources covered by the
agreed MVP plan, and the product must be built and demonstrated on the existing
internal/unlisted domain <https://tcg-cheap.d.alergeek.me> in the coming weeks.
Sealed recurring acquisition is agreed and deployed. The final broad-launch decision follows that demonstration. This
direction does not permit bypassing access controls.
Budgets, rate limits, safety, attribution, and data minimization remain
mandatory.

## Positioning

Thesis-validation product built around local cached data and transparent uncertainty. It does not fabricate seller counts, shipping costs, or false precision.

## Operating Context

- Mobile-first checks while making an in-store trade.
- Desktop research for Pokémon TCG singles and sealed products.
- Public use does not require public accounts.

## Capabilities and Constraints

- Phoenix LiveView application using Elixir, Ash, and PostgreSQL.
- Singles are searched and identified by exact printing, including set and collector number plus distinguishing metadata. The exact TCGdex identity path covers observed punctuation IDs such as `exu-!` and literal `exu-%3F` without accepting malformed escapes, path/query delimiters, padded identity, or overlong segments.
- Singles estimates are in EUR and target 24-hour freshness (strictly less than 24 hours is fresh; exactly 24 hours is stale). Home discovery is deliberately bounded to the fixed preceding 30 UTC dates, at least two daily points spanning one day, and at least 2% absolute movement.
- Public Sealed search/detail reads local approved/projection data. Trade unit and row prices remain EUR; side totals and complete differences also show Decimal PLN using the latest locally cached NBP rate.
- Provider calls must happen outside normal request paths; public requests should primarily read local cached data.
- The public exact-printing search surface is the local-only Home LiveView over the cached catalogue. Home defaults to Singles and presents a compact wordmark with `Compare Pokémon prices`, a direct `Find a card` search, and one-column exact-printing price rows with image, name, set, collector number, optional rarity, price, update state, and one solid `View price` CTA. The shared external 250ms `CardAutocomplete` hook serves Home and Trade, preserving the focused input node, query, caret/selection, and focus through result updates; composition pauses search and searches once after compositionend, while Escape cancels a pending debounce.
- Home has an accessible Singles/Sealed mode switch. Sealed search/detail reads only local approved/projection data and honestly shows Limited data when evidence is sparse; it does not claim public live acquisition.
- The sealed foundation now includes canonical AshPostgres `SealedProduct` and reviewable `SealedProductAlias` resources, plus the current local public Sealed search/detail projection. One curated product and one confirmed local listing have been validated; a product is draft-only until an administrator approves released, official Polish/English completeness; discontinued approved products remain readable and archive is soft/unpublished. Source imports are pending-only and cannot overwrite reviewed rows.
- Search preloads the active `tcgdex_cardmarket_v1` valuation relationship with the printing, avoiding an N+1 valuation read. Estimates explicitly distinguish current/fresh, stale, and unpriced states.
- Home exposes full policy, methodology, and non-affiliation caveats in a collapsed methodology disclosure, uses terse shipping language, 48px-class touch targets, keyboard semantics, and one reveal motion with a reduced-motion fallback. The calm warm-square refinement removes noise texture and heavy perimeter borders, keeps one subtle header/input separator, spaces Market movers by about 24px, uses title-case supporting headings, and presents compact `Price movement` with icon-led collapsed `Method` detail. Search, movement, freshness, and disclosure use selective official Fluent UI System Icons Regular; methodology/non-affiliation remains complete but hidden by default. Local-only Market movers show up to 10 total rows, capped at 5 risers and 5 fallers; Singles require the current active policy and current Cardmarket mapping, while Sealed requires current recent ready mapping-confident aggregates and approved public products.
- When a mode has no qualified movers, Home shows up to 10 real local `Recently tracked` rows instead of blank mover lanes. Singles rows retain exact identity and current valuation/freshness where available, otherwise `Price unavailable`; sealed rows are approved public releases within a five-year window. Copy explains that direction appears only after observations on at least two dates. Rows use direct `View price` or `View offers` links. The separate cross-category zero-search-result fallback remains unchanged.
- The 2026-08-08 minimal Home correction remains the presentation baseline. It uses plain collector language: `€…` or `Price unavailable`, `Updated …` plus `May be outdated`, and no instructional filler on search idle; the discovery fallback instead gives the concise explanation that direction appears only after observations on two dates. Rows do not expose TCGdex, legality, policy, freshness, or local-data jargon. The completed autocomplete uses real combobox/listbox semantics, stable `card-option-UUID` stream IDs, bounded ten-option results, visible first/active options, wrapping ArrowUp/ArrowDown, exact active Enter selection, Escape close with query/focus retained, validated touch/click selection, and query-specific live status.
- The approved warm square identity remains, now deliberately calm and restrained; the deployed UI correction commit `7a0f956` targets density, hierarchy, copy, jargon, and CTA clarity rather than replacing the product behavior or exact-data contract. Owner production testing/acceptance remains pending.
- Public `/trade` is the completed Phase 3 surface inside Singles: a mobile-first warm square decision bench with deterministic URL-only card IDs/quantities, one local search, explicit add-left/add-right actions, merged quantity rows, local bulk valuation, EUR-plus-PLN totals/difference, stale/unpriced/incomplete states, bounded background acquisition, safe CardDetail return/pick flows, and explicit canonical share/copy. NBP evidence shows the exact rate, effective date, relative age, and pending/failed/no-cache states; cached conversion is retained while acquisition is pending or failed. Public Sealed search/detail exists as a local projection; recurring acquisition is deployed, while production catalogue completion remains unverified/incomplete.
- Missing or stale data is preferable to fabricated data or silently exceeding acquisition constraints.

### Sealed catalogue foundation — Phase 4 begun, not complete

The current domain foundation is source-neutral and Polish-English official-SKU oriented. `SealedProduct` provides stable canonical slugs, normalized name/search text, an allowlisted product type, series/set and release date, optional finite positive PLN MSRP paired with provenance and source URL, image, language/official flags, draft/approved/archived publication state, current/discontinued distribution state, and source identity/provenance/private payload/timestamps. Draft-only imports use stable source plus source ID, may correct a draft slug, and cannot overwrite reviewed rows. Manual curation may omit source identity. Approval requires a released, non-future product with official Polish and English flags; discontinued approved products remain publicly readable, while archive is soft/unpublished.

`SealedProductAlias` supports name and EAN review, normalized aliases, original values and provenance, pending/approved/rejected queues, and approved-per-product reads. GTIN-8/12/13/14 ASCII normalization and GS1 checksum validation run in both application and database layers, with global uniqueness across canonical products. Imports are pending-only and idempotent and cannot overwrite reviewed aliases. Transaction-local row locks serialize product and alias review transitions and revalidate latest state and completeness under lock. Database constraints and indexes cover state/timestamp invariants, completeness, locale, source pairs, finite MSRP, canonical search fields, product type, GTIN/checksum, slugs, source identity, product foreign keys, and global EAN.

This is the source-neutral/domain foundation plus current public Sealed search/detail projection for Phase 4. LootQuest, CardzHouse, and BoosterPoint recurring acquisition is deployed; production completion remains unverified/incomplete. Weekly UTC runs are staggered Monday 01:00 LootQuest (`regular_retailer`), 02:00 CardzHouse (`lgs`), and 03:00 BoosterPoint (`lgs`). Deployment configures six providers total; each sealed source has 50/hour, 100/day, and 500/month limits, with provider disable controls and Coolify/app takedown as the operational stop. Latest private LootQuest refresh job 81 succeeded in one attempt with 5 admitted requests. Retained LootQuest state remains 154 listings, 154 immutable observations, 153 review mappings, 1 matched mapping, and 155 decisions, confirming unchanged refreshes do not append fake history. CardzHouse and BoosterPoint add LGS evidence, but no mappings are approved; no ready sealed bands or directional history are claimed. Broad launch follows the stakeholder demo.

The curated `Pokémon TCG: Scarlet & Violet—151 Booster Bundle` is approved and listing source ID 104164 is manually confirmed. Its local daily aggregate is `limited / too_few_regular_retailers` with one regular retailer; its guide is `limited / limited_market_aggregate`, confidence `0.19`, with no fabricated bands. Browser search/detail showed one 899.99 PLN LootQuest offer and honest Limited-data messages. The historical private TCGdex run exhausted all 218 set IDs at 192 synced, 15 excluded, 11 permanent failed, and 20,561 printings. A later live failed-set repair converted those 11 hard failures to partial, and the punctuation-ID correction plus one budget-admitted `exu` sync imported that set 28/28. Current private state is 203 sets, 20,964 printings, and 10 unresolved provider-partial sets. This is not a fully successful production import. Long-term reliability and complete production import remain open.

Detailed private enrichment now covers exactly `sv01-001` through `sv01-011`: all 11 matched Cardmarket IDs 702298–702308 and all 11 have current `tcgdex_cardmarket_v1` valuations. These real local observations range from EUR 0.03 to EUR 5.04; Pineco remains EUR 5.04. This is not representative coverage of the 20,964-printing catalogue; the two restored `exu` rows are pending and unpriced. Every successful listing ingest ensures a mapping in the same transaction: missing/invalid/ambiguous evidence creates or refreshes review; one eligible approved exact EAN may create or promote a mutable pending/review mapping to matched through the locked/product-validated Ash action and immutable decision history; terminal matched/rejected decisions are protected from source overwrite; failures roll back the batch.

## Owner-directed pricing refinement — 2026-08-27

The accepted refinement is deployed in commits `cedd80e` and `9556fbf`; GitHub CI runs [33096381670](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33096381670) and [33098246258](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33098246258) passed. Home movement rows are now hooks with exact identity plus signed movement only; prior/current prices, dates, and freshness belong on detail. Recently tracked rows keep identity and current estimate without freshness text. Every public TCG CHEAP wordmark uses Barlow Condensed 700 beside the official Fluent Gift Card Add Regular icon.

CardDetail uses a larger image column, places compact Current estimate and Printing side by side at wide desktop, and lets history span the full 72rem container. The adjacent information tooltip explains the consistent aggregated Cardmarket estimate via TCGdex without exposing metric, policy version, or timestamp. Trade is linked for comparison; no unsupported algorithm selector is claimed. The chart preserves gaps, shows min/max, exact window dates, guides, and exact date/EUR hover and focus tooltips. Escape dismisses both hover and focus tooltips without moving focus, and blur/click-away restores them. A full-width collapsed observation ledger exposes every exact observation for touch and detailed review; one observation still renders summary and ledger without a chart.

Production `/health` at 2026-08-27 17:30 UTC reported database ready, 7 Oban queues, and 6 providers. Connected production checks on Home and `/cards/me05-039` verified compact mover/recent rows, the new wordmark, mobile identity → estimate → image → Printing order, full-width history, three chart points, exact Jul 29 → Aug 27 window labels, working hover/Escape behavior, a full-width three-row observation ledger, zero horizontal overflow at 390px, and zero console warnings/errors. Wide desktop retained the 1152px overview/history container, 384px image, side-by-side estimate/Printing, and full-width history. Canonical `mix check --verbose` passed all gates and 883 tests.

## Owner-directed visual polish — 2026-08-31

The CardDetail/Home visual polish rollout is deployed in commits `8919a57` (visual polish), `965857a` (mobile chart alignment), `a116653` (detail-column alignment and right-justified Printing values), and `dd03d9e` (legal-format/GLC policy). Successful CI runs are [33394458609](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33394458609), [33395246388](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33395246388), [33396149077](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33396149077), and [33400947635](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33400947635). Canonical `mix check --verbose` passed all gates and 895 tests. Production health at 2026-08-31 14:16 UTC reported database ready, 7 Oban queues, and 6 providers.

Connected production checks at 320px and 1440px found zero horizontal overflow and console warnings, centered the 24px search icon/text, verified the estimate/Printing exact heading baseline, right-aligned Printing values, and aligned chart SVG/targets. They also verified Last update/no explanation/count/ledger behavior, tooltip Escape and recovery, Standard/Expanded/Gym Leader Challenge Fluent icons, and the Dhelmise local GLC legal result. CardDetail computes GLC eligibility under the implemented versioned local `glc_local_2026-04-20` policy; the [GLC rules](https://gymleaderchallenge.com/rules), [FAQ](https://gymleaderchallenge.com/faq), and [ban list](https://gymleaderchallenge.com/ban-list) links are provided, with future-review limitations retained. This records the implemented policy behavior and does not claim exact eligibility beyond that policy.

## Owner-directed operator observability rollout — 2026-09-01

Implementation commit `d641d01` is deployed. Successful [CI](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33509547612) covered the container build, DB image validation, and canonical gate; canonical local/CI validation passed 905 tests. Dependencies, base images, and devenv were refreshed, and the Hex audit reported no advisories. Production `/health` reported healthy with revision `d641d013b6721e26ce78772f7226a58aa1fa9acf`, DB ready, 7 Oban queues, and 6 providers.

The authenticated `/admin/dashboard` surface includes Phoenix LiveDashboard, Ecto Stats with `pg_stat_statements`, Request Logger, and live-only application logs; `/admin/oban` exposes jobs, queues, crons, and controls. Both routes redirect unauthenticated visitors to sign-in.

## Authenticated production operations audit and recovery — 2026-09-01

The authenticated audit covered Operations, Oban, LiveDashboard/Ecto Stats, review desk, cards, valuations, products, and import issues. Initial state was 5 card sets, 67 card printings, 415 historical valuation snapshots, 0 sealed products/aliases/import issues, 436 retailer listings/mapping records, and 25+ pending listing mappings; there were no product or alias drafts. No sealed product was created or approved because canonical product identity/evidence did not yet exist.

Oban showed 26 discarded Singles set-collection jobs, all exhausted on budget. One CardzHouse sealed refresh had remained executing for about six days and was cancelled by deployment/restart. CardzHouse and BoosterPoint last successful sealed refreshes remained Aug 24; LootQuest succeeded Aug 31. A controlled retry of the 26 discarded Singles jobs saturated the intended global 100/hour cap: 63 TCGdex catalogue and 37 Cardmarket valuation admissions. This raised cards from 67 to 127 and historical snapshots to 552. The 14:00 valuation sweep consumed the next hourly 100; daily usage was 200/1000.

Durable fix commit `608a4da` (`608a4da0195d420e7d717568816f8fa51078ce06`) preserves exact UTC reset timestamps, snoozes Singles bootstrap/set jobs and valuation jobs without consuming attempts, keeps terminal budget failures terminal, preserves telemetry without false terminal broadcasts, and fixes dated manual Singles bootstrap uniqueness while retaining seven-day cron cadence. The local canonical gate passed 914 tests/static checks; [CI](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33521933292) passed all jobs. Production `/health` reported healthy at revision `608a4da0195d420e7d717568816f8fa51078ce06`. Runtime proof with the ledger at 100/100: dated manual Singles collection queued a new canonical job, and Oban scheduled job 2217 for the 15:00 UTC reset at attempt 0/5 rather than discarding it.

Job 2217 was scheduled at the 15:00 UTC reset at attempt 0/5, resumed after one snooze, and completed. Immediately afterward the ledger was 8/100 hourly and 208/1000 daily. Its replay exposed a separate defect: five valid TCGdex sets were cancelled as provider-response failures, opening the 5/5 circuit. The root cause was direct Elixir term comparison of `%Date{}` values in Singles release/window logic.

Fix commit `9728dd2` uses semantic inclusive `Date.compare/2` boundaries and includes valid-current, safely skipped old-set, and future-set regressions. The canonical local gate passed all static checks and 917 tests; [CI](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33526404290) passed all jobs. Production health is healthy at revision `9728dd29a8850afa89756a3b5bef15aa2d9794e3`.

After deployment, TCGdex job 2246 (`me05`, offset 0) completed on attempt 3/5 in 1.539s. Idempotent continuation progressed through existing chunks; job 2257 (`me05`, offset 80) is scheduled for the 17:00 UTC reset at attempt 0/5 after the exact 100/100 hourly cap. TCGdex is active with a closed circuit and circuit failures 0/5; its last failure category is budget. Current global usage was 315/1000 daily and TCGdex usage 170/1000 daily. Cards remained 127 and valuation snapshots 553. This does not claim complete Singles import.

CardzHouse job 2247 completed in 3.727s, with last success `2026-09-01T15:03:09.362154Z` and two daily requests. BoosterPoint job 2248 completed in 10.006s, with last success `2026-09-01T15:04:38.263957Z` and four daily requests. Both providers are active with closed circuits and zero failure streak.

Listings and listing-product mappings are now 444 each, up from 436. Review remains 0 product drafts, 0 aliases, and 25+ pending mappings; no sealed approval was made because canonical identity evidence is absent. Ecto Stats findings remain small duplicate indexes only; cache ratios, bloat, and foreign-key checks are healthy. Residual product follow-up is limited to canonical sealed identity curation/mapping and allowing the already scheduled budget-safe Singles continuation to resume.

## Current deployment and visual refinement — 2026-08-26

The UI correction commit `7a0f956` is pushed and deployed to production; GitHub
[CI run 32970306496](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32970306496)
succeeded. Production `/health` at 2026-08-26 12:50 UTC reported database ready,
7 Oban queues, and 6 providers. Production Home renders `Price movement`, has no
`#market-movers-intro`, keeps `Method` collapsed by default, and renders the
Fluent search icon. Production `/cards/me01-114` renders `Current estimate`,
`Printing`, `Price history`, plain `Standard · Expanded`, valuation/provenance,
and the existing two-point history. Connected 390px Home/CardDetail checks had
zero horizontal overflow and zero console warnings/errors. CardDetail
supersedes the prior saturated orange archive board, boxed columns/status boxes,
colored legal-format treatments, and giant framed chart with calm warm paper:
desktop uses image plus one coherent detail column, mobile orders identity →
estimate → image → printing, and valuation/metadata/history are unboxed with
plain legal-format text, quiet statuses/disclosure, and a sensible chart width.
Exact identity, data, provenance, and history behavior are unchanged.
Canonical `mix check --verbose` passed all gates and 883 tests. Focused
Home/CardDetail/Trade/Sealed suites passed 96 tests (Home/CardDetail: 49).
Desktop and 390px Home/CardDetail plus 390px shared Trade/Sealed regression
checks found zero horizontal overflow, 48px sampled controls, and no
current-page console warnings or errors. One Impeccable detector pass found
only design-ramp typography advisories in changed CSS; touched public
metadata/date sizes were normalized to a 14px minimum. Review findings for
shared `decision-world` scope, the permanent icon class, and the Microsoft
notice were fixed.

Owner production testing/acceptance remains pending; existing sealed
catalogue/mapping and mover-history tuning limitations remain.

## Historical/superseded deployment checkpoint — 2026-08-19 (superseded by the current 2026-08-26 checkpoint)

Production is online at <https://tcg-cheap.d.alergeek.me>. The product owner
confirms that the pinned ParadeDB production setup is complete, automatic
release migrations are configured, and the first administrator is provisioned.
Independently verified: the public HTTPS root, `/health`, `/health/live`, a
connected LiveView search event, zero browser console warnings/errors, and the
successful GitHub CI run at
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32285087422>.
`/health` reported database ready, 7 Oban queues, and 3 acquisition providers.
At 2026-08-19 18:16 UTC, exact public Pitch Black `me05-001` through at least
`me05-040` had imported/scoped and rendered real Cardmarket aggregate snapshots
(examples: 001 €0.02, 021 €0.02, 040 €0.03); Tropius autocomplete returned exact
`me05-001`, while unscoped `base1-001` remained not found. Browser console
warnings/errors were zero. Collection was still budgeted/in progress: this
closes initial production data validation, not all 120 cards or complete
rolling IR/SIR coverage. Future deploys, migration gating, administrator
provisioning, ParadeDB upgrades/preload, backups, rollback, and incident
handling remain governed by the deployment runbook; no secrets or administrator
identity are recorded here.

The deployment is complete, but the broader MVP remains incomplete. Backup and
restore drill, external monitoring/alerts, complete 120-card Pitch Black
coverage, complete rolling IR/SIR coverage,
representative evidence, broader pilot/MVP work, and PostgreSQL 18.4-versus-18.6
update risk remain open.

## Approved production Singles collection — 2026-08-19

Singles production collection is fail-closed. `CardPrinting` scopes are
`pitch_black_full`, `rolling_ir_sir`, `curated_playable`, and `legacy_local`,
with expiry and provenance. Provider imports/briefs never auto-scope. Public
Home search/recent, CardDetail, Trade, and mover SQL require active nonexpired
scope. Migration backfill assigns existing local rows only to `legacy_local`,
preserving useful local state while empty production gains no broad rows; broad
catalogue discovery remains private.

Bootstrap starts within 15 minutes and is successful-run unique while retained by
the configured seven-day Oban Pruner.
It strictly discovers TCGdex sets, imports every `me05` card, and imports only
exact IR/SIR cards from the inclusive rolling prior two calendar years, in
chunks of at most 20. Complete set `cardCount` evidence is required;
incomplete/transient evidence retries, and scanned non-target cards are never
imported. Daily 14:00 UTC refresh keyset-paginates every active, nonexpired,
scoped, matched pricing candidate and proactively enqueues valuations, including
fresh candidates; public on-demand work remains missing/stale-only.
`ValuationWorker` remains the sole provider-budget admission immediately before
HTTP. Operations provides a manual scoped trigger.

`curated_playable` has a fixed seven-entry policy version `2026-08-19-naic`.
The dated official/Limitless/TCGdex evidence was explicitly approved for local
implementation, and the implementation is deployed. All seven exact routes
resolved at the initial checkpoint: four had valuations and three had honest
no-valuation states. Full valuation and coverage remains incomplete. Its
separate 15-minute bootstrap
is successful-run unique while retained by the configured seven-day Oban Pruner
and creates seven priority-1 child jobs. Completed bootstrap and child jobs remain
deduplicated while retained by that Pruner. Each child admits at most two TCGdex requests per
card per attempt, validates exact identity/legality/set, and uses fixed
non-sliding expiry.
Shared Ash transaction plus row-lock scope merging gives rolling/Pitch
Black/legacy/admin precedence; matched cards enqueue valuation. There is no
request-path HTTP and no sealed acquisition work occurs in this curated Singles worker path. Existing Pitch v2 remains independent; sealed adapters are separate from this curated path.
Curated rows become public only after successful deploy/import and expire
automatically. Evidence is in the
[curated manifest](knowledge-base/raw/2026-08-19-curated-playable-manifest.md),
which expires inclusive 2026-11-17. Representative evidence, backups, and
monitoring remain open.

## Current implementation checkpoint — 2026-08-10

The sealed retailer adapters use reusable `TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI` request, pagination, and normalization mechanics. The exact three-source registry and Monday 01:00/02:00/03:00 UTC schedule are deployed; deployment configures six providers total, each source has 50/hour, 100/day, and 500/month limits, and provider disable controls plus Coolify/app takedown provide operational stop controls. Their exact host/path/category/field policies enforce per-page admission, disabled redirects/retries, bounded pages/listings/body/time, strict PLN minor-unit conversion, conservative English sealed filtering, and exact direct-URL validation.

The two real local shops are deliberately registered as `lgs`; they are not representative `regular_retailer` evidence. CardzHouse job 88 completed in one attempt with 2 admitted requests and retained 96 listings, 96 immutable observations, 96 review mappings, and 96 decisions: 13 in stock and 83 sold out, priced PLN 22.95–1899.99. BoosterPoint job 89 completed in one attempt with 4 admitted requests and retained 232 listings, observations, review mappings, and decisions; all 232 source rows currently report sold out, priced PLN 3.99–990.00. Unchanged reruns jobs 90 and 91 used 2 and 4 admitted requests and retained exactly 96 and 232 rows, proving no duplicate observations or decisions.

No Woo response supplied reliable GTINs, so every new mapping remains `review`; no title-based auto-match was added. Manually inspectable 151 candidates are CardzHouse ID 8393, `Pokémon TCG: 151 – Booster Bundle`, 599.99 PLN sold out, and BoosterPoint ID 5423, `Pokémon TCG: Scarlet and Violet 151 – Booster Bundle (dodruk)`, 187.50 PLN sold out. Neither is approved because no authenticated administrator actor exists, leaving current aggregate, guide, and public-offer behavior unchanged. The focused concrete adapter suite passed 20 tests; the combined adapter/worker/refresh suite passed 45 after review hardening. Canonical `direnv exec . mix check --verbose` passed every static gate and 771 tests. Final review corrected a trailing-newline URL-anchor weakness with `\A...\z`, rejected same-host newline-suffixed URLs for all adapters, and added proof of one admission/one HTTP request on 503; no actionable finding remains.

Home’s local-only Market movers use the fixed preceding 30 UTC dates, at least two distinct daily points spanning at least one day, and at least 2% absolute movement. This deliberate 1-day/2% discovery threshold surfaces more bounded local evidence than the superseded 7-day/5% rule, while excluding single-point and zero-change rows and remaining subject to real-history tuning. With no qualified movers, `Recently tracked` shows up to 10 real local rows per active mode rather than blank riser/faller lanes. No real riser/faller can exist until a second daily observation; one matched regular retailer and one approved matched product currently mean Limited/no ready sealed movement, while the two additional LGS sources remain review evidence.

Final local validation: canonical `direnv exec . mix check --verbose` passed all static gates and 771 tests. Home-specific focused coverage passed 32 tests, and Home-specific browser validation with real rows passed at 1000px desktop and 390px mobile: 10 singles rows and 1 sealed row, direct routes, 44.8px actions, no horizontal overflow, and zero console warnings/errors. Impeccable retained two known square-border false positives plus existing/design-token advisories and no new structural blocker. A final code-review warning about zero-observation wording was corrected. Migration rollback and production-scale query-plan validation remain residual risks. Representative Polish multi-retailer validation, recurring history, production deployment/monitoring, and restore drill remain incomplete.

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
