# Provider and Acquisition Feasibility

- Updated: 2026-09-08
- Sources: [Production Singles scope source capture](../../raw/2026-08-19-production-singles-scope-sources.md); [Curated playable manifest](../../raw/2026-08-19-curated-playable-manifest.md); [Provider/source experiment capture](../../raw/2026-08-07-provider-source-experiments.md); [Scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md); [NBP API EUR rate](../../raw/2026-08-08-nbp-api-eur-rate.md); [LootQuest Store API capture](../../raw/2026-08-09-lootquest-store-api.md); [CardzHouse and BoosterPoint Store API capture](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md); [TCGdex punctuation card-ID capture](../../raw/2026-08-14-tcgdex-punctuation-card-ids.md); [current MVP north star](../product/mvp-implementation-plan.md); project code and validation; [2026-08-19 TCGdex set ordering and series capture](../../raw/2026-08-19-tcgdex-set-ordering-and-series.md)
- Raw: [2026-09-02 Boosterland and Colligere Store APIs](../../raw/2026-09-02-boosterland-colligere-store-apis.md); [2026-08-19 production Singles scope sources](../../raw/2026-08-19-production-singles-scope-sources.md); [2026-08-19 curated playable manifest](../../raw/2026-08-19-curated-playable-manifest.md); [2026-08-07 provider/source experiments](../../raw/2026-08-07-provider-source-experiments.md); [2026-08-07 scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md); [2026-08-08 NBP API EUR rate](../../raw/2026-08-08-nbp-api-eur-rate.md); [2026-08-09 LootQuest Store API](../../raw/2026-08-09-lootquest-store-api.md); [2026-08-10 CardzHouse and BoosterPoint Store APIs](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md); [2026-08-14 TCGdex punctuation card IDs](../../raw/2026-08-14-tcgdex-punctuation-card-ids.md); [2026-08-19 TCGdex set ordering and series capture](../../raw/2026-08-19-tcgdex-set-ordering-and-series.md)

## Current Singles source boundary and production checkpoint — 2026-09-08 (Raw: N/A — codebase update)

Bulk-only release `68b73cc624e0ac6f450bf1c0af05bdc35eaaf565` deployed 2026-09-08.
CI [34212821835](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/34212821835)
passed 1,117 tests; production health and browser Home/card/trade smoke passed
at EUR 263.65. Cleanup removes old Provider/Offer/default_v1 modules and
interfaces plus `pricing_checked_at` via generated migration; final
commit/deploy is pending at documentation time.

`cardmarket_bulk_v1` is the fixed public/new-write Singles source. TCGdex is
catalogue/detail/image/Cardmarket identity only. Historical
`tcgdex_cardmarket_v1` snapshots are retained/readable, but not selectable or
newly writable. There is no fallback, selectable policy, cutover/readiness
process, policy cache, per-card pricing worker, acquisition path, or 14:00 UTC
sweep. The only recurring Singles acquisition is the fixed daily 03:00 UTC bulk
sync. Local public Home, CardDetail, and Trade show stale/unpriced values
honestly; committed batch/mapping invalidations refresh mounted surfaces.
Malformed, implausible, anomalous, ambiguous, cross-batch, or non-exact evidence
fails closed; materialization requires exact mapping and the same successful
batch. Admin source, batch, catalogue, mapping, detail, and materialization
diagnostics are read-only.

## Historical Cardmarket bulk rollout and handoff — 2026-09-07 (Raw: N/A — codebase update)

Implementation commit `b7afc9049a8af42dd569f44d2c140cb58f64221c` (`b7afc90`) was
pushed and deployed on 2026-09-07. GitHub CI run
[34160080003](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/34160080003)
passed all three jobs and the canonical 1,162 tests. At approximately 20:40 UTC,
`/health` and `/health/live` were healthy at the exact `b7afc9049a8af42dd569f44d2c140cb58f64221c` SHA, with the
database ready, eight Oban queues, and ten acquisition providers. The configured
release migration gate succeeded for traffic promotion; exact inspection of the
seven migration table rows remains operator verification. Seven forward-only
migrations exist: `20260903120603_cardmarket_bulk_v1.exs`,
`20260903134323_cardmarket_bulk_crosswalk.exs`,
`20260907102216_harden_cardmarket_bulk_pipeline.exs`,
`20260907102604_harden_cardmarket_bulk_pipeline_constraints.exs`,
`20260907110602_cardmarket_expansion_review.exs`,
`20260907111314_cardmarket_expansion_review_hardening.exs`, and
`20260907134317_cardmarket_evidence_identity.exs`. The `20260907102216`,
`20260907111314`, and `20260907134317` down paths intentionally raise; all
seven are operationally forward-only.

Public connected smoke passed Home/search, valid `/cards/sv08-238`,
`/trade?left=sv08-238:1`, matching EUR 263.65 detail/trade, and history, with
Cardmarket via TCGdex as the effective source. The 390px and 1440px checks had
no overflow and zero console warnings/errors. `/cards/tk-sm-r-14` is absent/not
valid in production, not a regression. No administrator authentication was
available, so the explicit Coolify policy variable, `/admin/operations`,
Oban/dashboard, exact migration rows, Cron, first sync/import counts, and
persisted readiness remain unverified. Effective public policy is TCGdex;
bulk remains disabled pending the first real sync and two-batch readiness/cutover.

The daily 03:00 UTC queue/provider uses fixed product/price URLs, category 51
Pokémon Single, a 32 MiB response cap and 100,000-row cap, no redirect/retry, 5s connect and 15s receive/request
timeouts, and a 15-minute monotonic deadline with 30s cleanup margin. Lifecycle
is staged/succeeded/failed, with first-batch floors 10,000 products, 10,000
Singles prices, and 5,000 priceable Singles. Materialization requires product,
price, expansion mapping, and card mapping evidence from one successful batch;
only anchor/auto_matched card evidence is allowed. Missing, ambiguous,
unapproved, or cross-batch evidence fails closed. Expansion approval is the
latest-successful-batch exact pair, with immutable actor/version history and
decision-specific replay. Review is bounded to 25 rows plus `25+`, authorized
reads, a 1,000-row fail-closed resolution scan, and safe evidence only.

The parser requires nonblank product `dateAdded`. Mapping supports safe
same-batch A→B→A correction from immutable exact evidence, never overwrites
administrator mappings, and materialization is concurrent same-batch idempotent.

Only exact `tcgdex_cardmarket_v1` and `cardmarket_bulk_v1` policy values are
recognized; malformed/missing/error/unready cases select TCGdex. Readiness additionally requires a completed coherent nonfuture `all_sets` TCGdex catalogue run, no active catalogue run, and zero unresolved partial/malformed/failed catalogue-set issues; operations exposes bounded catalogue counts. Freshness
requires persisted UTC nonfuture fetched/completed/product-created/price-created
evidence within 129,600 seconds/36h, plus existing conservative count,
materialization, mapping/agreement, coverage, and overlap gates. Successful
persisted sync/replay invalidates mappings only after commit; notification
failure is retryable and idempotent, while rollback and normal attempt-1 no-op
emit no broadcasts. Coverage gain/overlap/agreement use only latest-batch approved exact staged-value/metric-matching valuations. Local evidence reached 169 TCGdex, 244 bulk, 169 overlap,
75 bulk-only, and 244 exact approved/unambiguous latest valuations; no previous
batch and failed gates kept cutover not ready.
The supervised policy cache is max 30 seconds, refreshes automatically,
broadcasts effective expiry changes, reconciles timed-out callers fail closed,
and mounted Home/CardDetail/Trade refresh policy-dependent data without mixing
or requesting TCGdex under bulk. Canonical local `mix check --verbose` passed
all static gates/Dialyzer and 1,162 tests; final read-only review found no
actionable or critical/high findings. First sync/import counts, persisted
readiness, and admin-only operational evidence remain unverified; CI, deployment,
health, and public smoke verification are recorded above.

