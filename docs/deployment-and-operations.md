# Deployment and operations

## Coolify deployment target

This repository is deployed from a public repository through Coolify at
<https://tcg-cheap.d.alergeek.me>. Public read pages remain unchanged and
public; administrative access is protected by the application's admin
authentication. Coolify builds
`deployment/Containerfile.app` and publish the application on internal
container port `4004` (the public hostname and TLS termination are configured
in Coolify).

The Coolify PostgreSQL service must use this exact validated ParadeDB image:

```text
docker.io/paradedb/paradedb:v0.25.2-pg18@sha256:f34b716407b4d509d3e59e649495964b296ad7c0931658dbf99d3cf1b35bc994
```

Use a persistent volume compatible with this ParadeDB PostgreSQL 18 target,
mounted at the image's PostgreSQL data directory, and retain the existing
database volume across redeploys. Do not switch the service to a stock
PostgreSQL image or reuse a volume initialized by an incompatible major
version.

The image ships `pg_search` and `pgvector` and may bootstrap their extension
installation on a fresh database. A compatible volume previously initialized
under stock PostgreSQL may expose the extensions as available without having
installed or preloaded them. Before using `pg_search`, the server must include
it in `shared_preload_libraries` and be restarted after changing that setting.
Before any future migration enables `pg_search`, an operator must verify:

```sql
SHOW shared_preload_libraries;
```

The result must include `pg_search`. Do not reset or delete an existing local
or production volume merely to enable preload. Back up the data and recreate
the container against the same compatible persistent volume. TCG Cheap-owned
migrations, resources, and queries do not currently depend on or use BM25 or
vector functionality.

GitHub-hosted CI never receives production application or database secrets.
Deployment secrets stay in Coolify, and no sibling `deploy-production`
workflow is reused. A stock Coolify Dockerfile pre-deployment command runs in
the existing container, so it is not sufficient for this migration gate. The
configured release orchestration runs the migration
against the private database network using the target/new image before
traffic promotion, aborts on failure, and handles future first deployments too.
Repository CI does not implement this orchestration. The configured release
gate must execute:

```text
/app/bin/migrate
```

Do not start or route traffic to an image whose migrations failed.

### Variables

Required production variables:

- `PHX_HOST` — the public HTTPS hostname. Runtime startup fails if it is
  missing or blank; there is no fallback host.
- `DATABASE_URL` — the production PostgreSQL connection URL.
- `SECRET_KEY_BASE` — the production Phoenix secret.

Optional variables:

- `ADMIN_AUTH_SIGNING_SECRET` — dedicated admin-token signing secret; if
  omitted, `SECRET_KEY_BASE` is used. If supplied, it must contain at least 32
  bytes.
- `PORT` — internal listener port; defaults to `4004`.
- `POOL_SIZE`, `ECTO_IPV6`, and `DNS_CLUSTER_QUERY` — runtime tuning/options.

Set `ADMIN_EMAIL` and `ADMIN_PASSWORD` only for the one-shot administrator
provisioning command below. Do not commit any of these values or bake them
into the image.

## Database and release migrations

ParadeDB **v0.25.2-pg18 is the pinned, validated production target**. This
image currently bundles PostgreSQL **18.4**, ships `pg_search` **0.25.2** and
`pgvector` **0.8.4**, may bootstrap extension installation on fresh databases,
and is the database image used by local Compose and CI. TCG Cheap-owned
migrations, resources, and queries currently use only its existing Ash
functions, `citext`, `pg_trgm`, and trigram queries; they do not depend on or
use BM25 search or vector functionality. Local Compose explicitly requests
`pg_search,pg_cron,pg_stat_statements` through
`shared_preload_libraries`; the current local container should not be
restarted blindly. That setting takes effect on the next intentional
`mix dev.down`/`mix dev.up` recreation, while production changes remain
operator-controlled.

