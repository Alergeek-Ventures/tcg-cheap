# Production Singles scope: primary-source capture

- Captured: 2026-08-19
- Purpose: Immutable evidence for the approved fail-closed Singles production collection scope.
- Access: Public HTTPS pages/GETs observed without authentication, CAPTCHA bypass, or access-control circumvention.
- Status: Evidence only; this does not grant production permission, a data license, or Pokémon/IP rights.

## Sources and observations

### TCGdex

- Live endpoint: <https://api.tcgdex.net/v2/en/sets/me05>
- `me05` was observed as Mega Evolution—Pitch Black, release `2026-07-17`, with `cardCount.official` `84`, `cardCount.total` `120`, and a `cards` array containing 120 briefs. This is complete set-list evidence: 84 official cards within 120 total cards, not 84 returned briefs.
- Set shape observed: identity/name, series, logo/symbol, release date, legalities, `cardCount`, and `cards`. Set card briefs include identity/basic brief fields such as `id`, `localId`, `name`, and image references. Rarity and category are taken from detailed card responses, which is why the worker fetches details; detailed cards also add set linkage, variants, legalities, illustrator, HP/types, attacks, weaknesses/resistances, retreat cost, and image references.
- Rarity strings observed include `Common`, `Uncommon`, `Rare`, `Double Rare`, `Ultra Rare`, `Illustration Rare`, `Special Illustration Rare`, `Hyper Rare`, and `ACE SPEC Rare`. These provider strings do not decide playability.

### Official Pokémon

- Announcement: <https://www.pokemon.com/us/pokemon-news/the-pokemon-tcg-mega-evolution-pitch-black-expansion-arrives-july-17-2026>
- Expansion overview/gallery: <https://tcg.pokemon.com/en-us/expansions/pitch-black/>
- Product gallery: <https://www.pokemon.com/us/pokemon-tcg/product-gallery/mega-evolution-pitch-black-booster-bundle>
- Official pages corroborate the Pitch Black/PBL release date `2026-07-17` and present official product/card material. They do not substitute for complete TCGdex `cardCount` evidence or grant reproduction rights.

### Official rotation

- <https://www.pokemon.com/us/pokemon-news/2026-pokemon-tcg-standard-format-rotation-announcement>
- The official announcement states 2026 Standard rotation starts 2026-04-10 for in-person events and 2026-03-26 for Pokémon TCG Live, with regulation-mark and reprint rules. Legality must be checked against current official rules/data.

### Limitless future candidate evidence

- Results: <https://limitlesstcg.com/tournaments>
- Tournament platform: <https://play.limitlesstcg.com/tournaments>
- Developer documentation: <https://docs.limitlesstcg.com/developer.html>
- These are candidate locations for dated tournament/deck evidence and developer-accessible data, not automatic curation or a republication license.

## Scope and caveats

The approved application scopes are `pitch_black_full`, `rolling_ir_sir`, `curated_playable`, and `legacy_local`. Curated playables remain empty until dated Limitless evidence, official legality evidence, and explicit editorial approval. No sealed production adapter is enabled.

TCGdex availability or repository/artifact licensing does not establish Pokémon artwork/IP rights, marketplace redistribution rights, or production authorization. Official Pokémon pages establish release/rules information, not a license for this application. Limitless access establishes candidate evidence only. Preserve attribution, terms, rate limits, provider constraints, and permission review; make no affiliation, endorsement, IP ownership, or broad production-permission claim.