### Current Singles source status and controls

The current public/new-write source is fixed `cardmarket_bulk_v1`; TCGdex is
catalogue/detail/image/Cardmarket identity only. Historical
`tcgdex_cardmarket_v1` snapshots remain readable but cannot be selected or
newly written.
Both sources are aggregate-only and do not prove seller-level fields,
shipping, or destination eligibility. When bulk is selected, the daily 14:00
UTC TCGdex refresh is a no-op and the daily 03:00 UTC bulk sync is the
acquisition path. The configured source-health boundary is 36 hours where a
current successful acquisition is required. Existing provider controls,
budgets, mapping locks, review routing, and `/admin/operations` evidence remain
the operational controls; next actions are the first real production sync and
later a second distinct successful bulk batch, followed by readiness review, not
a claim of cutover or production acceptance.

## Historical production provider state — 2026-09-03 (Raw: [capture](../../raw/2026-09-02-boosterland-colligere-store-apis.md))

Production revision `d55a26b1368084bbaf7a25b65a2211f437e6c540` is verified by passed CI runs [33747809832](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33747809832) and [33748881597](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33748881597). `/health` and `/health/live` returned 200 with healthy DB/Oban, seven queues, and nine providers. Boosterland (category 40, Monday 05:00 UTC) and Colligere (category 23, Monday 06:00 UTC) are active persisted `lgs` sources: one admitted request each, 8 and 37 active listings, six active retailers overall, no related import issues, and independent 50/hour, 100/day, 500/month budgets. PokeNest was rejected under terms §16; other candidates showed 402/404.

Sealed evidence currently includes 19 approved rows with sourced complete facts and positive applicable pack counts, 13 complete official USD reference-price tuples, and 17 complete canonical image tuples. Missing authoritative PLN MSRP/facts remain unset. Pitch Black Binacle 3-pack and SV151 Booster Bundle remain intentionally image-null and unpublished without qualified retailer image evidence. There is no production Singles-offer provider. Retailer mappings and real buying-model validation still require review.

Current public behavior is canonical non-Pocket paper cards with staged detail/pricing and strict Sealed factual/image publication readiness. Public Pitch Black search exposes Booster Box, Pack, and ETB; Pitch Black Booster Box/ETB and Destined Rivals Booster Box returned 200 with loaded canonical images/offers and no browser console/page errors. The image correction migration `20260903102840` was followed by the forward-only Pitch Black ETB product-type correction `20260903111025`. Max-attempt pricing persistence snoozes without advancing the serial chain; listing-derived drafts require the exact pending/review mapping under a transaction-local lock.

## Historical production checkpoint — 2026-08-25 (superseded)

Production commit `02b8d65` is deployed; [CI run 32369920522](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32369920522) succeeded. Health reported a ready database, 7 Oban queues, and 6 providers. All seven curated exact routes resolved publicly; the initial checkpoint had four valuations and three honest no-valuation states. Curated evidence expires 2026-11-17. The three-source sealed registry and Monday 01:00/02:00/03:00 UTC Cron are deployed. Jobs 916/917/918, Singles refresh 920, and aggregate 921 (15:01 UTC) were enqueued only; completion is unverified. Public sealed search for `151 Booster Bundle` returned no product, so approved production sealed catalogue/mappings remain incomplete. The strict 24-hour Singles change is the current release change being prepared, not a claim of pre-commit production verification.

## Historical Singles freshness and sweep correction — 2026-08-25 (superseded by 2026-09-08 bulk-only boundary; Raw: N/A — codebase update)

This dated checkpoint records the former strict 24-hour TTL and 14:00 UTC
on-demand/proactive refresh behavior. The current 2026-09-08 boundary supersedes
that Singles behavior: `cardmarket_bulk_v1` is the sole public/new-write source,
the daily 03:00 UTC bulk sync is the only pricing acquisition path, and no
per-card `ValuationWorker` or public on-demand enqueue exists.

## Current owner direction — 2026-08-20 (Raw: N/A — product-owner direction)

All interested source parties agreed that recurring source pulls and use on the
internal/unlisted demo domain are permitted for the agreed MVP. The agreement,
and any later stakeholder conversation, is private and out-of-band between the
owner and sources. Permission is settled and non-blocking for repository
implementation, validation, deployment, and demo work. The existing
internal/unlisted domain
<https://tcg-cheap.d.alergeek.me> is the required demonstration surface in the
coming weeks. Sealed recurring acquisition is agreed and implemented locally,
deployed through Coolify. If the owner needs to stop the demo, taking the app down
in Coolify is the operational mechanism; no application state machine is
required. Fixed source adapters, budgets, rate limits, no access-control
bypass, data validation, safety, attribution, and data-minimization controls
remain engineering requirements. No permission/publication gate or rights
state is modeled in the application.

## Approved production Singles acquisition — 2026-08-19

**Historical/superseded 2026-08-19 checkpoint:** Production checkpoint `ccc394c` validated green CI run
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32285087422>,
database/7 Oban queues/3 providers, and by 18:16 UTC exact public `me05-001`
through at least `me05-040` with real Cardmarket aggregates (001 €0.02, 021
€0.02, 040 €0.03). Exact Tropius autocomplete returned `me05-001`, unscoped
`base1-001` was not found, and browser console warnings/errors were zero. This
closes initial production validation only; collection was still budgeted/in
progress, not all 120 or complete rolling IR/SIR.

The curated batch then had dated official/Limitless/TCGdex evidence explicitly
approved for local implementation and was implemented locally under fixed policy
`2026-08-19-naic`: separate 15-minute bootstrap, successful-run unique
including seven completed prior days, seven priority-1 child jobs, completed
child-job deduplication for seven days, at most two TCGdex requests per card per
attempt, exact identity/legality/set validation, fixed expiry,
shared Ash transaction/row-lock scope merge with rolling/Pitch Black/legacy/admin
precedence, and valuation enqueue on matches. No request-path HTTP or sealed
adapter; Pitch v2 stays independent. Rows become public only after deploy/import
and expire automatically. Representative evidence, sealed-source reliability,
backups, and monitoring remain technical work. See [manifest](../../raw/2026-08-19-curated-playable-manifest.md).

### Collection policy v2

The 2026-08-19 capture observed 218 IDs with `me05` last in an
oldest-first-ish list, not an ordering guarantee. Initial discovery applies a
bounded candidate ID-prefix prefilter for configured `sv`/`me`, followed by
authoritative strict fetched `serie.id` revalidation; `tcgp` is excluded at
fetched evidence. `me05` initial/continuations have priority 0, an active
rolling set continuation has priority 1, and untouched rolling initial scans
have priority 2, so startup no longer fails slowly on irrelevant early IDs or
fans out across Pocket. Cron and manual actions use the exact policy version.
Legacy queued v1 jobs self-cancel before admission and consume no provider
budget. Chunks, budgets, and public scope are unchanged.

