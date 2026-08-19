FROM docker.io/hexpm/elixir:1.20.1-erlang-29.0.1-debian-bookworm-20260610-slim@sha256:ae3844d11c4803b239188eb1f195cde504593597faad8be2340f34f3b392d062 AS build

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

FROM docker.io/debian:trixie-slim@sha256:b6e2a152f22a40ff69d92cb397223c906017e1391a73c952b588e51af8883bf8 AS app

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
