# TCG Cheap — Buying and Trading Guide

- Updated: 2026-11-01
- Sources: Product-owner direction, 2026-10-30; [PRODUCT.md](../../../PRODUCT.md); project code (`lib/tcg_cheap/sealed/`, `lib/tcg_cheap_web/live/`)
- Raw: N/A — product specification

**Current product north star.** Work advances this guide unless the product
owner explicitly supersedes it.

## Purpose

TCG Cheap is a deliberately simple web app for Pokémon TCG fans in Poland. It
answers two questions:

1. **Buying (Zakupy):** is this sealed product (booster, bundle, booster box,
   ETB, tin, collection, …) a good buy at this price, and where in Poland is it
   cheapest right now?
2. **Trading (Wymiany):** is this trade of single cards fair?

Simplicity beats completeness. Every feature, table and screen must earn its
place; prefer deleting to preserving. No public accounts, no review queues, no
versioned pricing models.

## Principles

- **Realistic, never MSRP.** Verdicts use only prices you can actually buy at:
  in-stock offers in Polish shops, falling back to the Cardmarket trend. A
  suggested retail price is shown beside them for reference only.
- **Honest gaps.** Missing data is shown as missing; prices are never invented.
- **Polish first.** Polish is the default buying-guide language; English is
  available in the header. Prices keep Polish PLN formatting in both languages.
- **Shipping shown separately.** Prices and verdicts are item prices; each
  offer shows its shop's delivery terms next to it instead of folding an
  estimated shipping cost into the price.
- **Local reads.** Public pages read only the local database; external sources
  are fetched by background jobs.
- **Location stays with the visitor.** Only the visitor's browser remembers
  their location. The server receives it while a page is open and keeps it
  only in that page's memory: it is not written to the database, kept out
  of socket URLs, and filtered from request and crash logs.

## Phase 1 — buying guide (sealed), live

- **Catalogue from Cardmarket.** Every sealed Pokémon product in Cardmarket's
  public non-singles product file (≈4,400; Coins and Lots excluded) is
  imported daily with its kind, a set name (the English TCGdex set's, else
  derived from products sharing a Cardmarket expansion), its language edition
  (English, Japanese, Chinese, Korean, Indonesian or Thai, per expansion; see
  data sources) and the latest Cardmarket trend/low/avg in EUR. Only a few
  sealed-only Asian expansions are listed in code; products that disappear
  from the file are kept.
  Product images come from matched shop offers.
- **Shops.** 122 Polish shops, fixed in code (`TcgCheap.Sealed.Shops`):
  32 through the WooCommerce Store API (their Pokémon category ids), 4
  through Shopify's `products.json` (a Pokémon collection or the whole shop),
  28 Shoper shops through their whole-shop Google Merchant (26) or Ceneo (2)
  XML export, 7 IdoSell shops through the XML view of a Pokémon category or
  search, and 51 shops without a feed through their own Pokémon category
  listings (14 PrestaShop, 9 Shoper, 8 Sky-Shop, 8 shopGold, 4 on Sellingo,
  Selly or SOTE, 8 own storefronts); see
  [Data Sources](../architecture/data-sources.md). Each shop's `source` is the
  feed client module, so another feed type is one more module. A shop without
  curated sealed categories keeps only titles that name a sealed product
  (booster, box, tin, collection, deck, …); a whole-shop feed also needs
  "Pokémon" in the title or the shop's category. One daily job queues a fetch
  per shop after the catalogue import. Offers are matched to products
  automatically by strict title rules, or by a known EAN; an unmatched offer
  is better than a wrong one. Excluded on 2026-10-31: pokekarty.pl (robots.txt
  forbids the API), cardhorizon.pl (sells in EUR), maginarium.pl and
  crazypulls.pl (the API answers with a JavaScript bot challenge), and the
  XML shops elfwood.pl, futurex.pl, planszostrefa.pl and przyczolek.pl (too
  few sealed Pokémon items); on 2026-11-01 morigal.pl (Cloudflare challenge;
  the owner chose not to add it), cardverse.pl, pokeelite.pl, tcgumisia.pl
  and bastacentershop.pl (no reliable stock, `robots.txt`, empty category).
  Pre-orders never count as in stock (owner decision, 2026-11-01).
- **Delivery.** Each shop carries its cheapest published delivery price, its
  free-delivery threshold and the city of its own store where orders can be
  picked up, checked on the shops' pages on 2026-10-31; unknown values stay
  empty. The 40 shops with pickup also carry their store's coordinates
  (`pickup_location`), geocoded from the store address with OpenStreetMap
  Nominatim on 2026-11-01 (pokespot.pl: the centre of Luboń, street
  unpublished; mepel.pl: its registered address in Katowice; hearts.pub: the
  address search results quote from its contact page, which is behind a bot
  check). Some shops hand orders over only by appointment or after
  prepayment (merfolk.pl, wilczek.poznan.pl, plastiq.pl,
  japancollectibles.shop). Shops whose
  research found a store but no confirmed pickup have neither.