The scope-first boundary uses `pitch_black_full`, `rolling_ir_sir`,
`curated_playable`, and `legacy_local`, with expiry/provenance. Provider
imports/briefs never grant scope; public Home search/recent, CardDetail, Trade,
and mover SQL require active nonexpired scope. Existing local rows are backfilled
as `legacy_local`; empty production receives no broad catalogue. Bootstrap starts
within 15 minutes, is unique after a successful run for seven days, imports
complete `me05`, and imports only exact IR/SIR cards from the inclusive rolling
prior two calendar years in chunks of at most 20. Complete `cardCount` evidence
is required; incomplete/transient evidence retries and scanned non-target cards
are never imported. Daily 14:00 UTC keyset refresh enqueues every active,
nonexpired, scoped, matched candidate, including fresh valuations; public
on-demand remains missing/stale-only. `ValuationWorker` is the sole immediate
pre-HTTP budget admission.
Admin operations provides a scoped trigger. The curated seven-entry batch is
approved and deployed; production completion and full valuation coverage remain unverified/incomplete.
The sealed registry and Monday UTC bootstrap are deployed through Coolify; the
current registry has nine providers, including Boosterland/Colligere at 05:00
and 06:00 UTC, with persisted 8/37 active listings and six active retailers.

## Historical implementation checkpoint — 2026-08-14 (superseded)

The 2026-08-20 owner direction is authoritative current state: permission for
agreed-MVP recurring pulls and internal/unlisted demo use is settled and
non-blocking across implementation, validation, deployment, and demo work.
The agreement is private/out-of-band and is not represented as application
state. Remaining work below is technical evidence, implementation, deployment,
and operations work only; fixed adapters, budgets, rate limits, no
access-control bypass, and data validation remain mandatory.

**Historical 2026-08-14 adapter checkpoint (superseded):** The reusable `WooCommerceStoreAPI` owned bounded fixed-policy request, pagination, and normalization mechanics for the then-current three-source registry. Current production has six sealed sources and nine providers, with independent 50/hour, 100/day, and 500/month budgets. Exact host/path/category/field policies enforce per-page admission, disabled redirects/retries, bounded pages/listings/body/time, strict PLN minor-unit conversion, conservative English sealed filtering, and exact direct URL validation.

Private runs retained CardzHouse job 88 (2 requests; 96 listings/observations/review mappings/decisions; 13 in stock, 83 sold out; PLN 22.95–1899.99) and BoosterPoint job 89 (4 requests; 232 of each retained entity; all currently sold out; PLN 3.99–990.00). Jobs 90/91 were unchanged reruns with 2/4 requests and exactly 96/232 retained rows, proving no duplicate observations/decisions. Both real shops are deliberately `lgs`, not representative `regular_retailer` evidence. No reliable GTINs were supplied; all new mappings remain `review`, with no title auto-match. Candidates CardzHouse 8393 and BoosterPoint 5423 remain review work. The recurring sealed schedule is deployed.

The historical private catalogue run exhausted all 218 set IDs at 192 synced, 15 excluded, 11 permanent failed, 192 persisted sets, and 20,561 printings. Oban job 54 intentionally ended `cancelled / catalogue_sync_incomplete`. The newer live repair evidence below supersedes the hard-failure state without turning provider-partial coverage into a production-complete claim. Detailed private enrichment still covers exactly `sv01-001` through `sv01-011`, all matched to Cardmarket IDs 702298–702308 with current `tcgdex_cardmarket_v1` valuations ranging EUR 0.03–5.04. The 11 mappings are not representative coverage. Current remaining work is representative evidence and long-term reliability, not permission uncertainty.

Catalogue recovery distinguishes usable incomplete coverage from hard failure. Sets with a valid total larger than returned briefs, or with individually malformed skippable briefs, persist valid data and checkpoint as partial with separate imported-versus-provider counts and a normalized unresolved partial diagnostic. Impossible totals, duplicate identities, conflicts, and hard provider failures remain failures. A server-derived failed-set repair job reads at most 1,000 distinct unresolved malformed/failed set IDs, skips list discovery, and remains scope-isolated from the full-catalogue job through one active durable run plus mismatched-scope snoozing. A private live repair later completed in one attempt with 11 admitted requests: all 11 historical hard failures became partial, with no remaining hard failure. Ten sets still expose shorter card arrays than their declared totals and remain unresolved partial coverage outside repeated hard-failure repair. Per-set locking and private watermarks make concurrent ordering deterministic, including equal-time partial evidence remaining unresolved. Valid catalogue writes survive lifecycle-persistence errors, while retryable failure prevents the run checkpoint from advancing with stale issue state.

The eleventh partial, `exu`, exposed a local grammar defect rather than missing provider rows: its complete 28-card response includes valid `exu-!` and literal `exu-%3F`. Card identity now permits `!` and complete percent escapes within a strict 128-byte segment while retaining narrow set IDs and rejecting malformed escapes, raw delimiters/slashes, padding, and overlong input. The rule is shared across import, enrichment, fixed-host catalogue/Cardmarket requests, secret-safe diagnostics, and Trade URL/pick behavior. A fixed path encodes literal `%3F` as `%253F`. One later budget-admitted live sync imported all 28 `exu` cards, added the two pending printings, and resolved its partial. Current private state is 203 sets, 20,964 printings, and 10 unresolved partial sets.

Latest LootQuest private refresh job 81 succeeded in one attempt with 5 admitted requests. Retained state is 154 listings, 154 immutable observations, 153 review mappings, 1 matched mapping, and 155 decisions; unchanged refreshes do not append fake history. One retailer yields Limited data only, with no ready sealed bands/directional history or public rights claimed.

Home Market movers are local-only, up to 10 total, capped at 5 risers and 5 fallers, using the fixed preceding 30 UTC dates, at least two distinct daily points spanning one day, and at least 2% absolute movement. Singles require current active-policy/current Cardmarket mapping; Sealed requires current recent ready mapping-confident aggregates and approved public products. This deliberate 1-day/2% threshold supersedes the former 7-day/5% description to surface more bounded local evidence and remains subject to tuning. With no qualified movers, up to 10 real `Recently tracked` rows appear: exact singles identity plus valuation/freshness or `Price unavailable`, and approved public sealed releases in a five-year window. Direction copy requires observations on at least two dates; rows link directly to `View price`/`View offers`. The separate cross-category zero-search-result fallback remains independent.

At the 2026-08-14 checkpoint, local validation passed canonical `direnv exec . mix check --verbose` with all static gates and 813 tests; eight focused identity/catalogue/operations/pricing/trade files passed 172 tests. The generated card-target grammar migration passed test-database down/up, and final review found no actionable issue. A real encoded Trade pick rendered the exact `%3F` printing without a malformed warning, overflow, console warning, or console error. Earlier recovery migration/race and operations/Home browser evidence remains recorded for those unchanged surfaces. Production deployment is complete; production-scale query-plan validation, complete coverage of 10 provider-partial sets, representative mapping, Polish multi-retailer validation, recurring history, and monitoring/restore remain incomplete.

## Historical authority and access boundary — 2026-08-10 (superseded current-state wording)

For private/local/staging technical-feasibility work and self-testing around the already-deployed application, the then-current plan assumed source permission everywhere. This passage is superseded by the 2026-08-20 owner direction; its dated evidence remains historical. It never permitted authentication, payment, CAPTCHA, or other access-control circumvention, and did not override request budgets, rate limits, safety controls, attribution, or provider technical constraints.