The current stock PostgreSQL minor release is **18.6**, so this target carries
an honest minor-version tradeoff: the chosen current ParadeDB build bundles
18.4. Update the pinned ParadeDB image when a validated build includes newer
PostgreSQL fixes. Any future use of `pg_search` or vector features requires
generated migrations, application/query integration, tests, and upgrade and
backup/restore validation first.

Generated migrations create the required `citext`, `pg_trgm`, and Ash
functions. The migration role must be allowed to create and own the required
extensions and functions, or the complete migration must run with a
dedicated, sufficiently privileged migration role. Run it through the
configured Coolify release gate, not GitHub-hosted CI:

```text
/app/bin/migrate
```

The `pg_stat_statements` migration requires `pg_stat_statements` to be present
in PostgreSQL's `shared_preload_libraries` setting. It checks that setting
using `pg_settings` before creating the extension and raises a PostgreSQL
exception when the library is not preloaded. Therefore, a missing preload
causes `/app/bin/migrate` to exit non-zero; the release gate must fail the
deployment and prevent the new image from being routed until the setting is
corrected and PostgreSQL has been restarted.

The migration command is a deployment gate: a non-zero exit must fail the
Coolify webhook/deployment and prevent the new release from being routed.
Inspect migration logs and correct the database or schema issue before
retrying.

Database migrations are forward-only. Do not run, use, or require `down` or
`ecto.rollback` checks as a quality gate. Correct schema or data issues with a
new forward migration; recover disasters from a tested backup or PITR. Existing
historical down/up validation records remain historical evidence only. Image
rollback is a separate deployment concern and is permitted only when schema
compatibility has been proven; never reverse database migrations.

Implementation commit `b7afc9049a8af42dd569f44d2c140cb58f64221c` (`b7afc90`) was
pushed and deployed on 2026-09-07. GitHub [CI run
34160080003](https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/34160080003)
passed all three jobs: app container, DB image validation, and canonical `mix
check` (1,162 tests). At about 20:40 UTC, production `/health` and
`/health/live` reported healthy with exact revision `b7afc9049a8af42dd569f44d2c140cb58f64221c`, DB ready, Oban
ready with 8 queues, and acquisition budget ready with 10 providers. The
configured migration release gate necessarily succeeded for traffic promotion;
the migration table and exact seven migration rows were not directly inspected,
so that operator verification remains required. Connected public smoke passed
Home over LiveView, search, valid `/cards/sv08-238`, and
`/trade?left=sv08-238:1`; detail and trade agreed at EUR 263.65, history
rendered, the effective source tooltip identified Cardmarket via TCGdex, and
there were no console warnings/errors or horizontal overflow at 390px/1440px.
`/cards/tk-sm-r-14` is not a valid/present production printing and is not an
application regression. Six active sealed retailers are configured:
LootQuest, CardzHouse, BoosterPoint, PokeBooster, Boosterland, and Colligere.
Boosterland (category 40, Monday 05:00 UTC) and Colligere (category 23, Monday
06:00 UTC) are `lgs` Woo Store API sources, bounded to 50 requests/hour,
100/day, and 500/month. Each bootstrapped successfully with one admitted
request, persisting 8 and 37 active listings respectively, with no related
import issues. No production Singles-offer provider exists.

## Health checks

Enable health checks for the application resource in Coolify. Once enabled,
the Dockerfile `HEALTHCHECK` takes precedence and selects `/health`; Coolify
must wait for a healthy status before promoting the image or routing traffic
to it. `/health/live` remains a separate process-liveness endpoint for
external diagnosis and monitoring, not the container promotion gate.

The endpoints are:

- `/health` — readiness; fail-closed when PostgreSQL, Oban, or acquisition
  budget prerequisites are unavailable.
- `/health/live` — liveness; confirms the web process answers.

Both endpoints are served on internal port `4004` and do not call an external
provider.

The current production checks also verified public Pitch Black search routes for
its Booster Box/Pack/ETB and Pitch Black Booster Box/ETB, plus Destined Rivals
Booster Box routes: all returned 200 with loaded canonical images and current
offers.

