# Boosterland and Colligere Store API capture

- Source/collection date: 2026-09-02; bounded live adapter smoke, no persistence or production ingestion.
- Boosterland endpoint: <https://boosterland.pl/wp-json/wc/store/v1/products?category=40&per_page=1>
- Boosterland robots: <https://boosterland.pl/robots.txt>
- Boosterland terms: <https://boosterland.pl/regulamin/>
- Colligere endpoint: <https://colligere.pl/wp-json/wc/store/v1/products?category=23&per_page=1>
- Colligere robots: <https://colligere.pl/robots.txt>
- Colligere terms: <https://colligere.pl/regulamin/>

## Observed API samples

Boosterland category 40 returned sample ID `3935`, title `Pokémon TCG: 30th Celebration – Binder Collection`, permalink <https://boosterland.pl/sklep/pokemon/30-lecie/pokemon-tcg-30th-celebration-binder-collection/>, image <https://boosterland.pl/wp-content/uploads/2026/08/binder.jpg>, price `29900` PLN minor units, and stock text `19 w magazynie`.

Colligere category 23 returned sample ID `17025`, title `Pokémon TCG: 30th Celebration – Ex Box – Greninja ex`, permalink <https://colligere.pl/sklep/pokemon-tcg-30th-celebration-ex-box-greninja-ex/>, image <https://colligere.pl/wp-content/uploads/2026/08/Pokemon_30th_Greninja_ex_Box_od_lewej.webp>, price `18995` PLN minor units, and stock text `1 w magazynie`.

The bounded adapter smoke returned 8 eligible Boosterland listings and 35 eligible Colligere listings. Both are classified `lgs`; each source is bounded to 50 requests/hour, 100/day, and 500/month. No persistence or production ingestion is claimed. PokeNest's API was technically reachable, but it was rejected because its terms §16 disallows content use without written permission. Other candidates were observed failing with HTTP 402 or 404. These observations are not legal conclusions.
