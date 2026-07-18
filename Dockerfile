# syntax=docker/dockerfile:1

# The Erlang/OTP version pinned in the builder must match the runtime libs
# shipped in the release tarball (which carries ERTS). Both stages use Ubuntu
# 26.04 (resolute): that's the base hexpm publishes Elixir 1.17.3 with, and
# glibc is forward-only — a release built on Ubuntu 26.04 (glibc 2.43) cannot
# run on Debian bookworm-slim (glibc 2.36).
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.3.4.14
ARG UBUNTU_DATE=20260707
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-resolute-${UBUNTU_DATE}"
ARG RUNNER_IMAGE="ubuntu:resolute-${UBUNTU_DATE}"

# ─── Build stage ──────────────────────────────────────────────────────────
FROM ${BUILDER_IMAGE} AS builder

# build-essential + git are needed to compile native deps (bcrypt_elixir's NIF)
# and to fetch hex packages.
RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

# Fetch deps as a separate layer so source changes don't bust the hex cache.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
# config files need to be present before `mix deps.compile` so deps that read
# config at compile time (e.g. ecto, phoenix) can see them.
COPY config/config.exs config/${MIX_ENV}.exs config/runtime.exs config/
RUN mix deps.compile

# Now copy sources and build.
COPY priv priv
COPY lib lib
COPY assets assets

# mix compile runs the :phoenix_live_view compiler, which extracts colocated
# <style> blocks from templates into _build/prod/phoenix-colocated/banter/.
# Tailwind's @import "phoenix-colocated/banter/colocated.css" only resolves
# once that file exists, so compile MUST come before assets.deploy.
RUN mix compile

# assets.setup downloads the tailwind + esbuild binaries (no-op if present),
# then assets.deploy runs them with --minify and digests the output.
RUN mix assets.setup && mix assets.deploy

# Build the release. mix release without a `rel/` directory uses built-in
# defaults — fine for an MVP; run `mix phx.gen.release` if you want custom
# vm.args/env.sh.
RUN mix release

# ─── Runtime stage ────────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE}

# Runtime shared libraries:
#   libstdc++6  — bcrypt_elixir NIF
#   libssl3     — Req, :public_key
#   libncurses6 — runtime_tools
#   ca-certificates — outbound HTTPS (LLM provider, Brave Search, etc.)
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Phoenix generates UTF-8 locale strings in the release; make sure one exists.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

USER nobody

COPY --from=builder --chown=nobody /app/_build/prod/rel/banter ./

# Required for Phoenix to start the Bandit listener under releases.
ENV PHX_SERVER=true

EXPOSE 4000

CMD ["/app/bin/banter", "start"]
