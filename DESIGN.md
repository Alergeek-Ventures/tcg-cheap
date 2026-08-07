---
name: TCG Cheap Printing Archive
description: A physical, local-first archive wall for identifying exact printings.
colors:
  box-board: "#c86c3f"
  box-board-dark: "#a94f2f"
  ink: "#171614"
  tissue: "#f6f0df"
  sage: "#a9b69a"
  indigo: "#9fa8c8"
  lilac: "#c1b1c9"
  sunfade: "#e5bf70"
typography:
  display:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "clamp(3.4rem, 11vw, 8rem)"
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
  archive-header:
    backgroundColor: "{colors.box-board}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.square}"
    padding: "1rem clamp(1rem, 4vw, 3.5rem)"
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

# Design System: TCG Cheap Printing Archive

## Overview

**Creative North Star: "The Printing Archive Wall"**

The public archive is built like a working box-board drawer: burnt board surrounds tissue labels, black ink rules divide information, and every exact printing occupies its own labeled place. It is tactile and catalogued rather than promotional. Condensed display type makes the archive legible at a glance; monospaced data keeps identity fields precise.

The visual world favors near-square paper geometry, strong ruled edges, restrained color blocks, and a responsive wall of labels. It rejects the generic rounded marketplace thumbnail grid, glass surfaces, and decorative gradients. The field is the primary action, and catalogue states remain visible as honest notes.

**Key Characteristics:**
- Physical box-board, tissue, ink, and paper-label grammar.
- Exact-printing identity expressed through ruled metadata and archive chips.
- Mobile-first 1/2/3-column label wall with restrained tactile motion.

## Colors

The palette is a warm archive material system: box-board establishes the field, tissue carries readable surfaces, ink makes the rules, and muted chips annotate status.

### Primary
- **Box-board**: The burnt orange archive field behind the wall.
- **Box-board dark**: The darker board ink used for label line art and data labels.

### Secondary
- **Sage**: The status color for STANDARD archive chips.
- **Indigo**: The status color for EXPANDED archive chips.
- **Lilac**: The rarity chip color.
- **Sunfade**: The warm state-note surface and supporting archive accent.

### Neutral
- **Ink**: The near-black writing, rules, borders, and primary contrast.
- **Tissue**: The paper-colored label and drawer surface, including inverse header text.

**The Material Rule.** Use the palette as physical archive material inside `.archive-world`: board for the surrounding world, tissue for paper surfaces, ink for information structure, and muted colors for annotations. Other product surfaces must not inherit the archive field, fonts, texture, or light color scheme.

## Typography

**Display Font:** Barlow Condensed (sans-serif fallback)
**Body Font:** Azeret Mono (ui-monospace, monospace fallback)
**Label/Mono Font:** Azeret Mono

**Character:** Barlow Condensed 700 gives headings the compressed authority of a printed end label. Azeret Mono 400 makes search guidance, metadata, and state copy feel measured and inspectable.

### Hierarchy
- **Display** (700, `clamp(3.4rem, 11vw, 8rem)`, 0.83): Oversized archive-intro title and section headings.
- **Headline** (700, `clamp(2rem, 5vw, 3.5rem)`, 1): Search drawer and printing-wall headings.
- **Title** (700, `1.65rem`, 0.95): Exact printing names on labels.
- **Body** (400, `0.75rem`, 1.7): Introductory and explanatory copy.
- **Label** (400, `0.75rem`, 1.5): Collector metadata, readable header/meta, help, summary, set, data, and state copy. Chips use `0.7rem` as the smallest compact annotation size.

**The Identity Rule.** Keep exact-printing names in condensed display type and identity fields in monospaced data type; do not turn catalogue facts into marketing copy.

## Layout

The `.archive-world` uses a full-width archive header and a centered content container capped at `78rem`. Main content has responsive vertical padding, while the intro and drawer lead into a ruled shelf heading and label wall. The label wall is one `minmax(0, 1fr)` column by default, two columns from `46rem`, and three columns from `70rem`; columns use `1.5rem` horizontal gaps. Below `30rem`, labels reflow art above copy with a bottom separator so 200% text remains usable without horizontal overflow. Header metadata and shelf headings wrap, and label identity rows reflow to protect narrow screens.

