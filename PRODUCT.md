# Product

<!-- impeccable:product-schema 1 -->

> Product owner direction, 2026-10-30.

## Platform

web

## Users

- Pokémon TCG fans in Poland, Hungary, Sweden, Croatia, Slovenia, Portugal, the Netherlands and Czechia (players, collectors,
  parents buying gifts) who want to buy sealed products (boosters, bundles, booster boxes,
  Elite Trainer Boxes, tins, collections) without overpaying.
- The same fans when trading single cards with friends or in a local shop.

## Product Purpose

A deliberately simple guide with two parts:

1. **Zakupy (buying guide, live):** for any sealed Pokémon product, show where
   it is cheapest in shops delivering to the buyer's country right now and
   whether that price is good, normal or expensive compared with what other
   shops ask today, with the product's recent prices as context.
2. **Wymiany (trading guide, next phase):** check whether a trade of single
   cards is fair.

## Positioning

An honest, independent price check in the buyer's language. Verdicts are
based only on prices you can actually buy at (in-stock offers in the
country's shops, and in shops abroad with their delivery to that country,
falling back to the Cardmarket trend), never on MSRP. Missing data is shown
as missing.

## Operating Context

- On a phone in a shop or at a fair: "is this price OK?" in seconds.
- On desktop before buying online: compare shops and see the price history.
- No accounts. Domestic shops' prices exclude shipping; shops abroad count with
  their cheapest delivery to the buyer's country (owner decision, 2026-11-10:
  "liczyć jak polskie, ale z przesyłką"), and their price says so. A shop
  abroad whose delivery price is unknown is only listed.

## Regions

- A region is a country: its shops (domestic ones, and shops abroad with a
  delivery there), its currency and its own URLs – Poland under `/pl/` in
  złoty, Hungary under `/hu/` in forints, Sweden under `/se/` in kronor,
  Czechia under `/cz/` in koruna, Croatia under `/hr/`, Slovenia under `/si/`, Portugal under `/pt/` and the Netherlands under `/nl/` in euro. The root redirects to the visitor's region
  (their choice, else their location; Bosnia and Herzegovina to Croatia's,
  Poland for any other country). Polish URLs from before regions, including
  old home links with list filters, redirect permanently to their Polish page
  in one hop.
- Language is separate from region: Polish, Hungarian, Swedish, Croatian,
  Slovenian, European Portuguese, Dutch, Czech or English, by default the region's own, switchable on every page.
- Every region applies the same rules: the same verdicts and limits in its own
  currency, the price a shop abroad charges buyers in that country (converted
  at the NBP rate only when the shop states it in another currency) with its
  delivery there, the Cardmarket trend converted at the NBP rate. In a euro region the
  trend is taken as is, without conversion.
