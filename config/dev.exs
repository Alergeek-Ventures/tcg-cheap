import Config
config :ash, policies: [show_policy_breakdowns?: true]

# Configure your database
config :tcg_cheap, TcgCheap.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("DB_PORT", "5436")),
  url: System.get_env("DATABASE_URL", "ecto://postgres:postgres@localhost:5436/tcg_cheap_dev"),
  database: "tcg_cheap_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Code reloading and asset watchers.
config :tcg_cheap, TcgCheapWeb.Endpoint,
  # Listens on every IPv4 interface, so a preview link proxied from another
  # host reaches this server. Tidewave still answers only loopback requests.
  http: [ip: {0, 0, 0, 0}, port: 4004],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "RA6gZTR7RRXE6HG8w+/6rS388ID7Fi5Sm9c0FZNCz4kY5tQczQuMi3BpLIPqCICE",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:tcg_cheap, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:tcg_cheap, ~w(--watch)]},
    tailwind_admin: {Tailwind, :install_and_run, [:tcg_cheap_admin, ~w(--watch)]}
  ]

# This worktree's SeaweedFS from `mix dev.up` (local/compose.yml), served
# through this worktree's own /img route as in production.
config :tcg_cheap, :storage,
  services: [
    s3_public: [
      runtime_opts: [
        endpoint_url: {:localhost_url_from_port, env: "S3_PORT", default: 8333},
        public_base_url: {:localhost_url_from_port, env: "PORT", default: 4004, path: "/img"}
      ]
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
