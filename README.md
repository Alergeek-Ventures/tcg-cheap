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
backups, forward-only schema recovery, and incident guidance are documented in
[Deployment and operations](docs/deployment-and-operations.md).

Production is online at <https://tcg-cheap.d.alergeek.me>. Public read pages
remain public while administration is protected. The product owner confirms
that the pinned ParadeDB production setup, automatic release migrations, and
first administrator provisioning are complete. The deployment and operations
guide remains the source of truth for future deploys, migration gating, admin
provisioning, ParadeDB upgrades/preload, backups, forward-only schema recovery,
image rollback compatibility, and incidents.

Database migrations are forward-only. Do not run or require `down`/`ecto.rollback`
checks as a quality gate; fix schema/data issues with a new forward migration and
recover disasters from tested backup/PITR. Image rollback is separate and only
allowed after proving schema compatibility; it never reverses the database.

All interested parties agreed that recurring source pulls are permitted for the
internal MVP. The exact curated policy and three-source recurring acquisition
are deployed through Coolify. Budgets, rate limits, safety, attribution, and data-minimization
requirements remain in force. Broad launch follows the stakeholder demo.
The weekly schedule is Monday 01:00 UTC LootQuest (`regular_retailer`), 02:00
CardzHouse (`lgs`), and 03:00 BoosterPoint (`lgs`); deployment expects six
configured providers.

The approved production Singles collection is fail-closed: Pitch Black full,
rolling two-calendar-year IR/SIR, and explicitly approved curated playables
only. Existing local rows are retained as `legacy_local`; provider imports do
not grant public collection scope, and empty production does not receive broad
catalogue rows. See the [MVP plan](knowledge-base/wiki/product/mvp-implementation-plan.md)
and [operations guide](docs/deployment-and-operations.md) for the rules. This
initial scoped production validation succeeded for `me05-001` through at least
`me05-040`; full 120-card Pitch Black coverage and rolling IR/SIR coverage
remain incomplete.

The curated-playable manifest evidence is dated 2026-08-19 and expires
inclusive 2026-11-17. It covers seven exact Trainer/Item/Supporter identities
from NAIC Limitless lists, cross-checked against official rotation and exact
TCGdex legality; it must be replaced/reapproved before expiry. The current
production checkpoint is commit `02b8d65`: CI run
<https://github.com/Alergeek-Ventures/tcg-cheap/actions/runs/32369920522> is
green, and production health on 2026-08-25 reported the database ready, 7 Oban
queues, and 6 configured providers. The fixed curated policy is deployed; after
the 2026-08-20 deploy, all seven exact card routes resolved publicly. At that
initial checkpoint four had valuations and three honestly showed no valuation;
no later freshness is claimed. By 18:16 UTC, exact public Pitch Black cards
`me05-001` through at least `me05-040` had imported/scoped and rendered real Cardmarket aggregates
(for example 001 €0.02, 021 €0.02, 040 €0.03); this is initial validation, not
complete 120-card or rolling IR/SIR coverage.

The curated implementation is deployed, but production completion remains
unverified/incomplete. Retained completed bootstrap and child jobs remain deduplicated while
the configured seven-day Oban Pruner retains them. Each child permits at most two
TCGdex requests per card per attempt.
The sealed registry and weekly Cron are deployed, but manual jobs 916/917/918,
refresh 920, and aggregate 921 have unverified completion; public search for
`151 Booster Bundle` returned no product, so approved sealed catalogue/mappings
remain incomplete.
