# TCG Cheap — Buying and Trading Guide

- Updated: 2026-10-30
- Sources: Product-owner direction, 2026-10-30; project code
- Raw: N/A — product specification

**Current product north star.** It supersedes the
[Detailed MVP Implementation Plan](mvp-implementation-plan.md) and
[Sealed Buying Model v1](../architecture/sealed-buying-model-v1.md).

## Purpose

TCG Cheap is a deliberately simple web app for Pokémon TCG fans in Poland. It
answers two questions:

1. **Buying:** is this sealed product (booster, bundle, booster box, ETB, …) a
   good buy at this price, and where is it cheapest right now?
2. **Trading:** is this trade of single cards fair?

Simplicity beats completeness. Every feature, table and screen must earn its
place; prefer deleting to preserving. No accounts, no review queues, no
versioned pricing models, no acquisition budgets.

## Phase 1 — buying guide (sealed), polished first

- **Catalogue in code.** The curated list of official English-language sealed
  products sold in Polish shops lives in `TcgCheap.Sealed.Catalogue`. Adding a
  product means editing that file and deploying. Each product has match rules
  for shop titles and optional EANs.
- **Shops.** Six Polish shops with public WooCommerce Store APIs (LootQuest,
  CardzHouse, BoosterPoint, PokeBooster, Boosterland, Colligere) are fetched
  once a day each. Offers are matched to catalogue products by EAN, otherwise
  by strict title rules; an unmatched offer is better than a wrong one.
- **History.** After every fetch, each product's lowest in-stock price for the
  day is stored.
- **Verdict — realistic, never MSRP.** MSRP is misleading when regular shops
  have no stock, so it is not used at all. The typical price is the median of
  the daily lowest in-stock price over the last 30 days. With fewer than 7 such
  days the verdict is "Za mało danych"; with no current stock it is "Brak w
  sklepach" with the last known price. Otherwise the cheapest current offer is
  rated "Dobra cena" (≤ 95% of typical), "Normalna cena" (≤ 110%) or "Drogo",
  and the page shows the same thresholds in złoty so a price seen in a
  physical shop can be judged too.
- **UI in Polish.** `/` lists and searches products with the cheapest current
  price and verdict; `/produkty/:slug` shows the verdict, thresholds, all
  offers (in stock first, cheapest first, with check age and outbound links)
  and a 90-day price chart. Prices exclude shipping.
- **Admin.** One read-only page shows per-shop fetch state and the unmatched
  offers that may deserve a catalogue entry.

## Phase 2 — trading guide (singles), next

Singles keep the existing card catalogue (TCGdex identity), daily Cardmarket
bulk prices and the `/trade` calculator until phase 2 simplifies them under
the same principles.

## Constraints

- Elixir, Phoenix LiveView, Ash, PostgreSQL, Oban; one deployable app.
- Public pages read only the local database; shops are fetched in background
  jobs with fixed hosts, bounded pages, timeouts and strict validation of
  untrusted responses.
- Never fabricate prices; show "no data" honestly.

## See Also

- [Application Foundation](../architecture/application-foundation.md)
