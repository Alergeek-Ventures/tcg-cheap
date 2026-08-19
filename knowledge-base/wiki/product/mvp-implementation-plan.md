# Pokémon Market & Trade Platform — Detailed MVP Implementation Plan

- Updated: 2026-08-19
- Sources: Product specification supplied by project owner; [2026-08-10 CardzHouse and BoosterPoint Store API capture](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md); [2026-08-14 TCGdex punctuation card-ID capture](../../raw/2026-08-14-tcgdex-punctuation-card-ids.md); project validation
- Raw: [2026-08-10 CardzHouse and BoosterPoint Store APIs](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md); [2026-08-14 TCGdex punctuation card IDs](../../raw/2026-08-14-tcgdex-punctuation-card-ids.md)

## Current product-owner course correction — 2026-08-19

The personal pilot is now deliberately staged around deployment rather than a broad public launch. The first gate is deployment through the existing Coolify environment. Public read pages remain public on the existing unlisted/internal domain, while administration remains authenticated. This does not change robots or noindex behavior. There is no archive/backfill scope: history is collected prospectively.

For sealed stage one, include products released in the rolling last three years, with sourced MSRP/RRP when available, the current overall/Cardmarket benchmark, and retailer links. For singles stage one, include the full Pitch Black set, IR/SIR cards from the rolling last two years, and a curated set of playable Trainers/Items/Supporters; bulk singles remain out except for those playables. These are the current pilot priorities, not a silent deletion of the original MVP requirements below; the broader product scope, requirements, phases, and acceptance criteria remain historical authoritative requirements unless the owner explicitly supersedes them.

The deployment-foundation batch is implemented locally. The local, CI, and Coolify target is the exact multi-architecture OCI index `docker.io/paradedb/paradedb:v0.25.2-pg18@sha256:f34b716407b4d509d3e59e649495964b296ad7c0931658dbf99d3cf1b35bc994`, with amd64 and arm64 manifests, PostgreSQL 18.4, `pg_search` 0.25.2, and `pgvector` 0.8.4. Stock PostgreSQL current is 18.6; this is an explicit minor security/bugfix tradeoff to revisit on validated ParadeDB updates. Local Compose explicitly preloads `pg_search`, `pg_cron`, and `pg_stat_statements`. Existing compatible stock-PG18 volumes must not be reset: intentional container recreation/restart and `SHOW shared_preload_libraries` verification are required. Fresh ParadeDB may bootstrap extensions, while TCG Cheap-owned migrations/resources/queries currently require only existing Ash functions, `citext`, and `pg_trgm`, with no BM25/vector use.

The exact index manifest was verified; a fresh ParadeDB scratch reported expected versions/preload; canonical `mix check --verbose` passed all static gates and 813 tests against ParadeDB; the target app image built; `/app/bin/migrate` migrated an empty ParadeDB database; and app `/health` plus Docker HEALTHCHECK passed with PostgreSQL, 7 Oban queues, and 3 acquisition providers. Temporary app/scratch containers, image, and database were cleaned. The current persisted local DB was not reset (20,964 card printings, 1 sealed product, 94 Oban jobs; PostgreSQL 18.4 and extensions available); its running container still has empty preload because it was deliberately not restarted, and the new Compose setting takes effect on the next intentional `mix dev.down`/`mix dev.up`. CI has no production application/database secrets and performs neither migrations nor deployment. `.dockerignore`, the release overlay `/app/bin/migrate`, and the pinned Containerfile are part of the foundation. The container uses fail-closed `/health` readiness for Coolify promotion because Dockerfile health-check precedence applies; `/health/live` remains process liveness. `PHX_HOST` is required. The owner-provided Coolify webhook must run migrations using the target image and private database before promotion; no sibling `deploy-production` workflow is reused. Actual Coolify deployment, webhook exercise, domain/TLS, backup restore, administrator provisioning, external monitoring, and production-data validation remain pending.

## Current implementation checkpoint — 2026-08-14

The reusable `TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI` now owns bounded fixed-policy WooCommerce Store API request/pagination/normalization mechanics; LootQuest was refactored onto it without intended behavior change. CardzHouse category 742 and BoosterPoint category 61 are new development/private-test-only adapters. All three remain manual, with no sealed Cron/public schedule and independent zero-cost budgets of 50/hour, 100/day, and 500/month per source. Exact host/path/category/field policies, per-page admission, disabled redirects/retries, bounded pages/listings/body/time, strict PLN minor-unit conversion, conservative English filtering, and exact direct URL validation are enforced. Public recurring acquisition/republication permission remains unresolved.

Jobs 88 and 89 completed in one attempt with 2 and 4 admitted requests, retaining respectively 96 and 232 listings, immutable observations, review mappings, and decisions. CardzHouse was 13 in stock/83 sold out at PLN 22.95–1899.99; BoosterPoint was entirely sold out at PLN 3.99–990.00. Unchanged jobs 90/91 used 2/4 requests and retained exactly 96/232 rows, proving no duplicate observations/decisions. These real shops are deliberately `lgs`, not representative `regular_retailer` evidence. No reliable GTINs were supplied, so all new mappings remain `review`; title auto-match was not added. Candidates 8393 and 5423 remain unapproved without an authenticated admin actor, leaving aggregate/guide/public-offer behavior unchanged. Focused adapters passed 20 tests; combined adapter/worker/refresh passed 45 after review hardening; canonical `direnv exec . mix check --verbose` passed all static gates and 771 tests. Final review corrected `\A...\z` URL anchors, rejected newline-suffixed same-host URLs, and proved one admission/one request on 503.

The historical private TCGdex catalogue run exhausted all 218 set IDs: `completed`, next index 218, 192 synced, 15 excluded, 11 permanent failed, 192 persisted sets, and 20,561 card printings. Oban job 54 intentionally ended `cancelled / catalogue_sync_incomplete`; the later repair checkpoint below supersedes the hard-failure state without claiming production-complete coverage. Detailed private enrichment covers exactly `sv01-001` through `sv01-011`, all matched to Cardmarket IDs 702298–702308 with current `tcgdex_cardmarket_v1` valuations ranging EUR 0.03–5.04. These 11 mappings are not representative coverage.

Catalogue recovery is now partial-aware and operator-repairable. A valid detailed set whose provider `total` exceeds returned card briefs, or whose batch contains skippable malformed card briefs, persists the valid set/cards as an explicit `partial` outcome instead of discarding usable evidence or counting the set as hard failed. Run checkpoints retain separate synced/partial/failed/excluded counters; card-set administration shows provider totals beside imported-printing counts; current partial coverage is retained as a secret-safe unresolved diagnostic but is deliberately excluded from hard-failure repair. A later complete/excluded result atomically resolves the relevant partial/hard issue rows, while a later partial result resolves only prior hard rows and advances the current partial evidence. Per-set advisory locking and private resolution watermarks make record/resolve races order-independent: delayed older hard evidence stays resolved, equal-time hard evidence resolves, equal-time partial evidence remains current, and newer evidence remains unresolved. Acquired catalogue rows remain committed if lifecycle persistence fails, but the sync reports a retryable persistence failure and does not checkpoint success until issue resolution/partial evidence converges.

Authenticated operations can now queue one server-derived `failed_sets` repair scope containing only distinct unresolved malformed/failed set IDs, capped at 1,000. Full and repair jobs remain independently unique, but one scope snoozes without discovery or set fetch while the other scope owns the single durable active run; create races recheck scope before resuming. The admin surface exposes only the repairable count, never IDs, provider input, URLs, or raw job arguments. Empty repair state is disabled, issue-query overflow/failure disables only the repair control, and unrelated canonical manual targets remain available. At the implementation checkpoint that introduced this capability, no live repair/provider request had yet run and the local issue store had no unresolved hard set IDs.

That final sentence is now historical. A later private failed-set job completed in one attempt with 11 admitted requests and converted all 11 historical hard failures into explicit partial outcomes: 0 hard failures, 11 partial, 0 complete, and 0 excluded. The repair proved the scope and lifecycle path against the live provider, while also proving that the provider currently omits cards relative to `cardCount.total` for those sets. Ten sets remain unresolved partial coverage and are deliberately outside repeated hard-failure repair.

