---
name: TCG Cheap Decision Surface
description: A calm warm-paper decision surface for deciding about exact Pokémon TCG singles.
colors:
  box-board: "#f1eadc"
  box-board-dark: "#a94f2f"
  ink: "#171614"
  tissue: "#fffdf8"
  sage: "#a9b69a"
  indigo: "#9fa8c8"
  lilac: "#c1b1c9"
  sunfade: "#e5bf70"
  bench: "#f1eadc"
  bench-light: "#fffdf8"
  paper: "#fffdf8"
  orange: "#b54125"
  muted: "#6d6256"
  rise: "#27714b"
  fall: "#a6402f"
typography:
  display:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "clamp(2rem, 4vw, 2.5rem)"
    typeRamp: ["1.25rem", "1.5rem", "2rem", "2.5rem"]
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.04em"
  body:
    fontFamily: "Azeret Mono, ui-monospace, monospace"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.7
  label:
    fontFamily: "Azeret Mono, ui-monospace, monospace"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  square: "0"
spacing:
  scale: ["4px", "8px", "12px", "16px", "24px", "32px", "48px", "64px"]
  coreGrid: "8px"
  halfStep: "4px"
  intermediateStep: "12px"
  container: "72rem"
  desktopMax: "1100-1200px"
  desktopSectionGap: "24-48px by hierarchy"
  desktopPanelPadding: "24-32px"
  mobileDensityReduction: "33-50%"
components:
  decision-header:
    backgroundColor: "{colors.bench}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "8px max(16px, 4vw)"
  mode-switch:
    backgroundColor: "{colors.bench}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    minHeight: "3rem"
  decision-search:
    backgroundColor: "{colors.bench-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "16px 20px"
  price-row:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "6px 12px"
  archive-active-label:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.tissue}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "4px 8px"
  price-methodology:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "8px 0"
  printing-label:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.square}"
    padding: "1rem 0"
  archive-annotation:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "4px 8px"
---

# Design System: TCG Cheap Decision Surface

## Overview

**Creative North Star: "The Card-Shop Valuation Bench"**

Home is a calm warm-paper counter scene: a warm bench supports compact paper-like price rows, restrained ink separators, and selective orange action emphasis. It is practical and decision-oriented rather than promotional. Condensed display type makes the call legible at a glance; monospaced data keeps identity and supporting detail precise.

The Home decision-world keeps its warm square identity while becoming calm and restrained: no noise texture, no heavy perimeter borders on search, evidence, or market rows, one subtle header/input separator, and approximately 24px Market separation. It rejects generic rounded marketplace grids, glass surfaces, and decorative gradients. Search is the primary action; current, outdated, and unavailable states remain visible in plain collector language.

The `.archive-world` remains the CSS scope name and visual contract for card detail. CardDetail now uses calm warm paper with a transparent, unboxed printing surface, one coherent detail column, plain-text legal format, and a restrained chart. The archive world was scoped away from Home, not removed globally.

**Key Characteristics:**
- Calm warm-paper bench, square identity, restrained ink separators, and selective orange action grammar on Home.
- Exact-printing identity expressed through image, name, set, collector number, and optional rarity. Official Fluent Gift Card Add Regular sits beside every public TCG CHEAP wordmark; the wordmark is Barlow Condensed 700.
- One accessible mode switch, direct `Find a card` search, one solid `View price` action, and restrained reveal motion.

## Colors

The Home palette is a calm warm counter system: `#f1eadc` bench establishes the light field, `#fffdf8` paper carries evidence, restrained ink makes the separators, orange marks actions and evidence notices, and muted text supports caveats. Shared Trade/Sealed `.decision-world` surfaces retain their stronger `#f3ead7` decision-world baseline. Do not add noise texture to Home.

### Primary
- **Bench**: The warm light counter field for Home.
- **Bench light**: The bright search surface.
- **Paper**: The evidence-slip surface.
- **Orange**: Action, focus, and methodology emphasis; canonical `#b54125` keeps normal text contrast clear on warm surfaces.
- **Rise**: Positive directional evidence on paper; canonical `#27714b` keeps normal text contrast clear at `4.5:1` or better.
- **Fall**: Negative directional evidence on paper; canonical `#a6402f` keeps normal text contrast clear at `4.5:1` or better.

