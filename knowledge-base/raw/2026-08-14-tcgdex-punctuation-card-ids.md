# TCGdex punctuation card-ID capture

- Collected: 2026-08-14
- Source: Public TCGdex v2 English API
- Credentials: None
- Purpose: Preserve the provider evidence that exposed two valid card identities rejected by the earlier local grammar.

## Set response

`GET https://api.tcgdex.net/v2/en/sets/exu` returned HTTP 200. Relevant fields:

```json
{
  "cardCount": {"official": 28, "total": 28},
  "cards": [
    {"id": "exu-!", "localId": "!", "name": "Unown"},
    {"id": "exu-%3F", "localId": "%3F", "name": "Unown"},
    {"id": "exu-A", "localId": "A", "name": "Unown"}
  ],
  "id": "exu",
  "name": "Unseen Forces Unown Collection"
}
```

The returned `cards` array contained 28 entries. The remaining entries were `exu-B` through `exu-Z`.

## Exact-card path behavior

- `GET https://api.tcgdex.net/v2/en/cards/exu-!` returned HTTP 200 with `id: "exu-!"` and `localId: "!"`.
- `GET https://api.tcgdex.net/v2/en/cards/exu-%253F` returned HTTP 200 with `id: "exu-%3F"` and `localId: "%3F"`.
- `GET https://api.tcgdex.net/v2/en/cards/exu-%3F` returned HTTP 404.

The literal provider identity includes the three characters `%3F`; a path request therefore encodes the percent sign and sends `%253F` on the wire. This capture establishes only the observed identity/path behavior at collection time. It does not establish catalogue completeness, pricing availability, licensing, or long-term provider reliability.