The repair also exposed a local identity defect for `exu`: TCGdex returned all 28 briefs, but the earlier grammar skipped valid IDs `exu-!` and literal `exu-%3F`. Card IDs now accept `!` and complete percent escapes while retaining a strict 128-byte segment grammar; set IDs remain stricter. The rule is enforced across Sync, Enrichment, Importer, exact-card HTTP paths, Cardmarket valuation, import diagnostics, trade URL state, and Trade pick handling. Fixed-host requests encode literal `exu-%3F` as `/cards/exu-%253F`; malformed escapes, delimiters, slashes, padding, and overlong IDs still fail closed. One later budget-admitted live `exu` sync used one request, imported 28/28 cards, created the two previously missing pending printings, and resolved the `exu` partial issue. Current private local state is 203 sets, 20,964 printings, and 10 unresolved partial sets; the original 192/15/11 run remains historical execution evidence rather than current coverage.

Latest LootQuest private refresh job 81 succeeded in one attempt with 5 admitted requests. Retained state remains 154 listings, 154 immutable observations, 153 review mappings, 1 matched mapping, and 155 decisions, proving unchanged refreshes do not append fake history. One retailer yields Limited data only; no ready sealed bands/directional history or public rights are claimed.

Home Market movers are local-only, up to 10 total and capped at 5 risers/5 fallers. They use the preceding 30 UTC dates, require at least two distinct daily points spanning one day, and require at least 2% absolute movement. Singles require current active-policy/current Cardmarket mapping; Sealed requires current recent ready mapping-confident aggregates and approved public products. This deliberate 1-day/2% discovery threshold supersedes the former 7-day/5% description to surface more bounded local evidence and remains subject to real-history tuning. With no qualified movers, up to 10 real `Recently tracked` rows appear instead: exact singles identity and valuation/freshness or `Price unavailable`, or approved public sealed releases in a five-year window. Copy states direction appears only after observations on at least two dates; rows use direct `View price`/`View offers` links. The separate cross-category zero-search-result fallback remains unchanged.

Current validation passes `direnv exec . mix check --verbose` with every static gate and 813 tests; eight focused identity/catalogue/operations/pricing/trade files pass 172 tests. The generated card-target grammar migration passed test-database down/up in addition to the three earlier recovery migrations. Final review found no actionable issue. A real browser opened the encoded punctuation Trade pick as `Unown · Unseen Forces Unown Collection · %3F` with no malformed warning, horizontal overflow, console warning, or console error. The earlier operations and Home browser evidence remains valid for those unchanged surfaces. Public permission/republication, complete coverage for the remaining 10 provider-partial sets, representative exact-printing/Cardmarket mapping coverage, representative Polish multi-retailer validation, recurring history, production deployment/monitoring/restore, and real riser/faller evidence remain incomplete.

**Status:** **Current product north star.** Unless the product owner explicitly supersedes this article, every requirement, implementation phase, documentation deliverable, and acceptance criterion listed below is authoritative and must be completed in full. Phase 3 trade/share is complete. Phase 4 now has source-neutral product/alias/retailer/listing/mapping/observation foundations, reusable bounded WooCommerce Store API request/pagination/normalization mechanics, three development/manual adapters (LootQuest, CardzHouse, and BoosterPoint), an atomic unique refresh path, no sealed Cron/public schedule, an authenticated administrator review desk, and a local-only public Sealed search/detail foundation. Phase 5 now has a local-only versioned daily aggregate foundation, the pure provisional `sealed_buying_model_v1`, persisted versioned buying-guide snapshots/recomputation, and public rendering of persisted ready/Limited guides, plain-English explanations from persisted factors, and the fixed 30-day graph. Daily aggregate persistence atomically enqueues jobs identified by the exact current and preceding 30-day revisions, and historical corrections cascade through affected following guide dates; local snapshot reads retain model outputs and factors. Public guide projection validates bindings, exact source fingerprints, and invariants, failing closed on corruption or mismatch; stale bands remain previous/cached/outdated rather than current. A fail-closed request-level acquisition-budget foundation covers every in-tree operational TCGdex catalogue, TCGdex Cardmarket, NBP, and sealed-retailer request with provider/global UTC counters, estimated-spend caps, persisted provider kill switches, and passive automatic provider circuit opening from terminal source-facing failures. Public connected LiveViews additionally apply a bounded direct-peer IP throttle before stale/missing singles or NBP work can be enqueued. Authenticated AshBackpex and focused operations surfaces cover the implemented curation, inspection, safe manual execution, source-health, and provider-control slices documented below. Written production source permission, real catalogue/observations/model validation, actual-cost reconciliation, active provider probes, remaining operations/AshBackpex resources, homepage tuning/deployment, and other acceptance work remain incomplete. The overall MVP is not complete.
**Current permission status:** The 2026-08-10 owner assumption permits explicit non-public adapter/test configuration, candidate polling, observation/history retention, and derived benchmark validation under existing budgets, rate limits, safety controls, attribution, and provider constraints. LootQuest, CardzHouse, and BoosterPoint are registered only in development for explicit manual private testing; no sealed Cron/public schedule exists. Curated LootQuest job 58 completed in one attempt with 5 admitted requests, persisting 154 listings, 154 immutable observations, and initially 154 conservative review mappings; rerun job 63 completed in one attempt with 5 more admitted requests and unchanged retained evidence: 154 listings, 154 observations, 153 review plus 1 matched mapping, and 155 decisions, with no fake history appended. New CardzHouse job 88 and BoosterPoint job 89 completed in one attempt with 2 and 4 admitted requests, retaining 96 and 232 listings plus immutable observations and review mappings; unchanged jobs 90/91 used 2/4 requests and retained exactly 96/232 rows, proving idempotence. These are development/manual LGS review-only observations, not representative regular-retailer coverage; public rights remain gated, and external permission and republication remain public-launch gates.

**Audience:** Long-running implementation agent

**2026-08-10 deployment-readiness update:** A pinned non-root multi-stage OTP release image now compiles application code before standalone Tailwind/esbuild deployment, includes only the compiled release and required runtime packages, and carries a configurable-port fail-closed readiness healthcheck for Coolify promotion. `TcgCheap.Release` provides release-safe forward migrations and one-shot administrator provisioning without Mix or full application/Oban startup; provisioning errors never expose rejected password or Ash detail. Public `/health/live` is dependency-independent process liveness, while `/health` fails readiness closed unless PostgreSQL, the Oban root and every configured unpaused production queue, and the complete acquisition-budget configuration are available. Neither path calls an external source or exposes raw failure/configuration detail. The root README and a deployment/operations guide now document environment injection, migration-before-start, health verification, administrator provisioning, backups/restores, compatible rollback, Oban/provider controls, and cached/stale incident fallback. The image build, release migration command, non-root runtime, health metadata, and live container endpoints were locally verified; no actual production deployment, restore drill, monitoring/alerting system, active source probe, or production-data validation is claimed.

**2026-08-10 automatic provider circuit-breaker update:** `SourceHealth` now retains a separate source-facing failure streak and circuit-open timestamp alongside the broader consecutive-failure evidence. Fixed `rate_limit`, `timeout`, `transport`, and `provider_response` outcomes increment the circuit streak; budget, persistence, configuration, local-input, unknown, and stranded-run repair outcomes do not. A successful completion resets a closed streak, while an in-flight success cannot close a circuit already opened by another attempt. At the configured threshold, only a terminal failed/cancelled attempt atomically disables the provider and records the opening under shared provider/source locks; request admission, manual control, and concurrent completions preserve one serialized outcome. Manual disable does not fabricate circuit evidence, and stale-safe manual re-enable explicitly clears it. `/admin/operations` shows closed/open state and threshold progress, and malformed or future circuit evidence fails the overview closed. This completes passive outcome-driven automatic circuit breaking, not active provider probing, actual-cost reconciliation, priority classes, trusted-proxy attribution, or deployment.

**2026-08-10 operations update:** Authenticated `/admin/operations` now provides a bounded current UTC request/estimated-spend ledger, configured-provider state and stale-safe kill-switch controls, a secret-safe retained-job failure summary, persisted source-health lifecycle evidence, and bounded external-acquisition run evidence. The three outbound Oban workers retain fixed outcomes/categories plus admitted request counts without raw diagnostics. This completes a useful admin visibility/control slice, not automated circuit breaking, actual-cost reconciliation, broad AshBackpex CRUD, manual refresh/retry operations, or the overall operations acceptance criteria.