### Secondary
- **Sage**, **Indigo**, and **Lilac**: Retained archive/data tokens where existing detail behavior requires them; legal format is plain text, not a colored chip.
- **Sunfade**: The warm state-note surface and supporting archive accent.

### Neutral
- **Ink**: The near-black writing, rules, borders, and primary contrast.
- **Tissue**: The paper-colored label and drawer surface, including inverse header text.

Directional evidence uses `rise` and `fall` only as intentional accessible movement colors on paper. Derived warm art and state backgrounds use `color-mix()` from documented `paper`, `bench`, and `orange` tokens rather than introducing new literal colors.

**The Scope Rule.** Use bench, bench-light, paper, ink, orange, and muted tokens inside `.home-world` for Home. Shared Trade/Sealed `.decision-world` styling remains unchanged. Keep `.archive-world` as the CardDetail CSS scope only; neither world should silently inherit the other’s field or texture.

## Typography

**Action/display font:** Barlow Condensed (sans-serif fallback)
**Evidence font:** Azeret Mono (ui-monospace, monospace fallback)

**Character:** Barlow Condensed 700 gives the decision headline, search heading, estimate, mode controls, and detail action a compressed counter-sign voice. The 700 weight is a documented brand/asset exception: only the approved 700 asset exists, so do not substitute a requested semibold file. Azeret Mono is body and evidence: search guidance, identity metadata, methodology, disclaimer, and state copy stay measured and inspectable. Use no more than these two typefaces.

### Hierarchy
- **H1 / decision call** (700, `32–40px`, 0.92): `Compare Pokémon prices` and the first-viewport task.
- **H2 / action heading** (700, `24–28px`, 1): Search and disclosure headings; narrow display steps include `1.25rem` and `1.5rem` where the available width requires them.
- **H3 / supporting heading** (700, `20–22px`): Section and panel headings.
- **Price/name** (700, `1.45rem` name / `1.8rem` estimate, 0.9): Exact printing name and compact EUR estimate.
- **Body** (400, `16px`, 1.5–1.7): Explanatory and operational copy; prose stays at or below `70ch`.
- **Row metadata/label** (400, `14px` minimum, 1.5–1.7): Set, collector number, rarity, update state, shipping note, and caveat copy.

**The Identity Rule.** Keep exact-printing names in condensed display type and identity fields in monospaced data type; do not turn catalogue facts into marketing copy.

## Layout

The `.home-world` uses a compact full-width counter header and a centered Home container capped at the canonical `1152px` (`72rem`), within an approved desktop range of `1100–1200px`. Major sections use approximately `24–48px` separation by hierarchy, Market movers use approximately `24px`, and compact price/evidence rows are rows, not cards. The intro places the wordmark/call beside the accessible mode switch; below `42rem` they stack and the switch becomes full width. Mobile-first layouts stack, reduce spatial density by about `33–50%`, and preserve at least `48px` for every control; the header uses `16px` inline padding on mobile. The decision title is `32–40px`, while mode and action controls use `48px` minimum heights. The direct search precedes one vertical list of price rows. Each row uses a `5.5rem minmax(0, 1fr)` image/content split (`4.75rem minmax(0, 1fr)` below `24rem`), with identity, estimate, and one CTA in the content column; text wraps without horizontal overflow. Movement rows are discovery hooks: exact identity and signed movement only. `Recently tracked` is identity plus current estimate, without freshness text. Shared Trade/Sealed `.decision-world` surfaces retain their existing stronger `#f3ead7` baseline.

Home uses one subtle header/input separator rather than heavy perimeter rules. The search surface is the visual pause before results, with the input spanning the available width. Results are visible in the desktop viewport; mobile keeps mode, search, identity, estimate, and action usable in sequence.

### Action hierarchy and accessibility

Each screen has one primary task/action hierarchy with generous space around it. Home's search and `View price` flow is that hierarchy. Repeated result-row CTAs are contextual choices within the result list, not competing page-level primaries. In Trade, the equal left/right choices and row operations are necessary Operate-mode peers, so the two-sided ledger intentionally presents them symmetrically. Normal text meets at least `4.5:1` contrast, focus is always clearly visible, and interactive targets are at least `48px`.

## Elevation & Depth

Depth is physical but restrained. Bench, paper, and ink contrast do the structural work; Home has no ornamental card shadows. Evidence slips remain flat paper objects rather than floating cards.

