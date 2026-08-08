---
version: 1
slug: "lib-tcg-cheap-web-live-home-live-ex"
primary_target: "lib/tcg_cheap_web/live/home_live.ex"
related_targets: ["assets/css/app.css", "lib/tcg_cheap_web/components/layouts/root.html.heex"]
---

# Home decision surface

This surface is intentionally distilled for ordinary collectors: plain card search first,
compact exact-printing result rows, and one clear `View price` action. Stable TCGdex identity
remains in the route and result data; accessible exact identity uses the card name, set, and
collector number. Methodology, policy, and non-affiliation caveats remain available in
progressive disclosure.

- **Scope:** `/`
- **Mode:** Operate
- **Audience:** A person checking a Pokémon single at a card-shop counter on a phone.
- **Job:** Decide whether an exact printing is worth investigating before a trade.
- **Actions:** Search/select a single (default); verify identity and price; open value details. Sealed comparison is the second top-level feature when implemented. Trade composition belongs inside Singles and is not a third homepage category.
- **Current blocker:** The `99023f3` minimal Home baseline loses input focus on each typed letter. This is the highest-priority public UX/correctness correction before Phase 3 or later roadmap work; no implementation is claimed yet.

## Proof and content

- Exact image, name, set, and collector number; stable TCGdex identity remains in the route and result data, while accessible exact identity uses the card name, set, and collector number.
- Current local EUR estimate when present, otherwise `Price unavailable`.
- Plain `Updated …` or `May be outdated` freshness evidence from the existing seven-day `TcgCheap.Pricing.Singles.Freshness` policy.
- One clear `View price` action; no trade control before Phase 3.
- Usable autocomplete is a release requirement: preserve query, caret/selection, focus, and IME/composition across LiveView updates; never replace the input or steal focus; update results without moving focus; use combobox/listbox semantics, stable IDs, ArrowUp/ArrowDown, visible active option, Enter to open the exact printing price detail, Escape to close, touch/click selection, and screen-reader status.
- Keep legal/methodology honesty, exact-printing correctness, accessibility, and required caveats, but put technical detail behind concise secondary disclosure where feasible.

## Constraints

- Singles is the only working catalogue; switching to Sealed clears and hides singles results and states that sealed is unavailable.
- Local-only debounced exact-printing search; normalize and cap queries; no provider calls in render.
- Validate with LiveView regression coverage where possible and real desktop/mobile browser typing one character at a time, focus checks after every update, keyboard selection/Escape, no console errors, and no horizontal overflow.
- Stream results with stable IDs, canonical low WebP images, no-referrer hotlinking, and an honest missing-image fallback.
- Light, bright counter scene; square geometry; touch targets at least 44px; no horizontal overflow.
- Current colors, fonts, and warm square direction are approved; simplify information density and copy rather than replacing the visual system.

## Direction

Direction 7 from seed `ca73501c`: a card-shop valuation bench/laboratory comparison bench using warm board, tissue, and ink materials. Evidence slips replace archive labels; Barlow Condensed carries action hierarchy and Azeret Mono carries measurements.

## Memorable moment

The result reads like a physical bench slip: image and exact identity on one side, the estimate and one decisive “View price” action on the other.

## Unresolved decisions

- Sealed catalogue and pricing remain intentionally unavailable until that phase is implemented.
- Trade controls remain deferred to Phase 3.
- The autocomplete correction precedes Phase 3; do not add dead trade or sealed controls while fixing it.
- Do not add dead controls or imply sealed/trade capability before those capabilities are implemented.
