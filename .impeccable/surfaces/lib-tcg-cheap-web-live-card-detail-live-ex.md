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
- **Job:** Confirm the exact printing and understand the current aggregate estimate, its freshness, and its history.
- **Primary actions:** Read/verify, then return to search. Defer a trade action until Phase 3 exists.

## Proof and content

- Exact identity.
- Local current, stale, and unpriced states.
- Source, metric, policy, and UTC timestamp.
- Fixed 30-day daily history with gaps, plus an accessible ledger.
- Canonical TCGdex-hosted high WebP exact-printing image when available, displayed with no-referrer hotlinking.

## Constraints

- Local-first; no provider call during render.
- Subscribe before requesting through Oban/PubSub.
- Do not claim seller count, condition, language, or shipping.
- Printing surfaces may use canonical TCGdex low WebP thumbnails and card detail uses the high WebP exact-printing image, both with no-referrer hotlinking. Missing images retain an honest line-art fallback.
- The site is explicitly unofficial and non-affiliated; it makes no claim of independently licensed Pokémon art.
- Put mobile identity and value first.
- Preserve the archive-wall world.

## Direction

Make a ruled archive identity/value sheet with a tissue history ledger.

## Memorable moment

The honest broken-line/dot history preserves missing days instead of implying false continuity.

## Unresolved decisions

- Future trade CTA.
- Europe/Warsaw presentation if timezone infrastructure is added.