### Shadow Vocabulary
- **Home:** No ornamental card or search shadow; bench, paper, ink, and rules provide depth.
- **Archive detail:** CardDetail uses transparent, unboxed surfaces and material contrast rather than archive elevation; this remains scoped to `.archive-world` and is not a Home token.

**The One-Shadow Rule.** Do not add ornamental elevation to labels, chips, or state notes; use rules and material contrast instead.

## Shapes

The Home form language is square throughout: controls and price-row surfaces use zero-radius geometry. Search, evidence, and Market rows do not use heavy perimeter borders; separation comes from paper/bench contrast, spacing, and one subtle header/input separator. The printing-label art column and other archive-detail geometry remain part of `.archive-world`.

## Components

### Decision header / mode switch
- **Character:** A compact counter masthead with an accessible Singles/Sealed-products choice.
- **Shape:** Square geometry with one subtle ink separator.
- **Color:** Bench field, ink wordmark/context, and an ink active mode with bench-light text. The decision world explicitly uses a light color scheme.
- **Behavior:** The wordmark is a keyboard-focusable link with a clear ink focus outline and generous offset.

### Search surface / input
- **Character:** A bright counter surface and the primary decision action.
- **Shape:** Bench-light surface with square geometry; the input has no radius or shadow and uses the subtle shared separator.
- **Typography:** Heading and query use Barlow Condensed 700; evidence help uses Azeret Mono.
    - **Behavior:** The shared external `CardAutocomplete` hook searches local exact-printing data after `250ms`, without replacing or server-patching the focused input node. Query, caret/selection, and focus survive result updates; composition blocks intermediate searches and searches once after compositionend; Escape cancels pending debounce. Focus remains clearly visible.

### Autocomplete combobox / listbox
- **Character:** A compact ruled suggestion bench attached to the search surface, not a second card grid.
- **Semantics:** The input exposes combobox state with `aria-expanded`, `aria-controls`, and `aria-activedescendant`; direct streamed children use `role="option"` and stable `card-option-UUID` IDs. Accessible names reference visible name, set, rarity, price, and update state IDs.
- **Behavior:** The first result is visibly active, exactly one option is `aria-selected`, ArrowUp/ArrowDown wrap, Enter opens the exact active printing, Escape closes while retaining query/focus, and validated option click/touch follows the same route. There are no nested interactive controls. Query-specific live status changes even when the count is unchanged.
- **Spatial rule:** The bounded listbox is `min(45svh, 32rem)` and scrolls internally. The hook keeps the active option in view without moving page scroll or the input away. The active option receives a visible ink rule.

### Price row
- **Character:** One exact printing’s identity and honest local estimate, ready for a counter decision.
- **Shape:** Calm paper row with compact `6–12px` spacing and no heavy perimeter border, a `5.5rem minmax(0, 1fr)` image/content split (narrowed to `4.75rem minmax(0, 1fr)` below `24rem`), and a `48px` minimum action target.
- **Color:** Warm image backing, ink identity, orange emphasis, and paper surface.
- **Behavior:** Uses a low WebP thumbnail when available; missing imagery remains explicit. Results reveal once with `bench-reveal`; reduced motion removes it.

### Card detail image
- **Character:** Functional exact-printing identification, not promotional card merchandising.
- **Shape:** The high WebP TCGdex image sits in a transparent, unboxed printing surface within the `.archive-world` detail layout.
- **Behavior:** The image supports identity verification alongside one coherent, unboxed detail column. Missing imagery uses the same honest line-art fallback.

The meaningful image column is larger than the supporting detail region. At wide desktop, compact `Current estimate` and `Printing` sit side by side in the right region; mobile order is identity → estimate → image → Printing. History spans the full `72rem` detail container.

### CardDetail layout
- **Direction:** The prior saturated orange board, three boxed columns/status boxes, and giant framed chart are explicitly superseded.
- **Desktop:** Calm warm paper, subtle 1px header separator, and two columns: image plus one coherent detail column.
- **Mobile:** Identity → estimate → image → Printing. Valuation, metadata, and history are unboxed; legal format is plain text; statuses and disclosure are quiet; history spans the full `72rem` detail container on desktop.
- **Boundary:** `.archive-world` remains the CSS scope name only. Preserve exact identity, data, provenance, and history behavior.

