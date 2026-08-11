# Sealed Buying Model v1

- Updated: 2026-08-10
- Sources: [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md); [CardzHouse and BoosterPoint Store API capture](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md); project code; local synthetic validation
- Raw: [2026-08-10 CardzHouse and BoosterPoint Store APIs](../../raw/2026-08-10-cardzhouse-boosterpoint-store-apis.md)

**Status:** `sealed_buying_model_v1` is the initial pure, deterministic, versioned
sealed buying-policy implementation. Its weights and boundaries are provisional
until representative real Polish-market observations are available. Its outputs are
now persisted as local buying-guide snapshots and consumed by the public sealed page
through a fail-closed projection. Its exact current policy is also available through
authenticated read-only operations inspection.

Private feasibility checkpoint: the approved `Pokémon TCG: Scarlet & Violet—151 Booster Bundle` produced `limited / too_few_regular_retailers` with one regular retailer, and its guide produced `limited / limited_market_aggregate` at confidence `0.19`; no bands were fabricated. Browser search/detail showed one 899.99 PLN LootQuest offer and honest Limited-data messages with zero console errors. This validates sparse/Limited behavior only, not ready benchmark bands, representative Polish-market weights, multi-shop deduplication/outliers, recurring stock history, or public source rights.

The later private CardzHouse and BoosterPoint runs do not change that model boundary: both real shops are deliberately `lgs`, not representative regular-retailer evidence; all new mappings remain review because no reliable GTINs were supplied; and no candidate was approved without an authenticated administrator. Jobs 88/89 retained 96/232 rows and unchanged jobs 90/91 retained exactly those counts, while current aggregate/guide/public-offer behavior remains unchanged. Public recurring acquisition/republication permission remains unresolved.

## Decision

Use a fixed explainable model that combines the current robust regular-retailer
benchmark with optional MSRP, fresh LGS prices, and recent sold-out prices. Require
current evidence plus enough retained aggregate history before publishing four
bands. Return **Limited data** rather than deriving bands when a hard requirement
or confidence threshold fails.

The model remains separate from `sealed_market_daily_v1`. The daily aggregate owns
freshness filtering, one cheapest current offer per retailer, regular/LGS category
separation, and Tukey-IQR outlier removal for the regular-retailer benchmark. The
buying model validates and consumes that versioned result; it does not duplicate or
silently replace the aggregate algorithm.

## Inputs and defensive contract

The calculation receives:

- one current `sealed_market_daily_v1` aggregate;
- ready/limited aggregate history through a fixed 30-calendar-day window;
- optional finite positive PLN MSRP;
- one exact snapshot-aligned fresh LGS evidence row per counted LGS, with retailer
  ID, PLN price, and check time;
- latest-per-retailer sold-out price evidence matching the aggregate's inclusive
  0–14 and 15–30-day counts; and
- an explicit mapping-confidence decision.

Wrong aggregate versions, future or incoherent timestamps, nonfinite/non-positive
prices, contradictory same-time sold-out prices, duplicate LGS retailer IDs,
evidence/count mismatches, and impossible source counts fail with an error. Weak
but coherent evidence returns a limited result. All Decimal work runs inside a
fixed decimal128 context (precision 34, half-up arithmetic, exponent limits 6144
and -6143) and final money/confidence values use explicit half-up two-decimal
rounding, so caller process context cannot change a result.

## Reference price

Available component centers use these initial weights:

| Component | Weight | Trade-off |
| --- | ---: | --- |
| Robust regular-retailer benchmark | 0.55 | Primary live-market signal and intentionally dominant. |
| MSRP/RRP | 0.25 | First reference point, but not allowed to override current market evidence. |
| Median of fresh LGS evidence | 0.10 | Separate specialist-market support without treating LGS prices as regular-retailer observations. |
| Recency-weighted sold-out center | 0.10 | Adds scarcity context without letting expired promotions dominate indefinitely. |

Missing optional components cause the remaining weights to be renormalized rather
than treated as zero-price evidence. Sold-out prices checked 0–14 days before the
aggregate receive weight `1.00`; those 15–30 days old receive `0.35`; older rows do
not contribute. The LGS center is a median over one validated row per retailer.

## Confidence and hard requirements

Confidence is a weighted score from zero to one:

| Evidence | Weight | Full-credit target |
| --- | ---: | --- |
| Regular-retailer coverage | 0.30 | 8 fresh regular retailers |
| History | 0.25 | 3 unique ready points spanning at least 7 days |
| Current evidence freshness | 0.15 | Latest evidence no more than 7 days old, inclusive |
| MSRP present | 0.10 | One valid MSRP |
| LGS support | 0.10 | 2 fresh LGS retailers |
| Sold-out support | 0.10 | 2 latest-per-retailer priced rows within 30 days |

History credit multiplies point and span coverage, preventing several same-period
points from claiming complete history. A ready result requires confidence at least
`0.65` plus all hard requirements: confident mapping, a ready current market
aggregate, fresh current evidence, at least the aggregate's five regular retailers,
three ready points, and a seven-day span.

Limited reasons have deterministic precedence:

1. `uncertain_mapping`
2. `limited_market_aggregate`
3. `stale_market_evidence`
4. `insufficient_history`
5. `low_confidence`
6. `invalid_band_boundaries`

The last reason is a defensive fail-closed state when valid positive inputs become
non-strict band boundaries after two-decimal rounding.

## Trend, availability, and four bands

