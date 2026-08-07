# Application Foundation

- Updated: 2026-08-07
- Sources: Project code; local validation
- Raw: N/A — codebase update

## Current state

TCG Cheap is a Phoenix application using Phoenix LiveView, with the `TcgCheap.Core` Ash domain and `TcgCheap.Repo` AshPostgres repository providing the current domain/persistence foundation. The repository is developed in a Nix devenv with Elixir, PostgreSQL, Podman/Compose, Worktrunk, Tailwind, and esbuild tooling.

The Ash core/repo foundation is present. The historical provider-neutral singles core exists in `lib/tcg_cheap/pricing/singles/provider.ex`, `offer.ex`, and `valuation.ex`, with focused tests in `test/tcg_cheap/pricing/singles/provider_test.exs` and `valuation_test.exs`. `Provider`/`Offer`/`Valuation.default_v1` remain historical/post-MVP seller-level capability; `Offer` normalizes seller/language/condition/shipping/Decimal EUR fields and `Valuation` calculates five-lowest-distinct-seller values. The active aggregate adapter is implemented at `lib/tcg_cheap/pricing/singles/tcgdex_cardmarket.ex`: it uses Req against the fixed TCGdex card endpoint, Jason Decimal decoding, deterministic metric selection, half-up two-decimal rounding, `tcgdex_cardmarket_v1` provenance/timestamps/Cardmarket ID, safe bounded retries, and tagged errors. It is only a background-acquisition boundary; it is not integrated into an Ash resource, Oban, storage, or UI.

The active TCGdex aggregate intentionally has no seller/offer count field. The public UI must show source plus selected metric/methodology, not an unknown-count widget; no count may be fabricated, and a future shared storage field may be nullable/optional. Scraper paths remain post-MVP research, with broader seller-level acquisition and destination-eligibility validation still open.

## Local development

- PostgreSQL runs through the worktree's Compose project on loopback port 5436 by default (`DB_PORT` can override it).
- Phoenix development server runs on port 4004.
- Worktrunk provides isolated parallel worktrees and port/environment separation.
- The direct localhost workflow is current; Caddy/domain integration is deferred.
- Development lifecycle is managed with `mix dev.up` and `mix dev.down`; non-main worktree identities include a short hash of the original branch to prevent sanitized-name collisions. `dev.up` verifies the expected Compose `postgres` service, restarts its exact Phoenix tmux session, and requires a 2xx HTTP response before reporting readiness.
- Theme initialization is bundled in the self-hosted JavaScript asset rather than emitted as a raw inline script. Browser CSP explicitly allows self-hosted scripts/connect/images and self plus inline styles required by LiveView runtime behavior.

The TCGdex adapter has fixture-backed deterministic coverage: 24 adapter tests and 32 total tests under the singles pricing directory passed, using local Req stubs with no live external dependency by default. Canonical `mix check --verbose` passed with 47 tests, including format, Ash codegen, Sobelow, compile, unused dependencies, xref, Credo, Dialyzer, and tests. Final read-only code review found no remaining blocking- or warning-level code issues after request-option whitelisting, huge-Decimal safe fallback, and status-before-decode fixes. Bounded live runtime smoke validation normalized successful `:avg7` results for canonical TCGdex IDs `base1-4`, `base1-58`, and `sv03-125`; volatile prices were not preserved. Deterministic wiki lint reported 4 articles, 12/12 metadata fields, 4/4 index coverage, 16 relative links, and zero issues. Caddy integration and CI remain deferred.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Provider and Acquisition Feasibility](provider-acquisition-feasibility.md)