Both responses include a secret-safe `revision`. Coolify supplies the deployed
runtime's `SOURCE_COMMIT`; the application trims and validates it as a Git
object ID and normalizes a missing or invalid value to `unknown`. This makes it
possible to compare the running revision with Git without baking a commit ID
into the image.

## Operator observability

The authenticated operator surfaces are:

- `/admin/dashboard` — Phoenix LiveDashboard with Ecto Stats, OS/VM metrics,
  Request Logger, and live application logs.
- `/admin/oban` — Oban jobs, queues, crons, metrics, and operational controls.

Both routes use the existing admin authentication. There are no public runtime
or log pages. The LiveDashboard Logger is live-only and best-effort: it has no
prior history or persistence, and its backend is active only while the page is
being viewed. Use persisted Oban jobs and acquisition records for durable
operational evidence.

The `ecto_psql_extras` integration and the `pg_stat_statements` migration enable
database diagnostics in Ecto Stats, including the Calls and Outliers views.

## Current Sealed catalogue state — 2026-09-03

All 19 approved Sealed products have complete sourced details and positive
applicable pack counts. Thirteen have complete official USD price tuples and
17 have complete canonical image tuples. Pitch Black Binacle 3-pack and SV151
Booster Bundle intentionally remain image-null unless qualified retailer
evidence exists; missing authoritative PLN MSRP/facts remain unset.

The root cause of the image gap was legacy unsourced images preserved by initial
enrichment and subsequently removed by image hardening. Forward-only migration
`20260903102840` corrected that state, and forward-only migration
`20260903111025` corrected the Pitch Black ETB type. Preserve the forward-only
policy: fix future schema/data issues with new migrations, never roll back the
database.

### Post-deploy verification

After a successful release, verify:

- `/health` and `/health/live` respond and report the expected non-secret
  `revision` (or `unknown` when `SOURCE_COMMIT` is unavailable); compare it
  with the deployed revision in Git.
- An authenticated visit to `/admin/dashboard` renders, including Ecto Stats,
  and its Request Logger and live logs are available.
- An authenticated visit to `/admin/oban` renders the configured Oban queues
  and the configured cron entries, with metrics and controls available.
- Ecto Stats renders the Calls and Outliers diagnostics.
- Live application logs appear while the dashboard is open; do not treat their
  absence before viewing as evidence of a failure.

## Cardmarket bulk Singles operations — fixed source

The public/new-write Singles source is fixed to `cardmarket_bulk_v1`; there is
no policy switch, cutover, valuation queue, per-card valuation worker, or daily
Singles pricing sweep. Cardmarket bulk sync runs daily at 03:00 UTC from the
fixed product and price-guide sources. TCGdex is limited to catalogue/detail/image
enrichment and Cardmarket identity mapping; it is never a Singles price fallback.
Historical `tcgdex_cardmarket_v1` snapshots remain retained/readable but cannot
be selected or newly written.

### Sync checks and incident runbook

After each scheduled sync, inspect the read-only Operations diagnostics for the
source, batch lifecycle, catalogue/mapping/detail enrichment, and materialization.
Confirm the batch is successful, current, coherent, and exact. Anomaly and
plausibility thresholds, malformed input, same-successful-batch requirements,
and exact mapping checks remain fail-closed. Review mapping and batch
invalidations; mounted Home, CardDetail, and Trade must reload their local data.

Public pages read local exact current bulk snapshots. They show stale or
unpriced values honestly, and missing/stale values do not trigger Singles
pricing HTTP. NBP acquisition remains independent. During an incident, leave
the last successful local snapshot readable, stop/retry the bulk sync only
through its bounded operational controls, and do not bypass validation or
substitute TCGdex pricing. Investigate failed/anomalous batches and recover
forward from the next valid batch.

The generated migration
`20260908110348_remove_legacy_singles_pricing.exs` removes `pricing_checked_at`.
Apply it through the normal release gate; migrations are forward-only and must
not be rolled back. This documentation checkpoint records release
`68b73cc624e0ac6f450bf1c0af05bdc35eaaf565`, deployed 2026-09-08, CI
`34212821835` with 1,117 tests, and production Home/card/trade smoke at EUR
263.65. Final commit/deploy remains pending at documentation time.

