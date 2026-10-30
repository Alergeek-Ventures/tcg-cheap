# Product

<!-- impeccable:product-schema 1 -->

> Product owner direction, 2026-10-30. The full product north star is
> [Buying and Trading Guide](knowledge-base/wiki/product/buying-and-trading-guide.md).

## Platform

web

## Users

- Polish Pokémon TCG fans (players, collectors, parents buying gifts) who want
  to buy sealed products (boosters, bundles, booster boxes, Elite Trainer
  Boxes, tins, collections) without overpaying.
- The same fans when trading single cards with friends or in a local shop.

## Product Purpose

A deliberately simple guide with two parts:

1. **Zakupy (buying guide, live):** for any sealed Pokémon product, show where
   it is cheapest in Polish shops right now and whether that price is good,
   normal or expensive compared with what the product has really cost lately.
2. **Wymiany (trading guide, next phase):** check whether a trade of single
   cards is fair.

## Positioning

An honest, independent price check in Polish. Verdicts are based only on
prices you can actually buy at (in-stock offers in Polish shops, falling back
to the Cardmarket trend), never on MSRP. Missing data is shown as missing.

## Operating Context

- On a phone in a shop or at a fair: "is this price OK?" in seconds.
- On desktop before buying online: compare shops and see the price history.
- No accounts. Prices exclude shipping.

## Capabilities and Constraints

- Catalogue: every sealed Pokémon product listed on Cardmarket (≈4,400),
  imported daily; images come from matched Polish shop offers.
- Offers: six Polish shops (LootQuest, CardzHouse, BoosterPoint, PokeBooster,
  Boosterland, Colligere) fetched once a day and matched to products
  automatically; an administrator can assign the rest by hand.
- Verdict: typical price = median of the daily lowest Polish in-stock price
  over 30 days (≥ 7 days with stock), otherwise the Cardmarket trend in PLN.
  Good ≤ 95%, normal ≤ 110%, expensive above; thresholds are shown in złoty so
  a price seen in a physical shop can be judged too.
- Public pages read only the local database; shops and Cardmarket are fetched
  by background jobs.
- The singles/trade pages are still English and will be simplified next.

## Evidence on Hand

- Application code and tests in `lib/` and `test/`.
- Real daily feeds from the six shops and Cardmarket's public product and
  price files.
- No testimonials or customer proof yet. The site is unofficial and not
  affiliated with The Pokémon Company or the shops.

## Product Principles

- Simple over complete: every screen and feature must earn its place.
- Realistic over official: what you can buy it for, not the catalogue price.
- Honest gaps over invented numbers.
- Polish first: copy, number and date formats for Polish users.

## Accessibility & Inclusion

- Polish interface for the buying guide; mobile-first and responsive.
- Semantic markup, keyboard access, visible focus, sufficient contrast,
  48px touch targets, no horizontal overflow at 390px.
- Verdicts never rely on colour alone (text label plus icon).
