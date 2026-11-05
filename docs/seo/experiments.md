# SEO experiments

One entry per change. Update the entry in place as it moves from plan to PR,
merge, deploy and evaluation. Plan and measure: [strategy.md](strategy.md).

## E0 — Cards without an offer out of the index

- Hypothesis: about 8.5k card URLs, many without anything to buy, dilute
  crawling of a new domain; keeping only cards with an answer in the sitemap
  lets Google spend its crawl on pages that answer "<card> cena".
- Source: production sitemap on 2026-11-04 (9,251 URLs, 8,553 cards; 12 of 20
  sampled cards had no in-stock ungraded offer). Owner decision 2026-11-04.
- Change: PR #99, merged 2026-11-04 (`162ffb4`), deployed by CI.
- Verified on production 2026-11-04: sitemap 6,233 URLs (5,484 cards, 653
  products, 95 sets, home); an offer-less card (Crown Zenith 003 Bellossom)
  answers 200 with `noindex, follow`; a card with an offer is `index, follow`.
- Metric: GSC indexed vs. "Discovered – currently not indexed" for card URLs.
- Evaluate: 2026-11-25. Card count moves with stock; a drop is not a bug.
- Result: pending. GSC baseline from the owner (2026-11-04): 0 clicks,
  indexing in progress.

## E1 — Product structured data on card pages

- Hypothesis: sealed product pages already carry `Product` + `AggregateOffer`
  and Google reports them as valid product snippets. Card pages with an offer
  (5,484 in the sitemap) carry only `BreadcrumbList`, so they cannot show a
  price in results for "<card> <number> cena". Adding the same block makes
  them eligible, which should raise their click-through once they rank.
- Sources: production HTML on 2026-11-04 (card pages: `BreadcrumbList` only;
  product pages: `Product` + `AggregateOffer`); GSC "Product snippets" shared
  by the owner on 2026-11-04: 2 valid items, only optional warnings
  (`aggregateRating`, `review` — left alone; we have no real reviews).
- Change: card pages with an answer get `Product` (name "<card> <number>
  <set>", description as the meta description, our mirrored card image) and
  `AggregateOffer` (PLN, low/high and count) from the current in-stock,
  ungraded offers of the answer's variant, so the low price equals the "od"
  price the page and its description state. No offer, no block.
  PR #102 (branch `feat/seo-card-product-structured-data`).
- Baseline (2026-11-04): GSC product snippets valid items 2; organic search
  sessions since 2026-11-02: 1 (a product page), sessions with
  `shop_link_clicked` from organic search: 0.
- Metrics: GSC "Product snippets" valid items (expect card URLs to appear as
  they are indexed) and invalid items (must stay 0); later, GSC impressions
  and clicks for `/karty/` URLs and PostHog organic sessions landing on card
  pages with `shop_link_clicked`.
- Evaluate: first check one week after deploy (valid/invalid items), effect
  three weeks after deploy.
- State: PR #102 merged 2026-11-04 (`80aee1e`) and deployed. Verified on
  production 2026-11-04 (30/30 sampled indexable cards carry `Product` with
  `lowPrice` equal to the "od" price; 5/5 noindex cards carry none) and
  2026-11-05 (4/4 sampled cards still do).
- Evaluate: 2026-11-11 (GSC product snippets), 2026-11-25 (effect).
- Result: pending. PostHog 2026-11-02 – 2026-11-05 06:00 UTC: organic search
  sessions 1 (2026-11-02), with `shop_link_clicked` 0 — still the baseline.

## E2 — Set pages of cards in stock into the sitemap

- Hypothesis: the sitemap lists a set page only when one of the set's sealed
  products is in stock, a rule from before singles. Sets whose cards are in
  stock but whose boosters are not (mostly Sun & Moon era and promos) are
  missing, so their in-stock cards reach Google only as loose sitemap URLs,
  without the set page that links them. Submitting those set pages gives each
  of those cards a crawled hub and lets "<set> lista kart / ceny" match a page.
- Sources: production on 2026-11-05: sitemap 6,228 URLs (96 sets, 678
  products, 5,453 cards). Crawling the 96 submitted set pages reached 4,765
  of the 5,453 cards; the other 688 belong to sets missing from the sitemap
  (e.g. Cosmic Eclipse 115 cards, Team Up 77, Burning Shadows 73, SVP Black
  Star Promos 70). Those set pages answer 200, `index, follow`, canonical to
  themselves, and list their cards.
- Change: the sitemap adds the set page of every card it submits, under the
  name the card path uses; the sealed rule is unchanged. Branch
  `fix/seo-sitemap-card-sets`. On a copy of dev data: sets 88 → 118, products
  and cards unchanged; 30/30 added set pages 200, `index, follow`,
  self-canonical, linking cards; card sets without their set page 30 → 0.
- Baseline (2026-11-05): 688 submitted cards (12.6 %) without a submitted set
  page; GSC unavailable to the agent; organic sessions 1, organic
  `shop_link_clicked` 0.
- Metrics: after deploy, every card set in the sitemap (check on production);
  GSC indexed set pages and card URLs of the added sets vs. "Discovered –
  currently not indexed"; later organic sessions landing on `/rozszerzenia/`.
- Evaluate: production check right after deploy; GSC 2026-11-19; effect
  2026-12-03. Confounded with E0 and E1 on card indexing: compare the added
  sets' cards with the rest.
- State: PR #109 merged 2026-11-05 on the owner's instruction (`e0dcc2a`),
  deployed by CI. Verified on production 2026-11-05: sitemap 6,257 URLs
  (125 sets, 678 products, 5,453 cards, no duplicates); 29/29 added set
  pages 200, `index, follow`, self-canonical, linking cards; submitted cards
  without their set page submitted: 0.
- Result: pending.