Trend compares the earliest eligible ready benchmark with the current benchmark:
at least +5% is rising, at most -5% is falling, and the middle is stable.
Availability is abundant with at least 8 regular retailers and at most 1 recent
sold-out retailer. It is scarce when at most 5 regular retailers accompany at
least 3 recent sold-out retailers, or recent sold-out coverage exceeds half of
current regular-plus-LGS coverage. Otherwise it is balanced. Availability trend
becomes tightening/improving when current coverage or recent sold-out evidence
moves by at least 2 versus the earliest eligible point.

Three dynamic ceilings create four explicit bands:

| Ceiling | Base reference multiplier | Adjustment |
| --- | ---: | --- |
| Great price maximum | 0.90 | Trend ±0.02, availability ±0.02, availability trend ±0.01 |
| Fair price maximum | 1.05 | Same combined adjustment |
| Expensive maximum | 1.20 | Same combined adjustment |
| Avoid | Above the expensive maximum | No upper bound |

The Great ceiling cannot exceed the aggregate's typical low; the Fair ceiling
cannot fall below the market benchmark; and the Expensive ceiling cannot fall
below 1.05 times the typical high. Ceilings are inclusive and belong to the cheaper
preceding band; the next band's lower bound is exclusive. The public UI renders
inclusive ceilings with unambiguous at-or-below/above wording rather than overlapping ranges.

The result retains reference/component centers, confidence, trend and availability
states, four explicit interval records, and ordered machine-readable explanation
factors. Snapshot persistence and public plain-English explanations consume these
outputs rather than recalculating model policy in the LiveView. The public projection
validates expected product binding, exact aggregate and preceding-history
fingerprints, source-relative history, and time/version/currency/state/money/factor/
trend invariants; corrupt, mismatched, or unreadable data fails closed. Exact ready
guides render four inclusive-ceiling Great/Fair/Expensive/Avoid ranges, while exact
Limited guides render collector-readable reasons/factors. Older-ready and
newest-limited/older-ready combinations are explicitly previous/cached/outdated,
never current.

## Synthetic validation

The focused suite covers every representative case required before real-data
validation:

- widely available below MSRP: confidence `0.80`, reference `109.38`, and ceilings
  `90.00 / 111.57 / 127.97` PLN;
- widely available around MSRP: confidence `0.80`, reference `100.00`, and ceilings
  `88.00 / 103.00 / 118.00` PLN;
- scarce and rising after lower offers sold out: confidence `0.79`, reference
  `110.89`, and ceilings `90.00 / 121.98 / 138.61` PLN;
- cheap and expensive single-shop outliers removed by the upstream aggregate;
- a falling reprint: confidence `0.80`, reference `102.81`, and ceilings
  `88.42 / 103.84 / 119.26` PLN;
- a new release with insufficient history;
- one active shop limited by the market aggregate; and
- sporadic five-shop evidence limited by low confidence.

Tests also cover exact 7/14/30-day boundaries, 30-day history inclusion, Decimal
context isolation, evidence permutation, duplicate/conflicting retailer evidence,
four-band interval semantics, nonfinite values, malformed aggregate state, and
rounded-boundary failure.

These are synthetic policy fixtures, not proof of Polish-market quality.

## Consequences and remaining work

- The version and full policy are inspectable and deterministic, enabling future
  persisted snapshots to retain their meaning after a v2 model exists.
- The policy now explicitly publishes the strict recent-sold-out-majority scarcity
  rule and the aggregate typical-low/benchmark/typical-high band guardrails that were
  already applied by calculation. Authenticated `/admin/operations` renders the full
  decision policy through a bounded read-only projection. A deterministic exact-v1
  fingerprint rejects malformed or silently changed same-version policy, so changed
  weights or rules require a new model version. The desk labels v1 provisional and
  synthetic-only and exposes no edit or recomputation control.
- The model is intentionally conservative: missing MSRP alone does not always
  prevent readiness, but weak combined support falls below confidence; insufficient
  history always limits output.
- Current history uses first-to-current change rather than regression or
  interpolation. Missing days remain missing.
- LGS uses a robust median but no separate outlier fence; its 0.10 weight bounds its
  influence. Real validation may justify a v2 change rather than mutating v1.
- `SealedBuyingGuideSnapshot` persistence and exact-revision recomputation are now
  implemented. The daily aggregate retains policy-relevant normalized source evidence,
  snapshot-time MSRP, explicit mapping confidence, and a canonical SHA-256 revision;
  aggregate persistence and guide enqueue commit atomically. The guide stores model
  outputs, component centers, confidence, trend/availability, explanation factors,
  the current source fingerprint, and a canonical fingerprint of the exact preceding
  30-day aggregate revisions. Persistence locks and rechecks every consumed revision,
  and historical corrections enqueue every persisted following guide date through the
  end of the affected window.
- Real Polish retailer/SKU data and weight validation remain unfinished. The public
  bands, persisted-factor explanations, and fixed 30-day sealed graph are implemented
  in code: `SealedDailyAggregatePublic` defensively validates public aggregate state,
  while `SealedMarketHistory` renders an accessible fixed UTC-calendar-day SVG with
  benchmark line, typical-range band, missing-day gaps, no controls/interpolation,
  and a textual ledger using only canonical ready rows for the expected product.
  Under the 2026-08-10 product-owner assumption, private/local/staging source polling and
  real-data validation are permitted technical-feasibility work, subject to budgets, rate
  limits, safety controls, attribution, and provider constraints. External permission
  remains the boundary for public acquisition/republication and public launch; this is not
  a legal authorization claim. Local persistence and public rendering remain technically
  exercisable without claiming public source rights.

## See Also

- [Application Foundation](application-foundation.md)
- [Provider and Acquisition Feasibility](provider-acquisition-feasibility.md)
- [Detailed MVP Implementation Plan](../product/mvp-implementation-plan.md)
