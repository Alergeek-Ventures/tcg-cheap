# Provider and Acquisition Feasibility

- Updated: 2026-08-07
- Sources: [Provider/source experiment capture](../../raw/2026-08-07-provider-source-experiments.md); [Scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md); [current MVP north star](../product/mvp-implementation-plan.md)
- Raw: [2026-08-07 provider/source experiments](../../raw/2026-08-07-provider-source-experiments.md); [2026-08-07 scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md)

**Status:** Phase 0 selects TCGdex embedded Cardmarket aggregate pricing for the singles thesis-validation MVP under policy `tcgdex_cardmarket_v1`. Broader sealed-source research and any future seller-level singles provider remain open.

## Authority and access-policy boundary

The product owner superseded the exact seller-level singles direction on 2026-08-07. The MVP is aggregate-first and avoids scraping where practical. Free unauthenticated TCGdex embedded Cardmarket pricing is selected for thesis validation; the selected singles source costs $0 and needs no credentials. Public scraping and third-party services may remain post-MVP experiments, subject to terms and operational review. No authentication, payment, or CAPTCHA bypass is permitted; credentials remain server-side and out of git. The historical `default_v1` seller-level algorithm is preserved but is not the active MVP policy.

## Card metadata

Use TCGdex as the initial catalogue/import direction, with Pokémon TCG API as fallback/cross-check, subject to licensing and mapping validation. Earlier bounded observations counted 23,444 TCGdex cards versus 20,479 Pokémon TCG API cards; these are time-specific counts, not guarantees. TCGdex exposes Cardmarket IDs, but mappings can evolve or be shared/wrong and images can be missing. Set plus collector number is the primary human identity, with a material-variant discriminator when needed. Preserve provider IDs and raw provenance, and review ambiguous mappings. Image/IP licensing and marketplace redistribution rights remain unresolved.

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

## Implemented boundary and historical capability

The historical seller-level core remains implemented at `lib/tcg_cheap/pricing/singles/provider.ex`, `lib/tcg_cheap/pricing/singles/offer.ex`, and `lib/tcg_cheap/pricing/singles/valuation.ex`, with focused tests at `test/tcg_cheap/pricing/singles/provider_test.exs` and `valuation_test.exs`. `Provider`/`Offer`/`Valuation.default_v1` are preserved as historical/post-MVP seller-level capability: `Valuation` computes `default_v1` from five lowest distinct sellers, but this is not the active methodology. The active aggregate boundary is implemented at `lib/tcg_cheap/pricing/singles/tcgdex_cardmarket.ex`; it fetches the fixed TCGdex card endpoint using Req, uses Jason Decimal decoding, selects `avg7` -> `avg30` -> `trend` -> `avg` -> `low`, rounds half-up to two decimals, returns `tcgdex_cardmarket_v1` provenance/timestamps/Cardmarket ID, uses safe bounded retries, and returns tagged errors.

Catalogue storage now includes `CardSet` and expanded `CardPrinting` AshPostgres resources. `CardPrinting` has an indexed nullable `CardSet` relationship for legacy/minimal records, and storage covers metadata, legalities, assets, internal raw source payload, source/sync timestamps, `mapping_updated_at`, and Cardmarket product mapping state. Ash and PostgreSQL `CHECK` invariants protect mapping/count states. The fixed-endpoint TCGdex catalogue provider and one-card-plus-set importer fetch outside transactions, validate IDs, normalize numeric `localId`/assets, and atomically/idempotently store set and card data. PostgreSQL advisory locking and `FOR UPDATE`, plus source/mapping timestamps, reject stale response regression.

Mapping safeguards deliberately avoid guesses: one explicit Cardmarket ID with no material ambiguity is matched; no mapping is unmatched; first-edition, `wPromo`, stamps, pre-release, jumbo, special foil, nonstandard-size/material subtypes, multiple material identities, or multiple Cardmarket IDs are review states with no guessed ID. Finish-only normal/reverse/holo can be simplified. The `CardPrinting` and `SingleValuationSnapshot` resources persist exact-printing identity and successful aggregate provenance/history locally, with seven-day freshness classification. Automatic transaction-safe snapshot replacement/history is complete: `record_single_valuation` locks the parent printing, archives the exact card+policy current row, and inserts the replacement.

Fixture tests cover provider/import errors, retries, idempotency, rollback, stale response rejection, mapping review, assets, IDs, and database constraints. A bounded live adapter smoke succeeded for canonical `swsh3-136` and `swsh3` with default options and no persistence. Canonical `mix check --verbose` passed with 81 tests after resetting only the disposable test database to clear locally applied superseded uncommitted migration timestamps; `mix ash.codegen --check` and `git diff --check` passed. This does not claim Phase 2 catalogue completion.

## Cost and destination risk

The selected TCGdex aggregate source has $0 acquisition cost and no credentials. Historical paid-provider estimates remain relevant only to post-MVP seller-level experiments: Apify’s documented $0.005/listing and Parse’s Hobby plan would consume the global cap quickly; cardmarketapi Starter at $49.99 leaves no safety margin.

Destination shipping remains a central gap for any future seller-level valuation. Cardmarket shipping depends on origin, destination, weight, and dimensions, and seller country is not enough because sellers can opt out of countries. It is explicitly outside the active aggregate MVP; do not imply shipping-to-Poland eligibility in its UI or data.

## Licensing and evidence caveats

The TCGdex MIT license covers the repository/artifact, not Pokémon image/IP rights or marketplace redistribution rights. ISA Article 8.4 restricts aggregation/processing for redistribution and requires permission. Terms and robots rules remain operational risks even under the scrappy acquisition policy. Public documentation and bounded samples do not prove production authorization, contract rights, provider accuracy, or CardTrader shipping behavior.

## Controls and next actions

Use canonical IDs/known URLs only, seven-day TTL, bounded concurrency, backoff, provider quota and global cost reservation, kill switches, and stale/`?` fallback. Aggregate all account/provider usage under the same $50/month cap. The selected singles baseline is `$0`, free, and unauthenticated. Paid/live seller-level singles remains capability-gated, while broader sealed-source research remains unfinished.

1. **Complete:** the unauthenticated TCGdex `tcgdex_cardmarket_v1` aggregate adapter and metric selector, plus the bounded one-card-plus-set catalogue importer, are implemented and fixture-tested.
2. Implement full set/card catalogue sync and enumeration, then local PostgreSQL exact-printing search; retain conservative mapping review behavior.
3. Wire Oban valuation acquisition and PubSub updates, then add the public singles/card UI; keep provider fetches outside request paths.
4. Preserve `Provider`/`Offer`/`Valuation.default_v1` as historical/post-MVP seller-level capability; seller/offer count is unavailable from the active aggregate source and must not be fabricated (future shared storage may make it nullable/optional).
5. Request REBEL B2B data import/access and written SCD/data-reuse scope.
6. Request approved feeds/permissions from the initial retailer/LGS panel, including Media Expert only with permitted feed/access; this broader sealed research is not complete.
7. Complete image/data licensing review. Broader sealed and seller-level source research remains open.

All observations are time-specific. No credentials are committed.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Application Foundation](application-foundation.md)