**Current status / next actions:** The existing adapter contracts, bounded workers, observation/history storage, local aggregate/model paths, and public fail-closed projections remain the technical boundary. The bounded current TCGdex discovery smoke succeeds, live failed-set repair is validated, and `exu` now imports all 28 observed identities. The remaining catalogue task is not another blind hard-failure retry: investigate or cross-check the 10 provider-partial sets, preserve partial honesty, and expand representative detailed mapping/valuation coverage before claiming a complete available catalogue. The six-source registry and Monday 01:00–06:00 UTC staggered sealed bootstrap are deployed across nine providers; Boosterland/Colligere persisted 8/37 active listings after one admitted request each. Continue exercises only as needed under the independent budgets and safety controls. Representative multi-retailer validation, completion of the production catalogue/mappings, and field mappings, attribution evidence, storage behavior, and publication-scope validation remain technical work.

**Status:** `cardmarket_bulk_v1` is the sole public and newly writable Singles source; TCGdex is catalogue/detail/image/Cardmarket identity only, with historical snapshots readable but not selectable or newly writable. The daily 03:00 UTC bulk sync is the only Singles acquisition path; no fallback, readiness/cutover, policy cache, per-card worker, on-demand/public enqueue, or 14:00 sweep exists. Sealed retains its source-neutral product, alias, retailer, current-listing, mapping-review, immutable observation, atomic refresh, versioned local daily aggregate/benchmark, and persisted provisional buying-guide foundations plus six centrally configured WooCommerce adapters: LootQuest, CardzHouse, BoosterPoint, PokeBooster, Boosterland, and Colligere. The six-source registry is deployed with Monday 01:00–06:00 UTC staggered bootstrap; each source has a budget of 50/hour, 100/day, and 500/month. Production has 19 approved Sealed products and persisted Boosterland/Colligere evidence, while retailer mappings remain review and no ready sealed bands or real model validation are claimed.

The approved `Pokémon TCG: Scarlet & Violet—151 Booster Bundle` and manually confirmed listing source ID 104164 yielded local aggregate `limited / too_few_regular_retailers` with one regular retailer, and guide `limited / limited_market_aggregate` at confidence `0.19`, with no fabricated bands. TCGdex detailed private enrichment covers exactly `sv01-001` through `sv01-011`; all 11 match Cardmarket IDs 702298 through 702308 and all 11 have current `tcgdex_cardmarket_v1` valuations. Real local values range from EUR 0.03 to EUR 5.04, with Pineco at EUR 5.04; these 11 mappings are not representative coverage of the current 20,964 printings. The historical full run and its cancelled job remain valid execution evidence, while the newer repair converted its 11 hard failures to partial and the `exu` correction reduced unresolved partials to 10. This remains incomplete private coverage rather than a successful production import; remaining work is technical evidence and reliability.

Phase 4 has completed production checkpoints for six deployed sources—LootQuest, CardzHouse, BoosterPoint, PokeBooster, Boosterland, and Colligere—with persisted production evidence; representative mappings, recurring history/reliability, and model validation remain incomplete. `SealedProduct` and `SealedProductAlias` provide canonical official Polish-English SKU identity, draft-only source imports, review queues, aliases/EANs, optional provenance-backed finite PLN MSRP, and locked/revalidated approval transitions. `Retailer`, `RetailerListing`, and `ListingProductMapping` add source-neutral shop categories, current source projections, exact-approved-GTIN matching, and protected human review. `SealedListingObservation` retains immutable changed PLN price/stock/source states while unchanged checks advance current audit timestamps without duplicate history. `SealedRetailerRefresh` and its unique Oban path validate and atomically ingest one explicitly configured adapter batch. The exact six-source production registry and Monday 01:00–06:00 UTC staggered bootstrap are deployed through Coolify. An authenticated, admin-authorized review desk can correct/approve/archive draft products, approve/reject aliases, and confirm/reject listing mappings with displayed-version stale protection. A public local-only projection searches approved products and displays trustworthy matched MSRP/current/recent-sold-out shop evidence. The local-only `sealed_market_daily_v1` path can additionally display a ready benchmark/range or explicit Limited data from persisted daily aggregates without contacting a source. `sealed_buying_model_v1` defensively combines retained aggregate/history/MSRP/LGS/sold-out/mapping evidence into confidence plus four explicit intervals or Limited data, and a current-plus-history-revision Oban job persists those outputs in `SealedBuyingGuideSnapshot`; historical corrections cascade to affected following guide dates. App/DB constraints and transaction locks protect identity, GTIN, state, money, time, coverage, consumed source revisions, and concurrent ingest invariants. Private evidence includes matched LootQuest regular-retailer evidence plus CardzHouse and BoosterPoint LGS evidence; the latter mappings remain review, and representative multi-retailer/production evidence and public access remain pending. Local public guide/graph rendering is implemented.

## Authority and access-policy boundary

The product owner superseded the exact seller-level singles direction on 2026-08-07. The MVP is aggregate-first and avoids scraping where practical. No authentication, payment, or CAPTCHA bypass is permitted; credentials remain server-side and out of git. The historical `default_v1` seller-level algorithm is preserved post-MVP. The active aggregate does not prove language, condition, seller identity/count, finish exactness, or shipping to Poland; the UI must not imply those facts.

TCGdex remains the initial catalogue direction, with Pokémon TCG API as fallback/cross-check subject to licensing and mapping validation. TCGdex imagery is approved for the MVP by product-owner decision: commit `52a9c0d` uses only canonical `https://assets.tcgdex.net` URLs through strict `CardImage` behavior (high WebP detail, low WebP search, no-referrer, exact CSP host, no proxy/cache, honest missing/invalid fallback). This accepts pragmatic product risk for an explicitly unofficial review/comparison/decision-support site; it is not a legal conclusion or proof that underlying artwork is independently licensed. Third-party artwork rights remain unproven, and broader reuse/self-hosting is not approved. The hardened budget-admitted live set-list smoke now succeeds with 218 sorted unique IDs; a complete import and long-term production reliability remain unproven.

## Card metadata

Earlier bounded observations counted 23,444 TCGdex cards versus 20,479 Pokémon TCG API cards; these are time-specific counts, not guarantees. TCGdex exposes Cardmarket IDs, but mappings can evolve or be shared/wrong and images can be missing. Set plus collector number is the primary human identity, with a material-variant discriminator when needed.

## Credentialed spike

### TCG Scraper

https://tcg-scraper.com/ documents Free 100 requests/month and Starter €29/month for 25,000/month. `/api/v1/product` uses `X-API-Key`, Cardmarket URL, `language`, `minCondition`, and optional `sellerReputation`. Its public example exposes product metadata and summaries (`total_offers`, `lowest_price`, `sellers_count`, condition counts), not seller identity, destination, quantity, currency, or offer rows. A temporary evaluation account/key was created: one call exceeded a 30-second client timeout; a second fresh-key call to the documented Charizard example returned HTTP 502 after about 44.7 seconds with Cloudflare HTML rather than JSON. Keys were revoked and sessions signed out. No successful Apify/Parse call is claimed.

### cardmarketapi.com

A temporary 3-day trial was used for `GET /api/v1/card/869888`. It returned HTTP 200 after about 29.2 seconds, `X-Cache: MISS`, and rate-limit header 10. The JSON had top-level `id/game/name/expansion/image_url/currency/filter/prices/listings/fetched_at/source`. Exactly 50 listings were returned; each observed listing had only `cond/country/lang/price`, with no seller identity or quantity. There were 17 distinct seller countries, one language, and two conditions because `condition=nm` means NM-or-better. Currency was EUR, `avg5` and timestamp were present, and total availability was 241. The current https://cardmarketapi.com/panel/api/plans says Starter $49.99/30 days and 500/day, conflicting with some documentation advertising higher quotas; reconcile before use. The trial key was not retained and browser storage was cleared.

