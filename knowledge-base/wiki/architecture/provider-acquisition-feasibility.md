# Provider and Acquisition Feasibility

- Updated: 2026-08-07
- Sources: [Provider/source experiment capture](../../raw/2026-08-07-provider-source-experiments.md); [current MVP north star](../product/mvp-implementation-plan.md)
- Raw: [2026-08-07 provider/source experiments](../../raw/2026-08-07-provider-source-experiments.md)

**Status:** Phase 0 bounded research/source experiments are complete enough to choose catalogue sources and a sealed discovery direction, but the exact singles valuation acquisition plan is **BLOCKED**. Phase 0 as a whole and provider locking are not complete.

## Authority boundary

Current code and tests still have no product integrations. This ADR does not weaken the north-star fixed preset or allow aggregate substitutes to satisfy MVP acceptance. A stale or missing value is preferred to silently broadening matching requirements.

## Card metadata

**Catalogue-only direction:** use TCGdex as primary card metadata for the initial catalogue/import work, with Pokémon TCG API as fallback and cross-check, subject to licensing and mapping validation. This does not lock a singles pricing provider. The experiment observed 23,444 TCGdex cards versus 20,479 Pokémon TCG API cards; these are time-specific counts, not coverage guarantees.

TCGdex offers card/set identity, images, legalities and variants, and its Charizard response included Cardmarket product ID `273699` plus first-edition/holo flags. The observed exact identity example is set `base1`, collector/local ID `4` (`base1-4`). Pokémon TCG API supplies structured set/collector number, rarity, legalities, regulation mark, and images. Set plus collector number is the primary human identity; materially different variants remain separate, so internal matching also carries a material-variant discriminator when needed. Internal identity must never be a provider ID alone: preserve provider IDs and raw provenance, and route ambiguous mappings, missing images/cards, shared/wrong marketplace mappings, and evolving `variants_detailed` data to review. Image/IP licensing and marketplace redistribution rights remain separate unresolved questions.

## Singles acquisition matrix

| Candidate | Evidence, cost, and fit |
| --- | --- |
| Official Cardmarket API | Applications are currently closed. Not selectable without written access. |
| Cardmarket public catalogue/price guide | Free downloadable catalogue and aggregate daily price guide; useful metadata/reference, not seller-level offers or exact destination eligibility. |
| cardmarketapi.com | Starter `$49.99/month`, 2,000/day, one-hour cache. It documents condition/language/country/price but no distinct seller identity or shipping-to-Poland field; the site says it live-scrapes Cardmarket pages. Do not select: it leaves almost no budget margin and lacks acceptance proof. |
| TCGdex aggregate | Free and useful for metadata/aggregate Cardmarket mappings, but insufficient for exact printing + English + NM + Poland-shipping + five sellers + EUR + offer count. Not acceptance-compliant as a fallback. |
| CardTrader | Independent marketplace candidate: seller identity, condition, and language are documented, while shipping methods require a separate authenticated request by seller username. An authenticated Poland-account and commercial-use test is still required. |
| JustTCG | `$19/month + tax` Starter and `$49/month + tax` Professional tiers; paid tiers claim commercial display/storage rights, but no seller identity or destination proof is established. |
| PokemonPriceTracker | `$99` Cardmarket/commercial plan, over the cap. |

No candidate has yet been proven to meet all exact-printing, English, NM, ships-to-Poland, five-distinct-sellers, EUR, and offer-count requirements under $50/month.

## Sealed catalogue/source direction

**Decision:** REBEL Hurt is the best current primary catalogue/SCD discovery candidate, based on the observed `SCD`/`Chaos Rising` page and B2B terms. It is not proven exclusive or official TPCi MSRP authority. ISA is a historical fallback and requires permission for aggregation and republication. Treat SCD as a non-binding suggested reference, not authoritative MSRP.

Candidate panel:

- Regular retailers: REBEL retail, Empik-owned offers only, Media Expert only if a permitted feed/access exists, Smyk, TCG Love, Graal, LootQuest, PokeCollect.
- LGS/community: TCG Love, Graal, ShopGracz, Centrum MTG, Strefa MTG, Plan-Sza, Guildmage.

Before adapters, require released/English/official product filtering, preorder/import/marketplace filtering, and feed/terms approval. Media Expert's observed 403/404 instability is not an unattended endpoint.

## Cost, quota, and MVP scenarios

| Scenario | External monthly cost | Decision |
| --- | ---: | --- |
| Authorized development baseline: TCGdex + Pokémon API fallback + NBP + bounded/manual retailer research | `$0` | Proceed; paid singles disabled. |
| Any `$49.99` subscription | `$49.99` before tax/fees | Not a safe cap plan: only `$0.01` remains. |
| Retailer/commercial feeds | TBD | Disabled until price, quota, permission, and reuse scope are known. |

With a seven-day TTL, refreshing 2,000 distinct active cards requires about 8,700 requests per 30 days; 10,000 requires about 43,500, before retries. Capacity does not repair missing contract fields. Paid/live integrations remain disabled in MVP scenarios until exact matching and destination proof exists.

## Required controls before paid/live integration

Provider disabled by default with a kill switch; canonical IDs only; local reads; seven-day TTL; Oban uniqueness; hourly/daily/monthly hard budgets with atomic reservation; quota tracking; per-IP request limiting; no paid call after reservation failure; no retry if the retry would exceed the cap; stale/`?` fallback; and cost reconciliation. Paid providers must be unable to leak credentials or bypass their terms.

## Licensing and terms

The raw TCGdex repository license is MIT for the repository software/data artifact, but does not establish image/Pokémon IP or marketplace redistribution rights. Cardmarket terms and permission must be reviewed. ISA Article 8.4 requires permission for use and prohibits aggregation/processing for redistribution, as recorded in the raw capture. No scraping or control evasion is permitted. Retailer terms, robots rules, and written feed permission are required where applicable. TCG Love's one-request-per-second robots rule is an operational constraint, not permission to crawl disallowed paths.

## Evidence limitations

Public documentation and unauthenticated responses do not prove production authorization, contract rights, CardTrader Poland shipping behavior, or data accuracy.

## Required real-data work and next actions

The bounded requests above are evidence, not provider locking. Remaining blockers and actions are:

1. Obtain written Cardmarket/licensed-provider access and redisplay terms, or validate a legitimate equivalent.
2. Create/use legitimate CardTrader credentials and complete contract review plus bounded tests for exact printing, five seller identities, English/NM, the separate per-seller shipping-method request, and seller shipping methods to Poland using a Poland account.
3. Reject that path if destination eligibility cannot be determined without disproportionate calls.
4. Request REBEL B2B data import/access and written SCD/data-reuse scope.
5. Request approved feeds/permissions from the initial retailer/LGS panel.
6. Perform image/data licensing review.

No credentials should be committed.

## See Also

- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
- [Reference Project Conventions](reference-project-conventions.md)
- [Application Foundation](application-foundation.md)
