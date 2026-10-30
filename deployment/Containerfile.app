FROM docker.io/hexpm/elixir:1.20.5-erlang-29.1.2-debian-trixie-20261027-slim@sha256:bb266918bb26de22fb02ff19430f47e76331001601df0fc820806c21cd4164e0 AS build

ENV MIX_ENV=prod
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY mix.exs mix.lock ./
RUN mkdir config
COPY config/config.exs config/prod.exs ./config/
RUN mix local.hex --force && mix local.rebar --force \
    && mix deps.get --only prod \
    && mix deps.compile

COPY lib ./lib
COPY priv ./priv
COPY assets ./assets
RUN mix compile
RUN mix assets.deploy
COPY config/runtime.exs ./config/
COPY rel ./rel
RUN mix release

FROM docker.io/debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS app

ENV MIX_ENV=prod PHX_SERVER=true PORT=4004 \
    LANG=C.UTF-8 LANGUAGE=C.UTF-8 LC_ALL=C.UTF-8
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl libncurses6 libsctp1 openssl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --create-home --home-dir /home/tcgcheap tcgcheap

COPY --from=build /app/_build/prod/rel/tcg_cheap ./

RUN chown -R tcgcheap:tcgcheap /app
USER tcgcheap

EXPOSE 4004
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent "http://127.0.0.1:${PORT:-4004}/health" || exit 1

CMD ["/app/bin/tcg_cheap", "start"]