- Not every part exists everywhere yet. Polish only: articles, retail chain
  deals and today's deals on the home page. Singles from shops, with the same
  verdict rule, and a set's most valuable cards are in every region where a
  shop selling singles is at home or has a delivery there (shops abroad with
  their delivery, in the region's currency); a region without one gives a
  card's Cardmarket trend in its currency, and its set page opens with the
  single booster. A card page is indexed, with its sitemap entry and link
  preview, in every region where shops sell singles and one has the card in
  stock; the card pages of a region without such shops stay out of search.
- Text in each language reads as written for its buyers, never as a
  word-for-word translation.

## Capabilities and Constraints

- Catalogue: every sealed Pokémon product listed on Cardmarket (≈4,400),
  imported daily; images come from matched Polish shop offers.
- Offers: shops of every region with public product lists (feeds, store APIs
  or listing pages), fetched once a day and matched to products
  automatically; an administrator can assign the rest by hand. Each offer shows the shop's cheapest delivery,
  free-delivery threshold and pickup city where the shop publishes them.
- Verdict: the cheapest in-stock price against today's market. Typical price =
  median of the shops' lowest in-stock prices (one per shop, at least 3 shops).
  Good ≤ 95%, normal ≤ 110%, expensive above; a good price must also be ≤ 95% of
  the 30-day usual price and of the Cardmarket trend in the region's currency
  plus a tracked parcel from Germany, when they are known (the page says which
  one lowered the limit). The limits are rounded down to whole units of the
  region's currency, or 0.10 euro in a euro region, so a price seen in a
  physical shop can be judged too. With fewer shops there is no verdict: the
  list row and the product page say "Za mało sklepów", which opens a short note
  on why and how many shops have the product now (owner decision,
  2026-11-16), and the product page gives the Cardmarket trend in the region's
  currency as context.
- History bounds a good price only: the same price against the median
  daily lowest price of the last 30 days (≥ 7 days with stock), shown as one
  line ("Taniej / Tyle co / Drożej niż w ostatnich 30 dniach") and a chart
  behind a click.
- Pre-orders (owner decision, 2026-11-02) never count as in stock. A
  product with nothing in stock but pre-orders is rated the same way on its
  pre-order offers and clearly marked as a pre-order, with the days until
  the expansion's premiere (the same street date for every shop) when it is
  known; otherwise pre-orders are listed in their own group.
- Set pages (owner decision, 2026-11-03, banner revised 2026-11-04): every named
  expansion has a page (`/pl/rozszerzenia/<name>-<id>`, `/hu/szettek/…`, `/se/set/…`,
  `/hr/setovi/…`, `/si/seti/…`, `/pt/expansoes/…`, `/nl/sets/…`, `/cz/sety/…`) that answers first with a banner under the set's logo: in
  a region with singles shops its most valuable card and what pulling it from
  packs costs on average against buying it, then the next three cards the same
  way (a set without card prices, and every set of a region without singles
  shops, shows its single booster instead). The page then lists the set's
  products with their verdicts, its pull rates and its cards. One card price is
  used everywhere: the lower of the cheapest shop offer (abroad with delivery)
  and the Cardmarket trend, without delivery, in the region's currency; in a
  region without singles shops it is the Cardmarket trend. Pages state the answer in their first sentence and
  search metadata, so search engines and AI assistants can quote it.
- The card list (`/pl/karty`, `/hu/kartyak`, `/se/kort`, `/hr/karte`, `/si/karte`, `/pt/cartas`, `/nl/kaarten`, `/cz/karty`) filters by expansion like the
  product list; where shops sell singles a chosen expansion opens with a
  singles banner in the same style: the set's best deal (a shop price furthest
  under the Cardmarket price with delivery), its cards in stock in the region's
  shops, the whole set at the lowest prices and its most valuable card. Only a normal print's offer
  is compared with the Cardmarket price, as on the card's page.
- The home page (`/pl/`, owner decision, 2026-11-16) leads to the two lists
  rather than being one: first one search across products and cards, their
  first results right under it, narrowed to one kind only when the visitor
  chooses it; then, in Poland, today's deals in one row, shops' and retail
  chains' alike (a product furthest under its typical shop price; a chain's
  price only when it is a good price against the same typical price, which
  needs its exact product and enough shops); then the articles, each with a
  cover drawn from what it tells; then the two lists and the newest sets. A
  deal more than 40% under its reference is skipped as a likely wrong match.
- The products list lives at `/pl/produkty` (`/hu/termekek`, …), the card
  list's equal; old home links with the list's filters redirect there. The
  lists without an expansion open with our title and promise, then the search
  (owner decision, 2026-11-16): the home page carries the deals and numbers. A
  chosen expansion's list keeps its set banner.
- The search bar holds the query and Produkty/Karty, two tabs of equal width
  that keep a chosen set (owner decision, 2026-11-04, set dropped from the bar
  2026-11-05). Sets are chosen in one place: a column beside the list on a
  wide screen, a shelf above it on a narrow one. "Produkty" opens the kind and language menu; kinds come as five
  shelves (Boostery, Booster Boxy, Elite Trainer Box, Kolekcje i puszki,
  Talie), each shelf's exact kinds one step further. The tab keeps its name;
  a badge counts the chosen kind and language (owner decision, 2026-11-05).
  The tabs are slim on a desktop and wider on a phone, where the query takes
  the whole bar while it is typed.
- Public pages read only the local database; shops and Cardmarket are fetched
  by background jobs.
- The legacy singles catalogue, valuation and trade pages have been removed.
  Singles and trades will be rebuilt on the buying-guide domain; the former
  `/cards/:tcgdex_id` and `/trade` URLs redirect permanently to the Polish
  home page, or with their old filters to the Polish list they named.

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
- Local first: copy, number and date formats for each region's buyers.

## Accessibility & Inclusion

- Interface in Polish, Hungarian, Swedish, Croatian, European Portuguese, Dutch, Czech and English; mobile-first and responsive.
- Semantic markup, keyboard access, visible focus, sufficient contrast,
  48px touch targets, no horizontal overflow at 390px.
- Verdicts never rely on colour alone (text label plus icon).
