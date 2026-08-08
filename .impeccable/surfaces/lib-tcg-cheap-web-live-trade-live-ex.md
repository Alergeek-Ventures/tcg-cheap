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
- **Job:** Stage exact printings on two neutral sides, inspect honest EUR evidence, and judge an estimated difference without pretending to freeze a price or save a server trade.
- **Actions:** Restore deterministic URL state; search one local card at a time; explicitly add left or right; increment, decrement, or remove; open row detail while preserving the trade; follow a pending CardDetail pick; manually copy the URL when sharing is needed.
- **Proof:** Stable TCGdex IDs and quantities only in `left=id:qty,...&right=id:qty,...`; exact identity in rows; current EUR unit/row values; `Updated today/yesterday/N days ago`; stale/outdated, fetching, and failure states; incomplete `€x + ? (N unpriced)` totals; estimate-only difference when incomplete. Unknown valid IDs remain removable and unpriced.
- **Constraints:** URL-only state, no names/prices/internal UUIDs/server trade records; safe bounded parsing, duplicate merge, deterministic sorting, untrusted events rejected, no provider HTTP in public paths, no sealed capability, no auth, no snapshots. Controls are square and at least 44px; no 390px horizontal overflow.
- **Direction:** Extend the warm square card-shop valuation bench. Use a selected-card staging strip with two explicit side actions, symmetric ruled ledgers, desktop two-column layout, and stacked mobile layout. Preserve Barlow Condensed action hierarchy, Azeret Mono evidence, bench/paper/ink/orange palette, and no rounded/glass/gradient treatment.
- **Memorable moment:** A card selected once becomes an exact, removable paper row on either side, while honest `€x + ?` evidence makes uncertainty visible instead of hiding it.
- **Unresolved:** NBP EUR/PLN rate/resource/acquisition/display; explicit share/copy control (the deterministic URL is only manually copyable); sealed remains unavailable. Phase 3 steps 1–3 and EUR/stale/unvalued/incomplete/responsive foundations are implemented, but Phase 3 is not complete.
