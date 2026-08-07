# Provider and Acquisition Feasibility

- Updated: 2026-08-07
- Sources: [Provider/source experiment capture](../../raw/2026-08-07-provider-source-experiments.md); [Scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md); [current MVP north star](../product/mvp-implementation-plan.md); project code and validation
- Raw: [2026-08-07 provider/source experiments](../../raw/2026-08-07-provider-source-experiments.md); [2026-08-07 scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md)

**Status:** TCGdex embedded Cardmarket aggregate pricing remains the selected `$0`, unauthenticated singles MVP source under `tcgdex_cardmarket_v1`. Broader sealed research and future seller-level providers remain open.

## Authority and access-policy boundary

The product owner superseded the exact seller-level singles direction on 2026-08-07. The MVP is aggregate-first and avoids scraping where practical. No authentication, payment, or CAPTCHA bypass is permitted; credentials remain server-side and out of git. The historical `default_v1` seller-level algorithm is preserved post-MVP. The active aggregate does not prove language, condition, seller identity/count, finish exactness, or shipping to Poland; the UI must not imply those facts.

TCGdex remains the initial catalogue direction, with Pokémon TCG API as fallback/cross-check subject to licensing and mapping validation. TCGdex imagery is approved for the MVP by product-owner decision: commit `52a9c0d` uses only canonical `https://assets.tcgdex.net` URLs through strict `CardImage` behavior (high WebP detail, low WebP search, no-referrer, exact CSP host, no proxy/cache, honest missing/invalid fallback). This accepts pragmatic product risk for an explicitly unofficial review/comparison/decision-support site; it is not a legal conclusion or proof that underlying artwork is independently licensed. Third-party artwork rights remain unproven, and broader reuse/self-hosting is not approved. The TCGdex live set-list smoke still times out; no live list success is claimed.

## Card metadata

Earlier bounded observations counted 23,444 TCGdex cards versus 20,479 Pokémon TCG API cards; these are time-specific counts, not guarantees. TCGdex exposes Cardmarket IDs, but mappings can evolve or be shared/wrong and images can be missing. Set plus collector number is the primary human identity, with a material-variant discriminator when needed.

## Credentialed spike

### TCG Scraper

https://tcg-scraper.com/ documents Free 100 requests/month and Starter €29/month for 25,000/month. `/api/v1/product` uses `X-API-Key`, Cardmarket URL, `language`, `minCondition`, and optional `sellerReputation`. Its public example exposes product metadata and summaries (`total_offers`, `lowest_price`, `sellers_count`, condition counts), not seller identity, destination, quantity, currency, or offer rows. A temporary evaluation account/key was created: one call exceeded a 30-second client timeout; a second fresh-key call to the documented Charizard example returned HTTP 502 after about 44.7 seconds with Cloudflare HTML rather than JSON. Keys were revoked and sessions signed out. No successful Apify/Parse call is claimed.

### cardmarketapi.com

A temporary 3-day trial was used for `GET /api/v1/card/869888`. It returned HTTP 200 after about 29.2 seconds, `X-Cache: MISS`, and rate-limit header 10. The JSON had top-level `id/game/name/expansion/image_url/currency/filter/prices/listings/fetched_at/source`. Exactly 50 listings were returned; each observed listing had only `cond/country/lang/price`, with no seller identity or quantity. There were 17 distinct seller countries, one language, and two conditions because `condition=nm` means NM-or-better. Currency was EUR, `avg5` and timestamp were present, and total availability was 241. The current https://cardmarketapi.com/panel/api/plans says Starter $49.99/30 days and 500/day, conflicting with some documentation advertising higher quotas; reconcile before use. The trial key was not retained and browser storage was cleared.

Direct Cardmarket browser GET for the documented TCG Scraper Charizard Obsidian Flames product URL returned HTTP 403 / “Just a moment”; this was not necessarily product ID 869888, and no bypass was attempted.

## Singles acquisition matrix

