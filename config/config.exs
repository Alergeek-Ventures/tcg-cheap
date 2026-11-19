import Config

# Ash behaviours that become the default in its next major version; see
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  many_to_many_destroy_destination_on_match?: true,
  default_string_length_count: :codepoints,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :tcg_cheap,
  ecto_repos: [TcgCheap.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    TcgCheap.Pricing,
    TcgCheap.Accounts,
    TcgCheap.Cards,
    TcgCheap.Sealed,
    TcgCheap.Storage
  ],
  token_signing_secret: :endpoint_secret_key_base

# Session settings of every connection, in every environment.
# - plan_cache_mode: Ecto prepares each query once per connection, and after
#   five runs Postgres may switch to a generic plan, which ignores the
#   parameters' statistics: the card list's per-shop fetch times
#   (`TcgCheap.Cards.Offer`) then look like a handful of offers, and the plan
#   loops for seconds. A plan per run costs a few milliseconds.
# - jit: compiling a query took most of its time (about 1 s of 1.3 s for the
#   image mirror's source scan); no query here runs long enough to repay it.
config :tcg_cheap, TcgCheap.Repo, parameters: [plan_cache_mode: "force_custom_plan", jit: "off"]

config :backpex,
  pubsub_server: TcgCheap.PubSub,
  translator_function: {TcgCheapWeb.CoreComponents, :translate_error},
  error_translator_function: {TcgCheapWeb.CoreComponents, :translate_error}

# Files we serve ourselves live in a public bucket (TcgCheap.Storage):
# objects are uploaded public-read and linked without presigned URLs.
# dev.exs points it at the worktree's SeaweedFS, prod.exs at OVH Object
# Storage; keys come from AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
config :tcg_cheap, :storage,
  active_service: :s3_public,
  resources: [TcgCheap.Sealed.Product, TcgCheap.Storage.RemoteImage],
  services: [
    s3_public: [
      module: TcgCheap.Storage.Service.PublicS3,
      opts: [bucket: "tcg-cheap-public", region: "us-east-1"]
    ]
  ]

# Jobs every environment runs: exchange rates and image mirroring.
always_scheduled = [
  # NBP rates to PLN of every currency the guide needs
  # (TcgCheap.Sealed.Market.currencies/0), one job each.
  {"0 15 * * *", TcgCheap.Pricing.ExchangeRateWorker, args: %{}},
  # Product photos copied into our storage, a batch at a time.
  {"*/10 * * * *", TcgCheap.Sealed.PhotoMirrorWorker, args: %{}},
  {"*/10 * * * *", TcgCheap.Storage.RemoteImageWorker, args: %{}}
]

# The nightly reads of Cardmarket, the shops, TCGdex and REBEL. A development
# server runs them only on request (the enqueue_* MCP tools), so worktrees do
# not multiply the traffic shops see; SCHEDULED_FETCHES=1 opts a checkout in.
nightly_fetches = [
  # Buying guide: the Cardmarket sealed catalogue,
  # then one fetch job per shop; the sealed and shopify queues run them
  # one at a time each.
  # Times are UTC: the import starts at 3:00 Polish winter time (4:00 in
  # summer), so the data is fresh for the morning.
  {"0 2 * * *", TcgCheap.Sealed.CatalogueImportWorker, args: %{}},
  {"30 2 * * *", TcgCheap.Sealed.FetchWorker, args: %{}},
  # The cards of new TCGdex sets, for the single booster pages.
  {"0 3 * * *", TcgCheap.Cards.SyncWorker, args: %{}},
  # Suggested retail prices from the REBEL wholesaler, for the product pages.
  {"15 3 * * *", TcgCheap.Sealed.SuggestedPriceWorker, args: %{}}
]

scheduled_fetches? =
  config_env() != :dev or System.get_env("SCHEDULED_FETCHES") in ["1", "true"]

