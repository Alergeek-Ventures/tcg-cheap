# Application Foundation

- Updated: 2026-10-30
- Sources: Project code (`lib/`, `config/config.exs`, `config/runtime.exs`, `priv/repo/migrations/`), [deployment guide](../../../docs/deployment-and-operations.md)
- Raw: N/A — codebase update

One Phoenix LiveView + Ash + Oban application on PostgreSQL. The product is
described in the [Buying and Trading Guide](../product/buying-and-trading-guide.md);
this article describes how the code implements it.

## Domains

| Ash domain | Purpose | Main code |
| --- | --- | --- |
| `TcgCheap.Sealed` | Buying guide: products, shop offers, daily prices | `lib/tcg_cheap/sealed/` |
| `TcgCheap.Core` | Singles catalogue (TCGdex), Cardmarket bulk prices and mappings, valuation snapshots, NBP exchange rates | `lib/tcg_cheap/catalogue/`, `lib/tcg_cheap/pricing/` |
| `TcgCheap.Operations` | Acquisition budget, runs, source health, catalogue sync progress, import issues (singles and NBP only) | `lib/tcg_cheap/operations/` |
| `TcgCheap.Accounts` | Provisioned administrators (AshAuthentication password + tokens); no public sign-up | `lib/tcg_cheap/accounts/` |

The trade modules (`lib/tcg_cheap/trades/`, no Ash domain) are plain code: a
URL-safe trade composition and pure valuation arithmetic.

The schema is one squashed set of Ash-generated migrations
(`priv/repo/migrations/`) plus the Oban jobs migration. Extensions used:
`citext`, `pg_trgm` and Ash SQL functions; PostgreSQL ≥ 18.4
(`TcgCheap.Repo.min_pg_version/0`).

## Buying guide (sealed)

```text
Cardmarket products_nonsingles_6.json + price_guide_6.json
  └─ CatalogueImportWorker (03:30 UTC) ─ CatalogueImport ─┐
Six WooCommerce Store APIs                                 ├─ Refresh.recompute
  └─ FetchWorker per shop (04:00–06:30 UTC) ─ Refresh.run ─┘     │
                                                                  ├─ re-match offers (Matcher)
                                                                  ├─ DailyPrice per product/day
                                                                  └─ Product availability, lowest price, image
Public pages ─ Guide (read model) ─ PriceGuide.verdict
```

- **Resources.** `Product` (keyed by Cardmarket id, with kind, derived set
  name, Cardmarket trend/low/avg in EUR, slug, search text, availability,
  lowest price, image), `Offer` (one per shop product; title, URL, price,
  stock, EAN, image, `last_seen_at`, matched product, `manual?`), and
  `DailyPrice` (per product and day: lowest in-stock shop price, shops in
  stock, Cardmarket trend).
- **Catalogue import.** `TcgCheap.Sealed.CatalogueImport` downloads both files
  through the bounded `TcgCheap.Pricing.CardmarketBulk.Adapter`, builds rows
  with `TcgCheap.Sealed.Catalogue` (kinds from `TcgCheap.Sealed.Kinds`; Coins
  and Lots excluded; cases and displays of tins/blisters become `case`) and
  upserts everything in one transaction, then recomputes.
- **Shop fetch.** `TcgCheap.Sealed.Shops` fixes each shop's host, category
  ids, accepted category slugs, permalink shape and page limit.
  `TcgCheap.Sealed.WooCommerce` reads 100 products per page, at most
  `max_pages` pages and 2 MB per page, follows no redirects, skips invalid
  products and fails the whole fetch on any transport, status, pagination or
  shape problem. `TcgCheap.Sealed.Refresh.run/2` upserts offers and
  recomputes in one transaction; a failed fetch (including one listing no
  products at all) writes nothing and Oban retries (3 attempts). EANs are
  taken only from 12–13-digit SKUs with a valid GS1 check digit.
  Recomputations take a transaction-level advisory lock, so a fetch, the
  catalogue import and an admin decision never interleave.