### Post-deploy bulk verification

Verify `/health` and `/health/live`, the expected revision, the 03:00 UTC Cron,
the latest batch diagnostics, and authenticated Operations. Confirm Home,
CardDetail, and Trade render the same local current value, preserve honest
stale/unpriced states, and reload after mapping or batch invalidation. Do not
look for readiness/cutover controls or a TCGdex comparison; Operations is
read-only diagnostics.

## Historical/superseded Cardmarket bulk shadow rollout and cutover

The Cardmarket bulk implementation is deployed in
`b7afc9049a8af42dd569f44d2c140cb58f64221c`; this is deployment and public-smoke
evidence, not evidence of a first real sync, persisted readiness, or cutover.
The configured migration release gate succeeded, but the migration table and
exact seven migration rows still require direct operator verification. The seven
forward-only migrations are `20260903120603_cardmarket_bulk_v1.exs`,
`20260903134323_cardmarket_bulk_crosswalk.exs`,
`20260907102216_harden_cardmarket_bulk_pipeline.exs`,
`20260907102604_harden_cardmarket_bulk_pipeline_constraints.exs`,
`20260907110602_cardmarket_expansion_review.exs`,
`20260907111314_cardmarket_expansion_review_hardening.exs`, and
`20260907134317_cardmarket_evidence_identity.exs`. The `20260907102216`,
`20260907111314`, and `20260907134317` migrations intentionally raise on down;
operational rollback is forbidden for all seven: repair forward or restore
tested backup/PITR.

The implementation adds a daily 03:00 UTC `cardmarket_bulk` Oban queue/sync
using fixed HTTPS sources:

- <https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_6.json>
- <https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_6.json>

It uses fixed product/price URLs, category 51 Pokémon Single, a 32 MiB response
cap and 100,000-row cap,
no redirects/retries, 5s connect and 15s receive/request timeouts, and a
15-minute monotonic worker/end-to-end deadline with a 30-second cleanup margin.
It retains compressed immutable raw evidence, hashes/byte sizes/source
timestamps, coherent batches, strict filtering, staged products/prices,
crosswalk/mapping evidence, review routing, administrator authority,
material-variant safeguards, and immutable snapshots. Lifecycle is
`staged`/`succeeded`/`failed`; first-batch floors are 10,000 products, 10,000
Singles prices, and 5,000 priceable Singles. Exact materialization requires
same-successful-batch product, price, expansion mapping, and card mapping
evidence; only anchor/auto_matched card evidence qualifies. Missing,
ambiguous, unapproved, or cross-batch data fails closed. TCGdex remains
canonical printing metadata and detailed enrichment remains independent.

The parser requires nonblank product `dateAdded`. Mapping supports safe
same-batch A→B→A correction from immutable exact evidence, never overwrites
administrator mappings, and materialization is concurrent same-batch idempotent.

### Historical initial deployment and shadow procedure (retained for record)

1. Historical procedure: the former selectable policy was deployed before the
   fixed-source release. This step is superseded; do not configure a policy
   switch or activate a second Singles pricing source.
2. Pass the migration gate, confirm all seven migrations are applied, then
   verify effective policy is TCGdex, the queue/provider/Cron, and
   `/admin/operations`.
3. Run/observe the first real sync: verify connectivity, source health, batch
   lifecycle, and counts. Confirm public bulk policy does not mix sources,
   falls back to TCGdex when unready/error, disables the daily TCGdex sweep,
   and cancels already-queued TCGdex valuation HTTP work.
4. Before cutover, reconcile the canonical TCGdex catalogue: verify a
   completed coherent nonfuture `all_sets` run, no active catalogue run, zero
   unresolved partial/malformed/failed catalogue-set issues, and bounded
   catalogue counts in `/admin/operations`.
