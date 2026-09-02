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

As of the 2026-09-02 local batch, the pending configuration has six sealed
sources and nine total providers. Boosterland (category 40, Monday 05:00 UTC)
and Colligere (category 23, Monday 06:00 UTC) are `lgs` Woo Store API sources,
bounded to 50 requests/hour, 100/day, and 500/month. Their bounded smoke found
8 and 35 eligible listings respectively, without persistence or production
ingestion. Local work is uncommitted and not deployed; production remains the
previous four sealed sources/seven providers and 127 cards, 643 valuations, and
19 approved sealed products.

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

### Post-deploy verification

After a successful release, verify:

- `/health` and `/health/live` respond and report the expected non-secret
  `revision` (or `unknown` when `SOURCE_COMMIT` is unavailable); compare it
  with the deployed revision in Git.
- An authenticated visit to `/admin/dashboard` renders, including Ecto Stats,
  and its Request Logger and live logs are available.
- An authenticated visit to `/admin/oban` renders all seven configured queues
  and the configured cron entries, with metrics and controls available.
- Ecto Stats renders the Calls and Outliers diagnostics.
- Live application logs appear while the dashboard is open; do not treat their
  absence before viewing as evidence of a failure.

## Production Singles collection operations

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
deployed through Coolify: the centrally configured weekly
UTC schedule runs Monday at 01:00 for LootQuest (`regular_retailer`), 02:00 for
CardzHouse (`lgs`), and 03:00 for BoosterPoint (`lgs`). Deployment configures six
providers in total, and each sealed source is limited to 50 requests/hour,
100/day, and 500/month. Provider controls can disable a source; taking the
Coolify application down is the operational stop when needed.

Current production checkpoint is commit `02b8d65`, with green CI run
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32369920522>.
Production `/health` on 2026-08-25 reported database ready, 7 Oban queues, and
6 configured providers. All seven exact curated card routes resolved publicly
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

The three configured recurring sealed adapters—LootQuest, CardzHouse, and
BoosterPoint—can each be disabled through persisted provider controls. If a
broader stop is necessary, taking the app down in Coolify is the operational
stop. While refresh is disabled, continue serving cached or stale data and
label its age until source and persistence paths are safe; this does not claim
that production data exists.
