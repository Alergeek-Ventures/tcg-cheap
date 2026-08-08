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
    fontSize: "clamp(3.1rem, 9vw, 6rem)"
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
  container: "78rem"
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
    minHeight: "44px"
  decision-search:
    backgroundColor: "{colors.bench-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "clamp(1rem, 3vw, 1.75rem)"
  evidence-slip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "0.85rem"
  estimate-cell:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
  archive-active-label:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.tissue}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "0.45rem 0.55rem"
  search-drawer:
    backgroundColor: "{colors.tissue}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "clamp(1.25rem, 4vw, 2.5rem)"
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

Home is a light, bright counter scene: a warm bench supports paper-like evidence slips, black ink rules, and orange action emphasis. It is practical and decision-oriented rather than promotional. Condensed display type makes the call legible at a glance; monospaced data keeps identity and evidence precise.

The Home decision-world favors square geometry, strong ruled edges, warm bench/paper/ink/orange color blocks, and responsive evidence slips. It rejects generic rounded marketplace grids, glass surfaces, and decorative gradients. Search is the primary action; current, fresh, stale, and unpriced states remain visible as honest evidence.

The `.archive-world` remains the visual contract for card detail. The archive world was scoped away from Home, not removed globally.

**Key Characteristics:**
- Bright card-shop bench, paper, ink, and orange action grammar on Home.
- Exact-printing identity expressed through image, set/collector/TCGdex discriminators, and evidence slips.
- One accessible mode switch, direct local search, one clear value-details action, and restrained reveal motion.

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
- **Decision headline** (700, `clamp(3.1rem, 9vw, 6rem)`, 0.84): Home’s first-viewport call to action.
- **Action heading** (700, `clamp(1.8rem, 4vw, 3rem)`, 1): Search and evidence headings.
- **Evidence title** (700, `1.55rem`, 0.9): Printing name and estimate.
- **Evidence/label** (400, `.68rem–.75rem`, 1.5–1.7): Search guidance, identity, methodology, disclaimer, and freshness states.

**The Identity Rule.** Keep exact-printing names in condensed display type and identity fields in monospaced data type; do not turn catalogue facts into marketing copy.

## Layout

The `.decision-world` uses a full-width counter header and a centered Home container capped at `76rem`. The intro places the decision headline beside the accessible mode switch; below `42rem` they stack and the switch becomes full width. The local search and evidence heading precede responsive evidence slips, which use `minmax(min(100%, 22rem), 1fr)` columns and collapse to a narrower image column below `24rem`. Text wraps without horizontal overflow.

The decision header and evidence heading use `2px` ink rules. The search surface is the visual pause before results, with the input spanning the available width. The first results fit in the desktop viewport; mobile keeps mode, search, identity, estimate, and action usable in sequence.

## Elevation & Depth

Depth is physical but restrained. Bench, paper, and ink contrast do the structural work; Home has no ornamental card shadows. Evidence slips remain flat paper objects rather than floating cards.

### Shadow Vocabulary
- **Home:** No ornamental card or search shadow; bench, paper, ink, and rules provide depth.
- **Archive detail:** Any restrained archive elevation remains scoped to `.archive-world` and is not a Home token.

**The One-Shadow Rule.** Do not add ornamental elevation to labels, chips, or state notes; use rules and material contrast instead.

## Shapes

The Home form language is square throughout: controls and evidence surfaces use zero-radius geometry, with borders doing the outlining. The search input is transparent with no box shadow and a `3px` ink underline; evidence slips use a `1.5px` ink border; header and evidence rules use ink lines. The printing-label art column and other archive-detail geometry remain part of `.archive-world`.

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
- **Behavior:** The field searches local exact-printing data with a `250ms` debounce. Focus uses a `3px` orange outline; loading guidance appears beneath the field.

### Evidence slip
- **Character:** One exact printing’s identity and local estimate, ready for a counter decision.
- **Shape:** Paper surface, `1.5px` ink border, image column, ruled estimate, and minimum `44px` action target.
- **Color:** Warm image backing, ink identity, orange emphasis, and paper surface.
- **Behavior:** Uses a low WebP TCGdex thumbnail when available; missing imagery remains explicit. Results reveal once with `bench-reveal`; reduced motion removes it.

### Card detail image
- **Character:** Functional exact-printing identification, not promotional card merchandising.
- **Shape:** The high WebP TCGdex image sits inside a square tissue-and-ink frame that belongs to the archive wall.
- **Behavior:** The image supports identity verification while the ruled metadata and value/history sheet remain primary. Missing imagery uses the same honest line-art fallback.

### Archive chips
- **Character:** Small paper annotations, not calls to action.
- **Shape:** Square `1px` ink border, compact padding (`0.3rem 0.4rem`), wrapping in a flexible row.
- **Color:** Lilac marks rarity, sage marks STANDARD, and indigo marks EXPANDED; ink remains the text and border color.

### State notes
- **Character:** Plain decision status: current/fresh, stale, unpriced, empty, invalid, unavailable, or error; never hidden behind a decorative empty state.
- **Shape:** A `1px` top rule, vertical padding, and mono copy. Error notes use a sunfade surface and `1rem` padding.
- **Behavior:** Idle, short-query, empty, and unavailable states explain what local data can do next. Methodology and disclaimer stay visible; Sealed says honestly that it is not available yet.

## Do's and Don'ts

### Do:
- **Do** keep Home in the bright `.decision-world`; preserve `.archive-world` for card detail.
- **Do** make Singles the default and keep the mode switch keyboard-accessible with an honest unavailable Sealed state.
- **Do** make direct local search, image/identity/discriminators, evidence, freshness, and one value-details action obvious.
- **Do** use Barlow Condensed for action hierarchy and Azeret Mono for evidence only.
- **Do** preserve square rules, 44px touch targets, the single reveal motion, and its reduced-motion fallback.
- **Do** keep methodology and disclaimer visible, and use low WebP TCGdex thumbnails in search when available.

### Don't:
- **Don't** replace the decision bench with a generic rounded marketplace grid, glass, or decorative gradients.
- **Don't** imply sealed, trade, seller-count, language, condition, finish-specific, or Poland-shipping capability that is not present.
- **Don't** hide stale/unpriced estimates or methodology behind decorative treatment.
- **Don't** let Home’s decision-world tokens or copy erase the archive-world contract on card detail.