### Archive annotations
- **Character:** Small paper annotations, not calls to action.
- **Shape:** Plain text annotations with quiet spacing; legal format is never a colored chip.
- **Color:** Existing archive/data tokens remain available where behavior requires them, without turning legal format into a status treatment.

### State notes and price details
- **Character:** Plain decision status: `Updated …`, `May be outdated`, `Price unavailable`, empty, invalid, unavailable, or error; never hidden behind a decorative empty state.
- **Shape:** A `1px` top rule, vertical padding, and mono copy. Error notes use a sunfade surface and `1rem` padding.
- **Behavior:** Idle has no explanatory copy; short-query, empty, and unavailable states stay short. Full policy, methodology, non-affiliation, and shipping caveats live in a collapsed icon-led `Method` disclosure. Sealed says honestly that it is not available yet.

The estimate is compact and has an adjacent accessible `48px` information tooltip with concise consistent-calculation, source, and non-affiliation copy. It exposes no exact metric, policy version, or timestamp. Trade is linked for comparison only and does not support changing valuation algorithms.

History preserves date gaps, shows min/max and exact window dates, uses horizontal guides, and exposes exact date/EUR tooltips on hover or focus. Point controls are keyboard-focusable. A one-point history remains summary/ledger only, with no chart.

### Fluent UI icon system
- **Semantic use:** Selective official Fluent UI System Icons Regular support search, back, trade/swap, information, disclosure chevron, freshness/clock, and trend direction.
- **Implementation:** Icons are decorative `aria-hidden` inline SVGs from Microsoft’s official regular set. They support labels and never replace necessary text. The full MIT notice is recorded in `THIRD_PARTY_NOTICES.md`.

### Trade decision bench
- **Character:** An Operate-mode extension of the card-shop valuation bench for an in-store two-sided decision.
- **Layout:** One selected-card staging strip leads to two symmetric ledgers; desktop uses columns and mobile stacks the sides. The surface must not overflow a 390px viewport.
- **Controls:** Search is local and singular. Add-left and Add-right are explicit, square, and at least 48px; quantity decrement/increment/remove controls preserve exact identity and URL state.
- **Evidence:** Rows show exact printing identity and EUR-only unit/row values, with `Updated today/yesterday/N days ago`, stale/outdated, fetching/failure, and unknown valid IDs as removable but unpriced. Each side total shows EUR plus Decimal PLN; incomplete known subtotals show both currencies plus `?`, and complete difference shows both currencies while incomplete difference remains explicit. NBP evidence shows exact `1 EUR = … PLN`, effective date, relative age, and pending/failed/no-cache states; carry-forward rates remain honestly dated.
- **Acquisition:** Missing/stale composition rows render immediately, then use one bounded canonical bulk request and background jobs. Failure retains a stale estimate; search and pick alone never enqueue.
- **Boundary:** External `TradeShare` copies an absolute server-derived canonical `Composition.to_path` URL containing only stable IDs and quantities. Clipboard API and cleaned legacy fallback restore focus, avoid stale/overlapping/destroyed feedback, and expose one accessible feedback live region. Sealed remains unavailable; Phase 4 is next.

## Do's and Don'ts

### Do:
- **Do** keep Home in the calm `.home-world`; preserve `.archive-world` for card detail.
- **Do** make Singles the default and keep the mode switch keyboard-accessible with an honest unavailable Sealed state.
- **Do** make `Find a card`, image/name/set/collector identity, price/update state, and one solid `View price` action obvious.
- **Do** use Barlow Condensed for action hierarchy and Azeret Mono for body and evidence.
- **Do** preserve square rules, 48px touch targets, the single reveal motion, and its reduced-motion fallback.
- **Do** keep autocomplete active state visibly ruled, internally scrollable, keyboard/touch accessible, and stable through LiveView stream updates.
- **Do** keep caveats complete but hidden by default in the collapsed `Method` disclosure, use terse shipping language, and use low WebP thumbnails when available.

### Don't:
- **Don't** replace the decision bench with a generic rounded marketplace grid, glass, or decorative gradients.
- **Don't** imply sealed, trade, seller-count, language, condition, finish-specific, or Poland-shipping capability that is not present.
- **Don't** hide stale/unpriced estimates or methodology behind decorative treatment.
- **Don't** use form-level reassignment or nested interactive controls that steal focus or break option semantics.
- **Don't** let Home’s decision-world tokens or copy erase the archive-world contract on card detail.
