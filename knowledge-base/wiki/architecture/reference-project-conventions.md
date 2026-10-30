# Engineering Conventions

- Updated: 2026-10-30
- Sources: Read-only audits of the Alergeek reference projects Firmowid (Phoenix LiveView + Ash) and Onside (Ash/Oban backend); current TCG Cheap code and `AGENTS.md`
- Raw: N/A — codebase update

Conventions TCG Cheap follows, including what was deliberately adopted from or
rejected relative to the two reference projects. Neither reference defines
product requirements.

## Adopted

- Feature/domain-first namespaces with explicit Ash domains, resources,
  specific actions, policies and code interfaces; Ash-generated migrations and
  snapshots (`mix ash.codegen`).
- Req for every external HTTP call, behind a narrow client module with a test
  seam (`Req.Test` plugs).
- Standard Phoenix LiveView layouts, components, `to_form` forms, unique DOM
  ids and a standard `test/` tree; Tailwind and esbuild through Phoenix.
- Oban for all background work, with explicit queues, unique jobs and worker
  tests; jobs carry explicit ids in their args.
- AshAuthentication password/token sign-in only for provisioned administrators.
- AshBackpex/Backpex only for read-only admin inspection of singles resources;
  focused LiveViews for workflows generic CRUD cannot express
  (`/admin/buying-guide`, `/admin/operations`, mapping correction).
- Nix/devenv + direnv with per-worktree `mix dev.up`/`mix dev.down` and
  direct localhost ports; `mix check` as the single quality gate.
- Container pattern: pinned, non-root release image, release overlay
  `bin/migrate`, fail-closed `/health` readiness separate from `/health/live`.
- `Decimal` for money and exchange rates (never floats).

## Rejected

- Firmowid's `simple_form` `:let` forms, process-dictionary tenancy and
  colocated tests in `lib/`.
- Onside's React/Volt SPA frontend, AshAdmin and RPC layers; the UI is
  LiveView only.
- AshOban, multitenancy and storage libraries until a concrete requirement
  exists.
- Self-hosted runners or CI-driven deployments that would give CI production
  secrets; CI only checks and builds.

## See Also

- [Application Foundation](application-foundation.md)