**2026-08-10 acquisition-health hardening update:** A strict shared policy now distinguishes configured scheduled-source freshness from on-demand sources, marks running attempts overdue at the exact configured boundary, and fails the operations overview closed on malformed policy or impossible/future health evidence. NBP is stale after 36 hours without a successful tracked acquisition; the current TCGdex sources remain explicitly on demand. A unique 15-minute Oban reconciler now repairs at most 100 oldest terminally stranded runs per pass as failed/unknown under provider and row locks, preserving admitted request counts and source-health streaks; the acquisition query uses a running-only partial index. Valuation and exchange-rate workers now have explicit 60-second execution bounds. This completes terminal stranded-run reconciliation and passive stale-source policy, not active provider probing, automatic circuit breaking, acquisition priorities, actual-cost reconciliation, trusted-proxy attribution, or safe manual retry.

**2026-08-10 safe manual refresh update:** Authenticated `/admin/operations` now queues only three typed canonical targets: the fixed NBP EUR/PLN job, one exact locally imported TCGdex printing valuation, or one active local retailer whose source adapter is explicitly configured. The boundary validates a persisted administrator, bounded server configuration, current provider state, canonical local identity, and active Oban uniqueness; the UI distinguishes newly queued from already queued work. It never accepts a worker, URL, adapter, options, provider key, raw job arguments, or retained-job ID. Worker execution remains the only request-budget admission point, so each actual HTTP attempt still passes the provider/global hard cap and a disable race fails closed. This implements the required safe manual refresh/requeue capability for the three existing external-acquisition workers, not arbitrary retained-job replay, catalogue synchronization, active probes, automatic circuit breaking, or actual-cost reconciliation.

**2026-08-10 resumable catalogue synchronization update:** The earlier three-worker manual-refresh limitation above is now historical. A unique `catalogue_sync` Oban worker discovers and validates the canonical TCGdex set list once, persists a sorted/unique at-most-1,000-ID run, processes at most 20 sets per attempt, checkpoints every synced/excluded/permanently missing set under a row lock, and snoozes at least 15 minutes between unfinished batches. Transient decode/transport/rate-limit/provider-wide HTTP failures and budget rejection preserve the current checkpoint; only validated malformed set data, card-set conflicts, and set-specific HTTP 404/410 advance as failed. Every list/set request still enters request-budget admission immediately before HTTP, snoozed attempts retain successful acquisition-health evidence, and `/admin/operations` can queue or reuse only the canonical full-catalogue target. At this checkpoint live set-list reliability was unverified; the bounded live-success update immediately below supersedes that limitation. Public source permission, a successful production import, exact-printing coverage validation, and arbitrary retained-job replay remain open.

**2026-08-10 TCGdex discovery reliability update:** Every TCGdex catalogue request now has a five-second connect deadline, aligned 15-second receive/total deadline, disabled redirects, and a streamed 2 MiB response ceiling. Operational requests remain exactly one budget admission per wire attempt, while fixture-only callers retain at most two explicit safe retries. The adapter and provider-neutral synchronization boundary both reject more than 1,000 set briefs without truncation or downstream set fetches, and Req timeout errors now retain the dedicated timeout category for source health and passive circuit evidence. A post-change budget-admitted live discovery returned 218 sorted unique set IDs in 310 ms. This resolves the previously observed live list-timeout blocker for the current bounded smoke, not long-term provider reliability, a complete production import, enrichment/mapping coverage, or real search validation.

**2026-08-10 buying-model inspection update:** Authenticated `/admin/operations` now exposes a read-only, bounded projection of the complete current `sealed_buying_model_v1` policy: delegated aggregate version, reference and confidence weights, hard readiness gates, freshness/history thresholds, availability and sold-out-majority rules, all band adjustments and aggregate guardrails, deterministic arithmetic, and Limited-data precedence. A persisted administrator is revalidated before projection. The exact v1 policy fingerprint fails closed if any same-version policy value drifts, making a version bump mandatory before changed weights or rules can be presented as the same retained model meaning. The desk explicitly labels the policy provisional and synthetic-only; it adds no editing, recomputation, provider request, or real-market validation claim.

**2026-08-10 import-issue inspection update:** TCGdex catalogue Sync and Enrichment now retain normalized, secret-safe catalogue/set/card fetch, validation, and import issues plus unmatched/ambiguous external-mapping outcomes in `ImportIssue`. Exact issue identity preserves first occurrence and advances only the latest occurrence under concurrent repeats; app/database matrices reject incoherent operation-stage, stage-target, kind-code, provider, target, and time combinations. Raw reasons, payloads, URLs, exceptions, and callback details are discarded before persistence, and diagnostic failure never changes the import outcome. Authenticated `/admin/operations/import-issues` provides read-only index/show inspection with stable pagination and no mutation route. At that checkpoint this completed TCGdex catalogue import-issue persistence/inspection, not sealed-source diagnostics, card-mapping correction/history, active health probes/circuit breaking, actual-cost reconciliation, or all-job observability; later updates below close the first two limitations only.

**2026-08-10 sealed-retailer import-diagnostics update:** The configured sealed-retailer worker now records every validated refresh failure through the same `ImportIssue` normalization boundary without changing retry/cancel semantics. Canonical local retailer UUIDs anchor fetch, listing-validation, and listing-import stages; strict provider/operation/stage/target/category matrices are enforced in Ash and PostgreSQL. HTTP 408/429, transport, provider callback, malformed batch/listing, persistence, configuration, local-input, and unknown failures retain only fixed categories. Raw response detail, URLs, source listing IDs, payloads, provider options, and callback detail are absent; unsafe tuple outcomes are reduced before Oban can retain them, and diagnostic-write failure remains isolated. Existing authenticated read-only index/show inspection now covers TCGdex and sealed retailer issues. This completes local sealed-retailer refresh diagnostics, not production source permission/data, active health probing/circuit breaking, actual-cost reconciliation, all-job observability, or deployment.

**2026-08-10 all-job observability update:** Authenticated `/admin/operations` now counts every retained canonical Oban state across external and local-only workers and shows the newest 25 inserted jobs by default, with a hard maximum of 50. The projection contains only worker, queue, state, attempt, fixed failure category when applicable, and bounded time evidence; arguments, metadata, and raw errors remain excluded. Application and PostgreSQL Oban state sets must agree or the overview fails closed, and the bounded newest-job query uses insertion ID order supported by the Oban primary key. This closes the previous failed-job-only and local-job visibility gap, not active health probing/circuit breaking, actual-cost reconciliation, acquisition priorities, arbitrary retained-job replay, production source/data validation, or deployment.

**2026-08-10 card external-mapping correction update:** Authenticated card rows now link to a focused stale-safe correction/reopen workflow, and `/admin/catalogue/card-mapping-history` exposes immutable imported/baseline/provider-updated/corrected/reopened decision evidence with system or persisted-administrator attribution. Administrator authority survives provider imports; every mapping transition archives current valuations and shares one transaction with history. Active-policy writes, acquisition, workers, public current/history/search/trade relationships, and homepage movements require the currently matched positive Cardmarket product ID, so retained old-epoch snapshots cannot become current or enter public totals, graphs, or discovery. Provider imports and successful administrator UI transitions notify subscribed CardDetail and Trade consumers after commit; canonical single and bulk subscriptions re-read after subscribing, closing unresolved-to-matched and mutation/subscription races. The raw card upsert is internal to the locked importer rather than exposed through `Core`. This completes local card mapping correction/history and valuation binding, not production catalogue/mapping evidence or real exact-printing validation.

**2026-08-10 AshBackpex catalogue update:** AshBackpex `0.1.12` with Backpex `0.19.6` is now pinned and integrated under the existing administrator session at `/admin/catalogue/products`. The first main-CRUD slice lists and shows all sealed products and lets administrators create and stale-safely revise drafts; approved rows are inspectable but do not offer draft editing, and destructive actions are absent. The actual generic Ash read used by this AshBackpex release is strict-admin protected, while explicit public sealed reads remain separate. Review approval/archive, alias, and mapping decisions stay in the focused `/admin/review` desk. This validates the compatibility boundary and begins the required main admin interface; retailers, listings, cards, valuation snapshots, import issues, source health, manual refresh, model inspection, and other broad admin resources remain incomplete.

