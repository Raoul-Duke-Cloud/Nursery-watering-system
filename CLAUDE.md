# NurseryHub — Claude context

Multi-site nursery monitoring and auto-watering system. Elixir/Phoenix backend, ESP32 firmware, Mosquitto MQTT broker, SQLite database, Phoenix LiveView dashboard. v0.2.0.

---

## How to start it

```
# Mosquitto (auto-starts on Windows boot — usually already running)
net start mosquitto

# Elixir app (keep this terminal open — ctrl+c to stop)
cd C:\Users\Ramon\Downloads\nursery_hub
cmd /c "C:\Program Files\Elixir\bin\mix.bat" run -e ":timer.sleep(:infinity)"

# Dashboard
http://localhost:4000
```

Or double-click `Start NurseryHub.bat` on the Desktop — does all of the above.

First-time setup only:
```
cmd /c "C:\Program Files\Elixir\bin\mix.bat" setup
```

Simulator (no hardware needed — populates 8 zones across 2 fake sites):
```
cmd /c "C:\Program Files\Elixir\bin\mix.bat" sim
```

If port 4000 is already in use: `taskkill /IM beam.smp.exe /F`

---

## What was built

### Elixir app (`lib/`)

| File | Role |
|---|---|
| `nursery_hub/application.ex` | Startup supervisor — boots Repo, PubSub, ZoneRegistry, ZoneSupervisor, MQTTConnector, Endpoint in order |
| `nursery_hub/zone_server.ex` | GenServer per zone — holds state, runs watchdog every 60s, checks for timeouts/stuck valves/sensor faults/critical moisture, manages watering events |
| `nursery_hub/zone_supervisor.ex` | DynamicSupervisor — starts/restarts ZoneServer processes, lookup by {site_id, zone_id} |
| `nursery_hub/mqtt_connector.ex` | Tortoise311 MQTT client — connects to Mosquitto, subscribes to `nursery/#`, routes incoming messages |
| `nursery_hub/mqtt_handler.ex` | Parses MQTT payloads, routes data to zone processes |
| `nursery_hub/alerting.ex` | Sends email (gen_smtp) and SMS (Twilio HTTP) alerts; routing configured per alert type in settings; also sends daily heartbeat email |
| `nursery_hub/heartbeat.ex` | GenServer — sends daily system-alive email at configured UTC hour; includes zone summary (total/offline/alerts) |
| `nursery_hub/alert_log.ex` | Ecto schema + queries for the alert log table |
| `nursery_hub/sensor_reading.ex` | Ecto schema + insert for sensor readings |
| `nursery_hub/watering_event.ex` | Ecto schema — open/close watering events, moisture_before/after, duration_ms, trigger, dripper_fault |
| `nursery_hub/consumption.ex` | Water consumption tracking |
| `nursery_hub/settings.ex` | Loads/saves settings from SQLite (email, SMS, alert routing, OTA version) |
| `nursery_hub/repo.ex` | Ecto repo (SQLite) |

### LiveView pages (`lib/nursery_hub_web/live/`)

| File | URL | What it does |
|---|---|---|
| `dashboard_live.ex` | `/` | Main table — all zones, live updates via PubSub, filters (site/zone/status/mode/sensor ranges), CSV download, Water/Stop/History actions |
| `zone_live.ex` | `/zone/:site/:zone` | Per-zone history — moisture + VPD charts, date range picker, watering events table, CSV export |
| `logs_live.ex` | `/logs` | Alert log — all/active/resolved filter, colour-coded alert type badges |
| `settings_live.ex` | `/settings` | Email (SMTP), SMS (Twilio), alert routing per alert type, OTA firmware version, test email/SMS buttons |

### Controllers

| File | Role |
|---|---|
| `csv_controller.ex` | Serves CSV exports for dashboard and zone history |
| `firmware_controller.ex` | Serves OTA firmware binary to ESP32s |

---

## Data flow

**Incoming (sensor data):**
```
ESP32 → MQTT publish → nursery/{site_id}/{zone_id}/data
  → MQTTConnector receives → MQTTHandler parses
  → ZoneServer.receive_data/3 → GenServer.cast({:data, data})
  → ZoneServer updates state, runs checks, saves SensorReading, broadcasts PubSub
  → DashboardLive receives {:zone_update, state} → re-renders row
```

**Outgoing (commands):**
```
Dashboard "Water" button → DashboardLive handle_event
  → ZoneServer.send_command/3
  → Tortoise311.publish → nursery/{site_id}/{zone_id}/cmd
  → ESP32 opens valve for 15s
```

---

## Zone state

