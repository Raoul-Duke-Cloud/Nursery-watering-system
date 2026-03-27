# Nerves Pi — On-Site Hub Design Specification

## Purpose

One Nerves Pi device per site provides local intelligence that survives loss of WAN connectivity. The current system has zero resilience to 4G outages — data is lost, alerts are not delivered, and the operator has no visibility. The Nerves Pi closes that gap without changing the ESP32 hardware or the central server's role.

---

## Hardware selection

| Option | Cost | Why |
|---|---|---|
| **Raspberry Pi Zero 2W** | ~$20 | Sufficient CPU for Elixir/OTP; built-in WiFi; small form factor; lower power draw (~350mA at load) |
| Raspberry Pi 4 (1GB) | ~$55 | More headroom for ML preprocessing; overkill for v1 |

**Recommendation: Pi Zero 2W for v1.** Can be upgraded to Pi 4 if ML preprocessing moves on-site.

Power: 5V/2A micro-USB supply from the site 12V → 5V buck rail (same supply as ESP32). With the wide voltage variation at the primary site, the Pi PSU must also be rated for the full input range — use the same Meanwell DIN rail PSU recommendation from the architecture doc.

---

## Software topology on the Nerves Pi

```
ESP32s (all zones at site)
    │ WiFi — connects to Pi's local AP or site router
    │ MQTT publish → nursery/#
    ▼
Mosquitto (local)              ← runs on the Pi; ESP32s connect to Pi IP not cloud
    │
    ▼
NurseryHub Elixir app (local)  ← stripped-down version of the central app
    ├── ZoneServer processes (one per zone — same as central)
    ├── Alerting (email via Pi's own SMTP/relay; SMS via Twilio if WAN up)
    ├── Local SQLite (priv/nursery_hub_local.db)
    └── DataSync GenServer (pushes buffered data to central when WAN available)

    [WAN available] ──────────────────────────────────────────────────────▶ Central server
                                                                             aggregates all sites
                                                                             full dashboard
                                                                             ML layer
```

---

## Data flow

### Normal operation (WAN available)

1. ESP32 → publishes to local Mosquitto on Pi
2. Local Elixir app processes reading, writes to local SQLite
3. DataSync pushes reading to central server via HTTP or MQTT over WAN
4. Central server writes to its own SQLite — dashboard updates in real time

### WAN down

