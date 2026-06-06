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
| `nursery_hub/data_sync.ex` | GenServer — site Pi only; polls central /api/sync/health every 60s; pushes buffered readings in batches of 100; exponential backoff on failure; inactive (`:ignore`) on central server. Drives the WAN up/down indicator shown in Topology. |
| `nursery_hub/alert_log.ex` | Ecto schema + queries for the alert log table |
| `nursery_hub/sensor_reading.ex` | Ecto schema + insert for sensor readings |
| `nursery_hub/device_assignment.ex` | Ecto schema — maps chip_id (MAC-derived hardware ID) to asset tags (node_tag + sensor_tags JSON); `next_tag/1` and `next_tags/2` suggest next sequential numbers |
| `nursery_hub/watering_event.ex` | Ecto schema — open/close watering events, moisture_before/after, duration_ms, trigger, dripper_fault |
| `nursery_hub/consumption.ex` | Water consumption tracking |
| `nursery_hub/settings.ex` | Loads/saves settings from SQLite (email, SMS, alert routing, OTA version) |
| `nursery_hub/repo.ex` | Ecto repo (SQLite) |

### LiveView pages (`lib/nursery_hub_web/live/`)

| File | URL | What it does |
|---|---|---|
| `dashboard_live.ex` | `/` | Main table — all zones, live updates via PubSub, filters (site/zone/status/mode/sensor ranges), CSV download, Water/Stop/History actions |
| `topology_live.ex` | `/topology` | Visual equipment map — central server → sites → ESP32 nodes → shared sensor pills (DHT/LUX/IR with asset tags + ok/fault dots) → zone cards with moisture probe tags. Unregistered devices show chip_id in orange with inline Register form; form pre-fills next sequential tag numbers. Authoritative equipment register. |
| `zone_live.ex` | `/zone/:site/:zone` | Per-zone history — moisture + VPD charts, date range picker, watering events table, CSV export |
| `logs_live.ex` | `/logs` | Alert log — all/active/resolved filter, colour-coded alert type badges |
| `settings_live.ex` | `/settings` | Email (SMTP), SMS (Twilio), alert routing per alert type, OTA firmware version, test email/SMS buttons |

### Controllers

| File | Role |
|---|---|
| `csv_controller.ex` | Serves CSV exports for dashboard and zone history |
| `firmware_controller.ex` | Serves OTA firmware binary to ESP32s |
| `sync_controller.ex` | `GET /api/sync/health` (WAN probe) + `POST /api/sync/readings` (batch insert, deduplicates by site/zone/inserted_at) |

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
  chip_id,            # Raw hardware ID from ESP32 MAC e.g. "A4CF12345678" — immutable
  node_id,            # Resolved asset tag e.g. "ESP-001" (from DeviceAssignment) or chip_id if unregistered
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
  sensor_ids: %{},    # resolved asset tags: %{"moisture"=>"MST-001","dht"=>"DHT-001",...}
  alerts: [],         # active alert atoms: :offline, :valve_stuck, :sensor_fault, :critical_dry
  faulted_sensors: [] # debounce — only fires alert when fault set changes
}
```

Identity resolution: when a message arrives with `chip_id`, ZoneServer looks up DeviceAssignment and caches the resolved node_id + sensor_ids. Re-resolution is triggered by `ZoneServer.reassign/2` after a Topology page save.

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
- `sensor_readings` — every reading from every zone (site_id, zone_id, node_id, timestamps, all sensor values)
- `watering_events` — open/close pairs with trigger, duration_ms, moisture_before, moisture_after, moisture_rise, dripper_fault, dripper_baseline
- `alert_logs` — all alerts with resolved_at (null if still active)
- `settings` — single-row key/value store for email/SMS/routing/OTA config
- `device_assignments` — maps chip_id → node_tag + sensor_tags JSON (e.g. `{"dht":"DHT-001","lux":"LUX-001","moisture_0":"MST-001",...}`)

---

## MQTT topics

| Topic | Direction | Purpose |
|---|---|---|
| `nursery/{site_id}/{zone_id}/data` | ESP32 → server | Sensor readings (JSON, every 30s) |
| `nursery/{site_id}/{zone_id}/cmd` | Server → ESP32 | Commands (`{"cmd":"water"}`, `{"cmd":"stop"}`) |
| `nursery/{site_id}/{zone_id}/ota` | Server → ESP32 | OTA update trigger |

---

## ESP32 firmware

### Sketches

| Sketch | Folder | Purpose |
|---|---|---|
| `ESP32_Plant_Monitor_v5.ino` | `esp32_firmware/ESP32_Plant_Monitor_v5/` | Main firmware — sensor reads, MQTT, auto-watering, OTA |
| `Moisture_Calibration.ino` | `esp32_firmware/Moisture_Calibration/` | Interactive dry/wet calibration — outputs `MOISTURE_DRY` / `MOISTURE_WET` values to paste into main sketch |
| `Cable_Tester.ino` | `esp32_firmware/Cable_Tester/` | EOL loopback tester — continuity + reverse-direction diode protection test per cable type |
| `Sensor_Test.ino` | `esp32_firmware/Sensor_Test/` | Reads all sensors independently, no watering logic — for hardware verification |

### Main firmware (`esp32_firmware/ESP32_Plant_Monitor_v5/`)

Key config at top of file — only `SITE_ID` and hardware pin assignments need changing per device. **No NODE_ID or sensor tag defines** — asset tags are assigned server-side through the Topology page.

```cpp
#define NUM_ZONES 4               // 1–4 per ESP32
#define SITE_ID   "northcote"    // unique name
#define TEST_MODE true            // false = live, true = no WiFi/MQTT