Direct Cardmarket browser GET for the documented TCG Scraper Charizard Obsidian Flames product URL returned HTTP 403 / “Just a moment”; this was not necessarily product ID 869888, and no bypass was attempted.

## Singles acquisition matrix

| Candidate | Decision and evidence |
| --- | --- |
| TCGdex embedded Cardmarket aggregate | **Historical/read-only source.** Retained `tcgdex_cardmarket_v1` snapshots remain readable but cannot be selected or newly written. TCGdex is otherwise catalogue/detail/image/Cardmarket identity only. |
| Cardmarket bulk product/price-guide | **Fixed active MVP source.** `cardmarket_bulk_v1` is the sole public/new-write source; the daily 03:00 UTC sync materializes exact, validated local values. It is aggregate-only and does not prove seller-level fields or shipping to Poland. |
| Apify Phantom Coder | **Post-MVP experiment candidate.** Documents seller identity, condition, language, quantity, EUR/currency rows, seller-country input, max 1–500 results, and $0.005/listing Free / $0.004 Starter; reports 97.1% successful runs. Destination eligibility is absent. Signup stalled at identity/hCaptcha; no account creation is claimed. |
| Parse.bot Cardmarket API | **Post-MVP experiment candidate.** Documents seller usernames, condition, attributes, price, quantity, comments, pagination to Cardmarket’s 300 cap, and seller-country filtering; Free 100 credits or Hobby $30/1,000 credits, listing calls 2 credits. Destination eligibility is absent. Signup stalled at hCaptcha; no credentialed call. |
| cardmarketapi.com | **Indicative/aggregate fallback only.** Successful HTTP 200, but empirical listings lack seller identity, quantity, and destination. Its `avg5` is five listings, not five distinct sellers. Current Starter $49.99 leaves no safety margin and the plan API says 500/day. |
| tcg-scraper.com | **No-go for now.** Credentialed sample got HTTP 502/Cloudflare HTML and the documented response does not prove offer rows or required fields. |
| Official Cardmarket API | Applications are currently closed; not selectable without written access. |
| Cardmarket public catalogue/price guide | Free daily catalogue/price-guide material is aggregate-only; useful for metadata/reference, not seller-level offers or destination eligibility. |
| TCGdex metadata/catalogue | **Selected catalogue source.** Free metadata, detail imagery, and exact-printing/Cardmarket identity mappings; retain provider IDs and review ambiguous/material variants. |
| CardTrader | Seller identity, condition, and language are documented, but authenticated Poland-account shipping behavior and the separate shipping-method request remain unresolved. |
| JustTCG | `$19/month + tax` Starter and `$49/month + tax` Professional; no seller identity or destination proof is established. |
| PokemonPriceTracker | `$99` Cardmarket/commercial plan, over the cap. |

Do not make Apify or Parse part of the MVP. They may be evaluated later for seller-level post-MVP capability after successful credentialed real Pokémon runs validate actual rows.

## Sealed catalogue/source direction

REBEL Hurt remains the best current primary catalogue/SCD discovery candidate based on the observed `SCD`/`Chaos Rising` page and B2B terms, but it is not proven exclusive or official TPCi MSRP authority. ISA remains a historical fallback requiring permission for aggregation and republication. Treat SCD as a non-binding suggested reference, not authoritative MSRP. Candidate regular retailers are REBEL retail, Empik-owned offers, Media Expert only with permitted feed/access, Smyk, TCG Love, Graal, LootQuest, and PokeCollect; candidate LGS/community sources include TCG Love, Graal, ShopGracz, Centrum MTG, Strefa MTG, Plan-Sza, and Guildmage. Require released/English/official filtering and preorder/import/marketplace filtering for all runs; require feed/terms approval before **public** live adapters, while permitted private test runs may use explicit non-public configuration under the owner assumption.

LootQuest is now the strongest no-credential technical fixture candidate. Its public WooCommerce Store API returned bounded structured product identity, PLN minor-unit price, categories/tags, direct URL, purchasability, stock, and backorder fields. The same category also contained Korean imports, proving that category membership cannot establish MVP eligibility. Store terms require lawful/IP-respecting use but did not provide an explicit recurring extraction/republication grant; robots instructions are not a reuse license. The exact six-source production registry and Monday 01:00–06:00 UTC staggered bootstrap are deployed. Production/public route and acquisition evidence is verified, while representative regular-retailer mappings, recurring polling reliability/history, field mappings, attribution evidence, storage behavior, and real buying-model validation remain technical work.

The fixture-backed retailer adapter/refresh path, authenticated review desk, local public search/detail offer projection, local daily aggregate/benchmark foundation, persisted versioned buying-guide path, and public guide/graph/history projection are implemented. `/sealed/:slug` consumes persisted current-model guide snapshots only: it never recomputes the model or calls providers. `SealedBuyingGuidePublicProjection` validates expected product binding, exact aggregate/history fingerprints, source-relative history, and all public invariants, failing closed on corruption, mismatch, or read failure. `SealedDailyAggregatePublic` and `SealedMarketHistory` centralize defensive aggregate/history projection; the latter exposes a fixed 30 UTC-calendar-day SVG and textual ledger using only canonical ready rows for the expected product. Exact ready guides show inclusive-ceiling Great/Fair/Expensive/Avoid ranges and plain-English explanations from persisted factors; Limited guides show collector-readable reasons/factors, while stale bands remain explicitly previous/cached/outdated. Phase 4 is incomplete because representative regular-retailer mappings/history and real validation remain open, not because production catalogue/retailer evidence or guide/graph UI is absent. Phase 5 public rendering/graph/explanation items are implemented in code, awaiting real Polish data/model validation.

## Implemented sealed retailer persistence boundary

`Retailer` distinguishes representative regular retailers and LGSes and supports soft disable/enable. `RetailerListing.ingest` accepts only normalized adapter output with canonical retailer/source IDs, direct HTTPS URL, optional valid GTIN, PLN price, explicit stock state, source payload, and ordered first/last-seen/check timestamps. A per-listing transaction advisory lock serializes concurrent first insert and update; stale timestamps cannot regress the projection, and disabled rows cannot be silently re-enabled.

`SealedListingMatcher` only auto-matches one eligible approved exact GTIN alias. Missing, invalid, ambiguous, pending, draft, future, non-PL, or non-English identities remain review rather than guesses. `ListingProductMapping` persists one pending/review/matched/rejected decision per source listing, validates matched products, serializes human review, and prevents imports from overwriting reviewed decisions.

After each successful listing ingest, `SealedListingObservation` compares the persisted projection with the latest immutable observation inside the same transaction. It appends changed title/normalized title, URL, GTIN, numeric price, currency, stock state, or payload; a later unchanged check updates the projection only. Stock transitions and returns to previous states remain separate observations. One listing/check timestamp is one unique observation boundary, same-timestamp contradictions roll back, and hard listing deletion is restricted. Job 58 produced 154 local listings and immutable observations. Every ingest ensures a mapping in the same transaction: missing/invalid/ambiguous evidence creates or refreshes review; one eligible approved exact EAN can promote mutable pending/review evidence to matched; terminal decisions resist source overwrite; a failure rolls back the batch.

