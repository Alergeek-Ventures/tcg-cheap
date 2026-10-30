# TCG Cheap — Buying and Trading Guide

- Updated: 2026-10-30
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
  in-stock offers in Polish shops, falling back to the Cardmarket trend.
- **Honest gaps.** Missing data is shown as missing; prices are never invented.
- **Polish first.** Buying-guide copy, number and date formats are Polish.
  Prices exclude shipping.
- **Local reads.** Public pages read only the local database; external sources
  are fetched by background jobs.

## Phase 1 — buying guide (sealed), live

- **Catalogue from Cardmarket.** Every sealed Pokémon product in Cardmarket's
  public non-singles product file (≈4,400; Coins and Lots excluded) is
  imported daily with its kind, a set name derived from products sharing a
  Cardmarket expansion, and the latest Cardmarket trend/low/avg in EUR.
  Nothing is curated in code; products that disappear from the file are kept.
  Product images come from matched shop offers.
- **Shops.** Six Polish shops with public WooCommerce Store APIs — LootQuest,
  CardzHouse, BoosterPoint, PokeBooster, Boosterland, Colligere — are fetched
  once a day each. Offers are matched to products automatically by strict
  title rules (and by EANs learned from manual assignments); an unmatched
  offer is better than a wrong one.
- **Manual fixes.** An administrator can assign an unmatched or mismatched
  offer to any catalogue product, or clear that assignment. Automatic matching
  never overwrites a manual assignment.
- **History.** After every shop fetch and catalogue import, each product's
  lowest in-stock Polish price, the number of shops with stock, and the
  Cardmarket trend are stored for the day.
- **Verdict.** The typical price is the median of the daily lowest in-stock
  price over the last 30 days when at least 7 such days exist; otherwise the
  Cardmarket trend converted with the latest NBP EUR/PLN rate. The cheapest
  current in-stock offer is rated **Dobra cena** (≤ 95% of typical),
  **Normalna cena** (≤ 110%) or **Drogo**. Thresholds are whole złoty and are
  shown on the page, so a price seen in a physical shop can be judged too.
  Without current stock the verdict is **Brak w sklepach** (with the last
  known price); with stock but no typical price it is **Za mało danych**.
- **Pages.** `/` lists and searches products (filter by kind; in stock first,
  then newest) with the cheapest current price and verdict.
  `/produkty/:slug` shows the verdict and thresholds, every current offer
  (in stock first, cheapest first, with links to the shop), the Cardmarket
  price, and a 90-day price chart.
- **Admin.** `/admin/buying-guide` shows each shop's last fetch, matched and
  in-stock counts, current unmatched offers, and manual assignments.

## Phase 2 — trading guide (singles), next

Singles currently use the TCGdex card catalogue, daily Cardmarket bulk prices
mapped to exact printings, `/cards/:tcgdex_id` detail pages and the `/trade`
calculator (English UI). Phase 2 will simplify this part under the same
principles and bring it into the Polish guide. Until then it is maintained
as-is; see [Application Foundation](../architecture/application-foundation.md).

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
