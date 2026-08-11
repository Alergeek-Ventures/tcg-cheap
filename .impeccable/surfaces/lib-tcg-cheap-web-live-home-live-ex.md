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
- **Completed correction:** The former `99023f3` focus-loss path is fixed. The shared external 250ms `CardAutocomplete` hook keeps the same focused input node, query, caret/selection, and focus through server result updates; IME composition pauses search and searches once after compositionend, and Escape cancels pending debounce. The hook is shared with `/trade`; Phase 3 is complete, while the overall MVP proceeds to sealed catalogue/acquisition.

## Proof and content

- Exact image, name, set, and collector number; stable TCGdex identity remains in the route and result data, while accessible exact identity uses the card name, set, and collector number.
- Current local EUR estimate when present, otherwise `Price unavailable`.
- Plain `Updated …` or `May be outdated` freshness evidence from the existing seven-day `TcgCheap.Pricing.Singles.Freshness` policy.
- One clear `View price` action; `/trade` is entered through Singles/card-detail actions, not as a third homepage feature.
- Usable autocomplete is implemented: preserve query, caret/selection, focus, and composition across LiveView updates; use combobox/listbox semantics with stable `card-option-UUID` IDs, direct streamed `role=option` children, exactly one visible `aria-selected` active option, wrapping ArrowUp/ArrowDown, exact active Enter navigation, Escape close retaining query/focus, validated option click/touch navigation, and query-specific screen-reader status. Accessible names reference visible name/set/rarity/price/update IDs, with no nested interactive control.
- The active option is visibly ruled. The bounded listbox uses `min(45svh, 32rem)` and scrolls internally; the hook keeps the active option in view without scrolling the page or input away. Results retain only the bounded max-10 records needed to reinsert adjacent stream items when the active assign changes.
- Keep legal/methodology honesty, exact-printing correctness, accessibility, and required caveats, but put technical detail behind concise secondary disclosure where feasible.

## Constraints

- Singles is the only working catalogue; switching to Sealed clears and hides singles results and states that sealed is unavailable.
- Local-only debounced exact-printing search; normalize and cap queries; no provider calls in render.
- Validation is complete with LiveView regression coverage and real desktop/mobile browser typing one character at a time, focus/caret checks after every update, keyboard selection/Escape, composition-event simulation, no console errors, and no horizontal overflow.
- Stream results with stable IDs, canonical low WebP images, no-referrer hotlinking, and an honest missing-image fallback.
- Light, bright counter scene; square geometry; touch targets at least 48px; no horizontal overflow. Use mobile-first stacking, the 4/8/12/16/24/32/48/64px spacing scale on an 8px core grid, and reduce mobile spatial density by about 33-50%.
- Current colors, fonts, and warm square direction are approved; simplify information density and copy rather than replacing the visual system.
- Use a canonical 1152px/72rem desktop content container (within 1100-1200px), 48px major section spacing, and 24-32px desktop panel spacing. Body text is 16px, metadata is at least 14px, prose is at most 70ch, normal text contrast is at least 4.5:1, and focus is clear.
- Keep Barlow Condensed 700 as the documented brand/asset exception because only the approved 700 asset exists; Azeret Mono is body/evidence and no third typeface is introduced.
- Keep one primary task/action hierarchy with generous space around it. Repeated result-row `View price` CTAs are contextual, not competing page-level primaries.

## Direction

Direction 7 from seed `ca73501c`: a card-shop valuation bench/laboratory comparison bench using warm board, tissue, and ink materials. Evidence slips replace archive labels; Barlow Condensed carries action hierarchy and Azeret Mono carries measurements.

## Memorable moment

The result reads like a physical bench slip: image and exact identity on one side, the estimate and one decisive “View price” action on the other.

## Unresolved decisions

- Sealed catalogue and pricing remain intentionally unavailable until that phase is implemented.
- Trade controls, EUR-plus-PLN totals/difference, and explicit canonical share/copy now exist inside Singles; trade is not a third homepage feature.
- The autocomplete and Phase 3 trade batch are complete. Sealed remains unavailable and Phase 4 is next.
- Do not add dead sealed controls or imply finished trade capability.