`SealedRetailerRefresh` fetches outside a database transaction, revalidates the complete bounded batch and duplicate source IDs before writes, then locks and revalidates the canonical active retailer before atomically ingesting every row. A disable that completes during fetch prevents later persistence. Notifications dispatch only after commit; an invalid later row rolls back earlier writes, and an empty successful batch leaves absent listings unchanged. `SealedRetailerWorker` has active-state uniqueness by retailer/source, queue concurrency one, a finite six-minute execution timeout, retry/backoff for explicit transport/rate-limit/server/pagination-drift/database failures, and permanent cancellation for malformed data/configuration or unexpected adapter callbacks. Req requests disable internal retries, use fixed connect/receive/request timeouts, reject redirects, and leave whole-batch retries to Oban.

## Implemented acquisition and catalogue boundary

### NBP exchange-rate provider and acquisition boundary

Official NBP documentation and the time-specific 2026-08-08 capture establish the HTTPS-only Table A EUR endpoint, 404/no-data behavior, and 93-day historical-query cap; no published numeric quota was found. `TcgCheap.Pricing.ExchangeRateProvider.Result` is the normalized contract. `NbpExchangeRate` makes the exact current HTTPS request with Req, decodes the canonical JSON into Decimal, validates table/code/rate shape and rejects future or non-positive observations, and maps HTTP, transport, decode, and validation errors. The live official adapter smoke succeeded with `mid` 4.3010, effective date 2026-08-07, and publication `152/A/NBP/2026`.

The AshPostgres `ExchangeRate` resource stores one canonical NBP A EUR/PLN observation per effective date with positive Decimal rate, publication number, and fetched timestamp. Same-date upserts refresh the observation metadata; history remains retained. Generated migration/snapshot output was applied and reviewed. `ExchangeRateWorker` uses an Oban queue at concurrency 1, active-state uniqueness, retry/cancel behavior, and PubSub completion/failure events. `ExchangeRateAcquisition` subscribes before enqueueing and allows one fetch per UTC day based on fetched freshness, with latest-published carry-forward on weekends and holidays. Static scheduling is `0 15 * * *` UTC. TradeLive consumes the latest cache locally, preserves cached conversion during pending/failed acquisition, and strictly rejects malformed/noncanonical/nonfinite/future/older messages. Public PLN totals/difference and canonical share/copy are complete. No NBP HTTP runs in LiveView/request paths.

The active Singles adapter is the fixed Cardmarket bulk product/price-guide path. It materializes finite-positive, plausibility-checked values only for exact Cardmarket mappings supported by the same successful batch; row-count anomalies, non-Pocket/paper violations, malformed, ambiguous, or cross-batch evidence fails closed. TCGdex supplies catalogue/detail/image/Cardmarket identity only. Historical `tcgdex_cardmarket_v1` snapshots remain readable but cannot be selected or newly written. `CardSet` and `CardPrinting` persist exact-printing metadata, legalities, assets, source/sync timestamps, conservative Cardmarket mapping state, and provider-versus-administrator mapping authority. No provider call is on the render path.

Strict set enumeration and brief sync fetch provider data outside transactions. Impossible totals, duplicate identities, conflicts, malformed set identity, malformed percent escapes, raw path/query delimiters, padded identity, and overlong identity fail safely; the observed `!` and complete literal `%HH` card forms remain valid. A valid `cardCount.total` above the returned length or individually malformed skippable briefs retain valid set/card rows as explicit partial coverage. Set sync uses per-set PostgreSQL advisory locks and cross-set identity checks. Catalogue Sync acquires the same per-card transaction advisory lock as the full importer and sorts brief card IDs before locking, closing the intermittent brief/full unique-ID race and preventing lock-order cycles across overlapping sets. Provider fetches remain outside transactions. `sync_all_sets/1` continues after failures, reporting synced, partial, failed, and excluded sets separately and excluding `serie.id == "tcgp"`.

The production-safe catalogue job path is implemented. `CatalogueSyncWorker` owns independently unique full and failed-set repair requests, validates one strict server-side TCGdex configuration, and permits only one durable active run. Full scope discovers a sorted/unique at-most-1,000-ID list once; repair scope derives at most 1,000 distinct unresolved hard set IDs and performs no list discovery. A mismatched active scope snoozes without provider calls, including after a create race. Attempts process at most 20 sets and snooze at least 15 minutes; row-locked expected-index transitions retain separate synced/partial/failed/excluded counters and make completed work resumable after retry, restart, or deployment. Every actual list/set request is independently admitted by the provider/global budget. The adapter disables redirects, streams at most 2 MiB, applies a five-second connect and 15-second receive/total deadline, rejects over-1,000 set lists without truncation, and maps Req timeouts to dedicated timeout evidence. Hard set-specific malformed/conflicting and 404/410 outcomes remain failed progress, while usable incomplete coverage is partial and provider-wide/transient/persistence/budget failures preserve the checkpoint. Acquisition/source-health and normalized import-issue evidence remain secret-safe. A post-change live discovery returned 218 sorted unique IDs in 310 ms. Live failed-set repair is now evidenced by the 11-request completed attempt; all historical hard sets became partial, and one follow-up `exu` request resolved the local-grammar partial. Production-complete coverage, the 10 remaining provider-partial sets, long-term reliability, and representative mapping remain open technical work.

`TcgCheap.Catalogue.Enrichment.enrich_set/2` implements detailed set-level per-card enrichment and Cardmarket mapping. It fetches a detailed set exactly once with a timeout, validates exact set identity before TCG Pocket exclusion, and rejects malformed/truncated lists, duplicate or invalid canonical card IDs, and fan-out above 1,000 before card calls or writes. Card details are fetched at most once each outside DB transactions using ordered bounded `Task.async_stream` (default/max concurrency 4/16; default/hard timeout 30s/120s). Unexpected, raised, thrown, exited, and timeout callbacks are tagged and isolated so later cards continue. After provider calls, one clock is invoked and successful payloads are sequentially imported under one shared normalized UTC microsecond timestamp; an invalid clock writes nothing. Reports numeric seen/enriched/stale-preserved/failed counts plus ordered stage-tagged per-card failures. Reruns are idempotent and stale provider card/mapping data is preserved. `import_fetched_card/4` accepts explicit expected IDs and returns import/stale outcome while `import_card/2` retains its public card return; provider callback returns are normalized and set/card identity is validated before writes. Import and brief sync acquire locks set-before-card; real concurrent Sync plus fetched Importer coverage passed 20/20 repetitions. Cross-set reassignment, including stale payloads, is rejected; existing `CardSet` metadata is preserved during enrichment, set sync owns later metadata refresh, and missing sets can be created.

Provider-owned mapping changes now archive current bulk valuations and append immutable `provider_updated` decision evidence in the same transaction. Administrator corrections and reasoned reopens use a separate stale-safe authenticated workflow. Public views require the current Cardmarket product ID; retained old-epoch snapshots remain inspectable. Committed mapping changes and successful bulk materialization notify connected views, which reread local bulk data rather than reacquiring pricing.

## Exact-printing search boundary

`CardPrinting.search` is local PostgreSQL only and exposed as `TcgCheap.Core.search_card_printings`; it never calls a provider. Shared Unicode NFKC/whitespace/trim/lowercase normalization is applied on create/upsert and matches SQL backfill parity. Four concurrent GIN trigram indexes support escaped contains and `%` candidates. Deterministic ranking uses exact IDs/names/collectors/sets, prefixes, similarities, Standard legality tie-breaking, then stable identity. Default limit is 10, hard maximum 20, effective minimum 2; all mapping statuses and non-Standard cards remain searchable, exact printings remain distinct, and `CardSet` is loaded.