**2026-08-10 retailer catalogue update:** Authenticated `/admin/catalogue/retailers` now provides curated retailer create/list/show/edit with immutable post-create provider identity, category and active/disabled control, no provider payload fields, and displayed-version row-lock protection. `/admin/catalogue/listings` is a read-only current-projection index/show surface with retailer, identity, price, stock, direct-link, and audit-time evidence; it exposes no manual listing writer or payload. Direct generic reads are strict-admin protected, while narrowly scoped relationship-read authorization preserves the existing public-offer and local aggregate paths. AshBackpex's current one-column generic query path uses unique slug order for retailers and stable UUID order for listings rather than making a false chronological pagination claim. Retailer aliases, cards/mappings, valuation snapshots, import/source-health resources, safe manual refresh, model inspection, and broader operations remain unfinished.

**2026-08-10 alias catalogue update:** Authenticated `/admin/catalogue/aliases` now lists and shows all sealed-product name/EAN aliases, creates normalized pending manual aliases against a typeahead-selected canonical product, and stale-safely revises only manual pending rows. Provider-backed pending rows and approved/rejected decisions are inspectable but read-only; approval/rejection remains in `/admin/review`. Revisions lock and re-read the latest row, compare the displayed version, and reject any provider source, source reference, or retained payload even if a partially selected UI record looked manual. The generic alias read used by AshBackpex is strict-admin protected, while public sealed search traverses only a filtered approved-name relationship. Delete/bulk-delete and provider-payload display are absent. Cards/external mappings, valuation snapshots, import issues, safe manual refresh, model inspection, and broader operations remain unfinished.

**2026-08-10 mapping catalogue update:** Authenticated `/admin/catalogue/mappings` now lists and shows every listing-product mapping without exposing retained provider payloads; pending/review decisions remain in `/admin/review`. Terminal matched/rejected rows offer a separate reasoned correction confirmation that stale-safely reopens the row into review, preserving matched evidence as the next candidate. `/admin/catalogue/mapping-history` exposes immutable created/baseline/approved/rejected/reopened snapshots with safe evidence fields and administrator attribution. History writes share the mapping transaction, direct authorized history fabrication is forbidden, existing rows receive a migration baseline, import creates only a missing initial snapshot, and retained mapping/product references are restrictive. This completes mapping catalogue/correction history, not production mapping evidence or the remaining card/pricing/issue/refresh/model administration.

**2026-08-10 singles catalogue update:** Authenticated AshBackpex index/show surfaces inspect imported card sets, exact card printings with embedded Cardmarket mapping status/evidence, and immutable current plus archived single-valuation snapshots; the later focused workflow above adds card mapping correction and immutable decision history without enabling generic card edits or destructive actions. Generic reads are strict-admin protected while explicit catalogue/search/valuation actions and narrowly required relationship reads remain available to existing public and operational paths. Private source payloads, variant metadata, and normalized search columns are not selected by default or configured as fields. Because AshBackpex `0.1.12` applies only one UI sort through its generic query path, card sets/cards retain unique TCGdex-ID ordering and valuation snapshots use stable UUID ordering rather than claiming chronological pagination. Production catalogue/mapping evidence, manual refresh beyond existing typed workers, remaining operations, and deployment work stay incomplete.

**Historical earlier implementation checkpoint — superseded by the current 2026-08-10 checkpoint at the top:** The idle Home surface then read two bounded local discovery ledgers: up to four meaningful singles changes from the fixed preceding 30 UTC dates and up to four eligible sealed releases from a fixed inclusive 180-date window. Singles changes required last-successful daily closes on at least two dates spanning seven days, the active `tcgdex_cardmarket_v1` current latest snapshot, and at least 5% absolute movement; a generated `(policy_version, fetched_at, card_printing_id)` index bounded the retained-history window scan. Rows preserved exact identity, current EUR, signed movement, elapsed days, freshness/stale evidence, and direct routes. A selected-category zero match then performed one bounded local search in the other category and presented direct links in a separate recovery region outside the combobox/listbox, with availability announced through the persistent search live region. This was a conservative no-match fallback, not completed strong-versus-weak ranking tuning; that remained blocked on real catalogue collision evidence. Discovery stayed secondary/hidden while searching, used no provider call, and did not fabricate empty content.

## Current product-owner course correction — 2026-08-10

Before any public deployment, the product owner directs us to assume source permission everywhere solely for private/local/staging technical-feasibility work and self-testing. This unblocks enabling adapters, polling candidate public sources, storing observations/history, and exercising derived benchmarks in a non-public environment. Actual permission work proceeds externally and remains a gate for public launch and any public acquisition/republication.

This is an operating assumption for non-public testing, not a legal conclusion or a claim of actual third-party authorization. It does not permit authentication, payment, CAPTCHA, or other access-control circumvention. Request budgets, rate limits, safety controls, attribution, provider technical constraints, and all existing fail-closed boundaries remain in force. Historical checkpoints below are preserved; this decision supersedes older claims that written permission blocks private technical testing, which continue to describe the decision state at the time recorded.

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

This is a strong foundation, not completion of all Section 16 requirements. Active sources currently have zero acquisition cost, and estimated cost is conservatively reserved before HTTP. Public per-IP acquisition throttling is now implemented at the connected LiveView enqueue boundary as described below, the focused authenticated usage/failure ledger is documented in Section 16.6, and passive outcome-driven automatic circuit breaking is documented in Section 16.9. Actual-cost reconciliation for future paid responses, acquisition priority classes, and active provider probing remain required.

### 16.5 Implemented public per-IP acquisition throttle — 2026-08-09

Connected card-detail and trade LiveViews obtain the direct transport peer through Phoenix LiveView `:peer_data`; forwarded headers are deliberately not trusted. A supervised single-node fixed-window limiter allows 30 acquisition candidates per direct peer per hour by default, keeps at most 10,000 peer entries, prunes expired windows, serializes concurrent reservations, and fails closed for invalid/missing addresses or bounded-capacity exhaustion. The limit is configurable and is an abuse-smoothing control for the current one-VPS/direct-connection architecture, not a replacement for the persisted provider/global hard budget.

Only stale or missing work consumes the peer quota. Fresh local singles valuations and today's cached NBP rate do not reserve. Card-detail reserves immediately before a valuation job insert; Trade reserves separately for every canonical stale/missing card, so a large URL-backed composition cannot bypass the bound, while independently allowed cards may still enqueue. A stale/missing public NBP request reserves once before enqueue. Missing admitters and callbacks that raise, throw, exit, or return malformed values fail closed; direct trusted `enqueue` functions remain available for Cron/manual internal work and still pass through worker-level provider/global budget admission before HTTP. Rejection leaves stale values or `?`/PLN-unavailable states usable and queues no rejected job.

The peer limiter is intentionally in memory: a process/application restart clears its windows, while the PostgreSQL provider/global hourly, daily, monthly, and spend controls remain the durable hard-stop layer. If deployment later introduces a reverse proxy, explicitly trusted client-address resolution must be designed and tested before relying on per-client buckets; otherwise the direct peer would correctly be the proxy address and clients would share one bucket. Caddy/trusted-proxy integration remains deferred.

### 16.6 Implemented authenticated operations ledger — 2026-08-10

Authenticated `/admin/operations` reads a strictly validated maximum-100-provider server configuration, current configured-provider UTC counters, SQL-aggregated global current-window usage, exact retained counts for every canonical Oban state, and the newest 25 inserted Oban jobs by default (50 hard maximum) across external and local-only workers. Raw job arguments, metadata, and error messages are excluded; only retryable/discarded/cancelled rows receive a conservative timeout/rate-limit/budget/authorization/transport/persistence/generic category. The application state list is checked against PostgreSQL's `oban_job_state` values, and any count/query/configuration mismatch renders an explicit unavailable state rather than a healthy/empty assumption. The recent query orders by the indexed insertion identity instead of sorting all retained jobs by a derived expression.

Provider enable/disable actions accept only configured keys and require an administrator actor plus the displayed `updated_at`. A custom Ash change locks and compares the latest row inside the action transaction before applying the opposite state. Concurrent same-version controls allow one update, and admission-versus-disable races preserve one linear order. Unchanged acquisition upserts no longer touch `updated_at`, avoiding control-token churn during normal traffic; real configuration changes still invalidate old controls. Counters remain estimated reservations before HTTP. At this checkpoint actual paid-cost reconciliation, automated circuit breaking, and broader operational actions remained required; the later Section 16.9 circuit slice and Section 21 diagnostic slices supersede only those stated gaps.

