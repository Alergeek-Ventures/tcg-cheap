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

Provide locally searchable exact Pokémon TCG printings, honest aggregate Cardmarket estimates, and context for understanding trades and sealed-product prices. The completed homepage batch makes that decision surface concrete without claiming the unfinished trade or sealed capabilities.

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
- The public exact-printing search surface is built as a local-only Home LiveView over the cached catalogue. Home defaults to Singles and presents a card-shop valuation bench: direct search, image-backed identity, discriminators, a local estimate, evidence, and one value-details action.
- Home has an accessible Singles/Sealed-products mode switch. Sealed is visible as an honest unavailable state because no sealed catalogue or estimate capability was added in this batch.
- Search preloads the active `tcgdex_cardmarket_v1` valuation relationship with the printing, avoiding an N+1 valuation read. Estimates explicitly distinguish current/fresh, stale, and unpriced states.
- Home exposes the valuation methodology and disclaimer, and uses 44px-class touch targets, keyboard semantics, and one reveal motion with a reduced-motion fallback.
- Home is a functional foundation, not product-finished. The next Home pass must be minimal, use plain collector language, and provide clear CTAs for search/select, comparing a price, or adding a single to a trade. Use the fewest words needed for simple actions and states; prefer `Price unavailable` and `Updated …` over internal jargon. Keep technical evidence, policy/provider, freshness, local-data, IDs, and longer methodology in concise secondary disclosure where feasible while retaining legal/methodology honesty, exact-printing correctness, accessibility, and required caveats.
- The approved colors, fonts, and warm square visual direction remain; this correction targets density, copy, jargon, and CTA clarity rather than replacing the visual system.
- The planned sealed-product experience, trade calculator, and the associated public and internal workflows are also not yet represented in the current route/UI surface.
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
