# SEO strategy

The durable plan for organic acquisition of Polish buyers of sealed Pokémon
TCG products and English singles. Experiments and their results live in
[experiments.md](experiments.md). Product rules come from
[PRODUCT.md](../../PRODUCT.md); this file never overrides them.

## Goal and measure

Polish visitors who arrive from a search engine and go on to a shop.

- Outcome: sessions with `shop_link_clicked` whose channel is
  `Organic Search` (PostHog project "TCG Cheap", app URL `https://tcg.cheap`;
  data since 2026-11-02; exclude bots and the test-account cohort).
- Leading signals, in order of delay: valid rich-result items and indexed
  pages in Google Search Console (days to weeks), impressions and clicks
  (weeks), organic sessions per landing-page type (`/produkty/`,
  `/rozszerzenia/`, `/rozszerzenia/*/karty/`).
- "Discovered" in GSC is not "indexed"; a merge or deploy is not an effect.
  Judge an experiment only on its own evaluation date, never day to day.

## What buyers ask, and what we can answer truthfully

| Question | Page that answers it | Our verified data |
| --- | --- | --- |
| "<product> cena / najtaniej" | product page | in-stock offers from Polish shops, daily |
| "czy to dobra cena" | product page | verdict against other Polish shops and the 30-day usual price |
| "<set> drop rate / lista kart" | set page, single booster page | recorded pull rates, TCGdex card lists |
| "<card> <number> cena" | card page | in-stock ungraded offers, Cardmarket reference |
| delivery to Poland | offers list | shop's cheapest delivery and free-delivery threshold where published |
| contents of a box | product page | only recorded, sourced contents; never guessed |

Never: MSRP as the official price (REBEL is a wholesaler's suggested price),
guessed contents, opening/investment returns, invented ratings or reviews,
thin mass-generated pages, keyword stuffing.

## Indexing rules (current)

- Product, set and home pages: `index, follow`; filtered or searched lists
  `noindex, follow`.
- Card pages: indexed and in the sitemap only while they have an in-stock,
  ungraded offer (PR #99); otherwise `noindex, follow`, still 200 and linked.
- Set pages: in the sitemap when a sealed product or a card of the set is in
  stock (E2); always `index, follow` unless filtered or searched.
- Structured data mirrors visible content: `Product` + `AggregateOffer` only
  from current in-stock offers; `BreadcrumbList` on product, set and card
  pages; `WebSite` on the home page.

## Backlog

Ranked by expected effect on the measure, evidence first. Pick one experiment
at a time; move the running one forward before starting another.

1. Card pages: `Product` + `AggregateOffer` structured data (deployed,
   waiting for evaluation, see experiments.md, E1).
2. Set pages of cards in stock into the sitemap (E2, deployed 2026-11-05,
   waiting for evaluation).
3. Card pages are leaves: they link only to their set. Link a card to the
   sealed products whose set contains it and to the set's other cards with
   offers, so crawlers reach indexable cards outside the set page.
4. Set and card pages share the home link-preview image; give set pages
   their own (set logo plus the booster answer), as product pages have.
5. Sitemap has no `lastmod`; add it from the offers' last price change only
   if Google shows crawl lag on changed pages in GSC.

## Access (checked 2026-11-04; repo, GitHub, production and PostHog rechecked 2026-11-05)

- Repo, worktrees, GitHub push/PR/CI: yes. Merging to `main` deploys to
  production automatically (Coolify), so merge is the owner's decision.
- Production: public HTTP; product data read through the `tcg-cheap-prod`
  MCP (read tools only for SEO work).
- PostHog: project "TCG Cheap" readable.
- Google Search Console: not reachable from the agent's browser (not signed
  in). The owner reads it and shares numbers.
