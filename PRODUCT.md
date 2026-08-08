# Product

<!-- impeccable:product-schema 1 -->

> The facts in this record are collectively inferred from the explicit authoritative MVP plan and the current code/tests because a structured product interview was unavailable. They are not invented.

## Platform

web

## Users

- English-speaking Pokémon TCG players and collectors evaluating common in-shop singles trades.
- English-speaking Polish sealed-product buyers evaluating products and prices.
- The current public surface focuses on singles.

## Product Purpose

Provide locally searchable exact Pokémon TCG printings, honest aggregate Cardmarket estimates, and context for understanding trades and sealed-product prices. The minimal Home search-and-price baseline is now backed by a corrected, usable local autocomplete; Phase 3 trade foundations are the next priority.

The product has exactly two top-level customer features: **sealed product price comparison** and **singles price comparison**. Singles includes composing a trade and calculating the difference; trade is not a third equal homepage product category.

## Positioning

Thesis-validation product built around local cached data and transparent uncertainty. It does not fabricate seller counts, shipping costs, or false precision.

## Operating Context

- Mobile-first checks while making an in-store trade.
- Desktop research for Pokémon TCG singles and sealed products.
- Public use does not require public accounts.

## Capabilities and Constraints

- Phoenix LiveView application using Elixir, Ash, and PostgreSQL.
- Singles are searched and identified by exact printing, including set and collector number plus distinguishing metadata.
- Singles estimates are in EUR and target seven-day freshness.
- PLN sealed-product pricing and later PLN trade conversion are planned, but are not part of the current singles-focused surface.
- Provider calls must happen outside normal request paths; public requests should primarily read local cached data.
- The public exact-printing search surface is the local-only Home LiveView over the cached catalogue. Home defaults to Singles and presents a compact wordmark with `Compare Pokémon prices`, a direct `Find a card` search, and one-column exact-printing price rows with image, name, set, collector number, optional rarity, price, update state, and one solid `View price` CTA. Its colocated 250ms input hook preserves the focused input node, query, caret/selection, and focus through result updates; composition pauses search and searches once after compositionend, while Escape cancels a pending debounce.
- Home has an accessible Singles/Sealed mode switch. Sealed remains an honest unavailable state because no sealed catalogue or estimate capability was added.
- Search preloads the active `tcgdex_cardmarket_v1` valuation relationship with the printing, avoiding an N+1 valuation read. Estimates explicitly distinguish current/fresh, stale, and unpriced states.
- Home exposes full policy, methodology, and non-affiliation caveats in collapsed `How prices work` details, uses terse shipping language, 44px-class touch targets, keyboard semantics, and one reveal motion with a reduced-motion fallback.
- The 2026-08-08 minimal Home correction remains the presentation baseline. It uses plain collector language: `€…` or `Price unavailable`, `Updated …` plus `May be outdated`, and no idle copy. Rows do not expose TCGdex, legality, policy, freshness, or local-data jargon. The completed autocomplete uses real combobox/listbox semantics, stable `card-option-UUID` stream IDs, bounded ten-option results, visible first/active options, wrapping ArrowUp/ArrowDown, exact active Enter selection, Escape close with query/focus retained, validated touch/click selection, and query-specific live status.
- The approved colors, fonts, and warm square visual direction remain; this correction targets density, copy, jargon, and CTA clarity rather than replacing the visual system.
- The planned sealed-product experience, trade calculator, and the associated public and internal workflows are also not yet represented in the current route/UI surface. The autocomplete blocker is fixed and validated; Phase 3 URL-backed trade foundations are next. No trade or sealed capability was added.
- Missing or stale data is preferable to fabricated data or silently exceeding acquisition constraints.

## Evidence on Hand

- The authoritative MVP implementation plan: `knowledge-base/wiki/product/mvp-implementation-plan.md`.
- Current application code and tests in `lib/` and `test/`.
- No testimonials or customer proof are available.
- This thesis-validation product displays canonical TCGdex-hosted card images for exact-printing identification. Missing images retain an honest fallback. The site is explicitly unofficial and non-affiliated; it makes no claim that Pokémon art is independently licensed.

## Product Principles

- Exact identity over approximate matching.
- Honest uncertainty over fabricated precision.
- Fast, local-first reads over synchronous provider dependence.
- Stale data over a blank result when the data is clearly labeled.
- Operational restraint over unnecessary acquisition cost or complexity.

## Accessibility & Inclusion

- English-only MVP.
- Mobile-first and responsive, with desktop support.
- Keyboard-accessible controls and semantic markup.
- LiveView state changes must be communicated accessibly.
- Regression coverage and real browser validation type one character at a time, verify focus after every update, exercise keyboard selection/Escape and composition-event behavior, and cover mobile/desktop with no console errors or horizontal overflow. The completed pass also keeps the bounded listbox internally scrollable without moving the page or input.