The archive header is a flex row with a `2px` ink bottom rule. Label slots retain a bottom rule, and the shelf heading repeats the strong rule before the collection. The search drawer is the visual pause before results, with the input spanning the available width.

## Elevation & Depth

Depth is physical but restrained. Tissue surfaces sit above the box-board field with one soft drawer shadow; ink borders and tonal paper contrast do most of the structural work. Printing labels remain flat paper objects rather than floating cards.

### Shadow Vocabulary
- **Soft drawer shadow** (`7px 9px 13px rgb(76 33 22 / 32%)`): Used only by the search drawer to suggest a physical drawer or board lifted from the archive wall.

**The One-Shadow Rule.** Do not add ornamental elevation to labels, chips, or state notes; use rules and material contrast instead.

## Shapes

The form language is near-square throughout: the observed controls and archive surfaces use zero-radius geometry, with borders doing the outlining. The search input is transparent with no box shadow and a `3px` ink underline; labels use a `1.5px` ink border; shelf and header rules use ink lines. The printing-label art column is separated by a vertical rule.

## Components

### Archive header / active label
- **Character:** A compact archival masthead that names the collection and mode.
- **Shape:** Square geometry with a `2px` ink bottom rule.
- **Color:** Board field, ink wordmark/meta, and an ink active label with tissue text. The archive world explicitly uses a light color scheme.
- **Behavior:** The wordmark is a keyboard-focusable link with a `3px` ink focus outline offset by `5px`.

### Search drawer / input
- **Character:** A tactile paper drawer and the primary archive action.
- **Shape:** Tissue surface, square `2px` ink border, and soft drawer shadow. The input has no radius or shadow and ends in a `3px` ink underline.
- **Typography:** Drawer heading uses Barlow Condensed 700; query text uses the same display family at `clamp(1.2rem, 3vw, 2rem)`.
- **Behavior:** The field searches locally with a `250ms` debounce. Focus uses a `3px` ink outline with `5px` offset; loading guidance appears beneath the field.

### Printing label
- **Character:** The signature end label for one exact printing.
- **Shape:** Tissue paper, `1.5px` ink border, minimum height `12rem`, and `1rem` internal padding. The art column is separated by a `1px` vertical rule.
- **Color:** Box-board-dark line art, ink identity text, and tissue surface.
- **Behavior:** Labels pull down into place with the `pull-label` motion; reduced motion removes the animation.

### Archive chips
- **Character:** Small paper annotations, not calls to action.
- **Shape:** Square `1px` ink border, compact padding (`0.3rem 0.4rem`), wrapping in a flexible row.
- **Color:** Lilac marks rarity, sage marks STANDARD, and indigo marks EXPANDED; ink remains the text and border color.

### State notes
- **Character:** Plain catalogue status attached to the shelf, never hidden behind a decorative empty state.
- **Shape:** A `1px` top rule, vertical padding, and mono copy. Error notes use a sunfade surface and `1rem` padding.
- **Behavior:** Idle, short-query, empty, and unavailable states explain what the local archive can do next.

## Do's and Don'ts

### Do:
- **Do** preserve the box-board field, tissue paper surfaces, and strong ink rules.
- **Do** keep the container capped at `78rem` and the label wall responsive at `46rem` and `70rem`.
- **Do** make exact identity fields visibly distinct through monospaced metadata and archive chips.
- **Do** retain the soft drawer shadow and pull-label motion only where the implementation uses them.
- **Do** provide the reduced-motion fallback for label entrance motion.

### Don't:
- **Don't** replace archive labels with generic rounded marketplace thumbnail grids.
- **Don't** add glass surfaces, decorative gradients, or image-led card treatments.
- **Don't** invent buttons, pricing treatments, dark mode, or alias UI that is not part of this public archive.
- **Don't** use shadows as a general card treatment; the drawer is the one soft elevation.
