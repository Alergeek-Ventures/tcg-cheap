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
  Branch `feat/seo-card-product-structured-data`.
- Baseline (2026-11-04): GSC product snippets valid items 2; organic search
  sessions since 2026-11-02: 1 (a product page), sessions with
  `shop_link_clicked` from organic search: 0.
- Metrics: GSC "Product snippets" valid items (expect card URLs to appear as
  they are indexed) and invalid items (must stay 0); later, GSC impressions
  and clicks for `/karty/` URLs and PostHog organic sessions landing on card
  pages with `shop_link_clicked`.
- Evaluate: first check one week after deploy (valid/invalid items), effect
  three weeks after deploy.
- State: PR in review; not merged, not deployed.
- Result: pending.
