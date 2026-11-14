---
name: TCG Cheap Buying Guide
description: A calm warm-paper surface for checking whether a Pokémon TCG price is good.
colors:
  bench: "#f1eadc"
  bench-light: "#fffaf0"
  paper: "#fffdf8"
  ink: "#201d19"
  rule: "rgb(32 29 25 / 18%)"
  orange: "#b54125"
  muted: "#6d6256"
  rise: "#27714b"
  fall: "#a6402f"
typography:
  display:
    fontFamily: "Barlow Condensed, sans-serif"
    fontWeight: 700
  body:
    fontFamily: "Azeret Mono, ui-monospace, monospace"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  square: "0"
spacing:
  scale: ["0.25rem", "0.5rem", "0.75rem", "1rem", "1.5rem", "2rem", "3rem", "4rem"]
  container: "72rem"
components:
  verdict-badge:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.display}"
    rounded: "{rounded.square}"
    padding: "0.35rem 0.55rem"
  verdict-go:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.bench-light}"
    typography: "{typography.display}"
    rounded: "{rounded.square}"
    padding: "0 1.5rem"
---

# Design System: TCG Cheap Buying Guide

## Overview

The guide is a calm warm-paper counter: a warm bench carries paper-coloured
rows and panels, separated by thin rules, with orange reserved for focus and
emphasis. It is practical rather than promotional. Condensed display type
makes the answer legible at a glance; monospaced type carries the evidence.
It avoids rounded marketplace grids, glass surfaces and decorative gradients.

The whole public site (product list, product pages, set pages, card pages and
the guide articles) lives under the `.guide-world` CSS scope in
`assets/css/site.css`; the admin has its own scope in `assets/css/admin.css`.

## Colors

The tokens are custom properties on `.guide-world`:

- **Bench** (`#f1eadc`): the page field. **Bench light** (`#fffaf0`): the
  search surface and filled controls. **Paper** (`#fffdf8`): rows and panels.
- **Ink** (`#201d19`): text, rules and solid actions. **Rule**: ink at 18%,
  for hairlines. **Muted** (`#6d6256`): secondary text.
- **Orange** (`#b54125`): focus outlines, hover and emphasis.
- **Rise** (`#27714b`) and **Fall** (`#a6402f`): a good and an expensive
  verdict. Both keep normal text contrast on paper.

Derived tints use `color-mix()` from these tokens instead of new literals.

## Typography

**Display:** Barlow Condensed 700, used for headings, prices, verdicts and
action labels. Only the 700 file exists, so do not request another weight.
**Body and evidence:** Azeret Mono 400, `1rem` with a `1.6` line height. Use
no other typefaces. Both are self-hosted (`/fonts/`).

## Layout

Content sits in a centred column up to `72rem` (`.guide-main`), with spacing
from the `--space-*` scale (`0.25rem` to `4rem`). The masthead and the search
bar stay at the top while a list scrolls. Layouts are mobile-first: rows and
panels stack on a phone and gain columns from container or viewport
breakpoints (for example `42rem` for list rows and `56rem` for the product
page). Controls are at least `3rem` tall; price figures never wrap inside a
number.

## Shapes and depth

Geometry is square: controls, rows and panels use zero radius. The few
exceptions are small, such as shop logos and card art, which follow their
artwork, and pill-shaped counters. Depth comes from bench, paper and ink
contrast and from rules. Hard offset shadows (a solid ink block, no blur)
mark the search bar and floating notices, never soft elevation.

## Components

### Verdict marks

Verdict badges carry a drawn 16px stroke mark (`verdict-mark`, an inline
`aria-hidden` SVG) and a text label, so a verdict never relies on colour
alone: down arrow for good, two bars for normal, up arrow for expensive, a
question mark for too few shops, a dash for not in shops, a clock for a
pre-order. Good and expensive are filled rise and fall; normal is outlined
ink; too few shops is dashed; not in shops is a quiet borderless muted label.

### List rows

A product row shows a square picture, the name, and the shop, verdict and
price. Missing photos show a drawing of the product's kind. On wide lists the
shop, verdict and price take fixed columns so rows line up; when the row is
narrow they move under the name, and on a phone the row is compact with the
shop name left to the product page.

### Product page verdict panel

The first answer on the page is one block: a full-width verdict band (filled
rise, fall or ink, or a tinted band with a dashed or dotted rule when there is
no verdict), the cheapest price and shop beside the page's only solid action
(`verdict-go`, ink on bench light, linking to the shop), and the reasoning in
short lines. Price history and "how we calculate" are collapsed disclosures
(`details`). On a phone the photo stands above the name, as wide as the page.

### Offers

In-stock offers form the list; offers without stock sit behind a disclosure on
tinted rows. A row shows the shop logo, the shop name with a smaller muted
delivery line, the price (with a muted note only when something needs saying,
such as a stale check) and a quiet underlined link to the shop.

### Disclaimers

The independence disclaimer under the offers is a callout, not a footnote:
bench-light surface, a hairline border and an orange icon.

## Do's and Don'ts

### Do:
- **Do** use Barlow Condensed for decisions and prices and Azeret Mono for body
  and evidence.
- **Do** keep square geometry, visible focus outlines and `3rem` touch targets.
- **Do** keep one primary action per screen; repeated row links are quiet.
- **Do** keep reduced-motion users in mind: motion is optional polish.

### Don't:
- **Don't** replace the bench with a generic rounded marketplace grid, glass
  or decorative gradients.
- **Don't** mark verdicts with a coloured side stripe or Unicode arrows, or
  with threshold ranges that leave a gap between whole złoty.
- **Don't** hide stale or missing prices behind decorative treatment.
