import Config

# ── Nerves Pi (site hub) configuration ────────────────────────────────────────
#
# This file is imported by config/target.exs when building the Nerves firmware.
# It overrides config/config.exs for the on-site Pi role.
#
# To build the Pi firmware targeting a specific site:
#   export NERVES_TARGET=rpi0_2
#   export SITE_ID=site_01
#   export CENTRAL_URL=http://your-central-server.com
#   mix firmware
#
# Or hard-code the values below for a fixed deployment.

# ── Role ──────────────────────────────────────────────────────────────────────
# :site  — on-site Pi hub; runs DataSync, buffering, local alerting
# :central is the default (no this file loaded)
config :nursery_hub, :role, :site

# ── Site identity ─────────────────────────────────────────────────────────────
# Must match the site_id in MQTT topics from the ESP32s at this site.
# e.g. "site_01", "northcote", "heidelberg"
config :nursery_hub, :site_id, System.get_env("SITE_ID", "site_01")

# ── Central server ─────────────────────────────────────────────────────────────
# DataSync pushes buffered readings here when WAN is available.
# Set to nil to disable DataSync (standalone Pi, no central server).
config :nursery_hub, :central_url, System.get_env("CENTRAL_URL", "http://YOUR_CENTRAL_SERVER")

# Must match :sync_api_key on the central server.
config :nursery_hub, :sync_api_key, System.get_env("SYNC_API_KEY", "CHANGE_THIS_SYNC_API_KEY")

# ── MQTT ──────────────────────────────────────────────────────────────────────
# Local Mosquitto runs on the Pi itself. ESP32s connect to the Pi's IP.
config :nursery_hub,
  mqtt_host: "localhost",
  mqtt_port: 1883

# ── Database ──────────────────────────────────────────────────────────────────
# Nerves mounts a writable data partition at /data.
# The local SQLite acts as a buffer — all readings stored here, synced to central.
config :nursery_hub, NurseryHub.Repo,
  database: "/data/nursery_hub_local.db",
  pool_size: 3

# ── Web dashboard ─────────────────────────────────────────────────────────────
# Accessible on the local LAN: http://[pi-ip]:4000
# Useful during WAN outages — operator can check status on-site.
config :nursery_hub, NurseryHubWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  server: true

# ── Heartbeat ─────────────────────────────────────────────────────────────────
# Daily email still fires from the Pi when WAN is available.
# Uses the same email settings as the central app (configured via Settings UI).
config :nursery_hub, :heartbeat_hour, 8

# ── Watchdog thresholds (same as central — override here if site needs differ) ─
# config :nursery_hub,
#   zone_timeout_minutes:   30,
#   valve_max_open_seconds: 120,
#   stuck_moisture_hours:   6,
#   freeze_alert_celsius:   2,
#   freeze_clear_celsius:   4,
#   dripper_fault_alert_threshold: 3
