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
  ash_domains: [TcgCheap.Core, TcgCheap.Accounts, TcgCheap.Operations],
  token_signing_secret: :endpoint_secret_key_base

config :tcg_cheap, :acquisition_health,
  stranded_after_seconds: 900,
  reconcile_limit: 100,
  circuit_breaker_failure_threshold: 5,
  stale_after_seconds: %{"nbp" => 129_600}

config :backpex,
  pubsub_server: TcgCheap.PubSub,
  translator_function: {TcgCheapWeb.CoreComponents, :translate_error},
  error_translator_function: {TcgCheapWeb.CoreComponents, :translate_error}

config :tcg_cheap, Oban,
  repo: TcgCheap.Repo,
  queues: [
    valuations: 4,
    exchange_rates: 1,
    catalogue_sync: 1,
    operations: 1,
    sealed_retailers: 1,
    sealed_aggregates: 1,
    sealed_buying_guides: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", TcgCheap.Catalogue.SinglesScopeBootstrapWorker, args: %{}},
       {"0 14 * * *", TcgCheap.Pricing.Singles.ValuationRefreshWorker, args: %{}},
       {"0 15 * * *", TcgCheap.Pricing.ExchangeRateWorker,
        args: %{source: "nbp", table: "A", base_currency: "EUR", quote_currency: "PLN"}},
       # Daily at 16:00 UTC, after the 15:00 UTC NBP job.
       {"0 16 * * *", TcgCheap.Pricing.SealedDailyAggregateWorker, args: %{}},
       {"*/15 * * * *", TcgCheap.Operations.AcquisitionReconcilerWorker, args: %{}}
     ]}
  ]

config :tcg_cheap, :catalogue_sync,
  provider: TcgCheap.Catalogue.Tcgdex,
  provider_options: [],
  batch_size: 20,
  batch_delay_seconds: 900,
  budget_backoff_seconds: 3_600

config :tcg_cheap, :singles_collection,
  pitch_black_set_id: "me05",
  rolling_rarities: ["Illustration rare", "Special illustration rare"],
  chunk_size: 20

config :tcg_cheap, :valuation_clock, &DateTime.utc_now/0

config :tcg_cheap, :admin_login_limiter,
  limit: 5,
  window_ms: 5 * 60 * 1_000,
  max_entries: 10_000,
  prune_interval_ms: 60_000

config :tcg_cheap, :public_acquisition_limiter,
  limit: 30,
  window_ms: 60 * 60 * 1_000,
  max_entries: 10_000,
  prune_interval_ms: 60_000

config :tcg_cheap, :valuation_provider,
  adapter: TcgCheap.Pricing.Singles.TcgdexCardmarket,
  options: []

config :tcg_cheap, :exchange_rate_clock, &DateTime.utc_now/0
config :tcg_cheap, :sealed_daily_aggregate_clock, &DateTime.utc_now/0

config :tcg_cheap, :exchange_rate_provider,
  adapter: TcgCheap.Pricing.NbpExchangeRate,
  options: []

config :tcg_cheap, :acquisition_budget,
  global_hourly_request_limit: 100,
  global_daily_request_limit: 1_000,
  global_monthly_spend_limit: "50.00",
  providers:
    [
      [
        provider_key: "tcgdex_catalogue",
        display_name: "TCGdex Catalogue",
        estimated_cost_per_request: "0.00",
        hourly_request_limit: 100,
        daily_request_limit: 1_000,
        monthly_request_limit: 20_000,
        monthly_spend_limit: "0.00"
      ],
      [
        provider_key: "tcgdex_cardmarket",
        display_name: "TCGdex Cardmarket",
        estimated_cost_per_request: "0.00",
        hourly_request_limit: 100,
        daily_request_limit: 1_000,
        monthly_request_limit: 20_000,
        monthly_spend_limit: "0.00"
      ],
      [
        provider_key: "nbp",
        display_name: "Narodowy Bank Polski",
        estimated_cost_per_request: "0.00",
        hourly_request_limit: 24,
        daily_request_limit: 100,
        monthly_request_limit: 1_000,
        monthly_spend_limit: "0.00"
      ]
    ] ++
      (if config_env() == :dev do
         [
           [
             provider_key: "sealed_retailer:lootquest",
             display_name: "LootQuest sealed catalogue",
             estimated_cost_per_request: "0.00",
             hourly_request_limit: 50,
             daily_request_limit: 100,
             monthly_request_limit: 500,
             monthly_spend_limit: "0.00"
           ],
           [
             provider_key: "sealed_retailer:cardzhouse",
             display_name: "CardzHouse sealed catalogue",
             estimated_cost_per_request: "0.00",
             hourly_request_limit: 50,
             daily_request_limit: 100,
             monthly_request_limit: 500,
             monthly_spend_limit: "0.00"
           ],
           [
             provider_key: "sealed_retailer:boosterpoint",
             display_name: "BoosterPoint sealed catalogue",
             estimated_cost_per_request: "0.00",
             hourly_request_limit: 50,
             daily_request_limit: 100,
             monthly_request_limit: 500,
             monthly_spend_limit: "0.00"
           ]
         ]
       else
         []
       end)

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
       [version: "0.27.2"] ++
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
           ]
         ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
