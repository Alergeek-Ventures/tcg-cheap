import Config

# There is no test suite; this file exists because `mix check` compiles and
# analyses the project in the test environment.
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true
config :tcg_cheap, :token_signing_secret, "tcg-cheap-test-auth-secret"
config :tcg_cheap, Oban, testing: :manual

config :tcg_cheap, TcgCheap.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("DB_PORT", "5436")),
  database: "tcg_cheap_test"

config :tcg_cheap, TcgCheapWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "f1agcpbZFA2f7D36qqcFYgR44U7Y8Cf0RMPv5wN5uQGI6QvMK+NS/L2XSHkn3kXI",
  server: false

config :logger, level: :warning

# Initialize plugs at runtime for faster compilation
config :phoenix, :plug_init_mode, :runtime
