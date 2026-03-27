# NurseryHub — System Architecture

## What the system does

Monitors soil moisture, air temperature, humidity, light (lux), leaf temperature, and vapour pressure deficit (VPD) across multiple nursery sites. Automatically waters plants via drip/feed solenoid valves. Alerts on faults, sensor failures, critically dry zones, and environmental risks (freeze, heat). Logs all data centrally for review and future ML analysis.

---

## Current topology

```
NURSERY SITES                          CENTRAL SERVER (PC or RPi)
─────────────────────────────────      ──────────────────────────────────────

ESP32 (site_01, zones A–D)             Mosquitto MQTT Broker
│  reads sensors every 30s             │  receives all data from all ESP32s
│  controls solenoid valves            │
└──── WiFi/4G ────────────────────────▶│
                                       │
ESP32 (site_01, zones E–H)             Elixir NurseryHub app
└──── WiFi/4G ────────────────────────▶│  one BEAM process per zone
                                       │  watchdogs, alerts, degraded modes
ESP32 (site_02, zones A–D)             │
└──── WiFi/4G ────────────────────────▶│         │              │
                                       │    SQLite DB      Dashboard
(up to 20 sites)                       │   logs every     :4000 in browser
                                       │    reading       live updates
```

**Limitations of current topology identified by FMEA:**
- Loss of 4G connection at any site = loss of all monitoring, alerting, and data for that site (RPN 280)
- Central server is a single point of failure for the entire system (RPN 192)
- No local data buffering — readings during comms outages are permanently lost
- No local alerting — critical events (flooding, critically dry zones) go unreported during outages

---

## Planned topology — Nerves Pi at each site

```
NURSERY SITES                          CENTRAL SERVER (PC, RPi, or VPS)
─────────────────────────────────      ──────────────────────────────────────

ESP32 (zones A–D)  ─── local WiFi ──▶  Nerves Pi (site hub)
ESP32 (zones E–H)  ─── local WiFi ──▶  │  runs local Mosquitto broker
                                        │  runs subset of NurseryHub Elixir app
                                        │  local SQLite — buffers all readings
                                        │  local alerting (email/GSM)
                                        │  serves ESP32 OTA firmware locally
                                        │  [4G WAN] ──────────────────────────▶ Central server
                                                                                 │  aggregates all sites
                                                                                 │  full dashboard
                                                                                 │  ML layer
                                                                                 │  cross-site analysis
```

### Why Nerves and not a generic Linux device

- Nerves runs the Elixir/OTP app natively on bare hardware — no OS overhead, no Linux to maintain, no package manager drift
- Immutable firmware — the device either boots correctly or rolls back automatically; no "partially updated" state
- NervesHub provides OTA firmware management for the Pi with device identity, delta updates, and remote console access
- The same Elixir codebase runs on both the central server and the Nerves device — minimal duplication

### What the Nerves Pi adds at each site

| Capability | Without Nerves Pi | With Nerves Pi |
|---|---|---|
| Continues monitoring when 4G lost | No (ESP32 local fallback only) | Yes (full Elixir app runs locally) |
| Preserves data during outages | No (data lost) | Yes (local SQLite, syncs on reconnect) |
| Local alerting during outages | No | Yes (email relay or GSM modem) |
| ESP32 OTA over 4G | Yes (from central server) | Yes (served locally — faster, more reliable) |
| Cross-zone coordination on-site | No | Yes |
| BEAM fault isolation | Per zone, central only | Per zone, on-site + central |

### Cost per site

| Component | Cost |
|---|---|
| Raspberry Pi Zero 2W (Nerves device) | ~$20 |
| Additional SD card | ~$10 |
| ESP32s (unchanged) | No change |

One Pi per site regardless of zone count. For a site with 8 zones (2 ESP32s) this adds ~$30 to the per-site cost.

---

## Hardware topology — per site

```
  4G LTE Router (GL.iNet or TP-Link — site-owned SIM)
  │
  ├── Nerves Pi (site hub) — local WiFi AP or wired
  │
  ├── ESP32 #1 (zones A–D)
  │   ├── DHT22         — air temp + humidity (shared, GPIO27)
  │   ├── BH1750        — light level (I2C, GPIO21/22)
  │   ├── MLX90614 BAA  — leaf IR temp (I2C, GPIO21/22)
  │   ├── MicroSD       — local backup (SPI, GPIO5/23/19/18)
  │   ├── Zone A        — moisture sensor (GPIO32) + solenoid via relay (GPIO25)
  │   ├── Zone B        — moisture sensor (GPIO33) + solenoid via relay (GPIO26)
  │   ├── Zone C        — moisture sensor (GPIO34) + solenoid via relay (GPIO13)
  │   └── Zone D        — moisture sensor (GPIO35) + solenoid via relay (GPIO14)
  │
  └── ESP32 #2 (zones E–H)
      └── (same layout)
```

**Power chain (per ESP32 enclosure):**
```
  Input supply (12V DC)
    → DC-DC buck converter (LM2596 or equivalent → 5V)
    → ESP32 VIN + relay module VCC + solenoid valves
    → ESP32 3.3V reg → sensors via AO3401 MOSFETs (reverse polarity protection)
```

### Pending decisions — to be confirmed on next site visit

> These items are deferred until site conditions are re-checked. Do not proceed with hardware procurement or deployment until resolved.

