# NurseryHub — Server App Setup Guide

## What this is

The central server application that:
- Receives sensor data from all ESP32s across all nursery sites
- Runs one independent BEAM process per zone — isolated, self-healing
- Detects offline zones, stuck valves, sensor failures
- Alerts you when something needs attention
- Sends commands back to ESP32s (e.g. manual water trigger)
- Serves the live web dashboard at http://localhost:4000
- Logs every reading to a local SQLite database

---

## What you need to install first

### 1. Elixir
Download from https://elixir-lang.org/install.html
Choose the Windows installer. This also installs Erlang/BEAM automatically.

### 2. MQTT Broker (Mosquitto)
The broker is the message hub between your ESP32s and this app.
Download from https://mosquitto.org/download/
Install and run as a Windows service — it starts automatically on boot.

---

## Getting started

Open a terminal in the nursery_hub folder, then run:

```bash
# Download dependencies + create the database
mix setup

# Start the application
mix run --no-halt
```

Then open a browser and go to: **http://localhost:4000**

You should see:
```
NurseryHub starting — MQTT: localhost:1883
MQTT connected to localhost:1883
```

When an ESP32 comes online, each of its zones appears automatically:
```
New zone discovered: site_01/zone_a — starting process
New zone discovered: site_01/zone_b — starting process
New zone discovered: site_01/zone_c — starting process
New zone discovered: site_01/zone_d — starting process
```

No configuration needed on the server for new ESP32s or zones —
they register themselves the first time they send data.

---

## Configuration

Edit `config/config.exs` to change:
- MQTT broker address (if running on a different machine)
- How long before a silent zone triggers an alert (default: 30 min)
- Valve safety timeout (default: 120 seconds)

---

## Sending commands to a zone

From an Elixir shell (`iex -S mix`):

```elixir
# Manually trigger watering for 20 seconds
NurseryHub.ZoneServer.send_command("site_01", "zone_a", %{cmd: "water", duration: 20})

# Stop watering immediately
NurseryHub.ZoneServer.send_command("site_01", "zone_a", %{cmd: "stop"})

# Reboot the ESP32 that owns this zone
# Note: reboots the physical ESP32, so ALL zones on that board will restart
NurseryHub.ZoneServer.send_command("site_01", "zone_a", %{cmd: "reboot"})

# See the current state of a zone
NurseryHub.ZoneServer.state("site_01", "zone_a")

# List all active zones (across all sites)
NurseryHub.ZoneSupervisor.all_zones()

# List all zones at one site
NurseryHub.ZoneSupervisor.zones_for_site("site_01")
```

---

## Logging

- **Primary log**: every sensor reading from every zone is saved to
  `priv/nursery_hub.db` (SQLite — no separate database server needed)
- **Backup**: SD card on each ESP32 keeps logging locally if WiFi drops
- The dashboard History view reads from the SQLite database
- Open `nursery_hub.db` with **DB Browser for SQLite** (free) to query
  or export any data to Excel

---

## File structure

```
nursery_hub/
├── mix.exs                              Project config + dependencies
├── config/config.exs                    Settings (MQTT host, timeouts, port)
├── priv/
│   ├── nursery_hub.db                   SQLite database (auto-created on first run)
│   └── repo/migrations/                 Database table definitions
└── lib/
    ├── nursery_hub/
    │   ├── application.ex               Starts everything in the right order
    │   ├── repo.ex                      Database connection
    │   ├── sensor_reading.ex            Database schema + queries
    │   ├── mqtt_connector.ex            Connects to MQTT broker
    │   ├── mqtt_handler.ex              Routes incoming messages to zone processes
    │   ├── zone_supervisor.ex           Manages zone processes (start/restart/lookup)
    │   ├── zone_server.ex               The brain for each zone — state + watchdogs
    │   └── alerting.ex                  Alert handling (currently logs to console)
    └── nursery_hub_web/
        ├── endpoint.ex                  Web server
        ├── router.ex                    URL routes
        └── live/
            ├── dashboard_live.ex        Overview — all sites and zones
            └── zone_live.ex             Detail — history charts for one zone
```

---

## How zones and ESP32s relate

One ESP32 can control up to 4 zones. The server doesn't need to know this —
it tracks each zone independently regardless of how many share an ESP32.

One practical implication: the `reboot` command restarts the physical ESP32,
so all zones on that board will briefly go offline together. This is expected
behaviour and Elixir will detect and alert if they don't come back.

---

## Security

Before connecting any remote sites, complete the steps in **SECURITY_SETUP.md**.

Quick summary of what needs to be done:

1. Create Mosquitto password file (2 users: `nursery_hub` for the server, `esp32_device` for ESP32s)
2. Copy `mosquitto_config\mosquitto.conf` to `C:\Program Files\mosquitto\mosquitto.conf`
3. Update `mqtt_password` in `config/config.exs`
4. Update `MQTT_PASS` in ESP32 firmware
5. Change `dashboard_auth` password in `config/config.exs`
6. Run `mix phx.gen.secret` and update `secret_key_base` in `config/config.exs`
7. Set up WireGuard VPN for remote sites (see SECURITY_SETUP.md)

The dashboard already requires a login — username and password are set in `config/config.exs`.

---

## Next steps (future)

- Add email/SMS alerts in `alerting.ex` (Twilio for SMS, SMTP for email)
- Add the Python ML layer for predictive watering and anomaly detection
- Add NTP time sync to ESP32 for real wall-clock timestamps in the database