- **Current offers.** An offer counts when it was seen in its shop's latest
  successful fetch and that fetch is at most 3 days old
  (`TcgCheap.Sealed.current_offers/2`, optionally limited to given
  products in SQL). Removing a shop therefore drops its
  offers from verdicts within 3 days.
- **Matching.** `TcgCheap.Sealed.Matcher` normalises titles and names
  (diacritics, synonyms such as ETB, Polish language words, series prefixes).
  A product matches when all its name tokens are in the title, every
  qualifier in the title (box, case, half, mini, center, languages, …) is in
  the name, and at most two title words stay unexplained; the most specific
  product wins and ties stay unmatched. Preorders, multi-packs, empty,
  damaged, opened or used boxes, singles and accessories are excluded, even
  when the EAN is known. Otherwise an EAN seen on a manually assigned offer
  (and on no conflicting one) wins over the title. Every recompute re-matches all non-manual
  offers, so catalogue or rule changes apply retroactively.
- **Verdict.** `TcgCheap.Sealed.PriceGuide` (see the product article for the
  rule; the exact offer price is compared with limits rounded down to whole
  złoty, so no price above 95%/110% is rated better than it is);
  `TcgCheap.Sealed.Guide` assembles summaries, offers, 90-day history (plus
  the last stocked day when it is older, for the out-of-stock verdict) and
  the EUR/PLN rate for the LiveViews.
- **Web.** `TcgCheapWeb.HomeLive` (`/`), `TcgCheapWeb.ProductLive`
  (`/produkty/:slug`), shared `TcgCheapWeb.GuideComponents`, and
  `TcgCheapWeb.Admin.BuyingGuideLive` (`/admin/buying-guide`). Manual
  decisions (assign, never match, clear) run in a transaction together with
  `Refresh.recompute/1`. Image hosts allowed by CSP are derived from the shop
  list (`TcgCheap.Catalogue.ExternalImage`).
- Sealed jobs are not subject to the acquisition budget or run tracking;
  their operational evidence is the Oban job history and offer `last_seen_at`.

## Singles (trading guide, to be simplified in phase 2)

- **Catalogue.** TCGdex is the card identity source (`TcgCheap.Catalogue.Tcgdex`,
  `CardSet`, `CardPrinting`). `SinglesCatalogueBootstrapWorker` (cron every
  15 minutes, unique per week) queues the resumable, budget-aware
  `CatalogueSyncWorker` (all sets and card briefs) and the serial
  `CardDetailEnrichmentWorker` chain. A card detail page can also request
  enrichment on demand, limited per client IP
  (`TcgCheapWeb.PublicAcquisitionLimiter`, 30 per hour). Public reads show
  canonical paper cards (TCG Pocket excluded).
- **Collection scopes.** Printings carry informational scopes
  (`pitch_black_full`, `rolling_ir_sir`, `curated_playable`, `legacy_local`).
  `SinglesScopeBootstrapWorker`/`SinglesSetCollectionWorker` (manual trigger
  from `/admin/operations`, no cron) collect the Pitch Black and rolling
  IR/SIR scopes; `CuratedPlayableBootstrapWorker` collects curated playables
  from a fixed manifest (`CuratedPlayablePolicy`) that is valid until
  2026-11-17 and queues nothing afterwards. Public reads are not filtered by scope.
- **Prices.** `TcgCheap.Pricing.CardmarketBulk.SyncWorker` (03:00 UTC)
  downloads Cardmarket's `products_singles_6.json` and `price_guide_6.json`,
  checks plausibility (row minimums and a 10% row-count anomaly bound), keeps
  the compressed raw responses per batch, crosswalks TCGdex sets/printings to
  Cardmarket expansions/products conservatively
  (`TcgCheap.Catalogue.CardmarketCrosswalk`, anchored on TCGdex's Cardmarket
  ids), and materialises one current `SingleValuationSnapshot` per mapped
  printing in EUR using the first available of avg7, avg30, trend, avg, low.
  The only valuation policy is `cardmarket_bulk_v1`; TCGdex is never a price
  source. Valuations older than 24 hours are shown as stale.
