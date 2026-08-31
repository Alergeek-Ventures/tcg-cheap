---
version: 1
slug: "lib-tcg-cheap-web-live-card-detail-live-ex"
primary_target: "lib/tcg_cheap_web/live/card_detail_live.ex"
related_targets: ["assets/css/app.css","lib/tcg_cheap_web/live/home_live.ex"]
---

# Card detail

- **Scope:** `/cards/:tcgdex_id`
- **Mode:** Operate
- **Audience:** A mobile in-shop trader/collector.
- **Job:** Confirm the exact printing and understand the compact current aggregate estimate, its freshness, and its history.
- **Primary actions:** Read/verify, add this exact printing to a trade as a pending pick without choosing a side, then return through a canonical local `/trade` URL.

## Proof and content

- Exact identity.
- Local current, stale, and unpriced states.
- Source and non-affiliation context through an adjacent accessible 48px info tooltip; no exact metric, policy version, or timestamp is exposed.
- History with preserved date gaps, min/max, exact window dates, horizontal guides, and a compact Last update date/EUR summary. Exact date/EUR hover/focus tooltips are Escape-dismissible, and point controls are keyboard-focusable. There is no observation count, first-observed field, or ledger. One point remains summary-only without a chart.
- Canonical TCGdex-hosted high WebP exact-printing image when available, displayed with no-referrer hotlinking.
- `Add to a trade` preserves the exact identity and accepts only a reconstructed local `/trade` return target; malformed or open-redirect targets are rejected.

## Constraints

- Local-first; no provider call during render.
- Subscribe before requesting through Oban/PubSub.
- Do not claim seller count, condition, language, or shipping.
- Printing surfaces may use canonical TCGdex low WebP thumbnails and card detail uses the high WebP exact-printing image, both with no-referrer hotlinking. Missing images retain an honest line-art fallback.
- The site is explicitly unofficial and non-affiliated; it makes no claim of independently licensed Pokémon art.
- Put mobile identity and value first. The meaningful image column is larger; at wide desktop, compact `Current estimate` and `Printing` sit side by side in the right region. Mobile order is identity → estimate → image → Printing. History spans the full 72rem detail container.
- Preserve `.archive-world` as the CSS scope name, but supersede the prior saturated orange archive board, three boxed columns/status boxes, colored legal-format chips, and giant framed chart.
- Use calm warm paper with a subtle 1px header separator. Desktop is two columns with a larger image plus one coherent detail region; its compact estimate and Printing panels sit side by side. Mobile order is identity → estimate → image → Printing.
- Keep valuation, metadata, and history unboxed; legal formats use neutral original Fluent UI System Icons Regular paths for Standard (Card UI), Expanded (Stack), and Gym Leader Challenge (Ribbon). Tooltips use concise local status copy. GLC uses the pending `glc_local_2026-04-20` policy: Trainer and non-rule-box Pokémon are eligible unless an exact printing or Double Colorless Energy name is banned; other categories are not eligible. This is a conservative persisted-field heuristic, not a complete rules engine or future-list guarantee. Status treatment is not color-only; chart width is sensible. Exact identity, data, provenance, and history behavior remain unchanged.
- Use mobile-first stacking, at least 48px controls, and 33-50% lower mobile spatial density. Desktop content is capped at 1152px/72rem (within 1100-1200px), with 48px major section spacing and 24-32px panel spacing. Body is 16px, metadata is at least 14px, prose is at most 70ch, normal text contrast is at least 4.5:1, and focus is clear.
- Retain Barlow Condensed 700 as the documented brand/asset exception because only the approved 700 asset exists; the official Fluent Gift Card Add Regular icon appears beside every public TCG CHEAP wordmark. Azeret Mono is body/evidence, with no more than two typefaces.

## Direction

Make a calm warm-paper identity/value detail surface with coherent evidence and a compact history summary. The estimate tooltip uses concise consistent-calculation, source, and non-affiliation copy; Trade is linked only for comparison and does not support changing valuation algorithms.

## Memorable moment

The honest broken-line/dot history preserves missing days instead of implying false continuity.

Selective search, back, trade/swap, information, disclosure chevron, freshness/clock, and trend-direction controls use Microsoft’s official Fluent UI System Icons Regular as decorative `aria-hidden` inline SVGs. Icons support labels rather than replacing necessary text; the full MIT notice is in `THIRD_PARTY_NOTICES.md`.

## Unresolved decisions

- Trade composition is a completed URL-only Phase 3 flow. The side-neutral pick returns through canonical local `/trade`; the trade surface provides dated NBP EUR/PLN evidence and explicit canonical share/copy. Sealed remains unavailable; Phase 4 is next.
- Europe/Warsaw presentation if timezone infrastructure is added.
