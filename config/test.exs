import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :banter, Banter.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "banter_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :banter, BanterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "E0wMQgpue5r3mfGf0mtNtHoUNAsm4eauX0K1NL5E8B2vp+EWl+iMV6tHl8i8aqyC",
  server: false

# In test we don't send emails
config :banter, Banter.Mailer, adapter: Swoosh.Adapters.Test

# Use the scripted mock LLM provider in test
config :banter, :llm_provider, Banter.LLM.Mock
config :banter, Banter.LLM.Mock, model: "mock-model", models: ["mock-model", "mock-model-2"]

# Real provider tests route HTTP through a Req.Test stub
config :banter, Banter.LLM.OpenAI,
  base_url: "https://llm.test/v1",
  api_key: "test-llm-key",
  model: "test-model",
  models: ["test-model"],
  plug: {Req.Test, Banter.LLM.OpenAI}

# Route tool HTTP requests through Req.Test stubs
config :banter, Banter.Tools.WebSearch,
  api_key: "test-brave-key",
  plug: {Req.Test, Banter.Tools.WebSearch}

config :banter, Banter.Tools.WebFetch, plug: {Req.Test, Banter.Tools.WebFetch}

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