| Candidate | Decision and evidence |
| --- | --- |
| TCGdex embedded Cardmarket aggregate | **Selected MVP source.** Free and unauthenticated. Use policy `tcgdex_cardmarket_v1`; select the first finite positive EUR value in `avg7`, `avg30`, `trend`, `avg`, `low`. It does not prove language, condition, seller identity/count, finish-specific exactness, or shipping to Poland. |
| Apify Phantom Coder | **Post-MVP experiment candidate.** Documents seller identity, condition, language, quantity, EUR/currency rows, seller-country input, max 1–500 results, and $0.005/listing Free / $0.004 Starter; reports 97.1% successful runs. Destination eligibility is absent. Signup stalled at identity/hCaptcha; no account creation is claimed. |
| Parse.bot Cardmarket API | **Post-MVP experiment candidate.** Documents seller usernames, condition, attributes, price, quantity, comments, pagination to Cardmarket’s 300 cap, and seller-country filtering; Free 100 credits or Hobby $30/1,000 credits, listing calls 2 credits. Destination eligibility is absent. Signup stalled at hCaptcha; no credentialed call. |
| cardmarketapi.com | **Indicative/aggregate fallback only.** Successful HTTP 200, but empirical listings lack seller identity, quantity, and destination. Its `avg5` is five listings, not five distinct sellers. Current Starter $49.99 leaves no safety margin and the plan API says 500/day. |
| tcg-scraper.com | **No-go for now.** Credentialed sample got HTTP 502/Cloudflare HTML and the documented response does not prove offer rows or required fields. |
| Official Cardmarket API | Applications are currently closed; not selectable without written access. |
| Cardmarket public catalogue/price guide | Free daily catalogue/price-guide material is aggregate-only; useful for metadata/reference, not seller-level offers or destination eligibility. |
| TCGdex metadata/catalogue | **Selected alongside the embedded pricing source.** Free metadata and exact-printing mappings; retain provider IDs and review ambiguous/material variants. |
| CardTrader | Seller identity, condition, and language are documented, but authenticated Poland-account shipping behavior and the separate shipping-method request remain unresolved. |
| JustTCG | `$19/month + tax` Starter and `$49/month + tax` Professional; no seller identity or destination proof is established. |
| PokemonPriceTracker | `$99` Cardmarket/commercial plan, over the cap. |

Do not make Apify or Parse part of the MVP. They may be evaluated later for seller-level post-MVP capability after successful credentialed real Pokémon runs validate actual rows.

## Sealed catalogue/source direction

REBEL Hurt remains the best current primary catalogue/SCD discovery candidate based on the observed `SCD`/`Chaos Rising` page and B2B terms, but it is not proven exclusive or official TPCi MSRP authority. ISA remains a historical fallback requiring permission for aggregation and republication. Treat SCD as a non-binding suggested reference, not authoritative MSRP. Candidate regular retailers are REBEL retail, Empik-owned offers, Media Expert only with permitted feed/access, Smyk, TCG Love, Graal, LootQuest, and PokeCollect; candidate LGS/community sources include TCG Love, Graal, ShopGracz, Centrum MTG, Strefa MTG, Plan-Sza, and Guildmage. Require released/English/official filtering, preorder/import/marketplace filtering, and feed/terms approval before adapters.

## Implemented acquisition and catalogue boundary

The active adapter uses Req against fixed TCGdex card endpoints, with server-side configuration, selects the first finite positive EUR value in `avg7`, `avg30`, `trend`, `avg`, `low`, rounds half-up to two decimals, and records `tcgdex_cardmarket_v1` provenance/timestamps/Cardmarket ID with bounded retries and tagged errors. Oban 2.23 provides the valuations queue at concurrency 4 and a seven-day Pruner. `ValuationAcquisition` freshness-gates and deduplicates exact-printing jobs. The worker validates identity, policy, EUR value, and provenance, fetches outside transactions, records through the existing snapshot action with active uniqueness, classifies retryable/permanent failures, and emits card-specific success and terminal-failure PubSub events; a subscribe-before-request helper supports consumers. `CardSet` and `CardPrinting` persist exact-printing metadata, legalities, assets, source/sync timestamps, and conservative Cardmarket mapping state. Ambiguous first-edition, promo, stamp, pre-release, jumbo, special-foil, nonstandard/material, multiple-material, and multiple-ID cases go to review without guessed IDs; finish-only normal/reverse/holo differences may be simplified. No provider call is on the render path.

