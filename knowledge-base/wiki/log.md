# Wiki Log

## [2026-08-07] bootstrap verification | Complete final local validation
- Validation: Full `mix check` passed with 10 tests; homepage returned HTTP 200; LiveView mounted without current console errors; Tidewave MCP ping returned HTTP 200; PostgreSQL loopback connectivity was healthy.
- Deferred/hand-off state: Caddy integration and CI remain explicitly deferred. The app was intentionally left running after verification.

## [2026-08-07] bootstrap hardening | Fix lifecycle, CSP, and quality-gate blockers
- Task completed: Bound Compose PostgreSQL to loopback, made Compose failures actionable, isolated non-main identities with deterministic branch hashes, hardened `dev.up` service/readiness checks and tmux/fallback lifecycle behavior, moved theme initialization into the self-hosted asset, tightened CSP, and made checks non-mutating with Ash codegen validation.
- Files changed: `local/compose.yml`, lifecycle Mix tasks/tests, `assets/js/app.js`, root layout/router CSP, `.gitignore`, `.env.example`, `README.md`, `AGENTS.md`, and this foundation/log documentation.
- Validation: Pending the requested local format, compile, asset, codegen, security, lint, lifecycle, full test, Nix, Compose, Worktrunk, and diff checks.
- Remaining/blocking notes: The product MVP north star remains unchanged; product resources, authentication, jobs, and storage are still future work.

## [2026-08-07] product direction | Designate the MVP implementation plan as the current north star
- Task completed: Marked the product-owner MVP implementation plan as the authoritative current product north star; its requirements, phases, documentation, and acceptance criteria must be completed in full unless explicitly superseded by the product owner.
- Files changed: `knowledge-base/wiki/product/mvp-implementation-plan.md`, `knowledge-base/wiki/index.md`, `knowledge-base/wiki/architecture/application-foundation.md`, `.opencode/skills/llm-wiki/SKILL.md`, `AGENTS.md`, `lib/tcg_cheap_web/endpoint.ex`.
- Validation: Wiki metadata/link checks, formatting, compile with warnings as errors, and `mix check --no-test` completed locally; no CI was added.
- Remaining/blocking notes: Product resources, authentication, background jobs, and application storage remain to be implemented according to the north star.

## [2026-08-07] codebase update | Move MVP specification and bootstrap wiki
- Task attempted: Moved the complete product-owner specification into the product wiki and initialized the TCG Cheap knowledge base.
- Files changed: `knowledge-base/wiki/product/mvp-implementation-plan.md`, `knowledge-base/wiki/architecture/application-foundation.md`, `knowledge-base/wiki/index.md`, `knowledge-base/wiki/log.md`, `knowledge-base/raw/.gitkeep`, `.opencode/skills/llm-wiki/SKILL.md`.
- Validation: Compile, assets setup, and `mix dev.up`/`mix dev.down` are known validation targets; Caddy remains deferred. Wiki content, metadata, index entries, and links were checked locally.
- Remaining/blocking notes: Agent quality tooling is still being established; no product resources, authentication, jobs, or storage exist yet.
