# Application Foundation

- Updated: 2026-08-07
- Sources: Project code; local validation
- Raw: N/A — codebase update

## Current state

TCG Cheap is a Phoenix application using Phoenix LiveView, with the `TcgCheap.Core` Ash domain and `TcgCheap.Repo` AshPostgres repository providing the current domain/persistence foundation. The repository is developed in a Nix devenv with Elixir, PostgreSQL, Podman/Compose, Worktrunk, Tailwind, and esbuild tooling.

The Ash core/repo foundation is present. The historical provider-neutral singles core exists in `lib/tcg_cheap/pricing/singles/provider.ex`, `offer.ex`, and `valuation.ex`, with focused tests in `test/tcg_cheap/pricing/singles/provider_test.exs` and `valuation_test.exs`. `Provider`/`Offer`/`Valuation.default_v1` remain historical/post-MVP seller-level capability; `Offer` normalizes seller/language/condition/shipping/Decimal EUR fields and `Valuation` calculates five-lowest-distinct-seller values. The active aggregate adapter is implemented at `lib/tcg_cheap/pricing/singles/tcgdex_cardmarket.ex`: it uses Req against the fixed TCGdex card endpoint, Jason Decimal decoding, deterministic metric selection, half-up two-decimal rounding, `tcgdex_cardmarket_v1` provenance/timestamps/Cardmarket ID, safe bounded retries, and tagged errors. It is only a background-acquisition boundary; it is not integrated into an Ash resource, Oban, storage, or UI.

The active TCGdex aggregate intentionally has no seller/offer count field. The public UI must show source plus selected metric/methodology, not an unknown-count widget; no count may be fabricated, and a future shared storage field may be nullable/optional. Scraper paths remain post-MVP research, with broader seller-level acquisition and destination-eligibility validation still open.

The local catalogue/storage slice now includes `CardSet` and an expanded `CardPrinting` AshPostgres resource. `CardPrinting` keeps a unique TCGdex ID as the exact-printing identity and has a nullable `CardSet` relationship with an index, preserving compatibility for legacy/minimal records. Set metadata and printing metadata/legalities/assets/source payload plus source and sync timestamps are stored locally; `CardPrinting` also records `mapping_updated_at` and Cardmarket product-mapping state. Ash and PostgreSQL `CHECK` invariants protect mapping/count states. Raw source payload is retained for internal use only. The catalogue-import boundary is intentionally small: a fixed-endpoint TCGdex provider and one-card-plus-set importer fetch outside transactions, validate IDs, normalize numeric `localId` and asset values, and store set/card data atomically and idempotently. Postgres advisory locking plus `FOR UPDATE`, together with source/mapping timestamps, prevents stale responses from regressing newer state.

Mapping is conservative: only one explicit Cardmarket ID with no material ambiguity is matched; no mapping is unmatched. First-edition, `wPromo`, stamps, pre-release, jumbo, special foil, nonstandard-size or material subtypes, multiple material identities, and multiple Cardmarket IDs are review states with no guessed ID. Finish-only normal/reverse/holo differences may be simplified. The importer is not a full catalogue sync: it handles one explicitly requested card and set, while enumeration/scheduling, local search, background acquisition, and UI remain unfinished. `SingleValuationSnapshot` retains positive EUR aggregate valuations, policy/source/metric provenance, fetched and provider-update timestamps, optional Cardmarket product ID, and immutable current/archive state. `record_single_valuation` runs transactionally: it locks the parent `CardPrinting` with `FOR UPDATE`, archives only the prior current snapshot for the exact card and policy, and inserts the replacement. Policy-specific history is preserved, while the partial unique index permitting one current snapshot per card and policy remains defense-in-depth. `TcgCheap.Pricing.Singles.Freshness` classifies missing, fresh, and stale data at the exact seven-day boundary.

## Local development

- PostgreSQL runs through the worktree's Compose project on loopback port 5436 by default (`DB_PORT` can override it).
- Phoenix development server runs on port 4004.
- Worktrunk provides isolated parallel worktrees and port/environment separation.
- The direct localhost workflow is current; Caddy/domain integration is deferred.
- Development lifecycle is managed with `mix dev.up` and `mix dev.down`; non-main worktree identities include a short hash of the original branch to prevent sanitized-name collisions. `dev.up` verifies the expected Compose `postgres` service, restarts its exact Phoenix tmux session, and requires a 2xx HTTP response before reporting readiness.
- Theme initialization is bundled in the self-hosted JavaScript asset rather than emitted as a raw inline script. Browser CSP explicitly allows self-hosted scripts/connect/images and self plus inline styles required by LiveView runtime behavior.

The importer has fixture-backed deterministic coverage for provider errors, retries, idempotency, rollback, stale-response rejection, mapping review, assets, IDs, and database constraints. A bounded live adapter smoke succeeded for canonical card `swsh3-136` and set `swsh3` using default options; no data was persisted. Canonical `mix check --verbose` passed with 81 tests after resetting only the disposable test database to clear locally applied superseded uncommitted migration timestamps. `mix ash.codegen --check` and `git diff --check` also passed. Caddy integration and CI remain deferred.

Honest limitations: this batch imports one explicitly requested card and set only. Full catalogue enumeration/sync, an Oban scheduler, local PostgreSQL exact-printing search, a public UI, an admin review queue, immutable catalogue-observation history, and a production catalogue import have not been completed. The nullable `CardSet` relationship remains necessary for legacy/minimal `CardPrinting` records. Image/IP and redistribution licensing remain unresolved. Next priority is full set/card catalogue sync/enumeration and local exact-printing search, followed by Oban valuation acquisition, PubSub, and UI; broader sealed research remains open.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Provider and Acquisition Feasibility](provider-acquisition-feasibility.md)