`/` is the completed public local-only `HomeLive` decision surface: Singles by default; an accessible Singles/Sealed switch; category-specific search through the shared external 250ms `CardAutocomplete` hook used by Home and Trade; and stable, exact local result options. The hook preserves query/node/focus/caret/selection, blocks composition searches until compositionend, cancels pending debounce on Escape, carries the current query on Enter, and rejects stale cached selections. Singles rows retain exact image/name/set/collector/rarity and current estimate behavior. Sealed search uses only approved released official PL/en canonical names and approved name aliases, with bounded deterministic ranking and no EAN/public-draft leakage; rows show canonical name/type/series/set/release/discontinued identity, an honest no-image placeholder, and `View offers`. A zero-result primary search may perform one bounded local opposite-category query and render direct links in a separate recovery ledger outside the combobox/listbox; real-data strong-versus-weak tuning remains open. Idle Home uses balanced local Market movers of up to 10 total rows, capped at 5 risers and 5 fallers, with two daily dates spanning one day and at least 2% movement within the preceding 30 UTC dates. When no qualified movers exist, up to 10 real `Recently tracked` rows provide exact singles identity/valuation or approved public sealed releases within a five-year window; copy explains that direction appears only after observations on two dates. These indexed, stream-backed rows retain exact identity/freshness and call no provider. `/sealed/:slug` reads only persisted local projections, chooses one cheapest current listing and one recent sold-out listing per active shop, and displays MSRP provenance/direct links/check times/shipping exclusion separately. A valid current-version daily aggregate adds a local benchmark, typical range, source counts, dates, evidence time, and methodology; persisted exact guides add ready bands/factors or collector-readable Limited data. Older-ready and newest-limited combinations remain explicitly cached/outdated, and invalid/unreadable states fail closed. The fixed history graph has no controls or interpolation and plots only canonical ready rows for the expected product. No provider HTTP or model recomputation runs in render/event paths. The Home `decision-world`, card-detail `archive-world`, and sealed detail extension keep the approved warm square direction; Generic Layout stays neutral.

The public UI boundary now extends through the local card-detail consumer at `/cards/:tcgdex_id`. Search links to exact printings; detail reads local identity/current `cardmarket_bulk_v1` valuation and a bounded fixed 30-day history without pricing-provider calls on render or event paths. Missing TCGdex detail enrichment may use its separate background job; Singles pricing does not. Fresh, stale, unpriced, read-error, and insufficient-history collecting states are explicit; bulk and mapping invalidations trigger local rereads. Approved TCGdex imagery renders through `CardImage`, and CardDetail retains its side-neutral trade pick CTA.

## Cost, licensing, and next actions

The 2026-08-08 minimal Home correction is the presentation baseline for this boundary, and the autocomplete quality correction is implemented/current. Ordinary collectors see `Price unavailable`, `Updated …`, and `May be outdated`, not internal jargon; provenance and caveats remain in concise disclosure. Provider calls remain outside request paths.

The fixed bulk source is the sole public/new-write Singles source. TCGdex pricing is not an active path; historical snapshots are read-only. Shipping-to-Poland eligibility remains outside the aggregate MVP. Product-owner approval permits TCGdex imagery for the MVP, but does not resolve third-party artwork rights or approve broader reuse/self-hosting.

## Cost and destination risk

Historical paid-provider estimates remain relevant only to post-MVP seller-level experiments: Apify’s documented $0.005/listing and Parse’s Hobby plan would consume the global cap quickly; cardmarketapi Starter at $49.99 leaves no safety margin. Cardmarket shipping depends on origin, destination, weight, and dimensions, and seller country is not enough because sellers can opt out of countries. Do not imply shipping-to-Poland eligibility in the active aggregate UI or data.

## Licensing and evidence caveats

The TCGdex MIT license covers the repository/artifact, not Pokémon image/IP rights or marketplace redistribution rights. ISA Article 8.4 restricts aggregation/processing for redistribution and requires permission. Terms and robots rules remain public-launch/republication risks even under the private-testing permission assumption. Public documentation and bounded samples do not prove production authorization, contract rights, provider accuracy, or CardTrader shipping behavior.

## Controls and next actions

Use canonical IDs/known URLs only, fixed bulk request/deadline/row-count protections, mapping locks, kill switches, and stale/`?` presentation. The daily 03:00 UTC bulk sync is the only Singles acquisition path; there is no public on-demand acquisition, per-card worker, fallback, selectable policy, readiness/cutover control, or 14:00 sweep. Public pages read local values only and provider calls never run on render paths.

The implemented admission path stores coherent provider hour/day/month request limits, provider monthly estimated spend, a global hour/day request ceiling, and the global monthly estimated-spend ceiling. One serialized PostgreSQL transaction checks and increments exact UTC windows; subsecond timestamps cannot fragment a window, and a disabled provider is not re-enabled by configuration sync. Operational callers inject the admitter into provider options, each in-tree adapter runs it immediately before HTTP, all three WooCommerce adapters run it for every page, and metered paths disable internal Req retries. This closes the former gap where one paginated callback or hidden Req retry could represent multiple uncounted requests. TCGdex catalogue `Importer`, `Sync`, and `Enrichment` are included rather than bypassing operations accounting.

The public enqueue boundary now adds a supervised one-VPS fixed-window peer limiter: 30 stale/missing acquisition candidates per validated direct IPv4/IPv6 peer per hour by default, 10,000 bounded entries, and periodic expiry. CardDetail consumes one reservation only for missing TCGdex detail enrichment. Trade consumes one only for stale/missing public NBP work. Singles pricing never reserves or enqueues work; local stale/unpriced values remain until bulk sync. Missing, invalid, malformed, or crashing admission callbacks fail closed before Oban insert; rejected paths keep stale/`?`/PLN-unavailable public fallback. The peer window resets on application restart and deliberately ignores untrusted forwarded headers, so a future reverse proxy needs explicit trusted-client-address handling.

Authenticated admin usage/failure visibility is implemented as a focused `/admin/operations` desk. It bounds configuration at 100 providers, reads only configured-provider current UTC rows, aggregates global current windows in SQL, counts every canonical retained Oban state, and projects at most 25 newest inserted jobs across external and local-only workers plus 25 configured-provider acquisition attempts by default (50 hard maximum for each). Application/DB Oban state-set mismatch fails the overview closed; arguments, payloads, metadata, diagnostics, raw errors, and exception text are absent, while retryable/discarded/cancelled jobs receive only a fixed failure category. Operators can inspect safe run outcome/category, admitted request count, last provider success/failure, consecutive failure streak, source-facing circuit streak/open time, strict scheduled-source freshness, and overdue running evidence, and can enable/disable configured providers through an admin policy and transaction-local displayed-version lock. A unique 15-minute worker repairs the oldest at-most-100 terminally stranded attempts per pass under provider and row locks; NBP is stale after 36 hours without tracked success, while unscheduled TCGdex sources remain explicitly on demand. Unchanged admission upserts preserve the control version; real configuration changes invalidate it.

Passive automatic circuit opening is now implemented from durable worker outcomes. The strict health policy counts only rate-limit, timeout, transport, and provider-response failures toward a dedicated threshold (five by default); budget, persistence, configuration, local-input, unknown, and reconciler outcomes cannot trip it. Retryable outcomes accumulate evidence but preserve the next retry. A terminal failed/cancelled outcome at threshold disables the provider and records the opening in the same transaction as run/health finalization; shared source/provider locks linearize concurrent completions, admission, and manual controls. Success resets only a closed streak, manual disable does not fabricate an opening, and manual re-enable clears circuit evidence. Database and overview validation reject impossible, future, or open-on-active evidence. This does not add active probe traffic, half-open trials, or alerts.

