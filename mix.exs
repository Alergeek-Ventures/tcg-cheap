defmodule TcgCheap.MixProject do
  use Mix.Project

  def project do
    [
      app: :tcg_cheap,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      usage_rules: usage_rules(),
      dialyzer: [plt_add_apps: [:mix]],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TcgCheap.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:picosat_elixir, "~> 0.2"},
      {:argon2_elixir, "~> 4.1"},
      {:ash_authentication_phoenix, "~> 2.17"},
      {:ash_authentication, "~> 4.15"},
      {:sourceror, "~> 1.13", only: [:dev, :test]},
      {:usage_rules, "~> 1.3", only: :dev},
      {:tidewave, "~> 0.9", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:ash_credo, "~> 0.19", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.18", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ash_phoenix, "~> 2.3"},
      {:ash_backpex, "~> 0.5"},
      # live_dashboard_logger 0.0.3 (latest) still requires ~> 0.8.6; 0.9 keeps the
      # PageBuilder API it uses.
      {:phoenix_live_dashboard, "~> 0.9", override: true},
      {:live_dashboard_logger, "~> 0.0.3"},
      {:oban_web, "~> 2.13"},
      {:ecto_psql_extras, "~> 0.8"},
      {:ash_postgres, "~> 2.15"},
      {:oban, "~> 2.24"},
      {:ash, "~> 3.37"},
      {:ash_ai, "~> 1.4"},
      {:req, "~> 0.7"},
      {:ash_storage,
       github: "ash-project/ash_storage", ref: "28b895410cb9a4b90b49242ce8617682a7b8fc77"},
      {:req_s3, "~> 0.2.3"},
      {:resvg, "~> 0.6"},
      {:image, "~> 0.72.0"},
      {:saxy, "~> 1.6"},
      {:floki, "~> 0.38"},
      {:igniter, "~> 0.8", only: [:dev, :test]},
      {:phoenix, "~> 1.8"},
      {:gettext, "~> 1.0"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.7.50",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.3"},
      {:bandit, "~> 1.14"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: [
        "deps.get",
        "usage_rules.sync",
        "ash.setup",
        "assets.setup",
        "assets.build",
        "run priv/repo/seeds.exs"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind tcg_cheap", "esbuild tcg_cheap"],
      "assets.deploy": [
        "tailwind tcg_cheap --minify",
        "esbuild tcg_cheap --minify",
        "phx.digest"
      ],
      precommit: ["check"]
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        "phoenix:ecto",
        "phoenix:html",
        "phoenix:liveview",
        {:phoenix, sub_rules: []},
        {:ash, sub_rules: []},
        "ash:actions",
        "ash:authorization",
        "ash:code_structure",
        "ash:data_layers",
        "ash:generating_code",
        "ash:migrations",
        "ash:querying_data",
        "ash:relationships",
        "ash:testing",
        {:ash_postgres, sub_rules: []},
        :elixir,
        :otp
      ]
    ]
  end
end
