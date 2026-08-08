# LootQuest WooCommerce Store API — Raw Capture

- Collected: 2026-08-09
- Collection: Bounded, read-only HTTPS requests without credentials or access-control bypass; official store terms and robots review.
- Status: Immutable, time-specific external evidence. Public fetchability is not permission for recurring production collection or republication.

## Endpoint observation

The public WooCommerce Store API request below returned HTTP 200:

`https://lootquest.pl/wp-json/wc/store/v1/products?category=55&per_page=1&page=1&_fields=id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder`

The response exposed exactly the requested top-level fields. At collection time, response headers reported `x-wp-total: 492` and `x-wp-totalpages: 492` for `per_page=1`. These counts are volatile and do not prove that every row is an eligible released English sealed Pokémon product.

Observed eligible-shape example:

- ID: `165955`
- Name: `Pokémon TCG: First Partner Illustration Collection &#8211; Series 3`
- Permalink: `https://lootquest.pl/produkt/pokemon-tcg-first-partner-illustration-collection-series-3/`
- Price: minor-unit string `24999`, currency `PLN`, minor unit `2`
- Categories included `pokemon-tcg` and `pokemon-zestawy`
- Tags included `first-partner` and `nowosci-pokemon`
- `is_purchasable: true`, `is_in_stock: true`, `is_on_backorder: false`

The same public catalogue also exposed ineligible imports. Observed example:

- ID: `165139`
- Name: `Pokémon TCG &#8211; KOREA: &#8222;Abyss Eye&#8221; Booster`
- Permalink: `https://lootquest.pl/produkt/pokemon-tcg-korea-abyss-eye-booster/`
- Price: minor-unit string `899`, currency `PLN`, minor unit `2`
- Categories included `pokemon-tcg` and `pokemon-korean`

This proves the need for fail-closed filtering and canonical-product review; a broad Pokémon category is not a production catalogue of official English products distributed in Poland.

## Access and reuse boundary

- [LootQuest robots](https://lootquest.pl/robots.txt) named `bingbot` and `mj12bot` with a 10-second crawl delay and disallowed `dotbot`. It did not establish a general data-reuse or republication license.
- [LootQuest store terms](https://lootquest.pl/regulamin/) section 2.3 required lawful use and respect for copyright and intellectual-property rights. No explicit grant for recurring automated extraction, storage, commercial comparison, or republication was found in this bounded review.
- The Store API is technically public and unauthenticated, but production polling and public display remain disabled until written retailer permission defines permitted fields, cadence, attribution, storage, and republication.

The repository fixture preserves only the exact top-level granularity requested by the adapter. No description or image field was requested or retained. No real retailer, listing, observation, or production schedule was created from this capture.
