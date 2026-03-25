import Config

# ── OTA Firmware ──────────────────────────────────────────────────────────────
# Increment this when you deploy new firmware.
# ESP32s compare their FIRMWARE_VERSION define against this on every boot.
config :nursery_hub, :firmware_version, 42

# ── MQTT ──────────────────────────────────────────────────────────────────────
# Credentials must match the Mosquitto password file.
# See SECURITY_SETUP.md for how to create the Mosquitto password file.
config :nursery_hub,
  mqtt_host:             "localhost",
  mqtt_port:             1883,
  mqtt_username:         "nursery_hub",
  mqtt_password:         "CHANGE_THIS_MQTT_PASSWORD",
  zone_timeout_minutes:  30,
  valve_max_open_seconds: 120

# ── Dashboard login ────────────────────────────────────────────────────────────
# Username and password for the web dashboard.
# Change these before making the server accessible on your network.
config :nursery_hub, :dashboard_auth,
  username: "admin",
  password: "CHANGE_THIS_DASHBOARD_PASSWORD"

# ── Database (SQLite) ─────────────────────────────────────────────────────────
config :nursery_hub, NurseryHub.Repo,
  database: Path.expand("../priv/nursery_hub.db", __DIR__),
  pool_size: 5

# ── Web Dashboard ─────────────────────────────────────────────────────────────
# secret_key_base must be at least 64 bytes.
# Generate a new one with:  mix phx.gen.secret
# The current value is a safe default — regenerate before exposing to internet.
config :nursery_hub, NurseryHubWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  secret_key_base: "Nx2mK9pL4rT7vY1aE6sH3uW8bQ0dF5gJ2nX4mK7pL9rT1vY3aE8sH6uW0bQ2dF4gJ5n",
  live_view: [signing_salt: "mK7pL9rT1vY3aE8sH6uW0bQ2"],
  server: true

# ── Phoenix PubSub ────────────────────────────────────────────────────────────
config :nursery_hub, :pubsub,
  name: NurseryHub.PubSub,
  topic_zones: "zones:updates"