5. Review expansion decisions using the latest-successful-batch exact pair;
   this historical cutover step is superseded by the fixed-source runbook above.

Readiness additionally requires a completed coherent nonfuture `all_sets`
TCGdex catalogue run, no active catalogue run, and zero unresolved
partial/malformed/failed catalogue-set issues; operations exposes bounded
catalogue counts. It also requires latest and previous coherent successful
bulk batches; healthy/current source; persisted UTC nonfuture fresh
fetched/completed/product-created/price-created evidence within 129,600 seconds/
36h; no more than 10% relative anomaly for product, price, Singles-price, and
priceable-Singles counts; complete latest materialization; approved exact
batch-scoped mappings; exact staged-value/metric agreement; zero
ambiguous/unapproved current valuations; coverage gain of at least 100 and ratio
at least 1.10; and at least 100 overlaps with at least 95% overlap value
agreement within 5%. Coverage gain/overlap/agreement use only latest-batch
approved exact staged-value/metric-matching valuations. Malformed configuration/evidence
and unready/error states fall back to TCGdex. Review shows 25 rows plus `25+`,
uses authorized reads, scans at most 1,000 rows fail-closed, and renders only
bounded safe evidence. Successful persisted sync/replay publishes mapping
invalidations only after commit; retryable notification failure re-notifies
idempotently. No rollback or normal attempt-1 no-op broadcasts.

When active, Home/search/recent/movers, CardDetail current/history, and Trade
totals consistently use bulk without per-card fallback or source mixing; routine
TCGdex per-card valuation acquisition/sweep is a no-op. Both valuation histories
remain preserved and CardDetail metadata enrichment remains independent.

There is no database rollback procedure. The former deactivation-by-variable
procedure is superseded; do not delete history or reverse migrations. The fixed
source runbook above is authoritative.

Historical implementation detail (superseded): the supervised policy cache was
max 30 seconds, refreshed automatically,
broadcasts effective expiry changes, and reconciles timed-out callers fail
closed. Mounted Home, CardDetail, and Trade refresh policy-dependent data; bulk
does not mix with or request TCGdex. Canonical CI passed all static gates/Dialyzer
and 1,162 tests. Public smoke verified Home, search, `/cards/sv08-238`, and
`/trade?left=sv08-238:1`; detail and trade agreed at EUR 263.65, history
rendered, and the effective source was Cardmarket via TCGdex. No console
warnings/errors or horizontal overflow were observed at 390px/1440px.
Authentication to `/admin/operations`, Oban, and the dashboard was unavailable,
so the explicit Coolify environment variable, exact migration rows, Cron entry,
first Cardmarket sync/import counts, and persisted readiness were not directly
verified. Effective public behavior remains TCGdex; bulk must remain disabled.
The first real sync and readiness/cutover are pending, and cutover still
requires every readiness gate plus two distinct successful batches.

## Production Singles catalogue and detail enrichment

TCGdex acquisition is catalogue/detail enrichment only. It discovers and stores
local exact printings, detailed metadata, and images, and supports Cardmarket
identity mapping. It does not acquire Singles prices, provide a price fallback,
or enqueue per-card valuation work. Public pricing reads Cardmarket bulk
snapshots only; missing or stale values remain visibly missing or stale.

Catalogue/detail failures, malformed evidence, ambiguous identity, and mapping
uncertainty fail closed. Successful mapping or batch changes publish invalidations
after commit so mounted public views reload. The admin Operations surface shows
read-only catalogue, mapping, detail, and materialization diagnostics. Sealed
acquisition and its six Monday schedules remain independent.

## Historical/superseded Production Singles collection operations

### Owner direction — 2026-08-20

All interested parties agreed that recurring source pulls are permitted for the
internal MVP. The existing internal/unlisted domain
<https://tcg-cheap.d.alergeek.me> is the demonstration surface. Sealed recurring
acquisition is deployed through Coolify. Preserve budgets,
rate limits, safety, attribution, and data-minimization requirements. If the
demonstration is stopped, Coolify/app takedown is the operational stop; broad
launch follows the stakeholder demo.

