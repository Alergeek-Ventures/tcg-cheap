# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
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
    TcgCheap.Core,
    TcgCheap.Accounts,
    TcgCheap.Sealed,
    TcgCheap.Storage
  ],
  token_signing_secret: :endpoint_secret_key_base

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

config :tcg_cheap, Oban,
  repo: TcgCheap.Repo,
  queues: [
    exchange_rates: 1,
    sealed: 1,
    # Shopify shops, beside the others (TcgCheap.Sealed.FetchWorker).
    shopify: 1,
    media: 1
  ],
  # Jobs orphaned by a restart return to the queue; shop fetches are unique
  # while executing, so a stuck one would otherwise block its shop for good.
  lifeline: [rescue_after: {30, :minutes}],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     crontab: [
       # NBP rates to PLN: EUR for Cardmarket, HUF for the Hungarian market,
       # the others for shops abroad (TcgCheap.Pricing.ExchangeRate.currencies/0).
       {"0 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "EUR", quote_currency: "PLN"}},
       {"1 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "GBP", quote_currency: "PLN"}},
       {"2 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "SEK", quote_currency: "PLN"}},
       {"3 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "CZK", quote_currency: "PLN"}},
       {"4 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "DKK", quote_currency: "PLN"}},
       {"5 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "HUF", quote_currency: "PLN"}},
       # Buying guide: the Cardmarket sealed catalogue,
       # then one fetch job per shop; the sealed and shopify queues run them
       # one at a time each.
       # Times are UTC: the import starts at 3:00 Polish winter time (4:00 in
       # summer), so the data is fresh for the morning.
       {"0 2 * * *", TcgCheap.Sealed.CatalogueImportWorker, args: %{}},
       {"30 2 * * *", TcgCheap.Sealed.FetchWorker, args: %{}},
       # The cards of new TCGdex sets, for the single booster pages.
       {"0 3 * * *", TcgCheap.Sealed.CardSyncWorker, args: %{}},
       # Suggested retail prices from the REBEL wholesaler, for the product pages.
       {"15 3 * * *", TcgCheap.Sealed.SuggestedPriceWorker, args: %{}},
       # Product photos copied into our storage, a batch at a time.
       {"*/10 * * * *", TcgCheap.Sealed.PhotoMirrorWorker, args: %{}},
       {"*/10 * * * *", TcgCheap.Storage.RemoteImageWorker, args: %{}}
     ]}
  ]

# Requests to Shopify shops are signed as this site (TcgCheap.WebBotAuth),
# which serves the public key; the private key comes from WEB_BOT_AUTH_KEY.
config :tcg_cheap, TcgCheap.WebBotAuth, agent: "https://tcg.cheap"

config :tcg_cheap, :admin_login_limiter,
  limit: 5,
  window_ms: 5 * 60 * 1_000,
  max_entries: 10_000,
  prune_interval_ms: 60_000

config :tcg_cheap, :exchange_rate_provider,
  adapter: TcgCheap.Pricing.NbpExchangeRate,
  options: []

# Configure the endpoint
config :tcg_cheap, TcgCheapWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TcgCheapWeb.ErrorHTML, json: TcgCheapWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TcgCheap.PubSub,
  live_view: [signing_salt: "kshhPnxQ"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild. Nix provides a stable external path in devenv; outside
# devenv, the configured version is downloaded by the Mix task as before.
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
# devenv, the configured version is downloaded by the Mix task as before.
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

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
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

config :tcg_cheap, TcgCheapWeb.Gettext, default_locale: "pl", locales: ~w(pl en hu)