1. ESP32 → publishes to local Mosquitto on Pi (unchanged — ESP32 doesn't know WAN is down)
2. Local Elixir app processes reading, writes to local SQLite
3. DataSync detects WAN failure, buffers — does not drop data
4. Local alerting fires if zone goes offline, valve stuck, etc.
5. Operator can access local dashboard on site LAN: `http://[pi-ip]:4000`

### WAN restored

1. DataSync detects WAN up
2. Pushes all buffered readings and watering events to central server in order
3. Central server back-fills history — no gaps in charts

---

## Local app vs central app — differences

The Pi runs a subset of the NurseryHub codebase. The same `mix.exs` and Elixir modules are used — configuration determines behaviour.

| Feature | Central app | Local (Pi) app |
|---|---|---|
| Zone supervision | All zones, all sites | Only zones at this site |
| Dashboard | Full multi-site dashboard | Single-site view (optional — for on-site access) |
| Alerting | Full email + SMS | Email (local relay) + SMS (when WAN available) |
| Data storage | Primary SQLite | Local SQLite (buffer + local source of truth) |
| Data sync | N/A | DataSync pushes to central |
| ML layer | Yes (future) | No (reads from central) |
| OTA for ESP32s | Serves firmware over WAN | Serves firmware locally (no WAN dependency) |

The Pi app is configured via environment variables or a separate `config/nerves.exs` that sets:
- `role: :site` (vs `:central`)
- `central_url` (for DataSync push target)
- `site_id` (this Pi's site)
- SMTP relay credentials for local email

---

## DataSync module design

New module: `NurseryHub.DataSync`

```
State:
  - central_url       — HTTP endpoint on central server
  - wан_up            — boolean, checked every 60s
  - pending_count     — readings buffered but not yet pushed

Behaviour:
  - Polls central server health endpoint every 60s
  - On WAN restore: queries local SQLite for readings since last_synced_at
  - Pushes readings in batches of 100 to central server
  - Central server API accepts batch inserts and de-duplicates by (site_id, zone_id, timestamp)
  - Updates last_synced_at on each successful batch
  - On failure: exponential backoff, keeps buffering locally
```

Central server needs a new API endpoint:
```
POST /api/sync/readings
Body: [{ site_id, zone_id, timestamp, moisture, air_temp, ... }, ...]
Response: { accepted: N, duplicates: M }
```

This is the main new development work — the rest is configuration of existing code.

---

## NervesHub — OTA for the Pi

[NervesHub](https://nerves-hub.org) manages firmware updates to the Nerves Pi devices.

Setup steps:
1. Create account at nerves-hub.org (free tier: up to 5 devices)
2. Add `nerves_hub` dependency to `mix.exs`
3. Provision each Pi with a NervesHub certificate at first flash
4. On every `mix firmware` build, publish to NervesHub
5. Deploy to individual devices or device groups from the NervesHub dashboard

What NervesHub provides:
- **Device identity** — firmware targets a specific Pi, not broadcast
- **Delta updates** — sends only changed blocks (important on 4G SIM data budget)
- **Automatic rollback** — if new firmware fails to boot, Pi restores previous version
- **Remote IEx console** — SSH-over-HTTPS for live debugging without physical access
- **Deployment groups** — can roll out to one site first, verify, then push to others

### ESP32 OTA from the Pi (once Nerves Pi is deployed)

The existing ESP32 OTA mechanism (HTTP pull from the server) continues to work — the Pi replaces the central server as the OTA source for its site.

Update `OTA_VERSION_URL` and `OTA_FIRMWARE_URL` in ESP32 firmware to point to the Pi's local IP instead of the central server. Pi serves the same firmware binary via its local Phoenix endpoint.

This means ESP32 OTA works even when WAN is down — the Pi serves the binary locally.

---

## Hardware build — per site

Additional components needed per site (beyond existing ESP32 hardware):

| Item | Spec | Purpose |
|---|---|---|
| Raspberry Pi Zero 2W | With headers | Nerves device — site hub |
| MicroSD card | 16GB Class 10 | Nerves OS + app + local SQLite |
| Micro-USB power cable | Quality cable, short | Pi power from site PSU |
| Enclosure space | Existing or extended | Pi fits in same DIN rail enclosure or separate weatherproof box |

The Pi connects to the same local WiFi network as the ESP32s. The ESP32s are reconfigured to point MQTT at the Pi's local IP instead of the central server.

---

## Phased implementation plan

### Phase 1 — Local MQTT + data buffering
- Flash Nerves OS + NurseryHub app on Pi
- Configure ESP32s to connect to Pi's local Mosquitto
- DataSync buffers and pushes to central
- Local SQLite live

### Phase 2 — Local alerting
- Configure Pi with email relay (e.g. SMTP2GO API key, doesn't need persistent SMTP server)
- Alerting fires locally for zone offline, stuck valve, critical dry

### Phase 3 — Local dashboard
- Pi serves dashboard on local LAN (port 4000 on Pi's IP)
- Operator can check status on-site without internet

### Phase 4 — NervesHub
- Provision Pi with NervesHub certificates
- All future Pi firmware updates go via NervesHub (not manual re-flash)

### Phase 5 — ESP32 OTA from Pi
- Update ESP32 firmware to use Pi's IP for OTA checks
- OTA now works without WAN dependency

---

## First-time setup — flashing a Nerves Pi

This section covers the practical steps to build and flash the first Nerves Pi for a site. It assumes Elixir is already installed but no prior Nerves experience.

### Prerequisites

- Elixir 1.15+ installed
- Nerves bootstrap archive installed (one-time, installs Nerves build tooling):
  ```
  mix archive.install hex nerves_bootstrap
  ```
- A Raspberry Pi Zero 2W with headers
- A 16GB+ Class 10 microSD card
- A microSD card reader on your build machine

### Add Nerves dependencies to mix.exs

When ready to build Pi firmware, add these three deps to `mix.exs`:

```elixir
{:nerves, "~> 1.10", runtime: false},
{:nerves_hub_link, "~> 2.0"},                                          # OTA updates via NervesHub (Phase 4)
{:nerves_system_rpi0_2, "~> 1.0", runtime: false, targets: :rpi0_2},  # Pi Zero 2W system image
```

Also create a `config/target.exs` that imports the Nerves config:

```elixir
# config/target.exs
import_config "nerves.exs"
```

### Build the firmware

Set the target and site environment variables, then fetch deps and build:

```
export MIX_TARGET=rpi0_2
export SITE_ID=site_01
export CENTRAL_URL=http://your-central-server.com
export SYNC_API_KEY=your_shared_secret_here
mix deps.get
mix firmware
```

### Flash to SD card

```
mix burn
```

Nerves detects the SD card automatically and writes the firmware image. Safely eject the card after the command completes.

### First boot

- Insert the SD card into the Pi and power on
- Pi boots in approximately 15 seconds
- The app starts automatically — Mosquitto, the NurseryHub Elixir app, and the Phoenix dashboard all start on boot
- Dashboard is accessible at `http://[pi-ip]:4000` on the local network
- Logs are accessible via `ssh nerves.local` (default Nerves SSH)

### After first flash — reconfigure ESP32s

- Change `MQTT_HOST` in the ESP32 firmware from the central server IP to the Pi's local IP
- Change `OTA_VERSION_URL` and `OTA_FIRMWARE_URL` to point to the Pi (Phase 5)
- Re-flash all ESP32s at the site

### NervesHub provisioning (Phase 4)

Once NervesHub is set up, subsequent firmware updates do not require physical access to the Pi. Steps:

1. Create an account at nerves-hub.org
2. Add the `nerves_hub_link` dep to `mix.exs` (already listed above)
3. Run `mix nerves_hub.device create` to provision the Pi with a certificate on the first flash
4. All future updates: `mix firmware && mix nerves_hub.firmware publish && mix nerves_hub.deployment update`

---

## What this does to the FMEA

The two highest system-level failures (4G outage → data loss RPN 280, 4G outage → alerts lost RPN 280) both drop to ~28 and ~56 respectively. The central server single-point-of-failure (RPN 192) drops to ~72 because sites continue operating independently.

See `fmea/system_fmea.csv` `Nerves_Pi_Impact` and `Residual_RPN_with_Nerves` columns for the full breakdown.
