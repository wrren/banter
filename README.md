# Banter

A small harness for conversing with LLMs, with a terminal-styled web UI
and pluggable tools the model can call mid-conversation.

Built with Phoenix LiveView. Conversations are persisted in Postgres and
scoped per user account (username + password auth; register at
`/users/register`). Assistant responses stream token-by-token from any
OpenAI-compatible endpoint (OpenRouter by default, llama.cpp and friends
work too).

## Setup

* Run `mix setup` to install dependencies, create the database and build assets
* Configure the LLM endpoint (see below)
* Start the server with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

Banter talks to any OpenAI-compatible chat completions API, configured
with environment variables:

| Variable | Default | Notes |
| --- | --- | --- |
| `LLM_BASE_URL` | `https://openrouter.ai/api/v1` | e.g. `http://localhost:8080/v1` for llama.cpp |
| `LLM_API_KEY` | — | falls back to `OPENROUTER_API_KEY` |
| `LLM_MODEL` | `openai/gpt-4o-mini` | default model for new conversations |
| `LLM_MODELS` | — | comma-separated list offered by the UI model selector |
| `BRAVE_SEARCH_API_KEY` | — | required by the `web_search` tool |

Example, against a local llama.cpp server:

```sh
LLM_BASE_URL=http://localhost:8080/v1 LLM_MODEL=local mix phx.server
```

## Tools

Tools are modules the LLM can call during a conversation. Two ship with
the app:

* `web_search` — Brave Search API, returns a compact result list
* `web_fetch` — fetches a URL and returns the page's essential content
  (boilerplate stripped, whitespace collapsed, truncated) to keep token
  usage low

Tools can be enabled/disabled at runtime from the sidebar; the state is
persisted per user in the database. To install a new tool, implement the
`Banter.Tools.Tool` behaviour and add the module to the `:tools` list in
`config/config.exs`:

```elixir
config :banter, :tools, [Banter.Tools.WebSearch, Banter.Tools.WebFetch, MyApp.Tools.MyTool]
```

## Accounts

Banter uses username + password auth (no email required). Register at
`/users/register`; sign in at `/users/log-in`. Conversations and tool
preferences are scoped per user. Passwords can be changed from the
settings page (gear icon in the sidebar); changing your password signs
out all sessions.

## Development

* `mix test` — run the test suite (tool HTTP calls and the LLM provider
  are stubbed via `Req.Test`; conversations run against a scripted mock
  provider in `test/support/mock_llm.ex`)
* `mix precommit` — compile with warnings as errors, format, and test

## Deployment

A multi-stage `Dockerfile` is included. Build and run:

```sh
docker build -t banter .

docker run --rm -p 4000:4000 \
  -e DATABASE_URL="ecto://USER:PASS@HOST/DATABASE" \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST="your.host.example" \
  -e LLM_API_KEY="$LLM_API_KEY" \
  banter
```

The release itself does not run migrations; run them separately before
starting the container (e.g. `mix ecto.migrate` from a one-off host that
can reach the database, or a `mix release` init container, or a `psql`
migration job).

Required runtime environment variables:

| Variable | Notes |
| --- | --- |
| `DATABASE_URL` | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | generate with `mix phx.gen.secret`; used to sign cookies |
| `PHX_HOST` | the public hostname (defaults to `example.com`) |
| `LLM_API_KEY` | (or `OPENROUTER_API_KEY`) provider auth |
| `LLM_BASE_URL` | defaults to OpenRouter; set for llama.cpp |
| `LLM_MODEL` | defaults to `openai/gpt-4o-mini` |
| `BRAVE_SEARCH_API_KEY` | required only if the `web_search` tool is enabled |

The image exposes port 4000 and runs as the unprivileged `nobody` user.

### Compose

A `compose.yaml` is included for local development. It runs Postgres,
applies migrations via `bin/banter eval Banter.Release.migrate()`, and
exposes the app on **port 4009**:

```sh
cp .env.example .env
# edit .env to set SECRET_KEY_BASE and an LLM_API_KEY
docker compose up --build
# or, with apple/container:
#   container compose up --build   # requires the container-compose plugin
```

Then visit [`localhost:4009`](http://localhost:4009). Data persists in
the `banter_db` named volume; `docker compose down -v` will wipe it.

The migration step uses a `Banter.Release` module invoked through the
release's `eval` command — there's no `mix` in the runtime image.
