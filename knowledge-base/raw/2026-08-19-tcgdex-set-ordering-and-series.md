# TCGdex set ordering and series capture

- Captured: 2026-08-19
- Purpose: Immutable evidence for correcting bounded collection discovery.
- Access: Public unauthenticated HTTPS GETs; no CAPTCHA bypass or access-control circumvention.
- Status: Evidence only; this grants no license, permission, authorization, or Pokémon/IP rights.

## Observations

- `GET https://api.tcgdex.net/v2/en/sets` returned 218 entries.
- First five IDs: `miscp, base1, base2, basep, wp`.
- Last twelve IDs: `mee, me01, mep, B1, me02, B1a, B2, me02.5, B2a, me03, me04, me05`.
- This is consistent with the observed oldest-first-ish tendency, with exact pilot `me05` last; it is not an API ordering contract.
- `/v2/en/sets/A4` reported `serie.id=tcgp`, release `2025-07-30`.
- `/v2/en/sets/sv10` reported `serie.id=sv`.
- `/v2/en/sets/me05` reported `serie.id=me`, release `2026-07-17`, `cardCount.total=120`, and `cardCount.official=84`.

## Operational interpretation

Collection policy v2 applies a bounded candidate ID-prefix prefilter for configured `sv`/`me`, followed by authoritative strict fetched `serie.id` revalidation; `tcgp` is excluded at fetched evidence. Priorities are: `me05` initial/continuations priority 0; an active rolling set continuation priority 1; untouched rolling initial scans priority 2. This corrects fail-slow startup caused by observed provider order and avoids Pocket fanout. Chunks, budgets, and public scope remain unchanged. No deployment or production-data claim follows. Rights, sealed-data, representative-evidence, attribution, and curated-playable blockers remain in force.
