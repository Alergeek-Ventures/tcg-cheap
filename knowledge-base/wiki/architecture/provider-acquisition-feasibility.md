# Provider and Acquisition Feasibility

- Updated: 2026-08-07
- Sources: [Provider/source experiment capture](../../raw/2026-08-07-provider-source-experiments.md); [Scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md); [current MVP north star](../product/mvp-implementation-plan.md)
- Raw: [2026-08-07 provider/source experiments](../../raw/2026-08-07-provider-source-experiments.md); [2026-08-07 scrappy singles acquisition spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md)

**Status:** Phase 0 has a scrappy singles shortlist and a provider-neutral valuation boundary, but no production provider is selected. Exact capability validation remains mandatory.

## Authority and access-policy boundary

The product owner superseded the former access/terms-first blocker on 2026-08-07. Public scraping and third-party scraping services, plus project-controlled account/API-key pooling, are permitted under the product policy. Terms, robots, and access-control behavior remain documented operational risks. No authentication, payment, or CAPTCHA bypass is permitted; credentials remain server-side and out of git. This ADR does not weaken `default_v1`: English, NM, explicit ships-to-Poland eligibility, EUR, and five distinct sellers remain required.

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
| Apify Phantom Coder | **Primary next credentialed candidate.** Documents seller identity, condition, language, quantity, EUR/currency rows, seller-country input, max 1–500 results, and $0.005/listing Free / $0.004 Starter; reports 97.1% successful runs. Destination eligibility is absent. Signup stalled at identity/hCaptcha; no account creation is claimed. |
| Parse.bot Cardmarket API | **Fallback/parallel candidate.** Documents seller usernames, condition, attributes, price, quantity, comments, pagination to Cardmarket’s 300 cap, and seller-country filtering; Free 100 credits or Hobby $30/1,000 credits, listing calls 2 credits. Destination eligibility is absent. Signup stalled at hCaptcha; no credentialed call. |
| cardmarketapi.com | **Indicative/aggregate fallback only.** Successful HTTP 200, but empirical listings lack seller identity, quantity, and destination. Its `avg5` is five listings, not five distinct sellers. Current Starter $49.99 leaves no safety margin and the plan API says 500/day. |
| tcg-scraper.com | **No-go for now.** Credentialed sample got HTTP 502/Cloudflare HTML and the documented response does not prove offer rows or required fields. |
| Official Cardmarket API | Applications are currently closed; not selectable without written access. |
| Cardmarket public catalogue/price guide | Free daily catalogue/price-guide material is aggregate-only; useful for metadata/reference, not seller-level offers or destination eligibility. |
| TCGdex aggregate | Free and useful for metadata/aggregate Cardmarket mappings, but not compliant with the fixed English/NM/Poland/five-distinct-seller preset. |
| CardTrader | Seller identity, condition, and language are documented, but authenticated Poland-account shipping behavior and the separate shipping-method request remain unresolved. |
| JustTCG | `$19/month + tax` Starter and `$49/month + tax` Professional; no seller identity or destination proof is established. |
| PokemonPriceTracker | `$99` Cardmarket/commercial plan, over the cap. |

Do not call Apify or Parse a selected production provider until a successful credentialed real Pokémon run validates actual rows.

## Sealed catalogue/source direction

REBEL Hurt remains the best current primary catalogue/SCD discovery candidate based on the observed `SCD`/`Chaos Rising` page and B2B terms, but it is not proven exclusive or official TPCi MSRP authority. ISA remains a historical fallback requiring permission for aggregation and republication. Treat SCD as a non-binding suggested reference, not authoritative MSRP. Candidate regular retailers are REBEL retail, Empik-owned offers, Media Expert only with permitted feed/access, Smyk, TCG Love, Graal, LootQuest, and PokeCollect; candidate LGS/community sources include TCG Love, Graal, ShopGracz, Centrum MTG, Strefa MTG, Plan-Sza, and Guildmage. Require released/English/official filtering, preorder/import/marketplace filtering, and feed/terms approval before adapters.

## Implemented exact boundary

The pure core is implemented at `lib/tcg_cheap/pricing/singles/provider.ex`, `lib/tcg_cheap/pricing/singles/offer.ex`, and `lib/tcg_cheap/pricing/singles/valuation.ex`, with focused tests at `test/tcg_cheap/pricing/singles/provider_test.exs` and `valuation_test.exs`. `Provider` declares required capabilities and exposes deterministic missing-capability detection; `Offer` normalizes seller, language, condition, shipping, and Decimal EUR; `Valuation` computes `default_v1` from the five lowest distinct sellers. Future adapter selection must reject missing seller identity or destination rather than silently approximate them. No live adapter, selector, resource, job, or storage exists.

## Cost and destination risk

At Apify’s documented $0.005/listing, 10 rows/fetch is about $0.05; $50 buys at most about 1,000 such fetches/month before retries. With a seven-day TTL that is roughly 230 continuously active cards. This is gross cost before free credits; use a lower operational limit for safety. Parse’s Hobby plan is $30/1,000 credits and listing calls cost 2 credits, leaving limited call volume. Current cardmarketapi Starter at $49.99 leaves no safety margin and its current plan API says 500/day.

Destination shipping is the central capability gap. Cardmarket shipping depends on origin, destination, weight, and dimensions, and seller country is not enough because sellers can opt out of countries. A provider must expose explicit destination eligibility, or a separately approved conservative/changed preset is needed; do not silently change it here.

## Licensing and evidence caveats

The TCGdex MIT license covers the repository/artifact, not Pokémon image/IP rights or marketplace redistribution rights. ISA Article 8.4 restricts aggregation/processing for redistribution and requires permission. Terms and robots rules remain operational risks even under the scrappy acquisition policy. Public documentation and bounded samples do not prove production authorization, contract rights, provider accuracy, or CardTrader shipping behavior.

## Controls and next actions

Use canonical IDs/known URLs only, seven-day TTL, bounded concurrency, backoff, provider quota and global cost reservation, kill switches, and stale/`?` fallback. Aggregate all account/provider usage under the same $50/month cap. A `$0` development baseline—free catalogue/NBP/manual bounded research—can proceed while paid/live singles remains capability-gated.

1. Obtain a persistent project-owned Apify or Parse credential.
2. Run three representative Pokémon products.
3. Verify duplicate-seller handling and destination eligibility.
4. Implement only the passing adapter.
5. Configure account pools and global cost reservation later, without committing secrets.
6. Request REBEL B2B data import/access and written SCD/data-reuse scope.
7. Request approved feeds/permissions from the initial retailer/LGS panel, including Media Expert only with permitted feed/access.
8. Complete image/data licensing review.

All observations are time-specific. No credentials are committed.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Application Foundation](application-foundation.md)
