---
version: 1
slug: "lib-tcg-cheap-web-live-trade-live-ex"
primary_target: "lib/tcg_cheap_web/live/trade_live.ex"
related_targets: ["lib/tcg_cheap_web/live/home_live.ex", "lib/tcg_cheap_web/live/card_detail_live.ex", "assets/js/hooks/card_autocomplete.js", "assets/css/app.css"]
---

# Trade decision bench

- **Scope:** `/trade` inside Singles
- **Mode:** Operate
- **Audience:** A collector making a quick in-store Pokémon singles trade on a phone, with desktop support.
- **Job:** Stage exact printings on two neutral sides, inspect honest EUR and PLN evidence, and judge an estimated difference without pretending to freeze a price or save a server trade.
- **Actions:** Restore deterministic URL state; search one local card at a time; explicitly add left or right; increment, decrement, or remove; open row detail while preserving the trade; follow a pending CardDetail pick; share through the explicit canonical copy control.
- **Proof:** Stable TCGdex IDs and quantities only in `left=id:qty,...&right=id:qty,...`; exact identity in rows; EUR-only unit/row values; EUR plus Decimal PLN side totals and complete differences; incomplete known subtotals show both currencies plus `?`; `Updated today/yesterday/N days ago`; stale/outdated, fetching, and failure states; exact NBP rate/date/relative age and pending/failed/no-cache states. Unknown valid IDs remain removable and unpriced.
- **Constraints:** URL-only state, no names/prices/internal UUIDs/server trade records; safe bounded parsing, duplicate merge, deterministic sorting, untrusted events rejected, no provider HTTP in public paths, no sealed capability, no auth, no snapshots. Controls are square and at least 44px; no 390px horizontal overflow.
- **Direction:** Extend the warm square card-shop valuation bench. Use a selected-card staging strip with two explicit side actions, symmetric ruled ledgers, desktop two-column layout, and stacked mobile layout. Preserve Barlow Condensed action hierarchy, Azeret Mono evidence at `.75rem`, bench/paper/ink/orange palette, and no rounded/glass/gradient treatment.
- **Memorable moment:** A card selected once becomes an exact, removable paper row on either side, while honest `€x + ?` evidence makes uncertainty visible instead of hiding it.
- **Completed boundary:** TradeLive reads the latest cached NBP rate locally during render, subscribes before enqueueing once per connected LiveView, consumes PubSub completion/failure, retains cached conversion while pending/failed, and rejects malformed/noncanonical/nonfinite/future/older rate messages. `TradeShare` builds an absolute URL from server-derived canonical `Composition.to_path`; it excludes names, prices, UUIDs, pick/unknown parameters, fragments, and noncanonical ordering. Clipboard fallback cleans up and restores focus, protects overlapping/destroyed instances, exposes one accessible feedback live region, and ignores stale/malformed async results. Sealed remains unavailable; Phase 4 is next.