### 16.7 Implemented acquisition-run and source-health evidence — 2026-08-10

`AcquisitionRun` now durably identifies each TCGdex catalogue synchronization, TCGdex Cardmarket valuation, NBP exchange-rate, and configured sealed-retailer Oban attempt. It retains only canonical provider/operation/target identity, worker/queue/job attempt metadata, running/succeeded/retryable-failure/failed/cancelled status, a fixed secret-free failure category, admitted request count, and timestamps. Same persisted job/attempt execution is single-use; a valid snooze is successful evidence for that bounded batch. A normal worker result is not reported when run finalization fails; later attempts atomically reconcile lower still-running attempts for the same job/provider as failed/unknown. Independently, a unique 15-minute reconciler repairs the oldest at-most-100 attempts still running at or beyond the 15-minute boundary, using provider advisory locks plus row locks and preserving request counts. The running-only partial index keeps this scan bounded by active evidence rather than retained terminal history.

`SourceHealth` retains per-provider last start, last success, last failure, last outcome/category, the broad consecutive-failure streak, a source-facing circuit-failure streak, and an optional circuit-open timestamp. Provider-scoped advisory locking serializes concurrent starts/completions and keeps streak changes aligned with durable run outcomes. Database constraints require an explicit terminal status, chronologically coherent latest success/failure evidence, nonnegative circuit evidence, and an open timestamp backed by a positive streak plus failure time; the overview additionally rejects future, malformed, or active-provider/open-circuit evidence. Successful admission increments an in-memory attempt counter only after persisted budget reservation succeeds. Validly shaped local-card and retailer preflight failures are tracked without invoking providers; malformed jobs that cannot establish safe canonical identity remain untracked. Every metered in-tree Req adapter now disables redirects as well as internal retries, so one admission cannot silently cover a redirect chain.

The operations desk projects health onto configured provider dockets and at most 25 recent configured-provider runs by default, with a hard maximum of 50. A strict shared configuration marks NBP current/stale/not-yet-observed from its last successful tracked acquisition while explicitly marking unscheduled TCGdex providers on demand; running rows at the stranded boundary render overdue until reconciliation. Raw arguments, payloads, exceptions, and provider error detail do not enter persistence or LiveView state. This remains passive evidence rather than an active probe; the later Section 16.9 adds outcome-driven circuit automation without adding synthetic health requests.

### 16.8 Implemented safe canonical manual refresh — 2026-08-10

The authenticated operations desk exposes a separate bounded manual-refresh panel. Fixed controls enqueue only the canonical full TCGdex catalogue synchronization, NBP EUR/PLN, and exact locally imported TCGdex Cardmarket valuation jobs. Configured sealed-retailer controls are derived from at most 100 server-side adapter entries, an active canonical local retailer, and the corresponding `sealed_retailer:<source_key>` budget provider; the browser submits only the local retailer UUID. Malformed worker/adapter/provider configuration fails the affected target closed without hiding the rest of a valid operations overview.

Every target is revalidated at submission. Persisted disabled providers block enqueue, unpersisted configured providers retain the existing effective-active semantics, and active duplicates return the existing Oban job rather than creating parallel work. No budget is reserved at button click: the tracked worker invokes request admission immediately before each outbound HTTP request, avoiding double reservation while preserving the disable/admission race guarantee. Catalogue work resumes its durable active run rather than rediscovering completed sets; terminal work can be requested again as a fresh canonical job. Arbitrary Oban job replay remains intentionally unsupported because retained arguments and diagnostics are not a trusted mutation boundary.

### 16.9 Implemented passive automatic provider circuit breaker — 2026-08-10

The strict acquisition-health policy now requires a bounded `circuit_breaker_failure_threshold` (default five). Only fixed source-facing `rate_limit`, `timeout`, `transport`, and `provider_response` categories increment the dedicated circuit streak. Budget rejection, persistence, configuration, local-input, unknown, and stranded-run reconciliation remain visible in broad health evidence but cannot trip the circuit. Retryable attempts build evidence without disabling a provider; crossing the threshold opens only when the current durable outcome is terminal failed/cancelled, so an Oban retryable failure does not suppress its own future retry.

Completion, provider status control, and request admission share provider/source lock ordering. The terminal run, health increment, provider disable, and `circuit_opened_at` write commit or roll back together; an unpersisted but configured provider is materialized before disable. Concurrent terminal failures preserve every increment, admission cannot succeed after automatic disable wins, and automatic opening converges safely with stale-safe manual disable. Success resets a closed circuit streak but cannot clear an already opened circuit from another in-flight attempt. Manual disable records no fake opening, while manual re-enable clears both circuit fields under the same source lock. PostgreSQL constraints and the overview reject impossible, future, or open-on-active evidence. The admin docket presents exact closed/open state and `streak / threshold` progress without raw provider detail. Active probe jobs, half-open trial traffic, alerts, actual-cost reconciliation, and priority classes remain outside this slice.

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

**Implemented card-catalogue job checkpoint — 2026-08-10:** `CatalogueSyncWorker` satisfies the production-safe execution foundation for card catalogue synchronization: canonical active-state uniqueness, strict server-owned provider configuration, request-budget admission for discovery and every set, a durable canonical set list, serialized one-set transitions, bounded batches with snooze/resume, retryable checkpoint preservation, permanent set-level failure accounting, acquisition/source-health evidence, normalized import issues, and authenticated canonical manual queueing. A generated `CatalogueSyncRun` table enforces provider, list, index, counter, lifecycle, and timestamp invariants. The later bounded-discovery hardening and live smoke close the earlier list-timeout blocker; the first complete production import and production reliability evidence remain unclaimed.

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

**Implemented subset checkpoint — 2026-08-10:** The focused authenticated operations LiveView covers current configured-provider/global quota and estimated-spend inspection, secret-safe retained failure summaries, stale-safe configured-provider enable/disable, configured-provider source-health lifecycle evidence, and bounded external-acquisition attempt evidence. At that checkpoint it did not claim the main AshBackpex CRUD interface, retailer-adapter control, safe manual refresh/retry actions, automated freshness/health checks, import issues, valuation/catalogue CRUD, model-version inspection, actual-cost reconciliation, or complete observability for local-only jobs; later slices below add bounded capabilities without broadening those older claims retroactively.

**Implemented AshBackpex foundation — 2026-08-10:** The pinned authenticated AshBackpex/Backpex surface now covers sealed-product index/show, administrator-only draft creation, and administrator-only stale-safe draft revision. It excludes delete/bulk-delete and delegates consequential approval/archive review to the custom review desk. This is the first required main-CRUD resource, not completion of the resource list above.

**Implemented retailer catalogue slice — 2026-08-10:** The same authenticated AshBackpex shell now covers retailer list/show/create/edit with category and active/disabled state management, immutable post-create source identity, and stale-safe transaction-local row locking. Current retailer listings are inspectable through a separate read-only index/show resource; manual listing create/edit/delete and private provider payloads remain absent. This advances retailer management and listing inspection but does not complete the remaining resources or operational workflows.

**Implemented alias catalogue slice — 2026-08-10:** The AshBackpex shell now covers all sealed-product alias list/show plus manual pending creation and stale-safe manual pending revision. Provider-backed pending rows and reviewed rows are read-only, consequential approve/reject transitions stay in the focused review desk, public search is limited to approved name aliases, and source payloads/destructive actions are not exposed. This implements the ordinary alias-management slice without claiming production alias curation or broader mapping/card administration.

**Implemented mapping catalogue/history slice — 2026-08-10:** The authenticated shell now covers mapping list/show and immutable chronological decision-history list/show. Terminal rows can enter a focused reasoned reopen confirmation; the locked action rejects stale records/tokens, returns the mapping to the existing review queue, and records an administrator-attributed snapshot in the same transaction. Import and migration baselines prevent unexplained histories without recording every evidence refresh. Provider payloads and destructive actions remain absent.

