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
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:usage_rules, "~> 1.2", only: :dev},
      {:tidewave, "~> 0.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:ash_credo, "~> 0.17", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:oban, "~> 2.23"},
      {:ash, "~> 3.0"},
      {:req, "~> 0.5"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
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
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
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
      test: ["ash.setup --quiet", "test"],
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
