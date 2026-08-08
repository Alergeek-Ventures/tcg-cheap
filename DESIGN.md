---
name: TCG Cheap Decision Surface
description: A bright card-shop valuation bench for deciding about exact Pokémon TCG singles.
colors:
  box-board: "#c86c3f"
  box-board-dark: "#a94f2f"
  ink: "#171614"
  tissue: "#f6f0df"
  sage: "#a9b69a"
  indigo: "#9fa8c8"
  lilac: "#c1b1c9"
  sunfade: "#e5bf70"
  bench: "#f3ead7"
  bench-light: "#fffaf0"
  paper: "#fffdf8"
  orange: "#c64e2d"
  muted: "#6d6256"
typography:
  display:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "clamp(2.2rem, 6vw, 4rem)"
    fontWeight: 700
    lineHeight: 0.83
    letterSpacing: "-0.045em"
  body:
    fontFamily: "Azeret Mono, ui-monospace, monospace"
    fontSize: "0.75rem"
    fontWeight: 400
    lineHeight: 1.7
  label:
    fontFamily: "Azeret Mono, ui-monospace, monospace"
    fontSize: "0.75rem"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  square: "0"
spacing:
  unit: "1rem"
  container: "62rem"
components:
  decision-header:
    backgroundColor: "{colors.bench}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "1rem clamp(1rem, 4vw, 3.5rem)"
  mode-switch:
    backgroundColor: "{colors.bench}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    minHeight: "2.8rem"
  decision-search:
    backgroundColor: "{colors.bench-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "clamp(1rem, 3vw, 1.75rem)"
  price-row:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "0.75rem"
  archive-active-label:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.tissue}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "0.45rem 0.55rem"
  price-methodology:
    backgroundColor: "{colors.tissue}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "0.75rem 1rem"
  printing-label:
    backgroundColor: "{colors.tissue}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "1rem"
  archive-chip:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "0.3rem 0.4rem"
---

# Design System: TCG Cheap Decision Surface

## Overview

**Creative North Star: "The Card-Shop Valuation Bench"**

Home is a light, bright counter scene: a warm bench supports compact paper-like price rows, black ink rules, and orange action emphasis. It is practical and decision-oriented rather than promotional. Condensed display type makes the call legible at a glance; monospaced data keeps identity and supporting detail precise.

The Home decision-world favors square geometry, strong ruled edges, warm bench/paper/ink/orange color blocks, and a distilled vertical price-row system. It rejects generic rounded marketplace grids, glass surfaces, and decorative gradients. Search is the primary action; current, outdated, and unavailable states remain visible in plain collector language.

The `.archive-world` remains the visual contract for card detail. The archive world was scoped away from Home, not removed globally.

**Key Characteristics:**
- Bright card-shop bench, paper, ink, and orange action grammar on Home.
- Exact-printing identity expressed through image, name, set, collector number, and optional rarity.
- One accessible mode switch, direct `Find a card` search, one solid `View price` action, and restrained reveal motion.

## Colors

The Home palette is a warm counter system: bench establishes the light field, paper carries evidence, ink makes the rules, orange marks actions and evidence notices, and muted text supports caveats.

### Primary
- **Bench**: The warm light counter field for Home.
- **Bench light**: The bright search surface.
- **Paper**: The evidence-slip surface.
- **Orange**: Action, focus, and methodology emphasis.

### Secondary
- **Sage**: The status color for STANDARD archive chips.
- **Indigo**: The status color for EXPANDED archive chips.
- **Lilac**: The rarity chip color.
- **Sunfade**: The warm state-note surface and supporting archive accent.

### Neutral
- **Ink**: The near-black writing, rules, borders, and primary contrast.
- **Tissue**: The paper-colored label and drawer surface, including inverse header text.

**The Scope Rule.** Use bench, bench-light, paper, ink, orange, and muted tokens inside `.decision-world` for Home. Preserve board/tissue/archive tokens inside `.archive-world` for card detail; neither world should silently inherit the other’s field or texture.

## Typography

**Action/display font:** Barlow Condensed (sans-serif fallback)
**Evidence font:** Azeret Mono (ui-monospace, monospace fallback)

**Character:** Barlow Condensed 700 gives the decision headline, search heading, estimate, mode controls, and detail action a compressed counter-sign voice. Azeret Mono is evidence-only: search guidance, identity metadata, methodology, disclaimer, and state copy stay measured and inspectable.