**Implemented singles inspection slice — 2026-08-10:** `/admin/catalogue/card-sets`, `/admin/catalogue/cards`, and `/admin/catalogue/valuations` provide authenticated read-only index/show inspection of safe set/card identity, embedded external Cardmarket mapping state, and immutable current/archive valuation provenance. Private payload/variant/search-normalization attributes are deselected by default, generic reads require an administrator, public exact-card and valuation relationship paths remain narrowly authorized, and no create/edit/delete/correction action is exposed.

**Implemented safe manual refresh slice — 2026-08-10:** `/admin/operations` now offers fixed NBP refresh, exact local-card valuation refresh, and explicitly configured active sealed-retailer refresh. The typed coordinator validates persisted administrator identity, provider/adapter configuration, provider status, and canonical local targets before calling the existing unique enqueue APIs. It reports queued versus already queued work and accepts no arbitrary provider, URL, worker, arguments, or retained job. Generic arbitrary retry remains absent by design; terminal work is requeued only through a newly validated canonical target.

**Implemented resumable catalogue refresh slice — 2026-08-10:** The same desk now also offers one fixed TCGdex catalogue target. It can only enqueue/reuse the worker-owned `%{"scope" => "all_sets"}` job; discovery, durable progress, request admission, failure classification, batching, and resume behavior remain server-owned. No browser input can select a set, provider, adapter, URL, arguments, or retained job. This supersedes only the earlier catalogue-sync limitation, while generic arbitrary retry remains absent by design.

**Implemented buying-model inspection slice — 2026-08-10:** The same authenticated desk now renders the current provisional buying-model and delegated aggregate versions plus every decision-relevant v1 policy value through a strict read-only projection. Hidden implementation rules that were previously absent from `policy/0`—the recent-sold-out majority scarcity condition and Great/Fair/Expensive aggregate guardrails—are now explicit policy data without changing model behavior. Exact deterministic v1 fingerprint validation rejects silent same-version policy drift, while malformed policy renders an unavailable state independently of provider-overview availability. No model edit or recomputation control is exposed.

**Implemented TCGdex import-issue inspection slice — 2026-08-10:** `/admin/operations/import-issues` provides authenticated read-only index/show inspection of normalized TCGdex catalogue sync/enrichment failures and unmatched/ambiguous mapping outcomes. Canonical issue identity retains first/latest occurrence without raw diagnostics, concurrent repeats converge, operation/target/category matrices are enforced in app and database, and recording failure is isolated from import behavior. The generic read is strict-admin protected and no create/edit/delete UI exists. At that checkpoint, sealed-source diagnostics and card external-mapping correction/history remained separate unfinished boundaries; the later card-mapping and sealed-retailer diagnostics slices below supersede those two limitations.

**Implemented card external-mapping correction/history slice — 2026-08-10:** `/admin/catalogue/cards/:id/correct` provides a reasoned stale-safe exact Cardmarket product correction or reopen-to-review workflow, and `/admin/catalogue/card-mapping-history` exposes immutable scalar-only decisions. Mapping authority, transaction-local locks, displayed versions, valuation archival, decision writes, provider-import preservation, restrictive references, and an importer-private raw upsert make correction reversible and auditable without exposing raw payloads or generic destructive CRUD. Active `tcgdex_cardmarket_v1` persistence and public search/current/history/trade projections are product-ID bound; old mapping epochs remain retained history only. Mapping changes notify already mounted canonical CardDetail and Trade consumers after commit, including unresolved-to-matched transitions.

**Implemented sealed-retailer import-diagnostics slice — 2026-08-10:** The same authenticated `/admin/operations/import-issues` index/show now includes normalized configured sealed-retailer refresh failures. The worker records only after canonical job-argument validation and projects one safe provider/operation/stage/local-retailer/kind/code identity; repeated attempts converge while advancing only the newest occurrence. Adapter detail never enters `ImportIssue`, and malformed/unknown tuple outcomes are sanitized before Oban retention. Existing worker retry/cancel behavior remains intact, diagnostic persistence is non-authoritative, and app/database matrices reject cross-provider operations, invalid stages/targets, unsafe provider identities, malformed retailer UUIDs, and incoherent categories. No mutation route, live source, or production evidence is added.

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

1. **Production-safe execution and live repair validated; coverage remains incomplete:** Strict set/printing import has a canonical resumable Oban path with one validated discovery list, durable checkpoints, bounded budget-aware batches, and typed manual queue/reuse. Valid incomplete provider coverage is retained as explicit partial evidence; hard failed set IDs can be retried through a separate scope-safe server-derived repair job without list rediscovery. TCGdex catalogue requests retain aligned deadlines, a 2 MiB streamed response ceiling, no redirects, strict 1,000-set cardinality, exact timeout evidence, and an exact card-ID grammar that covers the observed `!`/literal `%HH` identities without permitting path delimiters. The private failed-set job processed the 11 historical failures in one attempt with 11 admitted requests and converted all to partial rather than hard failure. A one-request follow-up corrected `exu` to 28/28; 10 provider-partial sets, long-term reliability, representative mapping, and production coverage remain outstanding.
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
2. **Foundation advanced, not complete:** Added `SealedProductAlias` name/EAN review queues with normalized aliases, original values/provenance, pending/approved/rejected states, approved-per-product reads, and app/DB GTIN-8/12/13/14 ASCII normalization plus GS1 checksum enforcement and global canonical-product uniqueness. Imports are pending-only/idempotent and cannot overwrite reviewed aliases. The authenticated review desk can approve or reject pending aliases with canonical-product evidence and stale-row protection. Authenticated AshBackpex list/show plus manual pending create/stale-safe edit now supports local curation without letting provider-backed or reviewed evidence be rewritten. No production aliases/EANs/MSRP curation exists, so this step is not complete.
3. **Private technical checkpoint complete; public acquisition remains gated:** The reusable bounded WooCommerce Store API request/pagination/normalization mechanics now support three development/manual adapters: LootQuest, CardzHouse, and BoosterPoint. All remain bounded at 50/hour, 100/day, and 500/month per source, with no sealed Cron/public schedule. LootQuest job 58 completed in one attempt with 5 admitted requests; 154 listings, 154 immutable observations, and initially 154 conservative review mappings were persisted because the source supplied no GTIN evidence. Obvious import/preorder/accessory candidates remained filtered. Every successful ingest ensures a mapping in the same transaction; invalid/ambiguous evidence refreshes review, one eligible approved exact EAN may promote mutable review to matched, terminal decisions resist source overwrite, and failures roll back the batch. One curated `Pokémon TCG: Scarlet & Violet—151 Booster Bundle` and listing source ID 104164 were approved/confirmed; its aggregate is `limited / too_few_regular_retailers` and guide `limited / limited_market_aggregate` at confidence `0.19`, with no fabricated bands. CardzHouse job 88 and BoosterPoint job 89, followed by idempotent jobs 90/91, retained 96/232 listings and immutable review-only evidence; both are LGS observations, not representative regular-retailer coverage, and neither new mapping was approved. This is not production data or public permission.
4. **Foundation advanced, not complete:** Added conservative exact-approved-GTIN matching and one human-reviewable listing-to-product mapping projection with pending/review/matched/rejected transitions, locked review decisions, approved-product validation, and import protection. The authenticated review desk exposes one-row-at-a-time approval/correction or reasoned rejection with retailer/listing/candidate/evidence context. A separate authenticated catalogue lists/shows all mappings and immutable created/baseline/approved/rejected/reopened decision snapshots; reasoned terminal correction stale-safely reopens a row into review while retaining prior decisions. Mapping/history generic reads are strict-admin protected, direct history recording is denied, and history failure rolls back the parent transition. Every product, alias, and mapping review submits the displayed `updated_at` version and revalidates both the supplied and transaction-locked record versions, so stale forms or mixed stale-record/current-token callers cannot silently act on newer evidence. No real production mappings exist.
5. **Private evidence collected; foundation remains bounded:** Every successful current-listing ingest appends an immutable PLN price/stock/source observation only when content changes, and ensures a mapping in the same transaction. Job 58 collected 154 observations; a unique listing/check-time boundary rejects ambiguous same-timestamp changes and failed batches roll back. This does not establish recurring stock history or production/public data.
6. **Public rendering implemented; Phase 4 remains incomplete:** Current listing rows retain direct URL, price, stock state, first/last-seen and last-checked audit timestamps, while immutable history feeds the daily aggregate path. Public reads require an approved released official PL/en product, a matched mapping, and active listing/retailer. `/` searches local approved canonical names plus approved name aliases with bounded deterministic PostgreSQL ranking and stable accessible options; `/sealed/:slug` shows canonical identity, release/status, optional provenance-backed MSRP, one cheapest in-stock listing per shop sorted by PLN price, and one most recently checked sold-out listing per shop within 30 days in a separate section. Persisted current-model guide snapshots provide exact ready four inclusive-ceiling Great/Fair/Expensive/Avoid ranges and plain-English explanations from persisted factors, or exact Limited data reasons/factors. `SealedMarketHistory` provides the fixed 30 UTC-calendar-day SVG and textual ledger. Projection/aggregate/history corruption or mismatch fails closed; older-ready/newest-limited combinations remain explicitly cached/outdated and stale bands are never current. No provider runs in public paths and stale Enter events cannot select prior autocomplete options. Private testing is no longer blocked by permission; production catalogue/retailer evidence, real validation, and public acquisition/republication rights remain absent; no production data is claimed.