ZoneServer holds all of this in its GenServer state:

```elixir
%NurseryHub.ZoneServer{
  site_id, zone_id,
  last_seen,          # DateTime — nil until first data
  moisture,           # 0–100%
  lux,                # light level
  leaf_temp,          # IR leaf temperature
  air_temp, humidity, vpd,
  watering,           # boolean — valve currently open?
  valve_open_since,   # DateTime (nil if closed) — for stuck-valve detection
  mode,               # "normal" | "no_vpd" | "no_moisture" | "local" | "unknown"
  current_event_id,   # DB id of open watering event
  pending_check_event_id, # watering event waiting for post-drip moisture check
  valve_closed_at,    # used to time the post-drip moisture reading (1–5 min window)
  sensor_ok: %{},     # map of sensor_name => boolean
  alerts: [],         # active alert atoms: :offline, :valve_stuck, :sensor_fault, :critical_dry
  faulted_sensors: [] # debounce — only fires alert when fault set changes
}
```

Zone status derived from state for the dashboard:
- `online` — last_seen within 30 min, no active alerts
- `offline` — last_seen > 30 min ago (`:offline` in alerts)
- `watering` — watering == true
- `alert` — any alert in alerts list

---

## Alert types

| Atom | Trigger | Default routing |
|---|---|---|
| `:zone_offline` | No data for >30 min | Email |
| `:valve_stuck_open` | Valve open >120s | Email + SMS; also sends stop command |
| `:sensor_fault` | sensor_ok map has false values | Email |
| `:critical_dry` | moisture <= 10% | Email + SMS |
| `:sensor_out_of_bounds` | Reading outside physical bounds (temp/humidity/vpd/lux/leaf_temp/moisture) | Email; bad value discarded, previous retained; clears on next clean reading |
| `:stuck_moisture` | Moisture unchanged >=2% for >6h while not watering | Email; clears when reading changes |

Routing is configurable per type in Settings → Alert Routing.

---

## Database (SQLite — `priv/nursery_hub.db`)

Tables:
- `sensor_readings` — every reading from every zone (site_id, zone_id, timestamps, all sensor values)
- `watering_events` — open/close pairs with trigger, duration_ms, moisture_before, moisture_after, moisture_rise, dripper_fault, dripper_baseline
- `alert_logs` — all alerts with resolved_at (null if still active)
- `settings` — single-row key/value store for email/SMS/routing/OTA config

---

## MQTT topics

| Topic | Direction | Purpose |
|---|---|---|
| `nursery/{site_id}/{zone_id}/data` | ESP32 → server | Sensor readings (JSON, every 30s) |
| `nursery/{site_id}/{zone_id}/cmd` | Server → ESP32 | Commands (`{"cmd":"water"}`, `{"cmd":"stop"}`) |
| `nursery/{site_id}/{zone_id}/ota` | Server → ESP32 | OTA update trigger |

---

## ESP32 firmware (`esp32_firmware/ESP32_Plant_Monitor_v4.ino`)

Key config at top of file:
```cpp
#define NUM_ZONES 4               // 1–4 per ESP32
#define SITE_ID   "northcote"    // unique name
#define TEST_MODE true            // false = live, true = no WiFi/MQTT

const char* ZONE_IDS[]    = { "zone_a", "zone_b", "zone_c", "zone_d" };
const int MOISTURE_PINS[] = { 32, 33, 34, 35 };
const int RELAY_PINS[]    = { 25, 26, 13, 14 };
```

Shared sensors: DHT22 (GPIO27), BH1750 + MLX90614 (I2C GPIO21/22), MicroSD (SPI GPIO5/23/19/18).

Behaviour:
- Reads all sensors every 30s, publishes JSON to MQTT
- Runs local auto-watering logic autonomously even if server unreachable (`local` mode)
- Valve safety timeout: forces close after 60s regardless of server commands
- Dripper learning: tracks flow per zone, flags `dripper_fault` if expected rise doesn't happen after 3 baseline events
- OTA: checks server on boot, flashes if version mismatch, bootloader auto-rollback on crash

---

## Config (`config/config.exs`)

Key settings to change before going live:
- `dashboard_auth` — username/password for dashboard login
- `settings_password` — password required to save settings in the UI
- `mqtt_username` / `mqtt_password` — must match Mosquitto password file and ESP32 firmware
- `secret_key_base` — regenerate with `mix phx.gen.secret`
- `zone_timeout_minutes` — default 30
- `valve_max_open_seconds` — default 120

---

## What's planned next

- Python ML layer for predictive watering and cross-site anomaly detection
