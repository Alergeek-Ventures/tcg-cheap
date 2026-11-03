# Product

<!-- impeccable:product-schema 1 -->

> Product owner direction, 2026-10-30.

## Platform

web

## Users

- Polish Pokémon TCG fans (players, collectors, parents buying gifts) who want
  to buy sealed products (boosters, bundles, booster boxes, Elite Trainer
  Boxes, tins, collections) without overpaying.
- The same fans when trading single cards with friends or in a local shop.

## Product Purpose

A deliberately simple guide with two parts:

1. **Zakupy (buying guide, live):** for any sealed Pokémon product, show where
   it is cheapest in Polish shops right now and whether that price is good,
   normal or expensive compared with what other Polish shops ask today, with
   the product's recent prices as context.
2. **Wymiany (trading guide, next phase):** check whether a trade of single
   cards is fair.

## Positioning

An honest, independent price check in Polish. Verdicts are based only on
prices you can actually buy at (in-stock offers in Polish shops, falling back
to the Cardmarket trend), never on MSRP. Missing data is shown as missing.

## Operating Context

- On a phone in a shop or at a fair: "is this price OK?" in seconds.
- On desktop before buying online: compare shops and see the price history.
- No accounts. Prices exclude shipping.

## Capabilities and Constraints

- Catalogue: every sealed Pokémon product listed on Cardmarket (≈4,400),
  imported daily; images come from matched Polish shop offers.
- Offers: 122 Polish shops with public product feeds (WooCommerce, Shopify,
  Shoper and IdoSell XML), fetched once a day and matched to products
  automatically; an administrator can assign the rest by hand. Each offer shows the shop's cheapest delivery,
  free-delivery threshold and pickup city where the shop publishes them.
- Verdict: the cheapest in-stock price against today's market. Typical
  price = median of the Polish shops' lowest in-stock prices (one per shop,
  at least 3 shops). Good ≤ 95%, normal ≤ 110%, expensive above; a good
  price must also be ≤ 95% of the 30-day usual price and of the Cardmarket
  trend in PLN plus a tracked parcel from Germany, when they are known (the
  page says which one lowered the limit). The limits are shown in whole
  złoty so a price seen in a physical shop can be judged too. With fewer
  shops there is no verdict ("Za mało sklepów"); the Cardmarket trend in
  PLN is shown as context on the product page.
- History bounds a good price only: the same price against the median
  daily lowest price of the last 30 days (≥ 7 days with stock), shown as one
  line ("Taniej / Tyle co / Drożej niż w ostatnich 30 dniach") and a chart
  behind a click.
- Pre-orders (owner decision, 2026-11-02) never count as in stock. A
  product with nothing in stock but pre-orders is rated the same way on its
  pre-order offers and clearly marked as a pre-order, with the days until
  the expansion's premiere (the same street date for every shop) when it is
  known; otherwise pre-orders are listed in their own group.
- Set pages (owner decision, 2026-11-03): every named expansion has a page
  (`/rozszerzenia/<name>-<id>`) that answers first (the single booster's
  cheapest price, the rarest pull rates, the card count and the most valuable
  card), then lists the set's products with their verdicts, its pull rates
  and its cards with Cardmarket prices. Pages state the answer in their first
  sentence and search metadata, so search engines and AI assistants can quote
  it.
- Public pages read only the local database; shops and Cardmarket are fetched
  by background jobs.
- The singles/trade pages are still English and will be simplified next.

## Evidence on Hand

- Application code and tests in `lib/` and `test/`.
- Real daily feeds from the shops and Cardmarket's public product and
  price files.
- No testimonials or customer proof yet. The site is unofficial and not
  affiliated with The Pokémon Company or the shops.

## Product Principles

- Simple over complete: every screen and feature must earn its place.
- Realistic over official: what you can buy it for, not the catalogue price.
- Honest gaps over invented numbers.
- Polish first: copy, number and date formats for Polish users.

## Accessibility & Inclusion

- Polish interface for the buying guide; mobile-first and responsive.
- Semantic markup, keyboard access, visible focus, sufficient contrast,
  48px touch targets, no horizontal overflow at 390px.
- Verdicts never rely on colour alone (text label plus icon).