### Collection policy v2 — operational correction

The bounded discovery policy is v2. A public unauthenticated observation on
2026-08-19 returned 218 set entries in oldest-first-ish order, with `me05` last;
this is not treated as an API ordering contract. Initial discovery applies a
bounded candidate ID-prefix prefilter for configured `sv`/`me`, followed by
authoritative strict fetched `serie.id` revalidation; `tcgp` is excluded at
fetched evidence. `me05` initial/continuations have priority 0, an active
rolling set continuation has priority 1, and untouched rolling initial scans
have priority 2. This avoids fail-slow startup caused by the observed provider
order and avoids Pocket fanout; chunks, budgets, and public scope remain
unchanged. Legacy queued v1 jobs self-cancel without consuming a provider
budget. Cron and manual operations use the exact policy version.

The collection is fail-closed and scope-based: `pitch_black_full`,
`rolling_ir_sir`, `curated_playable`, and `legacy_local`, each with expiry and
provenance. Provider imports/briefs never auto-scope. Public Home search/recent,
CardDetail, Trade, and mover queries require active nonexpired scope; broad
unscoped discovery is private. Migration backfill assigns preexisting local
rows only to `legacy_local`, preserving useful local state while empty
production gains no broad rows.

Automatic bootstrap starts within 15 minutes and is unique after a successful
run for seven days. It discovers TCGdex sets, imports every `me05` card, and
imports only exact IR/SIR cards from the inclusive rolling prior two calendar
years. Chunks are at most 20; complete `cardCount` evidence is required;
incomplete/transient evidence retries; scanned non-target cards are never
imported. Daily at 14:00 UTC, refresh keyset-paginates every active, nonexpired,
scoped, matched card and enqueues valuations, including fresh cards; public
on-demand remains missing/stale-only. `ValuationWorker` is the sole
provider-budget admission immediately before HTTP.

Operations provides a manual scoped collection trigger. `curated_playable` has
dated official/Limitless/TCGdex evidence and explicit approval for local
implementation; its seven-entry implementation is deployed, but production completion and collection remain unverified/incomplete. Sealed recurring acquisition is
deployed through Coolify: the centrally configured weekly UTC schedule runs
Monday at 01:00 for LootQuest (`regular_retailer`), 02:00 for CardzHouse
(`lgs`), 03:00 for BoosterPoint (`lgs`), 04:00 for PokeBooster (`lgs`), 05:00 for
Boosterland (`lgs`), and 06:00 for Colligere (`lgs`). Deployment configures nine
providers in total, and each sealed source is limited to 50 requests/hour,
100/day, and 500/month. Boosterland and Colligere each bootstrapped with one
admitted request and persisted 8 and 37 active listings respectively, with no
related import issues. Provider controls can disable a source; taking the
Coolify application down is the operational stop when needed. No production
Singles-offer provider exists.

The 2026-09-03 sealed-catalogue checkpoint was revision `d55a26b1368084bbaf7a25b65a2211f437e6c540`, with green CI runs
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33747809832> and
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/33748881597>.
Production `/health` and `/health/live` returned 200 with database and Oban healthy,
7 Oban queues, and 9 configured providers. All seven exact curated card routes resolved publicly
after the 2026-08-20 deploy; at that initial checkpoint four had valuations and
three honestly showed no valuation. Do not infer later freshness from this checkpoint.
At 2026-08-19 18:16 UTC, exact public Pitch Black `me05-001` through at least
`me05-040` had imported/scoped and rendered real Cardmarket aggregate snapshots
(001 €0.02, 021 €0.02, 040 €0.03); Tropius autocomplete returned exact
`me05-001`, unscoped `base1-001` remained not found, and browser console
warnings/errors were zero. This closes initial production data validation, not
complete 120-card or rolling IR/SIR coverage; collection remained budgeted and
in progress.

### Curated playable manifest — approved deployed implementation; production completion unverified

