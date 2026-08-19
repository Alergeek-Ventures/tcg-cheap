# TCG Cheap

TCG Cheap is a Phoenix LiveView/Ash application. Its product north star is the
[MVP implementation plan](knowledge-base/wiki/product/mvp-implementation-plan.md).

## Development setup

Development uses Nix with [devenv](https://devenv.sh/) and direnv. Install
those tools, then allow the project environment from the repository root:

```sh
direnv allow
```

If direnv is unavailable, enter the same environment explicitly with:

```sh
devenv shell
```

Copying [`.env.example`](.env.example) to `.env.local` is supported, although
`mix dev.up` creates the local defaults for you. Do not put secrets in the
repository; keep them in local environment files.

Start and stop the worktree services with:

```sh
mix dev.up
mix dev.down
```

`mix dev.up` starts PostgreSQL and the Phoenix server for this worktree.
`mix dev.down` stops them. `mix dev.reset` intentionally removes the current
worktree's database volume; the next `mix dev.up` recreates it. Use reset only
when you want to discard local data.

The default direct URLs are:

- Phoenix: <http://localhost:4004>
- PostgreSQL: `localhost:5436`

The ParadeDB image ships `pg_search` and `pgvector` and may bootstrap their
extension installation on a fresh database. Local Compose explicitly requests
`pg_search`, `pg_cron`, and `pg_stat_statements` in
`shared_preload_libraries`; `pg_search` must be preloaded before use. A
compatible volume previously initialized under stock PostgreSQL may expose the
extensions as available without having installed or preloaded them. The
current local container should not be restarted blindly: this takes effect on
the next intentional `mix dev.down` followed by `mix dev.up`. Verify with
`SHOW shared_preload_libraries` and confirm it includes `pg_search` before any
future migration enables pg_search.

Do not use `mix dev.reset` or delete an existing local or production volume
just to enable preload. Back up the data and recreate the container against
the same compatible volume instead. TCG Cheap-owned migrations, resources,
and queries do not currently depend on or use BM25 or vector functionality.

Read `.server.port` for the current Phoenix port. Worktrunk assigns hashed
ports to parallel worktrees, so use that port for direct `localhost` URLs (and
for Tidewave at `http://localhost:{PORT}/tidewave/mcp`). Caddy integration is
deferred.

## Ash changes

After changing Ash resources, generate migrations and snapshots with a
lower-snake-case name:

```sh
mix ash.codegen describe_the_change
```

During an extended development session, `mix ash.codegen --dev` can be used
incrementally; run the final named codegen command before handing off changes.

## Checks

`mix check` is the canonical local quality gate, including non-mutating formatting and Ash codegen checks. Use `mix check --no-test` while
iterating on static checks and `mix check --verbose` when command output is
needed.

## Deployment and operations

Local development, CI, and the Coolify database target use the pinned ParadeDB
image `docker.io/paradedb/paradedb:v0.25.2-pg18@sha256:f34b716407b4d509d3e59e649495964b296ad7c0931658dbf99d3cf1b35bc994`.
See the [deployment and operations guide](docs/deployment-and-operations.md)
for its PostgreSQL/extension compatibility and upgrade requirements.

Production image build, automatic release migrations, administrator provisioning,
backups, rollback, and incident guidance are documented in
[Deployment and operations](docs/deployment-and-operations.md).

Production is online at <https://tcg-cheap.d.alergeek.me>. Public read pages
remain public while administration is protected. The product owner confirms
that the pinned ParadeDB production setup, automatic release migrations, and
first administrator provisioning are complete. The deployment and operations
guide remains the source of truth for future deploys, migration gating, admin
provisioning, ParadeDB upgrades/preload, backups, rollback, and incidents.
