# Application Foundation

- Updated: 2026-08-07
- Sources: Project code; local validation
- Raw: N/A — codebase update

## Current state

TCG Cheap is a Phoenix application using Phoenix LiveView, with the `TcgCheap.Core` Ash domain and `TcgCheap.Repo` AshPostgres repository providing the current domain/persistence foundation. The repository is developed in a Nix devenv with Elixir, PostgreSQL, Podman/Compose, Worktrunk, Tailwind, and esbuild tooling.

The Ash core/repo foundation is present. Provider/source research has recorded a catalogue-source direction, but does not complete Phase 0: the exact singles valuation acquisition plan remains blocked pending legitimate seller-level, exact-printing, English/NM, Poland-shipping evidence. Product resources, authentication, background jobs, and product-data storage have not yet been implemented.

## Local development

- PostgreSQL runs through the worktree's Compose project on loopback port 5436 by default (`DB_PORT` can override it).
- Phoenix development server runs on port 4004.
- Worktrunk provides isolated parallel worktrees and port/environment separation.
- The direct localhost workflow is current; Caddy/domain integration is deferred.
- Development lifecycle is managed with `mix dev.up` and `mix dev.down`; non-main worktree identities include a short hash of the original branch to prevent sanitized-name collisions. `dev.up` verifies the expected Compose `postgres` service, restarts its exact Phoenix tmux session, and requires a 2xx HTTP response before reporting readiness.
- Theme initialization is bundled in the self-hosted JavaScript asset rather than emitted as a raw inline script. Browser CSP explicitly allows self-hosted scripts/connect/images and self plus inline styles required by LiveView runtime behavior.

Agent quality tooling is now established and validated, including the repository's canonical compile, formatting, linting, type/code generation, static analysis, and test checks. Final local bootstrap verification passed `mix check` with 10 tests, plus HTTP, LiveView, Tidewave MCP, and PostgreSQL loopback checks. Validation is local-only; Caddy integration and CI remain deferred.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Provider and Acquisition Feasibility](provider-acquisition-feasibility.md)