### Hierarchy
- **Decision call** (700, `clamp(2.2rem, 6vw, 4rem)`, 0.92): `Compare Pokémon prices` and the first-viewport task.
- **Action heading** (700, `clamp(1.7rem, 4vw, 2.5rem)`, 1): Search and disclosure headings.
- **Price/name** (700, `1.45rem` name / `1.8rem` estimate, 0.9): Exact printing name and EUR estimate.
- **Row metadata/label** (400, `.62rem–.75rem`, 1.5–1.7): Set, collector number, rarity, update state, shipping note, and caveat copy.

**The Identity Rule.** Keep exact-printing names in condensed display type and identity fields in monospaced data type; do not turn catalogue facts into marketing copy.

## Layout

The `.decision-world` uses a compact full-width counter header and a centered Home container capped at `62rem`. The intro places the wordmark/call beside the accessible mode switch; below `42rem` they stack and the switch becomes full width. The decision title tops out at `4rem`, while mode and action controls use `2.8rem` minimum heights. The direct search precedes one vertical list of price rows. Each row uses a `5.5rem minmax(0, 1fr)` image/content split (`4.75rem minmax(0, 1fr)` below `24rem`), with identity, estimate, update state, and one CTA in the content column; text wraps without horizontal overflow.

The decision header and result heading use `2px` ink rules. The search surface is the visual pause before results, with the input spanning the available width. Results are visible in the desktop viewport; mobile keeps mode, search, identity, estimate, and action usable in sequence.

## Elevation & Depth

Depth is physical but restrained. Bench, paper, and ink contrast do the structural work; Home has no ornamental card shadows. Evidence slips remain flat paper objects rather than floating cards.

### Shadow Vocabulary
- **Home:** No ornamental card or search shadow; bench, paper, ink, and rules provide depth.
- **Archive detail:** Any restrained archive elevation remains scoped to `.archive-world` and is not a Home token.

**The One-Shadow Rule.** Do not add ornamental elevation to labels, chips, or state notes; use rules and material contrast instead.

## Shapes

The Home form language is square throughout: controls and price-row surfaces use zero-radius geometry, with borders doing the outlining. The search input is transparent with no box shadow and a `3px` ink underline; price rows use a `1.5px` ink border; header and result rules use ink lines. The printing-label art column and other archive-detail geometry remain part of `.archive-world`.

## Components

### Decision header / mode switch
- **Character:** A compact counter masthead with an accessible Singles/Sealed-products choice.
- **Shape:** Square geometry with a `2px` ink bottom rule.
- **Color:** Bench field, ink wordmark/context, and an ink active mode with bench-light text. The decision world explicitly uses a light color scheme.
- **Behavior:** The wordmark is a keyboard-focusable link with a `3px` ink focus outline offset by `5px`.

### Search surface / input
- **Character:** A bright counter surface and the primary decision action.
- **Shape:** Bench-light surface, square `2px` ink border. The input has no radius or shadow and ends in a `3px` ink underline.
- **Typography:** Heading and query use Barlow Condensed 700; evidence help uses Azeret Mono.
    - **Behavior:** The shared external `CardAutocomplete` hook searches local exact-printing data after `250ms`, without replacing or server-patching the focused input node. Query, caret/selection, and focus survive result updates; composition blocks intermediate searches and searches once after compositionend; Escape cancels pending debounce. Focus uses a `3px` orange outline.

### Autocomplete combobox / listbox
- **Character:** A compact ruled suggestion bench attached to the search surface, not a second card grid.
- **Semantics:** The input exposes combobox state with `aria-expanded`, `aria-controls`, and `aria-activedescendant`; direct streamed children use `role="option"` and stable `card-option-UUID` IDs. Accessible names reference visible name, set, rarity, price, and update state IDs.
- **Behavior:** The first result is visibly active, exactly one option is `aria-selected`, ArrowUp/ArrowDown wrap, Enter opens the exact active printing, Escape closes while retaining query/focus, and validated option click/touch follows the same route. There are no nested interactive controls. Query-specific live status changes even when the count is unchanged.
- **Spatial rule:** The bounded listbox is `min(45svh, 32rem)` and scrolls internally. The hook keeps the active option in view without moving page scroll or the input away. The active option receives a visible ink rule.