config :tcg_cheap, Oban,
  repo: TcgCheap.Repo,
  queues: [
    exchange_rates: 1,
    sealed: 1,
    # Shopify shops, beside the others (TcgCheap.Sealed.FetchWorker).
    shopify: 1,
    media: 1
  ],
  # A deploy stops the application a few seconds after it asks (container
  # stop), so running jobs get only moments to finish: all of them can run
  # again from their start or their saved progress, and a stopped one goes
  # back to the queue at once (TcgCheap.JobShutdown).
  shutdown_grace_period: :timer.seconds(5),
  # What a kill leaves executing (nothing ran TcgCheap.JobShutdown) returns to
  # the queue; shop fetches are unique while executing, so a stuck one would
  # otherwise block its shop for good. The Lifeline cannot tell a dead job
  # from a slow one, so this stays above the longest job timeout of any
  # worker (20 minutes).
  lifeline: [rescue_after: {25, :minutes}],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     crontab: always_scheduled ++ if(scheduled_fetches?, do: nightly_fetches, else: [])}
  ]

# Requests to Shopify shops are signed as this site (TcgCheap.WebBotAuth),
# which serves the public key; the private key comes from WEB_BOT_AUTH_KEY.
config :tcg_cheap, TcgCheap.WebBotAuth, agent: "https://tcg.cheap"

config :tcg_cheap, :admin_login_limiter,
  limit: 5,
  window_ms: 5 * 60 * 1_000,
  max_entries: 10_000,
  prune_interval_ms: 60_000

# Endpoint
config :tcg_cheap, TcgCheapWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TcgCheapWeb.ErrorHTML, json: TcgCheapWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TcgCheap.PubSub,
  live_view: [signing_salt: "kshhPnxQ"]

# LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild. Nix provides a stable external path in devenv; outside
# devenv, the Mix task downloads the configured version.
esbuild_options =
  case System.get_env("MIX_ESBUILD_PATH") do
    path when is_binary(path) and path != "" -> [path: path, version_check: false]
    _ -> []
  end

config :esbuild,
       [version: "0.28.2"] ++
         esbuild_options ++
         [
           tcg_cheap: [
             args:
               ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
             cd: Path.expand("../assets", __DIR__),
             env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
           ]
         ]

# Configure tailwind. Nix provides a stable external path in devenv; outside
# devenv, the Mix task downloads the configured version.
tailwind_options =
  case System.get_env("MIX_TAILWIND_PATH") do
    path when is_binary(path) and path != "" -> [path: path, version_check: false]
    _ -> []
  end

config :tailwind,
       [version: "4.3.3"] ++
         tailwind_options ++
         [
           tcg_cheap: [
             args: ~w(
          --input=assets/css/app.css
          --output=priv/static/assets/css/app.css
        ),
             cd: Path.expand("..", __DIR__),
             env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
           ],
           tcg_cheap_admin: [
             args: ~w(
          --input=assets/css/admin.css
          --output=priv/static/assets/css/admin.css
        ),
             cd: Path.expand("..", __DIR__),
             env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
           ]
         ]

# Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# JSON library
config :phoenix, :json_library, Jason

# The visitor's location (connect params and the location control's events)
# must never reach the logs; see TcgCheapWeb.VisitorLocation. Nor may the
# session's CSRF token, which LiveView sends in its connect params.
config :phoenix, :filter_parameters, ["password", "location", "_csrf_token"]

# Error reporting; runtime.exs sets the DSN, environment and release. Sentry's
# scrubber covers request params, LiveView event breadcrumbs and stacktrace
# variables, so it also gets the visitor's location key.
config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  in_app_otp_apps: [:tcg_cheap],
  scrubber: [param_keys: ["location"]],
  # Attaches Sentry's logger handler, which reports crashes after
  # TcgCheapWeb.LocationLogFilter; prod.exs also sends logs. Bandit logs a
  # crashed request under the :bandit domain, which Sentry skips by default (it
  # expects Sentry.PlugCapture, not recommended with Bandit).
  logs: [capture_excluded_domains: [:cowboy]]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

config :tcg_cheap, TcgCheapWeb.Gettext, default_locale: "pl"
