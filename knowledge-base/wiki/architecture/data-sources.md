# Data Sources

- Updated: 2026-11-01
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
| 26 Shoper shops (Google feed) | `https://<host>/console/integration/execute/name/GoogleProductSearch` (whole shop, one request) | daily from 04:00 UTC, one shop at a time | Sealed offers: price (sale price while effective), availability, URL, image, EAN (`g:gtin`) |
| 2 Shoper shops (Ceneo feed) | `https://<host>/console/integration/execute/name/CeneoV2` (whole shop, in-stock products only) | daily from 04:00 UTC, one shop at a time | Sealed offers: price, stock, URL, image, EAN attribute |
| 7 IdoSell shops | a Pokémon category or search listing with `getProductXML=t&counter=N` | daily from 04:00 UTC, one shop at a time | Sealed offers: gross price, availability status, URL, image, EAN (barcode) |
| 14 PrestaShop shops | the JSON view (`?from-xhr`) of their Pokémon category listings | daily from 04:00 UTC, one shop at a time | Sealed offers: price, add-to-cart availability, URL, image |
| 17 Shoper (no feed) and Sky-Shop shops | the HTML Pokémon category listing, page by page | daily from 04:00 UTC, one shop at a time | Sealed offers: price, add-to-cart availability, URL, image |
| 11 shopGold, Sellingo, Selly and SOTE shops | the HTML Pokémon category listings (`listing_paths`), page by page | daily from 04:00 UTC, one shop at a time | Sealed offers: price, availability, URL, image |
| 9 shops on their own storefronts | the HTML listing (or the Next.js page data) of a Pokémon category or search, one client each | daily from 04:00 UTC, one shop at a time | Sealed offers: price, availability, URL, image |
| TCGdex | `https://api.tcgdex.net/v2/en` | weekly bootstrap; on-demand card detail | Singles identity, set/card metadata, images, Cardmarket product ids |
| NBP | `https://api.nbp.pl/api/exchangerates/rates/a/eur/` | daily 15:00 UTC; on demand from `/trade` | EUR/PLN mid rate (table A) |

Shops (`TcgCheap.Sealed.Shops`, 122 as of 2026-11-01) were found by a
2026-10-31 survey of 152 Polish shops; the owner asked for as many as can be
read automatically. Each WooCommerce shop has a fixed category filter, a
permalink pattern and a page limit, plus accepted category slugs where the
category also holds non-sealed items; otherwise a title must name a sealed
product (`Matcher.sealed_title?/1`). Shopify shops read a Pokémon collection
or the whole shop (titles must then say Pokémon). Each shop also records its
published delivery terms (cheapest delivery, free-delivery threshold, pickup
city), shown with its offers. Left out: pokekarty.pl (`robots.txt` forbids
the API), cardhorizon.pl (prices in EUR), maginarium.pl and crazypulls.pl (a
JavaScript bot challenge answers the API).

Shoper and IdoSell shops publish XML. Shoper's Google (`GoogleFeed`) or Ceneo
(`CeneoFeed`) export covers the whole shop, so a product counts only when its
title names a sealed product and its title or category says Pokémon
(`ShopFeed.sealed_pokemon?/2`); IdoSell (`IdoSell`) reads a Pokémon category or
search, page by page until an empty page. No `robots.txt` of these shops
disallows `/console/` or `getProductXML`. Left out: elfwood.pl, futurex.pl and
planszostrefa.pl (3 or fewer sealed Pokémon items), przyczolek.pl (8 sealed
items, none in stock, in a 16 MB export).

Shops without a feed are read from their own category listings
(`TcgCheap.Sealed.HtmlListing` holds what the HTML clients share). PrestaShop
(`PrestaShop`) returns a listing as JSON when asked like its own
infinite-scroll script; Shoper themes without the export (`ShoperListing`),
Sky-Shop (`SkyShop`), shopGold, Sellingo, Selly and SOTE are parsed from HTML
with Floki; eight shops on their own storefronts have one small client each
(`Am76`, `Collectify`, `GildiaGrodzisk`, `Guildmage`, `MagicznyRynek`,
`Pasaz24` for two shops, `Planszomania`, `Smajk`). A listing must prove it
is complete: its stated product count (or page count where a theme states
none) must match what was read, so a missing or shifted page fails the
fetch. In stock means buyable now (an add-to-cart button or the shop's
availability label); a pre-order is not in stock, and the matcher also
excludes titles that say pre-order. Left out on 2026-11-01: morigal.pl (a
Cloudflare challenge answers non-browser clients), cardverse.pl (its listing
shows no stock), pokeelite.pl (its listing labels sold-out items available),
tcgumisia.pl (`robots.txt` forbids paging) and bastacentershop.pl (an empty
Pokémon category).

## Shared fetch rules

- Req only; fixed HTTPS hosts; no redirects; Req retries disabled (Oban
  retries the job instead); 5 s connect and 15 s receive timeouts.
- One request at a time with a 1 s pause before each: several shops answer
  quick successive requests with 403, and Shoper and Sky-Shop `robots.txt`
  ask for a 1 s crawl delay.
- Bounded responses: 5 MB per shop page, 64 MB for a whole-shop XML export
  (the largest, mrpuggy.pl, was 38 MB on 2026-10-31; Shoper does not compress
  it); 32 MB and 100,000 rows per Cardmarket file.
- HTML is parsed with Floki; a body a shop gzips regardless is inflated to
  at most the page limit.
- XML is parsed with Saxy (`TcgCheap.Sealed.XmlRecords`): no atoms, DTDs
  skipped, only character references and the predefined entities expanded,
  and only the wanted fields of wanted products kept while parsing.
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
- Whole-shop exports also let through accessories whose titles contain sealed
  words (Ultra Pro portfolios, deck boxes), some singles with "booster" in
  the name and Asian-language boosters absent from Cardmarket's catalogue;
  they stay unmatched. Shoper variants (e.g. tcghub.pl blisters) share one
  title. Some shops list sold-out items at a 1 zł or 999 zł placeholder
  price. Category listings may hold a stray item of another game (planszon.pl)
  or accessories; they stay unmatched.
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