- **Visitor location.** "Ustaw lokalizację" (then the town's name) in the
  header of `/` and `/produkty/:slug` opens a panel: "Użyj mojej lokalizacji" (browser geolocation, coarse)
  or a typed Polish town (case- and accent-insensitive suggestions from the
  2,537 GeoNames towns of at least 1,000 inhabitants in `priv/geo/towns.tsv`;
  GeoNames, CC BY 4.0, credited as a selection in the location panel next to the OpenStreetMap credit for store positions). The browser
  keeps coordinates rounded to 0.01° (≈1 km) and a town name in
  `localStorage` and sends them in a `location-restore` event once the page
  connects — not in the LiveView connect params, which phoenix.js appends to
  the socket URL that proxies log. Until that event the page shows no
  location-dependent parts, so nothing flashes. Without a remembered
  location the page asks for the device location by itself, once per browser
  session and not when the browser already refuses; a refusal shows nothing.
  The server keeps the
  location only in the LiveView's assigns and accepts a point only inside
  Poland's bounding box and within 30 km of a Polish town (Prague, Lviv or
  Kaliningrad are refused). `location` parameters are filtered from Phoenix
  logs (`:filter_parameters`), and `TcgCheapWeb.LocationLogFilter`, the first
  primary `:logger` filter, replaces any `"location"`/`:location` value in
  crash reports with `[FILTERED]` before Elixir turns them into text.
  Visitors can remove it. The panel closes on
  Escape or a tap outside, and a screen-reader announcement confirms a new
  location. Without JavaScript the control is hidden and no distances appear. Distances are straight lines
  (haversine, `TcgCheap.Geo`), rounded to whole km; "near" means within 50 km.
- **Barcodes.** Known EANs are a product's own list (filled in by an admin or
  an agent; Cardmarket publishes none) plus the EANs of offers and REBEL
  items assigned to it manually; a code claimed by two products identifies
  neither. The scanner and search also know the EANs of automatically
  matched REBEL items, which never match offers. Typing a known
  EAN/UPC into the search, or scanning it with the phone camera where the
  browser supports `BarcodeDetector` (e.g. Chrome on Android), opens the
  product directly; an unknown code says so.
- **Manual fixes.** An administrator, or an AI agent through the MCP server
  at `/mcp`, can assign an unmatched or wrongly matched offer to any catalogue
  product, keep an offer unmatched for good, or hand it back to automatic
  matching; the agent can also ask why a title matches or not and set product
  barcodes. Automatic matching never overwrites a manual decision. `/mcp`
  needs `MCP_API_TOKEN` outside development.
- **History.** After every shop fetch and catalogue import, each product's
  lowest in-stock Polish price, the number of shops with stock, and the
  Cardmarket trend are stored for the day.
- **Verdict.** The typical price is the median of the daily lowest in-stock
  price over the last 30 days when at least 7 such days exist. The cheapest
  current in-stock offer is then rated **Dobra cena** (≤ 95% of typical),
  **Normalna cena** (≤ 110%) or **Drogo**. Thresholds are whole złoty and are
  shown on the page, so a price seen in a physical shop can be judged too.
  Before 7 days the price is only compared with the Cardmarket trend
  converted with the latest NBP EUR/PLN rate, as a neutral **+14% vs
  Cardmarket** without thresholds: a European price without shipping made
  almost every Polish price "Drogo" (owner decision, 2026-10-31). Without
  current stock the verdict is **Brak w sklepach** (with the last known
  price); with stock but no reference price it is **Za mało danych**.
- **Suggested price.** The SCD (suggested retail price, gross PLN) of the
  REBEL wholesaler's public catalogue (`hurt.rebel.pl/search/pokemon-tcg.html`),
  collected daily with each item's EAN and kept after REBEL drops the item
  (it lists only its current range, from about 30th Celebration and Ascended
  Heroes on). Items match English products automatically (EAN or title;
  "Booster Display (36)" is a Booster Box; other items of several units only
  when named a display), and an agent can assign or exclude one through the
  MCP server. It is the only explicit, fetchable SCD/MSRP source found
  (2026-11-01 research: official Pokémon pages give no amounts or block bots,
  Japanese official prices may not be republished, no other Polish, European
  or US source lists them); REBEL's status as official distributor and any
  reuse terms are unconfirmed (owner decision to collect it, 2026-11-01).