Strict set enumeration and brief sync fetch provider data outside transactions, validate `cardCount.total == length(cards)` and every brief, then seed pending minimal rows atomically while preserving enriched/mapped rows and existing images. Set sync uses per-set PostgreSQL advisory locks and cross-set identity checks. Catalogue Sync now acquires the same per-card transaction advisory lock as the full importer and sorts brief card IDs before locking, closing the intermittent brief/full unique-ID race and preventing lock-order cycles across overlapping sets. Provider fetches remain outside transactions. `sync_all_sets/1` continues after failures, returning ordered failures and excluding `serie.id == "tcgp"`.

`TcgCheap.Catalogue.Enrichment.enrich_set/2` implements detailed set-level per-card enrichment and Cardmarket mapping. It fetches a detailed set exactly once with a timeout, validates exact set identity before TCG Pocket exclusion, and rejects malformed/truncated lists, duplicate or invalid canonical card IDs, and fan-out above 1,000 before card calls or writes. Card details are fetched at most once each outside DB transactions using ordered bounded `Task.async_stream` (default/max concurrency 4/16; default/hard timeout 30s/120s). Unexpected, raised, thrown, exited, and timeout callbacks are tagged and isolated so later cards continue. After provider calls, one clock is invoked and successful payloads are sequentially imported under one shared normalized UTC microsecond timestamp; an invalid clock writes nothing. Reports numeric seen/enriched/stale-preserved/failed counts plus ordered stage-tagged per-card failures. Reruns are idempotent and stale provider card/mapping data is preserved. `import_fetched_card/4` accepts explicit expected IDs and returns import/stale outcome while `import_card/2` retains its public card return; provider callback returns are normalized and set/card identity is validated before writes. Import and brief sync acquire locks set-before-card; real concurrent Sync plus fetched Importer coverage passed 20/20 repetitions. Cross-set reassignment, including stale payloads, is rejected; existing `CardSet` metadata is preserved during enrichment, set sync owns later metadata refresh, and missing sets can be created.

## Exact-printing search boundary

`CardPrinting.search` is local PostgreSQL only and exposed as `TcgCheap.Core.search_card_printings`; it never calls a provider. Shared Unicode NFKC/whitespace/trim/lowercase normalization is applied on create/upsert and matches SQL backfill parity. Four concurrent GIN trigram indexes support escaped contains and `%` candidates. Deterministic ranking uses exact IDs/names/collectors/sets, prefixes, similarities, Standard legality tie-breaking, then stable identity. Default limit is 10, hard maximum 20, effective minimum 2; all mapping statuses and non-Standard cards remain searchable, exact printings remain distinct, and `CardSet` is loaded.

`/` is a complete public local-only `HomeLive` surface: `to_form`, 250ms debounce, shared normalization, effective minimum 2/max 100, stream-reset results, stable accessible IDs/`aria-live` for idle/short/invalid/empty/error/results, and distinct same-name results showing original name/set/collector/TCGdex ID plus optional rarity/legalities. No provider HTTP or invented price is used in render/event paths. Approved imagery is rendered only through `CardImage` using canonical TCGdex assets. The responsive scoped archive-wall world is documented in `PRODUCT.md`, `DESIGN.md`, and `.impeccable/design.json`; self-hosted Barlow Condensed/Azeret Mono fonts carry OFL notices, with 1/2/3-column labels, keyboard focus, reduced motion, and a light scoped world. Generic Layout stays neutral; broader UI is not complete and the archive framing is the highest-priority public-UI course correction.

The public UI boundary now extends through the local card-detail acquisition consumer at `/cards/:tcgdex_id`. Search links to exact printings; detail reads local identity/current valuation and a bounded fixed 30-day history, including disconnected/static reads, without a provider call on render or event paths. On stale/missing valuation it subscribes before requesting the freshness-gated Oban job, then reconciles card-specific PubSub completion or terminal failure. History failure does not erase the current value. Fresh, stale, fetching, unpriced, read-error, terminal-failure, and insufficient-history collecting states are explicit; daily gaps remain unconnected and the UI carries source/metric/policy/timestamp/methodology/disclaimer evidence. Approved TCGdex imagery renders through `CardImage`; trade remains deferred to Phase 3.

## Cost, licensing, and next actions