const char* ZONE_IDS[]    = { "zone_a", "zone_b", "zone_c", "zone_d" };
const int MOISTURE_PINS[] = { 32, 33, 34, 35 };
const int RELAY_PINS[]    = { 25, 26, 13, 14 };
```

Every payload includes `chip_id` (12-char hex from `ESP.getEfuseMac()`) and `zone_index` (0–3). The server resolves these to human-readable asset tags via DeviceAssignment.

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

## Nerves Pi — site hub (Phase 2)

Application code is complete and runs on the Pi. Firmware build is pending physical hardware.

**Expected operation:**
- ESP32s connect to Mosquitto running on the Pi (not directly to central)
- Pi runs full NurseryHub app locally — same ZoneServer, watchdogs, alerting
- DataSync pushes to central in near real-time when WAN is up
- WAN down: Pi buffers locally, local alerts still fire, central shows "WAN down" in topology
- WAN restore: DataSync pushes all buffered readings, no data gap in history charts

**What's done:**
- DataSync, ZoneServer, Alerting, SyncController — all run on the Pi
- `config/nerves.exs` — site hub config (SITE_ID, CENTRAL_URL, MQTT, SQLite path)
- `config/target.exs` — Nerves entry point (imports nerves.exs when MIX_TARGET is set)
- `mix.exs` — Nerves deps added (`nerves`, `nerves_system_rpi0_2`, `nerves_hub_link`),
  guarded by `targets: [:rpi0_2]` so they're ignored in normal builds
- `config/nerves.exs` — NervesHub config with full setup instructions in comments

**What's pending (hardware required):**
- NervesHub account + product setup at nerves-hub.org
- Generate firmware signing key: `mix nerves_hub.key pair_generate signing-key`
- First flash: `MIX_TARGET=rpi0_2 mix nerves_hub.device create --identifier HUB-001`
- `mix firmware && mix burn`

**NervesHub OTA workflow (after first flash):**
```
mix firmware                                         # build
mix nerves_hub.firmware publish --product nursery-hub-pi  # upload to NervesHub
mix nerves_hub.deployment update [name] --firmware [uuid] # push to fleet
# Pi downloads + applies on next boot, auto-rolls back if boot fails
```

When Pi is deployed, ESP32 firmware only needs `MQTT_HOST` and OTA URLs updated to Pi's local IP.

---

## What's planned next

- Python ML layer for predictive watering and cross-site anomaly detection
