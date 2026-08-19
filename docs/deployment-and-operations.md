# Deployment and operations

## Coolify deployment target

This repository is prepared for deployment from a public repository through
Coolify; the actual Coolify deployment exercise is still pending. Public read
pages remain unchanged and public; administrative access is protected by the
application's admin authentication. Coolify will build
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
deployment owner must provide webhook orchestration that runs the migration
against the private database network using the target/new image before
traffic promotion, aborts on failure, and handles the first deployment too.
Repository CI does not implement this orchestration. The owner-provided
webhook must execute:

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
owner-provided Coolify webhook, not GitHub-hosted CI:

```text
/app/bin/migrate
```

The migration command is a deployment gate: a non-zero exit must fail the
Coolify webhook/deployment and prevent the new release from being routed.
Inspect migration logs and correct the database or schema issue before
retrying.

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

## First administrator

Provision the first administrator once, after migrations succeed. Inject
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

Sealed adapters are disabled by default and must not be treated as a claim
that production data exists. During an incident, keep serving the last known
cached or explicitly stale data, label its age, and disable refreshes until
source and persistence paths are safe.