Generated Ash migration/snapshot sets `20260808160842_sealed_catalogue_foundation`, `20260808204902_sealed_retailer_listing_foundation`, `20260808213452_sealed_listing_observations`, the `20260808231641`/`20260808231642` administrator-authentication pair, `20260809003932_public_sealed_lookup`, `20260809140042`–`20260809145258` for sealed daily aggregates, `20260809163539`–`20260809185311` for persisted buying guides/source evidence/current-plus-history revision hardening, and `20260810033425`/`20260810033437` for immutable mapping decisions plus existing-row baseline were applied and reviewed. The public lookup migration adds concurrent GIN trigram indexes for canonical sealed names and aliases. The generated authentication-extension rollback was narrowly corrected because dropping shared pre-existing Ash functions was demonstrably unsafe. Product/alias/mapping review transitions use transaction-local row locks plus displayed-version checks; listing ingest uses a stable per-listing transaction advisory lock. Aggregate and guide app/database constraints cover version/currency/state, canonical limited reasons, finite ordered money, nonnegative/coherent coverage counts, evidence/calculation time, exact current/history source fingerprints, restrictive parent references, and one product/date/version row. Other app/database constraints continue covering review state, immutable mapping-decision transitions/snapshots/actors/evidence, identity, timestamp, locale, source, finite-money, stock/price, GTIN/checksum, URL, foreign-key, and unique observation-boundary invariants.

Latest sealed validation includes the prior observation/retailer/listing/mapping/concurrency, LootQuest contract, bounded worker, administrator authentication/authorization, dual-key throttling, stale-review coverage, daily aggregate calculator/resource/worker/public-snapshot suite, pure buying-model suite, persisted-guide input/resource/worker integration, and the new public guide/history/graph rendering coverage. Canonical `direnv exec . mix check --verbose` passes 523 tests with format, Ash codegen, Sobelow, warnings-as-errors compile, unused dependencies, xref, Credo, and Dialyzer clean. The four focused new/updated public aggregate/guide/history/LiveView files pass 29 tests; assets build passes; final code review is clean. Browser checks at desktop 1000px and mobile 390px show ready bands/reasons/graph/ledger, no horizontal overflow, sampled controls at least 44px, and no console warnings/errors. Impeccable found only the two known square-border false positives plus design-system advisories; graph colors align with existing tokens. Temporary browser fixture rows were deleted and counts verified zero. No production SKU, retailer, listing, aggregate, guide, provider permission, live schedule, or fabricated production history was added. Written source access, real catalogue/observations/model validation, AshBackpex/operations, actual-cost/source-health/admin controls, homepage discovery/tuning/deployment, and broader MVP acceptance work remain blockers; the later public per-IP throttle is documented in Section 16.5 and Phase 6.
**Historical feasibility checkpoint — superseded by the current 2026-08-10 checkpoint at the top:** The focused refresh suite passed 11 tests; the then-current canonical `direnv exec . mix check --verbose` passed 752 tests with format, Ash codegen, Sobelow, compile, unused dependencies, xref, Credo, and Dialyzer clean; browser search/detail had zero console errors. Review findings about mutable mapping reconciliation, Credo nesting, and retry headroom were corrected. That checkpoint observed 100/218 sets before later attempts and described the full catalogue as an in-progress private exercise. The current checkpoint now records completed 218-ID execution with 11 permanent failures; these older test results and partial-progress counts remain historical. One retailer still validates sparse/Limited behavior only, not ready benchmark bands, representative Polish-market weights, multi-shop dedup/outliers, recurring stock history, or public source rights.

The mapping catalogue/history batch brings canonical validation to 614 passing tests. Focused mapping history/catalogue plus review coverage passes 23 tests, including strict generic reads, denied direct history fabrication, import/baseline history, transaction rollback, stale record/token rejection, safe evidence projection, reasoned reopen, and secret-free rendering. Migration up/down and a real rejected-row baseline were exercised. Desktop and 390px browser checks covered sign-in, chronological mapping/history navigation, blank and successful correction, review-queue return, 45px actions, no horizontal page overflow, and no console warnings/errors; temporary rows and session data were removed and verified absent. Final read-only review was clean after chronological admin ordering was corrected. This adds no production mapping evidence.

The singles catalogue/valuation inspection batch brings canonical validation to 618 passing tests. Focused admin coverage proves route authentication, strict generic reads, administrator catalogue reads, preserved anonymous search/current-valuation/card-set relationships, private attributes remaining `Ash.NotLoaded`, safe index/show fields, relationship links, immutable current/archive visibility, and absent mutation actions. A 327-test catalogue/singles/Home/CardDetail/Trade regression passed before the full gate. Desktop and 390px browser checks covered card and valuation ledgers, internal table scrolling without page overflow, both current/archive rows, no console warnings/errors, and complete temporary record/token cleanup; the Impeccable detector returned no findings and final read-only review was clean. This adds inspection only, not production catalogue or mapping evidence.

The acquisition-health hardening batch brings canonical validation to 640 passing tests. Focused operations/worker/admin coverage passes 101 tests, including exact freshness/overdue boundaries, strict configuration, one-clock overview projection, future-evidence rejection, explicit worker timeouts, oldest-first bounded idempotent reconciliation, missing-health restoration, post-lock completion time, invalid-configuration no-mutation behavior, and database terminal-state chronology. Generated migration rollback/up passed; live PostgreSQL inspection confirmed the running-only partial index and strict source-health constraint. Browser validation showed scheduled/on-demand freshness states, an overdue synthetic attempt, and its failed/unknown reconciliation; restart-only LiveView connection errors were observed during the intentional server restart. Temporary run, health, administrator, and tokens were removed and verified absent. Final read-only review found no actionable issue. Active probes/circuit breaking, actual-cost reconciliation, priority classes, safe manual retry, production evidence, real validation, and deployment remain.

The later safe-manual-refresh batch brings canonical validation to 653 passing tests. Its 24 focused coordinator/LiveView tests cover persisted versus forged administrators, canonical arguments and active duplicate reuse for all three acquisition workers, malformed/oversized/tampered targets, adapter bounds, disabled/unconfigured providers, secret-free projections, immediate provider-control synchronization, and invalid-input preservation. `mix check --verbose`, the mechanical UI detector, and final read-only review are clean. Desktop and 390px browser checks showed explicit states, 44.8px controls, stacked mobile dockets, no horizontal overflow, no console warning/error, and no dynamic provider request; the temporary administrator/tokens were deleted and verified absent.

The buying-model-inspection batch brings canonical validation to 657 passing tests. Fifty-six focused model/inspection/LiveView tests cover exact versions and policy shape, persisted versus forged administrators, ordered safe projection, deterministic same-version fingerprint rejection, nonfinite/malformed evidence, all operative market and band guardrails, independent provider-overview failure, and absent mutation controls. Canonical static checks, the mechanical detector, and final read-only review are clean. Desktop 1000px and 390px browser checks confirmed the provisional boundary, hard five-shop minimum versus eight-shop confidence target, ordered Limited reasons, 44.8px navigation, no model control, no horizontal overflow, and no console warning/error; the temporary administrator/tokens were deleted and verified absent.

