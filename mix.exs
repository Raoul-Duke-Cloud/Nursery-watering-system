defmodule NurseryHub.MixProject do
  use Mix.Project

  # Nerves hardware targets — deps tagged with `targets: @nerves_targets` are only
  # included when building Pi firmware (MIX_TARGET=rpi0_2). Normal Mix builds ignore them.
  @nerves_targets [:rpi0_2]

  def project do
    [
      app: :nursery_hub,
      version: "0.2.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {NurseryHub.Application, []},
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      # MQTT client
      {:tortoise311, "~> 0.12"},

      # JSON
      {:jason, "~> 1.4"},

      # Web dashboard (Phoenix + LiveView)
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_html, "~> 4.0"},
      {:bandit, "~> 1.0"},          # HTTP server

      # Database (SQLite — no separate server needed)
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.15"},

      # Email delivery
      {:gen_smtp, "~> 1.2"},

      # ── Nerves (Pi firmware builds only — ignored in normal Mix builds) ─────────
      # Install bootstrap archive once on the build machine:
      #   mix archive.install hex nerves_bootstrap
      {:nerves,              "~> 1.10", runtime: false,  targets: @nerves_targets},
      {:nerves_system_rpi0_2,"~> 1.24", runtime: false,  targets: :rpi0_2},
      {:nerves_hub_link,     "~> 2.4",                   targets: @nerves_targets}
    ]
  end

  defp aliases do
    [
      # Run this once after setup to create the database
      setup: ["deps.get", "ecto.create", "ecto.migrate"]
    ]
  end
end
