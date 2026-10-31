# Data Sources

- Updated: 2026-10-31
- Sources: Project code (`lib/tcg_cheap/sealed/`, `lib/tcg_cheap/pricing/`, `lib/tcg_cheap/catalogue/`, `config/config.exs`); raw captures listed below
- Raw: [LootQuest](../../raw/2026-08-09-lootquest-store-api.md), [CardzHouse/BoosterPoint](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md), [Boosterland/Colligere](../../raw/2026-09-02-boosterland-colligere-store-apis.md), [NBP](../../raw/2026-08-08-nbp-api-eur-rate.md), [TCGdex IDs](../../raw/2026-08-14-tcgdex-punctuation-card-ids.md), [TCGdex sets](../../raw/2026-08-19-tcgdex-set-ordering-and-series.md), [Singles scope](../../raw/2026-08-19-production-singles-scope-sources.md), [Curated playables](../../raw/2026-08-19-curated-playable-manifest.md), [Provider experiments](../../raw/2026-08-07-provider-source-experiments.md), [Singles API spike](../../raw/2026-08-07-scrappy-singles-acquisition-spike.md)

Every external source the application reads, how it is read, and what it is
used for. All sources are public and need no credentials. Raw captures are
time-specific evidence from when each source was evaluated.

## Sources in use

| Source | Endpoint (fixed in code) | Schedule | Used for |
| --- | --- | --- | --- |
| Cardmarket sealed files | `downloads.s3.cardmarket.com/productCatalog/productList/products_nonsingles_6.json`, `…/priceGuide/price_guide_6.json` | daily 03:30 UTC | Sealed catalogue and Cardmarket trend/low/avg (EUR) |
| Cardmarket singles files | `…/productList/products_singles_6.json`, `…/priceGuide/price_guide_6.json` | daily 03:00 UTC | Singles valuations (`cardmarket_bulk_v1`) |
| 32 WooCommerce shops | `https://<host>/wp-json/wc/store/v1/products` with fixed categories | daily from 04:00 UTC, one shop at a time | Sealed offers: price, stock, URL, image, EAN (SKU) |
| 4 Shopify shops | `https://<host>/products.json` or a Pokémon collection's, after `/meta.json` confirms PLN | daily from 04:00 UTC, one shop at a time | Sealed offers per variant: price, availability, URL, image, EAN (SKU) |
| TCGdex | `https://api.tcgdex.net/v2/en` | weekly bootstrap; on-demand card detail | Singles identity, set/card metadata, images, Cardmarket product ids |
| NBP | `https://api.nbp.pl/api/exchangerates/rates/a/eur/` | daily 15:00 UTC; on demand from `/trade` | EUR/PLN mid rate (table A) |

Shops (`TcgCheap.Sealed.Shops`, 36 as of 2026-10-31) were found by a
2026-10-31 survey of 152 Polish shops; the owner asked for as many as can be
read automatically. Each WooCommerce shop has a fixed category filter, a
permalink pattern and a page limit, plus accepted category slugs where the
category also holds non-sealed items; otherwise a title must name a sealed
product (`Matcher.sealed_title?/1`). Shopify shops read a Pokémon collection
or the whole shop (titles must then say Pokémon). Each shop also records its
published delivery terms (cheapest delivery, free-delivery threshold, pickup
city), shown with its offers. Left out: pokekarty.pl (`robots.txt` forbids
the API), cardhorizon.pl (prices in EUR), maginarium.pl and crazypulls.pl (a
JavaScript bot challenge answers the API). Shoper and IdoSell shops publish
XML product feeds and are the next candidates.

## Shared fetch rules

- Req only; fixed HTTPS hosts; no redirects; Req retries disabled (Oban
  retries the job instead); 5 s connect and 15 s receive timeouts.
- Bounded responses: 5 MB per shop page; 32 MB and 100,000 rows per
  Cardmarket file.
- Untrusted fields are validated (ids, titles, URLs, prices, image hosts);
  invalid items are skipped, but a transport, status, pagination or shape
  error fails the whole fetch so a partial feed never replaces a complete one.
- Rendered images must come from `assets.tcgdex.net`, Pokémon hosts or a
  configured shop host (`TcgCheap.Catalogue.ExternalImage`); the CSP is
  derived from the same list.
- TCGdex, Cardmarket singles and NBP requests pass through the acquisition
  budget (`config :tcg_cheap, :acquisition_budget`); sealed requests do not.

## Known quirks

- Cardmarket publishes no expansion names; sealed set names are derived from
  product names sharing an expansion id and may be empty.
- Shop titles are free text in Polish and English; matching is conservative
  and some offers need a manual assignment in `/admin/buying-guide`.
- TCGdex card ids can contain punctuation (see the TCGdex IDs capture) and its
  set list is not in release order (see the TCGdex sets capture).
- The curated playables manifest evidence expires on 2026-11-17.

## Not used

Paid or credentialed singles price APIs and scraping of Cardmarket offer pages
were evaluated early (see the provider experiments and singles API spike
captures) and are not used.
MSRP is not a data source.

## See Also

- [Application Foundation](application-foundation.md)
- [Buying and Trading Guide](../product/buying-and-trading-guide.md)
