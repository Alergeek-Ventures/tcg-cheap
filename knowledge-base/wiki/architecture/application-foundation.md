# Application Foundation

- Updated: 2026-08-07
- Sources: Project code; local validation; `PRODUCT.md`; `DESIGN.md`; `.impeccable/design.json`
- Raw: N/A — codebase update

## Current state

TCG Cheap is a Phoenix LiveView application using the `TcgCheap.Core` Ash domain and `TcgCheap.Repo` AshPostgres repository. The local catalogue includes `CardSet` and exact-identity `CardPrinting` storage, with metadata, legalities, assets, source payload, sync timestamps, and conservative Cardmarket mapping state. `CardSet` is nullable for legacy/minimal records. The active TCGdex aggregate is a background-acquisition boundary; it is not called by public rendering or events, and no seller/offer count is fabricated.

The repository is developed in a Nix devenv with Elixir, PostgreSQL, Podman/Compose, Worktrunk, Tailwind, and esbuild tooling. The historical provider-neutral singles core exists in `lib/tcg_cheap/pricing/singles/provider.ex`, `offer.ex`, and `valuation.ex`, with focused tests in `test/tcg_cheap/pricing/singles/provider_test.exs` and `valuation_test.exs`. `Provider`/`Offer`/`Valuation.default_v1` remain historical/post-MVP seller-level capability; `Offer` normalizes seller/language/condition/shipping/Decimal EUR fields and `Valuation` calculates five-lowest-distinct-seller values. The active aggregate adapter uses Req against the fixed TCGdex card endpoint, Jason Decimal decoding, deterministic metric selection, half-up two-decimal rounding, `tcgdex_cardmarket_v1` provenance/timestamps/Cardmarket ID, safe bounded retries, and tagged errors. It is not integrated into an Ash resource, Oban, storage, or UI.

The active TCGdex aggregate intentionally has no seller/offer count field. The public UI must show source plus selected metric/methodology, not an unknown-count widget; no count may be fabricated, and a future shared storage field may be nullable/optional. Scraper paths remain post-MVP research, with broader seller-level acquisition and destination-eligibility validation still open.

Strict TCGdex set enumeration and brief-card sync fetch provider payloads outside writes, validate counts and briefs before one transaction, preserve enriched rows/images, and seed pending minimal cards. Catalogue Sync uses per-set locking and now acquires the same per-card transaction advisory lock as the full importer, sorting brief card IDs before locking. This closes the intermittent brief/full unique-ID race and prevents lock-order cycles across overlapping sets. Provider fetches remain outside transactions. Cross-set conflicts are rejected atomically; TCG Pocket sets are excluded as designed. The one-card importer also uses `FOR UPDATE` and source/mapping timestamps to reject stale responses.

Mapping is conservative: only one explicit Cardmarket ID with no material ambiguity is matched; first-edition, `wPromo`, stamps, pre-release, jumbo, special foil, nonstandard-size or material subtypes, multiple material identities, and multiple Cardmarket IDs are review states with no guessed ID. Finish-only normal/reverse/holo differences may be simplified. The one-card detailed importer handles one explicitly requested card and set; set enumeration and brief-card seeding plus local exact-printing search are implemented, while detailed per-card enrichment, scheduling, and background acquisition remain unfinished. `SingleValuationSnapshot` retains positive EUR aggregate valuations, policy/source/metric provenance, fetched and provider-update timestamps, optional Cardmarket product ID, and immutable current/archive state. `record_single_valuation` locks the parent `CardPrinting` with `FOR UPDATE`, archives only the prior current snapshot for the exact card and policy, and inserts the replacement. Policy-specific history is preserved, and seven-day freshness classification remains defined.

Local exact-printing search is exposed as `TcgCheap.Core.search_card_printings`. Private persisted fields derive from name, set, collector number, and TCGdex ID through shared Unicode NFKC, whitespace collapse, trim, and lowercase normalization; SQL backfill parity uses PostgreSQL 18 `pg_unicode_fast`. Four concurrent GIN trigram indexes support escaped contains and `%` candidates. Ranking is deterministic and bounded (exact IDs/names/collectors/sets, prefixes, similarities, Standard legality tie-break, stable identity); default 10, hard max 20, effective minimum 2. All mapping statuses and non-Standard cards remain searchable; exact printings are never collapsed and `CardSet` is loaded.

`/` is now a public local-only exact-printing search surface in `HomeLive`. It uses `to_form`, a 250ms `phx-change` debounce, the backend-shared normalization, effective minimum 2/max 100 handling, and LiveView stream resets. Idle, short, invalid, empty, error, and results states have stable accessible IDs and `aria-live`. Same-name printings remain separate and show original name/set/collector/TCGdex ID plus optional rarity/legalities. No provider HTTP runs from render/event paths, no price or image is invented, and external card imagery remains unused while licensing is unresolved.

The public visual world is a responsive scoped archive-wall design documented in root `PRODUCT.md`, `DESIGN.md`, and `.impeccable/design.json`. Self-hosted Barlow Condensed/Azeret Mono fonts carry OFL notices; the surface supports 1/2/3-column labels, keyboard focus, reduced motion, and a light scoped world. Generic shared Layout remains neutral; broader product UI completion is not claimed.

## Validation and limitations

HomeLive passed 6 tests, all web tests passed 10, and catalogue tests passed 56. The concurrency regression passed 20/20 focused repetitions. Canonical `mix check --verbose` passed 118 tests. Assets build, codegen/static checks, migrations, JSON/design docs, and `git diff --check` passed. Manual browser validation passed desktop 1440px/mobile 390px, idle/short/results/empty, keyboard focus, no horizontal overflow or console errors, and 200% text reflow without overflow. Impeccable had one false positive for a 3px input bottom border whose computed radius is zero. The TCGdex live list timeout remains unresolved.

## Local development

- PostgreSQL runs through the worktree's Compose project on loopback port 5436 by default (`DB_PORT` can override it).
- Phoenix development server runs on port 4004.
- Worktrunk provides isolated parallel worktrees and port/environment separation.
- The direct localhost workflow is current; Caddy/domain integration is deferred.
- Development lifecycle is managed with `mix dev.up` and `mix dev.down`; non-main worktree identities include a short hash of the original branch to prevent sanitized-name collisions. `dev.up` verifies the expected Compose `postgres` service, restarts its exact Phoenix tmux session, and requires a 2xx HTTP response before reporting readiness.
- Theme initialization is bundled in the self-hosted JavaScript asset rather than emitted as a raw inline script. Browser CSP explicitly allows self-hosted scripts/connect/images and self plus inline styles required by LiveView runtime behavior.

The importer/sync boundary has fixture-backed deterministic coverage for provider errors, retries, idempotency, rollback, stale-response rejection, mapping review, assets, IDs, database constraints, set enumeration, brief validation, count mismatch, preservation, cross-set conflicts, TCG Pocket exclusion, and aggregate failure reporting. Focused search coverage passed 14 tests; SQL/Elixir Unicode parity and live PostgreSQL `EXPLAIN` index usage were verified. Caddy integration and CI remain deferred.

Detailed per-card enrichment/Cardmarket mapping, valuation refresh/Oban/PubSub, card detail, trade, sealed, admin, alias modeling, immutable catalogue-observation history, and production operations remain unfinished. Ranking needs real full-catalogue tuning. Image/IP and redistribution licensing remain unresolved. The next coherent Phase 2 task is detailed enrichment/Cardmarket mapping (or the valuation job path afterward), not another search-foundation task.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Provider and Acquisition Feasibility](provider-acquisition-feasibility.md)