- **Contents.** A product can record what the box holds
  (`TcgCheap.Sealed.ProductContents`, embedded on the product): items
  (boosters with their set, every named card such as promos, typed
  accessories shown in Polish or English), the https sources and the day
  they were checked. Agents fill it through the MCP tool
  `set_product_contents` from facts that a publisher page or two shops
  agree on; nothing is guessed. A card given by its TCGdex id gets its set,
  number, picture and Cardmarket product from TCGdex (an unknown id, or one
  whose TCGdex name differs from the given name, is rejected), and links to
  Cardmarket (`/en/Pokemon/Products?idProduct=…`). Deck lists are not kept
  (owner, 2026-11-01). The product page shows it under "Co jest w środku".
  2026-11-01 research over 328 in-stock products: official Pokémon pages,
  Cardmarket and Bulbapedia block automated reading, several shops too, and
  many shop descriptions list no contents; about 80 products got
  consistent facts.
- **Languages.** The public buying guide (`/` and `/produkty/:slug`) has PL / EN
  links in the header on desktop and phones (including 360 px). Polish copy is
  unchanged; English covers filters, verdicts, delivery/pickup, location and
  scanner feedback, dates, plurals and page titles. Product/set/shop names and
  PLN formatting stay as supplied. `TcgCheapWeb.Gettext` uses Polish msgids,
  with complete `pl` (three plural forms) and `en` catalogues under
  `priv/gettext/`. `GET /lang/:locale` stores only `pl` or `en` in the session,
  defaults to Polish, and returns to a validated local path including its query
  string. A guide-only plug and LiveView `on_mount` set the process locale and
  root HTML `lang`; links work without JavaScript. Admin, trade and card pages
  are outside this language switch. The desktop logo and location align with
  the 72rem content column while the header border remains full width.
- **Pages.** `/` lists and searches products (in stock first, then newest; a
  known barcode jumps to its product) with the cheapest current price and
  verdict. A side panel (behind "Filtry" on phones) filters by kind, language
  edition (with counts) and expansion: the named expansions under the other
  filters, newest first, twelve before "Pokaż wszystkie", English ones as
  their TCGdex logo (hotlinked from `assets.tcgdex.net`). Each card names
  the product's kind, its set unless the product name already contains it,
  and its language edition unless English; the product page names the
  edition too.
  `/produkty/:slug` shows the verdict and thresholds, every current offer
  (in stock first, cheapest first, with links to the shop; the shop's logo
  (wide screens only) and name, not its listing title, which only repeats the product) with its shop's
  delivery line — "dostawa od 14,99 zł · darmowa od 400 zł", "darmowa
  dostawa" when the item alone reaches the threshold, "koszt dostawy w
  koszyku" when the shop publishes no price, and "odbiór osobisty: Gdynia"
  (with "(491 km)" once a location is set; within 50 km a bold "odbiór:
  Gdynia, 20 km" line of its own) — the Cardmarket price, REBEL's suggested
  price when one matches, and a 90-day price chart once there are 7 days of
  prices. Below the verdict's reasoning
  and above the thresholds comes pickup: without a location, when a shop
  with stock has pickup, "Odbierzesz gdzieś blisko? Podaj miejscowość"
  (opens the header panel); with one, the cheapest in-stock offer with
  pickup within 50 km, "Najtaniej z odbiorem osobistym do 50 km:
  CardzHouse, Gdynia · 20 km · 659,99 zł (+110 zł)" ("– najtaniej" when it
  is the cheapest offer overall), or else "brak do 50 km – potrzebna dostawa" with
  the cheapest shop's delivery ("W Colligere dostawa gratis"). On `/` a
  product with an in-stock pickup within 50 km shows the cheapest one, where
  and for how much
  ("odbiór: Gdynia, 20 km · 79,99 zł"), since that is often not the row's
  cheapest price. Verdicts and prices do not change with location.
- **Admin.** `/admin/buying-guide` shows each shop's last fetch, matched and
  in-stock counts, current unmatched offers, automatically matched offers
  (filterable by title) and manual decisions.

## Phase 2 — trading guide (singles), next

Singles currently use the TCGdex card catalogue, daily Cardmarket bulk prices
mapped to exact printings, `/cards/:tcgdex_id` detail pages and the `/trade`
calculator (English UI). Phase 2 will simplify this part under the same
principles and bring it into the Polish guide. Until then it is maintained
as-is and not linked from the guide (the header has no navigation); see [Application Foundation](../architecture/application-foundation.md).

## Constraints

- Elixir, Phoenix LiveView, Ash, PostgreSQL, Oban; one deployable container.
- External fetches use fixed hosts, bounded pages and sizes, timeouts, no
  redirects, and strict validation of untrusted responses; a failed fetch
  writes nothing.
- The site is unofficial and not affiliated with The Pokémon Company or the
  shops.

## See Also

- [Application Foundation](../architecture/application-foundation.md)
- [Data Sources](../architecture/data-sources.md)