| Item | What to check | Why |
|---|---|---|
| Supply voltage | Measure VAC at proposed installation point at different times of day | Confirm 205–275VAC range and decide on PSU spec and whether AVR is needed |
| Hard water | Test water hardness (TDS meter or lab test) at irrigation supply point | Confirm severity; determine whether inline softener or descaler is required or whether filter + flush schedule is sufficient |
| Water pressure | Measure static and dynamic pressure at supply | Confirm adequate pressure for drip system; size pressure regulator |
| SIM data plan | Check coverage at site for 4G | Confirm carrier and data allowance before ordering SIM |

---

### Site-specific electrical note

The confirmed supply voltage at the primary deployment site varies **205–275VAC** during the day. This exceeds the input range of standard consumer adapters and most 90–264VAC wide-input PSUs.

**Mandatory for this site:**
- Use industrial PSU rated for ≥85–305VAC input (e.g. Meanwell HDR-15-12 DIN rail)
- Add Type 2 SPD (surge protection device) on mains input before the PSU
- Do not use consumer wall adapters or standard 240VAC-only adapters at this site
- Verify PSU output voltage at both 205V and 275V input during commissioning

This is the highest-risk item in the FMEA (RPN 512) and must be resolved before hardware deployment.

### Hard water note

The primary site has confirmed hard water (high calcium and mineral content). This directly affects:
- Drip emitters — calcium scale progressively blocks flow (use pressure-compensating self-flushing emitters)
- Solenoid valve seats — scale buildup causes valve failure (plan for 12-monthly replacement cycle)
- Moisture sensors — calcium coating on capacitive plates causes reading drift (clean every 3 months; recalibrate)
- Pipework — schedule periodic citric acid flush of all drip lines

Install inline sediment filter + descaler on main supply before the irrigation system.

---

## Component redundancy — planned

The FMEA identified two components where redundancy significantly reduces risk:

| Component | Current | Planned | Why |
|---|---|---|---|
| Soil moisture sensor | 1 per zone | 2 per zone | Calibration drift (RPN 324) and stuck readings (RPN 320) are the highest hardware risks. Cross-comparison between two sensors drops Detection from 9→2 |
| DHT22 (air temp/humidity) | 1 per ESP32 | 2 per ESP32 | Drift affects all zones on the board (RPN 270). Cross-comparison drops Detection from 9→2 |

Both components cost <$5 each. Designing the PCB with dual sensor footprints now avoids rewiring later.

A secondary moisture sensor per zone also enables validation of the dripper_fault mechanism — instead of waiting for a post-drip moisture rise, cross-comparison gives immediate detection of a stuck/drifted sensor.

---

## Alert types

| Alert | Trigger | Delivery |
|---|---|---|
| `zone_offline` | No data for >30 min | Email |
| `valve_stuck_open` | Valve open >120s | Email + SMS; stop command sent |
| `sensor_fault` | ESP32 reports sensor hardware failure | Email |
| `critical_dry` | Moisture ≤10% | Email + SMS |
| `sensor_out_of_bounds` | Reading outside physical plausibility bounds | Email; bad reading discarded |
| `stuck_moisture` | Moisture unchanged ≥2% for >6h while not watering | Email |
| `freeze_risk` | Air temp ≤2°C | Email + SMS; stop command sent; watering suspended until >4°C |

---

## OTA firmware updates

### ESP32 firmware

1. Increment `FIRMWARE_VERSION` in firmware
2. Arduino IDE → Sketch → Export Compiled Binary
3. Copy `.bin` to `priv/static/firmware/esp32_plant_monitor.bin`
4. Settings → OTA Firmware → update version → Save & Deploy
5. ESP32s check on next boot and flash automatically
6. ESP32 bootloader auto-rollback if new firmware crashes

With Nerves Pi: firmware is served locally from the Pi — no dependency on 4G for OTA.

### Nerves Pi firmware (planned)

Managed via [NervesHub](https://nerves-hub.org):
- Device identity — firmware targets a specific device, not broadcast
- Delta updates — sends only changed blocks (important on 4G SIM data budget)
- Remote console access over HTTPS
- Automatic rollback on boot failure
- NervesHub.io free tier covers up to 5 devices — adequate for initial deployment

---

## Planned ML layer

A Python service (future) that consumes the NurseryHub SQLite data and provides:
- **Predictive watering** — model optimal watering timing based on VPD, light, temperature trends, and historical moisture recovery rates
- **Cross-site anomaly detection** — flag zones behaving anomalously relative to similar zones at other sites
- **Sensor drift detection** — statistical detection of calibration drift before it enters the plausible range
- **Dripper health** — model expected moisture rise per watering event and alert on systematic degradation (early blockage detection)

The ML layer is additive — the core system operates without it. It reads the existing SQLite schema and publishes recommendations back via MQTT or a simple HTTP endpoint.

---

## Security — before going live

| Step | Where |
|---|---|
| Set MQTT password | Mosquitto password file + `config/config.exs` |
| Change dashboard login | `config/config.exs` → `dashboard_auth` |
| Set settings page password | `config/config.exs` → `settings_password` |
| Regenerate secret_key_base | `mix phx.gen.secret` |
| Set up WireGuard VPN | Between each 4G router and central server |

Full details: `SECURITY_SETUP.md`
