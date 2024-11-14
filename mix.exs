defmodule Todoplace.MixProject do
  use Mix.Project

  def project do
    [
      app: :todoplace,
      version: "0.1.0",
      elixir: "~> 1.17.2",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix_swagger] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], plt_file: {:no_warn, "priv/plts/dialyzer.plt"}],
      xref: [exclude: [Morphix]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Todoplace.Application, []},
      extra_applications: [:logger, :os_mon, :runtime_tools, :crypto, :pdf_generator]
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
      {:phoenix, "~> 1.7.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # TODO bump on release to {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_live_view, "~> 1.0.0-rc.1", override: true},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},

      # customly added below
      {:bamboo, "~> 2.3.0"},
      {:finch, "~> 0.13"},
      {:hackney, "~> 1.20"},
      {:money, "~> 1.12"},
      {:pdf_generator, ">=0.6.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:tesla, "~> 1.11"},
      {:thousand_island, "1.3.5"},
      {:tz, "~> 0.26.1"},
      {:tz_extra, "~> 0.26.0"},
      {:paginator, "~> 1.2"},
      {:plug_crypto, "~> 1.2.0"},
      {:ecto_commons, "~> 0.3.3"},
      {:struct_access, "~> 1.1"},
      {:nimble_options, "~> 0.5.0"},
      {:broadway_cloud_pub_sub, "~> 0.8.0"},
      {:oban, "~> 2.14"},
      {:csv, "~> 3.0"},
      {:fun_with_flags, "~> 1.10.1"},
      {:fun_with_flags_ui, "~> 0.8"},
      {:stripity_stripe, "~> 2.17.3"},
      {:kane, git: "https://github.com/dforce-2/kane.git", ref: "master"},
      # {:kane, "~> 0.9.0"},
      {:google_api_storage, "~> 0.40.1"},
      {:ueberauth_google, "~> 0.10"},
      {:icalendar, "~> 1.1.0"},
      {:google_api_pub_sub, "~> 0.36.0"},
      {:google_api_sheets, "~> 0.29.2"},
      {:bcrypt_elixir, "~> 3.0"},
      {:live_phone, git: "https://github.com/nkezhaya/live_phone", ref: "master"},
      {:ecto_psql_extras, "~> 0.7.2"},
      {:elixir_email_reply_parser, "~> 0.1.2"},
      {:html_sanitize_ex, "~> 1.4"},
      {:flow, "~> 1.1"},
      {:libcluster, "~> 3.3"},
      {:bbmustache, "~> 1.12"},
      {:phoenix_view, "~> 2.0"},
      {:plug_cowboy, "~> 2.6"},
      {:packmatic, "~> 1.2"},
      # {:packmatic, "~> 1.1.2"},
      {:gcs_sign, "~> 1.0"},
      {:goth, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:sentry, "~> 8.0"},
      {:size, "~> 0.1.0"},
      {:cll, "~> 0.2.0"},
      {:cors_plug, "~> 3.0"},
      {:con_cache, "~> 1.0"},
      {:morphix, "~> 0.8.0"},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:phoenix_swagger, "~> 0.8", override: false},
      {:ex_json_schema, "~> 0.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0.0", only: [:dev, :test]},
      {:bypass, "~> 2.1", only: :test},
      {:ex_machina, "~> 2.7.0", only: [:dev, :test]},
      {:triplex, "~> 1.3.0"}, # Or the latest version compatible with your setup
      {:redix, "~> 1.1"},
      {:httpoison, "~> 2.2"},
      {:wallaby, "~> 0.30.3", runtime: false, only: :test},
      {:inflex, "~> 2.1"},
      {:poison, "~> 3.0"},
      {:countries, "~> 1.6.0"},
      {:ex_cldr_units, "~> 3.0"}
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["cmd --cd assets npm install", "assets.build"],
      "assets.build": ["cmd --cd assets npm run build:prod"],
      "assets.deploy": ["cmd --cd assets npm run build:prod", "phx.digest"],
      "swagger": ["phx.swagger.generate priv/static/swagger.json --router DistanceTracker.Router --endpoint DistanceTracker.Endpoint"]
    ]
  end
end