### Price row
- **Character:** One exact printing’s identity and honest local estimate, ready for a counter decision.
- **Shape:** Paper surface, `1.5px` ink border, a `5.5rem minmax(0, 1fr)` image/content split (narrowed to `4.75rem minmax(0, 1fr)` below `24rem`), and a `2.8rem` minimum action target.
- **Color:** Warm image backing, ink identity, orange emphasis, and paper surface.
- **Behavior:** Uses a low WebP thumbnail when available; missing imagery remains explicit. Results reveal once with `bench-reveal`; reduced motion removes it.

### Card detail image
- **Character:** Functional exact-printing identification, not promotional card merchandising.
- **Shape:** The high WebP TCGdex image sits inside a square tissue-and-ink frame that belongs to the archive wall.
- **Behavior:** The image supports identity verification while the ruled metadata and value/history sheet remain primary. Missing imagery uses the same honest line-art fallback.

### Archive chips
- **Character:** Small paper annotations, not calls to action.
- **Shape:** Square `1px` ink border, compact padding (`0.3rem 0.4rem`), wrapping in a flexible row.
- **Color:** Lilac marks rarity, sage marks STANDARD, and indigo marks EXPANDED; ink remains the text and border color.

### State notes and price details
- **Character:** Plain decision status: `Updated …`, `May be outdated`, `Price unavailable`, empty, invalid, unavailable, or error; never hidden behind a decorative empty state.
- **Shape:** A `1px` top rule, vertical padding, and mono copy. Error notes use a sunfade surface and `1rem` padding.
- **Behavior:** Idle has no explanatory copy; short-query, empty, and unavailable states stay short. Full policy, methodology, non-affiliation, and shipping caveats live in collapsed `How prices work` details. Sealed says honestly that it is not available yet.

### Trade decision bench
- **Character:** An Operate-mode extension of the card-shop valuation bench for an in-store two-sided decision.
- **Layout:** One selected-card staging strip leads to two symmetric ledgers; desktop uses columns and mobile stacks the sides. The surface must not overflow a 390px viewport.
- **Controls:** Search is local and singular. Add-left and Add-right are explicit, square, and at least 44px; quantity decrement/increment/remove controls preserve exact identity and URL state.
- **Evidence:** Rows show exact printing identity and EUR-only unit/row values, with `Updated today/yesterday/N days ago`, stale/outdated, fetching/failure, and unknown valid IDs as removable but unpriced. Each side total shows EUR plus Decimal PLN; incomplete known subtotals show both currencies plus `?`, and complete difference shows both currencies while incomplete difference remains explicit. NBP evidence shows exact `1 EUR = … PLN`, effective date, relative age, and pending/failed/no-cache states; carry-forward rates remain honestly dated.
- **Acquisition:** Missing/stale composition rows render immediately, then use one bounded canonical bulk request and background jobs. Failure retains a stale estimate; search and pick alone never enqueue.
- **Boundary:** External `TradeShare` copies an absolute server-derived canonical `Composition.to_path` URL containing only stable IDs and quantities. Clipboard API and cleaned legacy fallback restore focus, avoid stale/overlapping/destroyed feedback, and expose one accessible feedback live region. Sealed remains unavailable; Phase 4 is next.

## Do's and Don'ts

### Do:
- **Do** keep Home in the bright `.decision-world`; preserve `.archive-world` for card detail.
- **Do** make Singles the default and keep the mode switch keyboard-accessible with an honest unavailable Sealed state.
- **Do** make `Find a card`, image/name/set/collector identity, price/update state, and one solid `View price` action obvious.
- **Do** use Barlow Condensed for action hierarchy and Azeret Mono for evidence only.
- **Do** preserve square rules, 44px touch targets, the single reveal motion, and its reduced-motion fallback.
- **Do** keep autocomplete active state visibly ruled, internally scrollable, keyboard/touch accessible, and stable through LiveView stream updates.
- **Do** keep caveats available in collapsed `How prices work` details, use terse shipping language, and use low WebP thumbnails when available.

### Don't:
- **Don't** replace the decision bench with a generic rounded marketplace grid, glass, or decorative gradients.
- **Don't** imply sealed, trade, seller-count, language, condition, finish-specific, or Poland-shipping capability that is not present.
- **Don't** hide stale/unpriced estimates or methodology behind decorative treatment.
- **Don't** use form-level reassignment or nested interactive controls that steal focus or break option semantics.
- **Don't** let Home’s decision-world tokens or copy erase the archive-world contract on card detail.