The operations desk retains typed controls for unrelated catalogue, NBP, and sealed-retailer workflows. Singles source, batch, mapping, detail, and materialization diagnostics are read-only; no manual Singles refresh/retry/readiness/cutover control or public Singles enqueue exists. The AshBackpex catalogue retains its curation and read-only inspection boundaries without exposing provider payloads or raw diagnostics. Actual-cost reconciliation, active source probing, acquisition priorities, arbitrary retained-job replay, and the remaining broad AshBackpex resources remain unfinished.

The historical seller-level concepts and `default_v1` algorithm were removed from the current codebase; they remain post-MVP design history only. The active Singles path is the fixed `cardmarket_bulk_v1` sync/materialization boundary with exact-ID, same-batch, paper-only/non-Pocket, finite-positive, plausibility, and row-count safeguards. There is no per-card pricing acquisition or active TCGdex aggregate adapter.

1. **Complete:** the fixed `cardmarket_bulk_v1` bulk sync/materialization path is implemented with exact-ID, same-successful-batch, paper-only/non-Pocket, finite-positive, plausibility, and row-count-anomaly safeguards; TCGdex remains catalogue/detail/image/Cardmarket-identity infrastructure.
2. **Production-safe job path and live repair validated; private coverage remains incomplete:** the resumable budget-aware run exhausted 218 IDs, and the later 11-request failed-set repair converted every historical hard failure to partial. The punctuation-ID correction plus one budget-admitted `exu` sync imported that set 28/28. Preserve conservative mapping review, investigate/cross-check the 10 remaining provider-partial sets, and record representative mapping/complete coverage evidence before claiming production readiness.
3. **Complete:** the public exact-printing search/result surface, concurrency hardening, detailed set-level enrichment/Cardmarket mapping, fixed bulk materialization, and local-first card-detail valuation/history consumer are implemented while keeping provider fetches outside request paths.
4. Preserve seller-level concepts only as post-MVP design history; the old `Provider`/`Offer`/`Valuation` modules are removed. Seller/offer count is unavailable from the active bulk source and must not be fabricated.
5. Request REBEL B2B data import/access and written SCD/data-reuse scope.
6. Exercise candidate adapters privately under the current assumption while externally requesting approved feeds/permissions from the initial retailer/LGS panel, including Media Expert only with permitted feed/access; public sealed research and launch rights are not complete.
7. Retain the evidence caveat that third-party artwork rights are not independently proven; broader image reuse/self-hosting, sealed research, and seller-level source research remain open.
8. **Complete:** the minimal Home correction retains approved colors, fonts, and warm square direction while reducing density and using plain-language CTAs. The shared external focus-preserving autocomplete, URL-only EUR/PLN trade/share surface, local-only public Sealed search/detail offer foundation, versioned daily sealed benchmark/range foundation, persisted provisional buying-guide path, and public guide/graph/factor projection are implemented and test validated. Sealed production acquisition and real catalogue/observation/model validation remain unfinished Phase 4/5 work.

All observations are time-specific. No credentials are committed.

Pre-fix validation for the `99023f3` baseline remains historical: focus moved to BODY after the first character. The completed correction passed the 185-test canonical check, browser desktop/mobile focus/caret/composition simulation, ten-option keyboard/internal-scroll/Enter/Escape checks, no-console/no-overflow checks, detector review, JSON/wiki lint, and `git diff --check`. The composition result is explicitly a browser composition-event simulation, not a native IME claim. Its then-unresolved TCGdex list timeout is superseded by the current bounded live-success evidence.

The autocomplete correction and Phase 3 URL-only EUR/PLN trade/share surface are complete, and the NBP/PLN backend/local cache is complete. The authenticated sealed review desk is complete for draft/alias/mapping decisions. The local-only public Sealed search/detail offer projection, daily aggregate/benchmark foundation, persisted `sealed_buying_model_v1` guide path, fail-closed public guide/graph/factor projection, request-level provider/global budget-admission foundation, bounded direct-peer public acquisition throttle, persisted external-attempt/source-health evidence, passive automatic circuit opening, resumable partial-aware full-catalogue execution, scope-safe and live-validated failed-set repair, punctuation-safe exact card identities, bounded successful TCGdex discovery, exact read-only buying-model inspection, authenticated AshBackpex product/manual-alias/retailer, and listing/mapping/history plus card-set/card correction/mapping-history/valuation/normalized TCGdex-and-sealed-import-issue catalogues are implemented. Typed manual refresh applies only to catalogue/detail, NBP, and sealed workflows; it never refreshes Singles pricing. Peer throttling applies only to missing detail enrichment and NBP. Sealed production acquisition/data, complete coverage of 10 provider-partial card sets, representative exact-printing mapping, real catalogue/observation/model validation, remaining AshBackpex resources, actual-cost reconciliation, and active health probes remain unfinished. Ranking still needs real full-catalogue tuning; third-party artwork rights remain unproven as an evidence caveat, while UTC/Warsaw presentation and future trusted-proxy client attribution remain open. This does not declare the overall MVP complete.

Historical (2026-08-10; superseded by the current initial validation checkpoint): the authenticated operations desk implemented bounded current quota/estimated-spend visibility, exact all-state retained Oban counts plus bounded secret-safe newest-job evidence across external and local-only workers, persisted external acquisition attempts, source-health lifecycle/streak/freshness/circuit evidence, passive terminal-outcome circuit opening, overdue projection, periodic terminal stranded-run repair, stale-safe configured-provider controls, typed canonical refresh/requeue for every existing external-acquisition worker, and exact read-only current buying-model configuration/version inspection. The pinned authenticated AshBackpex catalogue provided sealed-product list/show/draft create/stale-safe edit, all-alias list/show plus manual pending create/stale-safe edit, curated stale-safe retailer management, current retailer-listing/mapping/history inspection, card-set/card embedded-external-mapping correction with immutable decision history, immutable valuation inspection, and normalized TCGdex catalogue plus configured sealed-retailer refresh issue inspection without destructive actions, provider payload exposure, or raw failure text. Active source probing, actual-cost reconciliation, acquisition priorities, arbitrary retained-job replay, and production-data validation were then unfinished; the current initial validation checkpoint supersedes that status.

## See Also

## Trade acquisition boundary — complete Phase 3 boundary

Trade composition consumes local cached cards and current `cardmarket_bulk_v1` valuations in one bounded bulk read (maximum 100 IDs), with no N+1 valuation reads and no provider HTTP in public paths. Missing/stale rows remain local and visibly unpriced/stale until a successful bulk sync; committed batch/mapping invalidations trigger local rereads. Search and pick do not enqueue pricing work.

Phase 3 is complete. The pure trade valuation counts unknown/unvalued rows and retains stale values, while the URL contains only validated stable IDs and quantities. NBP EUR/PLN acquisition/resource/local cache uses the official HTTPS adapter; public totals/difference show Decimal PLN with exact dated rate evidence, and explicit share/copy canonicalizes an absolute `Composition.to_path` URL. The selected aggregate source remains free and unauthenticated; no seller-level data, destination eligibility, snapshots, or credentials are introduced.

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Application Foundation](application-foundation.md)
- [Sealed Buying Model v1](sealed-buying-model-v1.md)