The selected aggregate source costs `$0` and needs no credentials. Paid seller-level candidates remain capability-gated under the shared `$50/month` cap; shipping-to-Poland eligibility remains outside the aggregate MVP. Product-owner approval permits TCGdex imagery for the MVP, but does not resolve third-party artwork rights or approve broader reuse/self-hosting.

## Cost and destination risk

Historical paid-provider estimates remain relevant only to post-MVP seller-level experiments: Apify’s documented $0.005/listing and Parse’s Hobby plan would consume the global cap quickly; cardmarketapi Starter at $49.99 leaves no safety margin. Cardmarket shipping depends on origin, destination, weight, and dimensions, and seller country is not enough because sellers can opt out of countries. Do not imply shipping-to-Poland eligibility in the active aggregate UI or data.

## Licensing and evidence caveats

The TCGdex MIT license covers the repository/artifact, not Pokémon image/IP rights or marketplace redistribution rights. ISA Article 8.4 restricts aggregation/processing for redistribution and requires permission. Terms and robots rules remain operational risks even under the scrappy acquisition policy. Public documentation and bounded samples do not prove production authorization, contract rights, provider accuracy, or CardTrader shipping behavior.

## Controls and next actions

Use canonical IDs/known URLs only, seven-day TTL, bounded concurrency, backoff, provider quota and global cost reservation, kill switches, and stale/`?` fallback. Aggregate all account/provider usage under the same $50/month cap. The selected singles baseline is `$0`, free, and unauthenticated. Paid/live seller-level singles remains capability-gated, while broader sealed-source research remains unfinished.

The historical seller-level core remains implemented at `lib/tcg_cheap/pricing/singles/provider.ex`, `lib/tcg_cheap/pricing/singles/offer.ex`, and `lib/tcg_cheap/pricing/singles/valuation.ex`; `Valuation.default_v1` computes from five lowest distinct sellers and remains post-MVP capability, not the active methodology. The active aggregate adapter uses Req, deterministic metric selection, half-up rounding, provenance/timestamps/Cardmarket ID, safe bounded retries, and tagged errors.

1. **Complete:** the unauthenticated TCGdex `tcgdex_cardmarket_v1` aggregate adapter and metric selector, plus strict set enumeration and transactional brief-card sync, are implemented and fixture-tested.
2. Resolve bounded live list access/reliability, then run the implemented full set/card sync through a production-safe job path; retain conservative mapping review behavior.
3. **Complete:** the public exact-printing search/result surface, concurrency hardening, detailed set-level enrichment/Cardmarket mapping, Oban valuation acquisition/PubSub path, and local-first card-detail valuation/history consumer are implemented while keeping provider fetches outside request paths.
4. Preserve `Provider`/`Offer`/`Valuation.default_v1` as historical/post-MVP seller-level capability; seller/offer count is unavailable from the active aggregate source and must not be fabricated.
5. Request REBEL B2B data import/access and written SCD/data-reuse scope.
6. Request approved feeds/permissions from the initial retailer/LGS panel, including Media Expert only with permitted feed/access; broader sealed research is not complete.
7. Retain the evidence caveat that third-party artwork rights are not independently proven; broader image reuse/self-hosting, sealed research, and seller-level source research remain open.

All observations are time-specific. No credentials are committed.

Validation: CardImage plus web-focused tests 23; canonical `mix check --verbose` passed with 177 tests; assets and static checks passed; product owner confirmed valid live image rendering; browser checks passed at 1440x1000 and 390x844 with value in the first mobile viewport, no horizontal overflow, and no console errors. The mechanical detector had one known false-positive warning on the existing square 3px search-input bottom border and advisories; new off-palette hover/type drift was corrected, code-review blockers/warnings were fixed, and `git diff --check` is clean. The unresolved live TCGdex set-list timeout remains.

No alias model, trade, sealed, admin, production operational tracking/budgets, full scheduling, or broader product UI is complete. Ranking still needs real full-catalogue tuning; third-party artwork rights remain unproven, while UTC/Warsaw presentation and the TCGdex live timeout remain open. The highest-priority active public-UI goal is the homepage course correction toward decision support; the next coherent enabling work may be Phase 3 URL-backed trade composition/search/add-side/quantity foundations. Earlier operations/admin/budget and sealed-source roadmap work remains unfinished; this does not declare prior phases globally complete.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Application Foundation](application-foundation.md)