- **Corrections.** Administrators can correct a printing's Cardmarket mapping
  (`/admin/catalogue/cards/:id/correct`); decisions are immutable history and
  `MappingReplayWorker` replays the crosswalk and materialisation.
- **Trade.** `/trade` keeps the trade in the URL as TCGdex ids and quantities
  (`TcgCheap.Trades.Composition`), totals both sides in EUR
  (`TcgCheap.Trades.Valuation`; unvalued cards are listed but excluded from
  totals) and in PLN with the stored NBP rate, requesting a fresh rate in the
  background when needed.
- **Exchange rate.** `TcgCheap.Pricing.ExchangeRateWorker` stores the NBP
  table A EUR/PLN mid rate daily at 15:00 UTC; the buying guide uses the
  latest stored rate on or before today.
- **Operations.** `TcgCheap.Operations.AcquisitionBudget` admits external
  requests for the three configured providers (`tcgdex_catalogue`,
  `cardmarket_bulk`, `nbp`) within hourly/daily/monthly limits;
  `AcquisitionReconcilerWorker` (every 15 minutes) repairs stranded runs;
  source health treats `nbp`/`cardmarket_bulk` as stale after 36 hours
  (`:acquisition_health` config). `/admin/operations`
  shows provider health and offers manual refreshes; Backpex pages under
  `/admin/catalogue/*` and `/admin/operations/import-issues` are read-only
  inspection.

## Jobs

Oban queues (concurrency 1 each): `exchange_rates`, `catalogue_sync`,
`operations`, `cardmarket_bulk`, `sealed`. Completed jobs are pruned after 7
days. Schedules (UTC) are in `config/config.exs`:

| Cron | Worker |
| --- | --- |
| `*/15 * * * *` | `SinglesCatalogueBootstrapWorker`, `CuratedPlayableBootstrapWorker`, `AcquisitionReconcilerWorker` |
| `0 3 * * *` | `Pricing.CardmarketBulk.SyncWorker` |
| `30 3 * * *` | `Sealed.CatalogueImportWorker` |
| `0 4`, `30 4`, `0 5`, `30 5`, `0 6`, `30 6` | `Sealed.FetchWorker` for lootquest, cardzhouse, boosterpoint, pokebooster, boosterland, colligere |
| `0 15 * * *` | `Pricing.ExchangeRateWorker` (NBP) |

## Key decisions

- Public pages never call external services synchronously; they read local
  data and show missing or stale data honestly.
- Untrusted feeds are validated strictly and fail closed: a partial or
  malformed fetch writes nothing.
- Money is `Decimal`; Cardmarket values stay in EUR and are converted with the
  stored NBP rate only for display and the sealed fallback.
- Sealed matching prefers no match over a wrong match; a human fixes the rest
  in `/admin/buying-guide`.
- Administration is behind provisioned admin accounts with login throttling
  (`TcgCheapWeb.AdminLoginLimiter`); there is no public registration.
- `/health` is fail-closed readiness (database, Oban, acquisition budget);
  `/health/live` is liveness only.

## Validation

`mix check` is the gate: format, Ash codegen check, Sobelow, warnings-as-errors
compile, unused dependencies, Credo strict and Dialyzer. There is no
automated test suite (owner decision); changes are verified in the running
app. CI (`.github/workflows/ci.yml`) runs the gate, validates the pinned
ParadeDB image and builds `deployment/Containerfile.app`.

## See Also

- [Buying and Trading Guide](../product/buying-and-trading-guide.md)
- [Data Sources](data-sources.md)
- [Engineering Conventions](reference-project-conventions.md)
