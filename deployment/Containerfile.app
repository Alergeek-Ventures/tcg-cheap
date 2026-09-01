FROM docker.io/hexpm/elixir:1.20.4-erlang-29.0.5-debian-bookworm-20260824-slim@sha256:468bb08c48e673cce404087adfafcac1a881b77326eff6bce438141f668e27c9 AS build

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

FROM docker.io/debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS app

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
