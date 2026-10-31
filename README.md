# TCG Cheap

A simple, independent price guide for Pokémon TCG fans in Poland, built with
Phoenix LiveView, Ash, Oban and PostgreSQL.

- **Buying guide (Polish, live):** `/` lists every sealed Pokémon product from
  Cardmarket with the cheapest current price in 36 Polish shops and a
  verdict (good / normal / expensive) based on what the product has really
  cost over the last 30 days. `/produkty/:slug` shows all offers with each
  shop's delivery cost and pickup city, and a 90-day price chart.
- **Trading guide (singles, next phase):** `/cards/:tcgdex_id` and `/trade`
  value single cards with daily Cardmarket prices.
- **Admin:** `/admin` (provisioned accounts only) — buying-guide desk for
  manual offer matching, operations, Oban and LiveDashboard.

## Local development

Tooling comes from Nix [devenv](https://devenv.sh/) with direnv:

```sh
direnv allow   # or: devenv shell
mix dev.up     # PostgreSQL (Podman/Docker Compose) + setup + Phoenix server
mix dev.down   # stop this worktree's services
```

`mix dev.up` creates `.env.local` from defaults, starts the pinned ParadeDB
PostgreSQL from `local/compose.yml`, runs `mix setup` (dependencies,
migrations, assets) and starts Phoenix. `mix dev.reset` removes this
worktree's database volume; use it only to discard local data.

Defaults: Phoenix on <http://localhost:4004>, PostgreSQL on `localhost:5436`.
Parallel worktrees get their own ports, so read `.server.port` for the actual
Phoenix port. In development, Tidewave MCP is at
`http://localhost:{PORT}/tidewave/mcp` and the buying-guide agent tools at
`http://localhost:{PORT}/mcp`.

A fresh database is empty until the background jobs run (see
[deployment and operations](docs/deployment-and-operations.md#first-data) for
how to queue them immediately).

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
- [Deployment and operations](docs/deployment-and-operations.md) — first
  deployment, configuration, jobs, day-2 tasks, backups.
- [Knowledge base](knowledge-base/wiki/index.md) — the product north star
  ([Buying and Trading Guide](knowledge-base/wiki/product/buying-and-trading-guide.md)),
  architecture and data sources.
- [AGENTS.md](AGENTS.md) — instructions for coding agents.
