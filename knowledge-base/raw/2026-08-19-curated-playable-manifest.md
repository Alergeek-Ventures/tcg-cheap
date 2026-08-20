# Curated playable manifest: immutable evidence capture

- Captured: 2026-08-19
- Purpose: Immutable external evidence for the proposed seven-card curated playable Trainer/Item/Supporter manifest and its Standard-legality boundary.
- Access: Public HTTPS GETs observed without authentication, CAPTCHA bypass, or access-control circumvention; TCGdex card endpoints are listed exactly below.
- Status: Evidence only; manifest evidence expires inclusive 2026-11-17 (90 days) and must be replaced/reapproved. No license or republication rights are claimed.

## Official rotation evidence

- Source: <https://www.pokemon.com/us/pokemon-news/2026-pokemon-tcg-standard-format-rotation-announcement>
- The 2026 Standard rotation makes regulation marks H, I, and J legal, and rotates G. The announcement gives 2026-04-10 for in-person events and 2026-03-26 for Pokémon TCG Live. Reprints remain legal where the current Standard rules permit the reprinted card, so legality is not inferred from a tournament list alone.

## Limitless NAIC evidence

- 1st place: <https://limitlesstcg.com/decks/list/28249>: Ultra Ball — MEG/131; Crispin — SCR/133; Boss's Orders — MEG/114; Prime Catcher — TEF/157.
- 2nd place: <https://limitlesstcg.com/decks/list/28236>: Lillie's Determination — MEG/119; Crispin — SCR/133; Boss's Orders — MEG/114; Ultra Ball — MEG/131; Buddy-Buddy Poffin — TEF/144; Unfair Stamp — TWM/165.

## TCGdex exact identity and legality observations

Observed 2026-08-19 from the exact card endpoints:

| TCGdex ID | Card | Category | Regulation | Legality | Endpoint |
| --- | --- | --- | --- | --- | --- |
| `me01-131` | Ultra Ball | Trainer / Item | I | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/me01-131> |
| `sv05-144` | Buddy-Buddy Poffin | Trainer / Item | H | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/sv05-144> |
| `sv05-157` | Prime Catcher | Trainer / Item | H | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/sv05-157> |
| `sv06-165` | Unfair Stamp | Trainer / Item | H | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/sv06-165> |
| `sv07-133` | Crispin | Trainer / Supporter | H | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/sv07-133> |
| `me01-114` | Boss's Orders | Trainer / Supporter | I | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/me01-114> |
| `me01-119` | Lillie's Determination | Trainer / Supporter | I | `legal.standard=true` | <https://api.tcgdex.net/v2/en/cards/me01-119> |

All seven observations reported category `Trainer` and `legal.standard=true`. The set-code crosswalk came from the exact Limitless product links and exact TCGdex IDs, not from card-name inference. Limitless evidence is tournament evidence, not a license or automatic editorial approval.

## Replacement boundary

This dated manifest is valid only through 2026-11-17 inclusive. It must be replaced with fresh evidence and reapproved before expiry; any implementation must also recheck official legality and exact identity before rows become public.
