# TCG Cheap

A simple, independent price guide for Pokémon TCG fans, built with Phoenix
LiveView, Ash, Oban and PostgreSQL. It runs per region (`/pl`, `/hu`; `/`
redirects to one) and its pages come in Polish, English and Hungarian.

- **Buying guide:** the product list shows every sealed Pokémon product from
  Cardmarket with the cheapest current price in the region's shops and a
  verdict (good / normal / expensive) based on what other shops ask today and
  what the product has really cost over the last 30 days. Product pages
  (`/pl/produkty/:slug`, `/hu/termekek/:slug`) show all offers with each
  shop's delivery cost and pickup city, and a 90-day price chart.
- **Sets and single cards:** every named expansion has a page with its
  products, pull rates and cards, and each card has a page with its best
  offers. The card list lives beside the product list. The trade-fairness
  check is not built yet.
- **Guide articles:** booster prices, the most expensive cards and how to
  check a card's value.
- **For AI agents:** every page has a Markdown version (add `.md` to its URL
  or send `Accept: text/markdown`), and `/llms.txt` describes the site.
- **Admin:** `/admin` (provisioned accounts only) — buying-guide desk for
  manual offer matching, Oban and LiveDashboard. The buying-guide tools are
  also served over MCP at `/mcp`.

## Local development

Tooling comes from Nix [devenv](https://devenv.sh/) with direnv:

```sh
direnv allow   # or: devenv shell
mix dev.up     # services + setup + Phoenix server
mix dev.down   # stop this worktree's services
```

`mix dev.up` creates `.env.local` from defaults, starts the pinned ParadeDB
PostgreSQL and a SeaweedFS S3 server (a stand-in for production object
storage) from `local/compose.yml`, runs `mix setup` (dependencies, migrations,
assets) and starts Phoenix. `mix dev.reset` removes this worktree's database
volume; use it only to discard local data.

Defaults: Phoenix on <http://localhost:4004>, PostgreSQL on `localhost:5436`,
S3 on `localhost:8333`. Parallel worktrees get their own ports, so read
`.server.port` for the actual Phoenix port. In development, Tidewave MCP is at
`http://localhost:{PORT}/tidewave/mcp` and the buying-guide agent tools at
`http://localhost:{PORT}/mcp`.

A fresh database is empty, and a development server does not run the nightly
catalogue import and shop fetches on its own. To get data, either copy it from
another local database or let this server fetch it:

```sh
mix dev.seed                 # copy the data of the main checkout's database
mix dev.seed ecto://…        # or of any other local database
```

`SCHEDULED_FETCHES=1` in `.env.local` turns the nightly schedule on for one
checkout; the agent tools at `/mcp` (`enqueue_catalogue_import`,
`enqueue_shop_fetch`, …) run a single job on request.

To create a local administrator:

```sh
ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD='a long password' mix admin.provision
```

## Quality gate

```sh
mix check   # format, Ash codegen, Sobelow, compile, deps, Credo, Dialyzer
```

After changing Ash resources, generate migrations and snapshots with
`mix ash.codegen describe_the_change`.

## Documentation

- [PRODUCT.md](PRODUCT.md) — product brief; [DESIGN.md](DESIGN.md) — visual design.
- [AGENTS.md](AGENTS.md) — instructions for coding agents.