The automatic provider circuit-breaker batch brings canonical validation to 736 passing tests. Focused operations/worker/admin coverage passes 146 tests; dedicated cases cover strict threshold configuration/category selection, retryable evidence without opening, terminal failed/cancelled opening, configured-provider materialization, excluded categories, success reset versus in-flight-open preservation, manual disable/re-enable semantics, invalid-policy rollback, malformed/future/binding evidence, concurrent increments, and admission/control/opening races. Generated migrations `20260810135856_automatic_provider_circuit_breaker` and `20260810142702_harden_provider_circuit_evidence` plus Ash snapshots were reviewed and passed test-database down/up; static checks and final multi-agent review are clean. An authenticated browser check confirmed three configured-provider dockets rendering `CLOSED` and `0 / 5` at desktop and 390px with no page overflow or operations-page console warning/error; the temporary administrator and tokens were removed.

### Phase 5 — Buying intelligence

1. **Implemented and privately exercised; broader validation remains:** A unique daily local-only Oban worker reads approved products and every matched active listing, skips products with no mapped evidence rather than fabricating history, and upserts one retained product/date/version aggregate. The 16:00 UTC schedule follows NBP but performs no external request. The curated bundle persisted `limited / too_few_regular_retailers` with one regular retailer; broader benchmark validation remains open.
2. **Initial v1 implementation complete, real-market validation outstanding:** `sealed_market_daily_v1` chooses one cheapest fresh (maximum seven-day age) in-stock listing per retailer, requires five regular retailers, keeps LGS separate, deduplicates the latest eligible sold-out listing per retailer into 0–14/15–30-day buckets, removes Tukey 1.5-IQR outliers, and stores the half-up two-decimal median plus inlier min/max range. Canonical limited reasons cover no fresh current evidence, too few regular retailers, and insufficient inliers. App/database invariants and public defensive validation fail closed on inconsistent state/count/time/money.
3. **Initial implementation, public projection, and authenticated policy inspection complete; real validation outstanding:** `sealed_buying_model_v1` is a deterministic, fixed-Decimal, versioned module with inspectable component/confidence weights, sold-out recency and majority rules, trend/availability thresholds, hard requirements, aggregate guardrails, limited-reason precedence, and two-decimal rounding. It defensively validates aggregate/history/LGS/sold-out evidence and does not call providers. A current-plus-history exact-revision worker persists its result separately, the public path consumes it without recomputation, and `/admin/operations` exposes the exact current policy through a fingerprint-locked read-only projection. The [Sealed Buying Model v1 ADR](../architecture/sealed-buying-model-v1.md) records the decision and trade-offs.
4. **Synthetic cases and one private checkpoint complete; real-market validation gated:** Required representative policy fixtures remain covered. The curated bundle produced Limited data at confidence `0.19` and no fabricated bands; initial weights remain provisional until representative Polish-market observations, multi-shop dedup/outlier evidence, and recurring history exist. Public launch still requires externally completed permission work.
5. **Persistence/recomputation and public behavior implemented; real validation outstanding:** The model returns explicit Great/Fair/Expensive/Avoid intervals or deterministic Limited data, including fail-closed rounded-boundary handling. `SealedBuyingGuideSnapshot` retains one model-versioned product/date result, current aggregate plus preceding-history revision fingerprints, confidence, component centers, trend/availability states, ceilings, and explanation factors. Daily aggregate persistence atomically enqueues unique exact-revision recomputation for every affected guide date; source rows are locked and rechecked before write, stale jobs enqueue the latest successor, transient reads retry, and local latest/ready/history reads are available. Public projection validates bindings/fingerprints/invariants and renders persisted bands/factors or Limited reasons; real catalogue/observations/model validation remains.
6. **Implemented and browser-validated on private evidence:** Consume persisted guide factors for plain-English explanations and render the fixed 30 UTC-calendar-day sealed graph with benchmark line, typical-range band, gaps, and textual ledger. The private browser search/detail showed one 899.99 PLN offer and honest Limited-data messages with zero console errors; only canonical ready rows are plotted.

### Phase 6 — Homepage, hardening, and deployment

1. **Current balanced local implementation complete; production population/caching remains:** Home now shows up to 10 local Market mover rows, balanced at up to 5 risers and 5 fallers, using two daily dates spanning one day and at least 2% movement within the preceding 30 UTC dates. When no qualified movers exist, it shows up to 10 real `Recently tracked` singles or approved public sealed rows within a five-year window, with concise copy explaining that direction requires observations on two dates. The ledgers remain secondary to search, and the separate local cross-category recovery path appears only after zero primary matches. It does not fabricate discovery rows.
2. **Blocked on real catalogue evidence:** Tune primary ranking and strong-versus-weak cross-category fallback using measured collision cases after production catalogues exist. The current zero-match fallback is intentionally conservative.
3. **Foundation advanced, not complete:** request-level provider/global UTC limits, estimated-spend caps, persisted provider kill switches, passive outcome-driven automatic circuit opening, a bounded direct-peer public acquisition throttle, authenticated current usage/failure visibility, persisted external acquisition attempts, source-health lifecycle/broad/circuit streak evidence, strict scheduled-source freshness projection, overdue evidence, and periodic terminal stranded-run reconciliation are implemented; actual-cost reconciliation, priority classes, active automated health probes, and trusted-proxy client-address handling for a future proxied deployment remain.
4. **AshBackpex catalogue expanded plus focused operations desks implemented; broader admin incomplete:** authenticated sealed-product list/show/draft create/stale-safe edit, manual pending alias list/show/create/stale-safe edit, curated stale-safe retailer management/category/status control, read-only current retailer-listing inspection, mapping list/show, immutable decision-history list/show, card-set/card identity plus embedded external-mapping inspection and reasoned correction/history, immutable single-valuation snapshot inspection, and normalized TCGdex catalogue plus configured sealed-retailer refresh issue inspection now exist in pinned AshBackpex. Consequential product/alias and pending sealed-listing mapping decisions stay in the focused review desk; terminal listing and card mapping correction use stale-safe focused confirmations. Authenticated current quota/estimated-spend ledgers, all-state retained Oban counts plus a bounded secret-safe newest-job ledger across external and local-only workers, bounded external-attempt evidence, source-health freshness and automatic-circuit evidence, overdue detection, periodic stranded repair, stale-safe provider controls, typed safe manual refresh/requeue for every existing external-acquisition worker including the server-derived failed-set repair scope, and exact read-only buying-model configuration/version inspection also exist. Active provider probes, arbitrary retained-job replay, actual-cost reconciliation, acquisition priorities, and broader operational workflows remain.
5. **Deployment health foundation implemented; broader monitoring remains:** Public JSON liveness and fail-closed readiness endpoints now distinguish process availability from PostgreSQL/Oban/acquisition-configuration readiness. The readiness projection checks every configured unpaused production queue without provider traffic or raw diagnostics, and the container uses fail-closed `/health` readiness for Coolify promotion while `/health/live` remains separate process liveness. Active external source probes, alerts, metrics export, and production monitoring integration remain unfinished.
6. **Automated suite current; live repair complete but catalogue still partial:** Canonical validation passes 813 tests and all static gates. The private 218-ID historical run's 11 hard failures were processed by the live scope-safe repair in one attempt; all became partial, and the punctuation-ID correction plus one budget-admitted `exu` sync reduced current unresolved partial coverage to 10 sets while retaining 20,964 printings. Representative mapping coverage, complete provider coverage, accumulated observation/history validation, search collision/ranking tuning, sealed observations/stock transitions, and Polish-market buying-model validation remain open under budgets and safety controls. Public acquisition/republication and launch still require external permission work plus reliable, attributable, non-fabricated evidence.
7. **Initial deployment/operations documentation and release path implemented; production exercise remains:** A pinned non-root OTP release image, release-safe migration/admin commands, environment guidance, health verification, backup/restore expectations, rollback constraints, and Oban/provider incident runbook are present and locally container-verified. An actual production deployment, backup restore drill, trusted-proxy/TLS topology, and production operational acceptance still remain.

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

**2026-08-10 deployment-documentation checkpoint:** The root README, `.env.example`, and `docs/deployment-and-operations.md` now cover setup entry points plus the production image/release, runtime environment, migration, administrator provisioning, health, backup/restore, rollback, provider-control, and incident procedures. This closes the initial deployment guide and operations-runbook artifact gap only. The broader architecture overview/resource map, provider adapter/import/test guides, known-limitations roadmap consolidation, actual production exercise, and any still-unwritten required artifacts remain part of this section.

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
