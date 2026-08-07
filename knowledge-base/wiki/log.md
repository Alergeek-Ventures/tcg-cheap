# Wiki Log

## [2026-08-07] scrappy singles acquisition spike | Supersede acquisition policy and record provider evidence
- Task completed: Recorded the product-owner supersession of the former strict compliance boundary, bounded credentialed TCG Scraper/cardmarketapi.com experiments, direct Cardmarket 403, Apify/Parse candidate evidence, and the exact provider-neutral valuation boundary. No provider secret was retained; the temporary external-account footprint is documented honestly.
- Files changed: `lib/tcg_cheap/pricing/singles/provider.ex`, `lib/tcg_cheap/pricing/singles/offer.ex`, `lib/tcg_cheap/pricing/singles/valuation.ex`, `test/tcg_cheap/pricing/singles/provider_test.exs`, `test/tcg_cheap/pricing/singles/valuation_test.exs`, `knowledge-base/raw/2026-08-07-scrappy-singles-acquisition-spike.md`, `knowledge-base/wiki/product/mvp-implementation-plan.md`, `knowledge-base/wiki/architecture/provider-acquisition-feasibility.md`, `knowledge-base/wiki/architecture/application-foundation.md`, `knowledge-base/wiki/index.md`, and this log.
- Validation: Focused tests passed with 8 tests; deterministic wiki lint checked 4 compiled articles, 12/12 metadata fields, 4/4 index coverage, and 16/16 relative links with zero missing/duplicate issues; `mix check --verbose` passed with 23 tests; `git diff --check` passed.
- Remaining/blocking notes: Obtain a persistent project-owned Apify or Parse credential, run three representative Pokémon products, verify duplicate-seller handling and destination eligibility, then implement only the passing adapter. Configure account pools and global cost reservation later without committing secrets.

## [2026-08-07] phase 0 provider/source research | Record acquisition feasibility batch
- Task completed: Captured bounded read-only real HTTP observations and reconciled them against primary provider, retailer, terms, robots, quota, and pricing sources. Recorded TCGdex/Pokémon TCG API metadata direction, REBEL Hurt sealed discovery direction, and the exact singles acquisition blocker without changing the north star or claiming Phase 0 completion.
- Files changed: `knowledge-base/raw/2026-08-07-provider-source-experiments.md`, `knowledge-base/wiki/architecture/provider-acquisition-feasibility.md`, `knowledge-base/wiki/architecture/reference-project-conventions.md`, `knowledge-base/wiki/index.md`, `knowledge-base/wiki/architecture/application-foundation.md`, and this log.
- Validation: Bounded HTTP experiments/primary-source reconciliation; deterministic wiki lint checked 4 compiled articles, 12/12 metadata fields, 4/4 index coverage, and 14/14 relative links with zero missing/duplicate issues; `mix check --verbose` passed with 15 tests; `git diff --check` passed. Older unresolved wording was reconciled as historical/stale.
- Remaining/blocking notes (historical, superseded by the newer scrappy policy and provider ADR): Obtain written Cardmarket/licensed-provider terms or validate CardTrader with legitimate credentials and bounded exact-offer/Poland-shipping tests; request REBEL and retailer/LGS feed permissions; complete image/data licensing review. No credentials are committed.

## [2026-08-07] phase 0 references | Audit Firmowid and Onside conventions
- Task completed: Audited the two read-only reference repositories against the Phase 0 categories, recorded authority, adopted/rejected conventions, version compatibility, and implications for later phases. Firmowid was clean; Onside already had an unrelated modified `shell.nix`; neither reference was changed.
- Files changed: `knowledge-base/wiki/architecture/reference-project-conventions.md`, `knowledge-base/wiki/index.md`, `knowledge-base/wiki/architecture/application-foundation.md`, and this log.
- Validation: Source/commit/path evidence reconciled; wiki metadata, index coverage, and internal links checked; `mix check --verbose` passed with 15 tests; `git diff --check` passed. Reference commits: `8a18f66aa28ac8444b5b3445fa3c7b6613fdf056` and `ac8d1d942a086bfe868043274fc0f430f30aacef`.
- Historical status at this entry: Provider/source experiments, cost ADR, acquisition feasibility, authentication/admin/background dependency validation, and subsequent MVP implementation phases remain unfinished. The newer provider ADR supersedes this entry's provider-research status; it does not claim the remaining tasks complete.

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