The fixed seven-entry policy version is `2026-08-19-naic`. A separate
15-minute bootstrap is successful-run unique while retained by the configured
seven-day Oban Pruner and creates seven priority-1 child jobs. Completed bootstrap
and child jobs remain deduplicated while retained by that Pruner. Each child admits at most two TCGdex requests
per card per attempt and validates exact identity, legality,
and set;
expiry is fixed and non-sliding. Shared Ash transaction plus row-lock scope
merging applies rolling/Pitch Black/legacy/admin precedence, and matched cards
enqueue valuation. No request-path HTTP or sealed adapter is involved; existing
Pitch v2 remains independent. Rows become public only after successful deploy
and import, then expire automatically. This batch is deployed, but production
completion and collection remain unverified/incomplete. The evidence manifest is [here](../knowledge-base/raw/2026-08-19-curated-playable-manifest.md),
expires inclusive 2026-11-17. Representative evidence, backups, and monitoring
remain required.

## First administrator

The first production administrator has been provisioned. For future
environments, provision the first administrator once, after migrations succeed.
Inject
`ADMIN_EMAIL` and `ADMIN_PASSWORD` only into this one-shot command, then remove
them from the Coolify runtime variables:

```sh
podman run --rm --env-file production.env -e ADMIN_EMAIL -e ADMIN_PASSWORD \
  tcg-cheap:release /app/bin/tcg_cheap eval "TcgCheap.Release.provision_admin()"
```

The equivalent Coolify one-shot release command is the same release eval
invocation. Keep `ADMIN_AUTH_SIGNING_SECRET` independently configured. The
release does not print the password or validation detail.

## Build and run locally

Build the non-root release image with either engine:

```sh
podman build --format docker -f deployment/Containerfile.app -t tcg-cheap:release .
# or: docker build -f deployment/Containerfile.app -t tcg-cheap:release .
```

Production requires `DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_HOST`.
`PORT` defaults to `4004`; `POOL_SIZE`, `ECTO_IPV6`, and `DNS_CLUSTER_QUERY`
are optional. `ADMIN_AUTH_SIGNING_SECRET` is optional and falls back to
`SECRET_KEY_BASE`, but should be separate when possible. Never put values in
the image or shell history; inject them through the runtime secret mechanism.

Run migrations before starting a new image:

```sh
podman run --rm --env-file production.env tcg-cheap:release /app/bin/migrate
```

The same command works with `docker run`. Start and verify the service:

```sh
podman run -d --name tcg-cheap --env-file production.env -p 4004:4004 tcg-cheap:release
curl --fail http://127.0.0.1:4004/health/live
curl --fail http://127.0.0.1:4004/health
podman healthcheck run tcg-cheap
```

## Backups, restore, and rollout

Use Coolify/PostgreSQL encrypted, tested snapshot/PITR backups and regularly
verify a restore into an isolated database. For a restore, stop writers,
verify the target and PostgreSQL version, restore into the intended target,
and record the change; never overwrite production casually.

The initial production rollout is intentionally non-rolling: build the
immutable image, run `/app/bin/migrate`, verify readiness, then replace the
old process and route traffic. Roll back the image only when its schema is
compatible. Never blindly reverse data migrations; restore a tested backup or
ship a forward-compatible corrective migration.

Oban jobs are persisted in PostgreSQL. Observe queue depth, failures, retries,
and scheduled jobs; pause or drain queues during maintenance and resume after
the application is healthy. Provider controls and circuit breakers should be
used as kill switches for failing or rate-limited upstreams. They prevent fresh
acquisition work while cached, stale data remains available; they are not a
substitute for fixing credentials, limits, provider outages, or other source
failures.

The six configured recurring sealed adapters—LootQuest, CardzHouse,
BoosterPoint, PokeBooster, Boosterland, and Colligere—can each be disabled
through persisted provider controls. If a broader stop is necessary, taking the
app down in Coolify is the operational stop. While refresh is disabled, continue
serving cached or stale data and label its age until source and persistence paths
are safe; this does not claim that the catalogue is complete.
