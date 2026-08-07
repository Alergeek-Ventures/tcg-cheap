# Provider and Source Experiments — Raw Capture

- Collected: 2026-08-07
- Collection: Bounded, read-only HTTP experiments using the existing Req client; no credentials and no bypassing access controls.
- Status: Immutable external evidence capture for the provider-acquisition feasibility ADR. Observations are time-specific.

## Primary source URLs and exact observations

These are concise captures of the independently verified requests, not broad conclusions.

- [`https://api.tcgdex.net/v2/en/cards`](https://api.tcgdex.net/v2/en/cards) — `GET` returned HTTP 200 and a JSON list of 23,444 cards. First observed brief item: `id: exu-!`, `localId: !`, `name: Unown`.
- [`https://api.tcgdex.net/v2/en/cards/base1-4`](https://api.tcgdex.net/v2/en/cards/base1-4) — `GET` returned HTTP 200. Observed `id: base1-4`, `localId: 4`, `name: Charizard`; Cardmarket pricing included `idProduct: 273699`, currency `EUR`, updated `2026-08-07T08:03:04.680Z`. The response exposed first-edition and holo variant flags. This live price is volatile and is not preserved as a decision input.
- [`https://api.pokemontcg.io/v2/cards?page=1&pageSize=1&select=id,name,set,number,rarity,legalities,regulationMark,images`](https://api.pokemontcg.io/v2/cards?page=1&pageSize=1&select=id,name,set,number,rarity,legalities,regulationMark,images) — `GET` returned HTTP 200; `totalCount: 20,479`; first observed card `id: hgss4-1`, `name: Aggron`.
- [`https://api.cardmarket.com/ws/v2.0/output.json/games`](https://api.cardmarket.com/ws/v2.0/output.json/games) — `GET` returned HTTP 410 with: `Please switch to https://apiv2.cardmarket.com`.
- [`https://cardmarketapi.com/api/v1/card/869888`](https://cardmarketapi.com/api/v1/card/869888) — `GET` without a key returned HTTP 401.
- [`https://hurt.rebel.pl/categories/pokemon-me-04-chaos-rising-7005.html`](https://hurt.rebel.pl/categories/pokemon-me-04-chaos-rising-7005.html) — `GET` returned HTTP 200 and 108,678 bytes in this fetch; content contained `SCD` and `Chaos Rising`.
- [`https://www.tcglove.pl/pokemon-tcg`](https://www.tcglove.pl/pokemon-tcg) — `GET` returned HTTP 200 and 417,542 bytes in this fetch; content contained `Pokémon` and `application/ld+json`.
- [`https://www.mediaexpert.pl/szukaj?query%5Bquery%5D=pokemon%20tcg`](https://www.mediaexpert.pl/szukaj?query%5Bquery%5D=pokemon%20tcg) — final independent `GET` returned HTTP 404. An earlier bounded research fetch saw HTTP 403. This is unstable/not suitable as an unattended public endpoint; no bypass was attempted.
- [`https://api.cardtrader.com/api/v2/games`](https://api.cardtrader.com/api/v2/games) — `GET` returned HTTP 401; the response identified unauthorized access.
- [`https://api.justtcg.com/v1/games`](https://api.justtcg.com/v1/games) — `GET` returned HTTP 401 with `MISSING_API_KEY`.
- [`https://www.pokemonpricetracker.com/api/v2/cards?search=charizard&limit=1`](https://www.pokemonpricetracker.com/api/v2/cards?search=charizard&limit=1) — `GET` returned HTTP 401 with a missing Authorization header.

## Primary documentation excerpts and claims

- [Cardmarket API help](https://help.cardmarket.com/en/cardmarket-api): “Currently, we are not accepting applications for access to the Cardmarket API.”
- [Cardmarket price guide and product catalogue announcement](https://news.cardmarket.com/en/Magic/were-making-the-price-guide-and-product-catalogue-available-for-download): the price guide is updated once daily; the product catalogue is updated when releases are added; the old API endpoint is deprecated.
- [TCGdex FAQ](https://tcgdex.dev/faq): no authentication; no published hard rate limits; cache bulk data. It also records known missing images/cards, wrong/shared marketplace mappings, and that `variants_detailed` is still evolving.
- [Pokémon TCG API rate limits](https://docs.pokemontcg.io/getting-started/rate-limits/): without a key, 1,000 requests/day and a maximum of 30/minute; with a key, the default is 20,000/day.
- [cardmarketapi.com documentation](https://cardmarketapi.com/docs): Starter is `$49.99/month`, 2,000/day, with a one-hour cache; filters include language and minimum condition. Its listing schema documents condition/language/country/price, but no seller identity and no destination/shipping-to-Poland field. The site says it live-scrapes Cardmarket pages; this capture does not characterize it as licensed.
- [CardTrader full API reference](https://www.cardtrader.com/en/docs/api/full/reference): docs require Bearer authentication; blueprints expose Cardmarket IDs; marketplace product responses document condition/language, seller `user.id`/username/country, and the cheapest 25 products. Shipping methods are a separate authenticated request by seller username, described as shipping “from his country to yours.” The marketplace endpoint is lightly cached and rate-limited. CardTrader is only an independent marketplace candidate until a Poland-account request shape, exact Pokémon fields, commercial terms, and per-card call cost are verified.
- [JustTCG quickstart](https://justtcg.com/docs/quickstart): an API key is required. [Current pricing/home](https://justtcg.com/) showed Free 1,000 calls/month personal, Starter `$19/month + tax` for 10,000 calls/month, and Professional `$49/month + tax` for 50,000 calls/month. Paid tiers claim commercial display/storage rights, but no seller identity or Poland-destination offer eligibility is documented for the required valuation.
- [PokemonPriceTracker API/pricing](https://www.pokemonpricetracker.com/pokemon-card-price-api): the page showed Business `$99/month`, Cardmarket EUR prices, and commercial use; it is over budget and aggregate-oriented.
- [ISA terms, Article 8.4](https://isa.pl/regulamin.html): Article 8.4 requires permission for use and prohibits aggregation/processing for redistribution.
- [TCGdex repository license](https://github.com/tcgdex/cards-database/raw/refs/heads/master/LICENSE): the repository software/data artifact is MIT-licensed; this does not grant Pokémon image/IP or marketplace redistribution rights.
- [REBEL B2B regulations](https://hurt.rebel.pl/regulations): business verification; starter order 3,000 PLN net; at least 1,500 PLN net every three months; suggested prices are not binding; current warehouse amounts are account-visible. SCD is therefore a suggested reference, not authoritative MSRP.
- [TCG Love robots](https://www.tcglove.pl/robots.txt): crawl delay/request-rate is one request per second, with disallowed paths.

## Additional primary evidence URLs

These URLs were recorded for follow-up; this capture does not fabricate fetched response details for them:

- [TCGdex card reference](https://tcgdex.dev/reference/card)
- [TCGdex sets REST docs](https://tcgdex.dev/rest/sets)
- [TCGdex cards database](https://github.com/tcgdex/cards-database)
- [TCGdex repository license](https://github.com/tcgdex/cards-database/raw/refs/heads/master/LICENSE)
- [Pokémon TCG API card docs](https://docs.pokemontcg.io/api-reference/cards/card-object/)
- [Pokémon TCG API data repo](https://github.com/PokemonTCG/pokemon-tcg-data)
- [Cardmarket general terms](https://www.cardmarket.com/en/Policies/GeneralTermsAndConditions) — bounded unauthenticated fetch returned HTTP 403; this remains the official link.
- [Cardmarket downloads](https://www.cardmarket.com/Data/Download)
- [Cardmarket Pokémon price guide](https://www.cardmarket.com/en/Pokemon/Data/Price-Guide)
- [CardTrader full API reference](https://www.cardtrader.com/en/docs/api/full/reference)
- [JustTCG quickstart](https://justtcg.com/docs/quickstart)
- [JustTCG pricing/home](https://justtcg.com/)
- [PokemonPriceTracker API/pricing](https://www.pokemonpricetracker.com/pokemon-card-price-api)
- [ISA terms](https://isa.pl/regulamin.html)
- [REBEL retail robots](https://www.rebel.pl/robots.txt)
- [Empik Pokémon search](https://www.empik.com/szukaj/produkt?q=pokemon%20tcg)
- [Smyk](https://www.smyk.com/)
- [Graal Pokémon category](https://sklep-graal.pl/pl/c/Pokemon-TCG/25)
- [LootQuest Pokémon category](https://lootquest.pl/kategoria-produktu/karciane/pokemon-tcg/)
- [PokeCollect](https://pokecollect.pl/)
- [ShopGracz Pokémon category](https://shopgracz.pl/39-pokemon-tcg)
- [Centrum MTG Pokémon](https://www.centrum-mtg.com.pl/pokemon)
- [Strefa MTG](https://strefamtg.pl/)
- [Plan-Sza](https://plan-sza.pl/)
- [Guildmage](https://guildmage.pl/)

This evidence is what is available to the compiled ADR. Raw observations, response sizes, counts, prices, and availability statements are time-specific and must be rechecked before implementation.
