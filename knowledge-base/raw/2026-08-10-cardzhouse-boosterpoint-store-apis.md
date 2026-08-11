# CardzHouse and BoosterPoint WooCommerce Store APIs — Raw Capture

- Collected: 2026-08-10
- Collection: Bounded, read-only HTTPS requests without credentials or access-control bypass; official API documentation, robots, and terms review.
- Status: Immutable, time-specific external evidence. Public fetchability and robots allowance are not permission for recurring collection or republication.

## Common API reference

- Official WooCommerce Store API products documentation: https://developer.woocommerce.com/docs/apis/store-api/resources-endpoints/products/
- The requests used the public unauthenticated `GET /wp-json/wc/store/v1/products` endpoint with only the fixed category, pagination, and requested fields:
  `category=<fixed-category>&per_page=100&page=<page>&_fields=id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder`
- No credentials, login, payment, CAPTCHA, redirect following, or retry was used.

## CardzHouse observation

Exact endpoint/query shape:

`https://cardzhouse.pl/wp-json/wc/store/v1/products?category=742&per_page=100&page=1&_fields=id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder`

The response reported `x-wp-total: 162`, corresponding to 2 pages at `per_page=100`. A second request used the same endpoint and fields with `page=2`. These volatile counts do not establish that every row is an eligible released English sealed Pokémon product.

Observed 151 candidate:

- ID `8393`
- Name `Pokémon TCG: 151 – Booster Bundle`
- Price `59999` PLN minor units, currency `PLN`, minor unit `2` = **599.99 PLN**
- Stock state: sold out

The bounded source review used https://cardzhouse.pl/robots.txt and the legal-information/terms page https://cardzhouse.pl/informacje-prawne/ . No explicit recurring extraction or republication grant was found in the bounded terms review. Do not fabricate quotations from either page.

## BoosterPoint observation

Exact endpoint/query shape:

`https://boosterpoint.pl/wp-json/wc/store/v1/products?category=61&per_page=100&page=1&_fields=id,name,permalink,prices,categories,tags,is_purchasable,is_in_stock,is_on_backorder`

The response reported `x-wp-total: 348`, corresponding to 4 pages at `per_page=100`. Requests for pages 2 through 4 used the same endpoint and fields. These volatile counts do not establish that every row is an eligible released English sealed Pokémon product.

Observed 151 candidate:

- ID `5423`
- Name `Pokémon TCG: Scarlet and Violet 151 – Booster Bundle (dodruk)`
- Price `18750` PLN minor units, currency `PLN`, minor unit `2` = **187.50 PLN**
- Stock state: sold out

The bounded source review used https://boosterpoint.pl/robots.txt and the store-terms page https://boosterpoint.pl/regulamin-sklepu/ . At collection time, robots explicitly disallowed `GPTBot`; the terms reserved site-content rights. Do not fabricate quotations from either page.

## Access and reuse conclusion

Both APIs were technically accessible without authentication for this bounded capture. That technical access, and any robots allowance (or non-allowance), is not a republication license. Public recurring acquisition, storage scope, attribution, and republication permission remain unresolved.
