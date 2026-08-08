---
version: 1
slug: "lib-tcg-cheap-web-live-home-live-ex"
primary_target: "lib/tcg_cheap_web/live/home_live.ex"
related_targets: ["assets/css/app.css", "lib/tcg_cheap_web/components/layouts/root.html.heex"]
---

# Home decision surface

- **Scope:** `/`
- **Mode:** Operate
- **Audience:** A person checking a Pokémon single at a card-shop counter on a phone.
- **Job:** Decide whether an exact printing is worth investigating before a trade.
- **Actions:** Choose Singles (default) or Sealed products; search exact printing locally; verify identity and estimate; open value details.

## Proof and content

- Exact image, name, set, collector number, and TCGdex identity.
- Current local EUR estimate when present, otherwise `?` and an honest unpriced state.
- Existing seven-day `TcgCheap.Pricing.Singles.Freshness` evidence: fresh or stale.
- Clear value-details action; no trade control before Phase 3.

## Constraints

- Singles is the only working catalogue; switching to Sealed clears and hides singles results and states that sealed is unavailable.
- Local-only debounced exact-printing search; normalize and cap queries; no provider calls in render.
- Stream results with stable IDs, canonical low WebP images, no-referrer hotlinking, and an honest missing-image fallback.
- Light, bright counter scene; square geometry; touch targets at least 44px; no horizontal overflow.

## Direction

Direction 7 from seed `ca73501c`: a card-shop valuation bench/laboratory comparison bench using warm board, tissue, and ink materials. Evidence slips replace archive labels; Barlow Condensed carries action hierarchy and Azeret Mono carries measurements.

## Memorable moment

The result reads like a physical bench slip: image and exact identity on one side, the estimate and one decisive “Open value details” action on the other.

## Unresolved decisions

- Sealed catalogue and pricing remain intentionally unavailable until that phase is implemented.
- Trade controls remain deferred to Phase 3.
