# Scrappy Singles Acquisition Spike

- Collected: 2026-08-07
- Method: bounded public-doc/HTTP/browser experiments; temporary evaluation accounts only; no provider credentials retained in repository

## TCG Scraper

Public documentation at https://tcg-scraper.com/ shows Free 100 requests/month and Starter €29/month for 25,000/month. The documented `/api/v1/product` request uses `X-API-Key`, a Cardmarket URL, `language`, `minCondition`, and optional `sellerReputation`.

The public example exposes product metadata and summary fields (`total_offers`, `lowest_price`, `sellers_count`, condition counts), but does not document seller identity, destination, quantity, currency, or an offer array. A temporary evaluation account/key was created. One product call exceeded a 30-second client timeout. A second fresh-key call to the documented Charizard example returned HTTP 502 after about 44.7 seconds with Cloudflare HTML rather than JSON. Test keys were revoked and browser sessions signed out; no key was retained.

## cardmarketapi.com

One temporary 3-day free-trial key was confirmed and used for `GET /api/v1/card/869888`. The response was HTTP 200 after about 29.2 seconds, with `X-Cache: MISS` and rate-limit header 10. JSON had top-level `id`, `game`, `name`, `expansion`, `image_url`, `currency`, `filter`, `prices`, `listings`, `fetched_at`, and `source`.

There were exactly 50 listings. Every observed listing had only `cond`, `country`, `lang`, and `price`; no seller/user/shop identity and no quantity. There were 17 distinct seller countries, one language, and two conditions because `condition=nm` means NM-or-better. Currency was EUR; `avg5` and a timestamp were present; total availability was 241. The free-trial key was not stored and browser auth/storage was cleared; it naturally expires with the trial.

The current machine-readable https://cardmarketapi.com/panel/api/plans showed Starter $49.99/30 days and 500/day, conflicting with some documentation advertising higher quotas. This requires reconciliation.

## Direct Cardmarket

A direct browser GET for the documented TCG Scraper Charizard Obsidian Flames product URL returned HTTP 403 with “Just a moment”. This was not necessarily Cardmarket product ID 869888. No bypass was attempted.

## Candidate services and supporting evidence

- Apify Phantom Coder actor, https://apify.com/phantom_coder/cardmarket-listings-scraper, documents rows with `sellerName`, condition, language, quantity, price, currency, sellerComment, and product URL; seller-country input; max results 1–500; and $0.005/listing Free / $0.004 Starter pricing. It reports 97.1% successful runs. Documented destination eligibility is absent. A credentialed run did not complete because automated temporary signup stalled at identity/hCaptcha; form data was cleared. No account creation is claimed.
- Parse.bot Cardmarket API, https://parse.bot/marketplace/d6eff58a-dd95-45bc-886b-f1cd346d961c/cardmarket-com-api, documents seller usernames, condition, attributes, price, quantity, comments, pagination up to Cardmarket's 300 cap, seller-country filtering, and a 10/10 endpoint health claim. Pricing is Free 100 credits or Hobby $30/1,000 credits; listing calls cost 2 credits. Destination eligibility is absent. Temporary automated signup stalled at hCaptcha and inputs were cleared; no credentialed call occurred.
- Cardmarket shipping help, https://help.cardmarket.com/en/ShippingCosts, says shipping depends on origin, destination, weight, and dimensions. Seller guide/news confirms sellers can opt out of countries, so seller country alone is not proof of shipping to Poland.

## External operational footprint

Two TCG Scraper evaluation accounts remain with revoked keys. One CardmarketAPI trial account/key remains ephemeral until trial expiry, but credentials were not retained. Temporary mailbox accounts were used. Apify/Parse accounts were not completed. These observations are time-specific.
