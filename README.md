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

Production image build, release migrations, administrator provisioning,
backups, rollback, and incident guidance are documented in
[Deployment and operations](docs/deployment-and-operations.md).
