# NurseryHub — System Overview & Installation Guide

---

## What the system does

Monitors soil moisture, temperature, humidity, light, and VPD across multiple
nursery sites. Automatically waters plants via drip/feed solenoid valves.
Alerts you when something goes wrong. Logs all data centrally for review.

---

## Software topology

How the software components communicate with each other.

```
  NURSERY SITES                        CENTRAL SERVER (your PC or RPi)
  ─────────────────────────────────    ──────────────────────────────────────

  ESP32 (site_01, zones A–D)           Mosquitto MQTT Broker
  │  reads sensors every 30s           │  message hub — receives all data
  │  controls valves                   │  from all ESP32s simultaneously
  └──── WiFi/4G ──────────────────────▶│
                                       │
  ESP32 (site_01, zones E–H)           Elixir NurseryHub app
  └──── WiFi/4G ──────────────────────▶│  subscribes to all MQTT topics
                                       │  one BEAM process per zone
  ESP32 (site_02, zones A–D)           │  watchdogs, alerts, degraded modes
  └──── WiFi/4G ──────────────────────▶│
                                       │         │              │
  (up to 20 sites)                     │    SQLite DB      Dashboard
                                       │  logs every     :4000 in browser
                                       │   reading       live updates
```

**Data path for one reading:**

```
ESP32 reads sensors
  → bundles into JSON message
  → publishes to MQTT topic: nursery/site_01/zone_a/data
  → Mosquitto broker receives it
  → Elixir subscribes, receives message
  → routes to zone_a process
  → process updates state, checks for faults
  → saves reading to SQLite database
  → broadcasts update to dashboard via WebSocket
  → dashboard card updates in browser (no page refresh)
```

**Command path (e.g. manual water from dashboard):**

```
You click "Water now" in dashboard
  → dashboard sends event to Elixir
  → Elixir publishes to: nursery/site_01/zone_a/cmd
  → ESP32 subscribed to that topic receives it
  → opens valve for 15 seconds
```

---

## Hardware topology

How the physical hardware is arranged across sites.

```
YOUR OFFICE / HOME
┌──────────────────────────────────────────────┐
│  Central Server (PC or Raspberry Pi)         │
│  ├── Mosquitto MQTT broker                   │
│  └── NurseryHub Elixir app + dashboard       │
└──────────────────────┬───────────────────────┘
                       │ internet
          ┌────────────┴────────────┐
          │                         │
  SITE 01 (e.g. Northcote)   SITE 02 (e.g. Fitzroy)
  ┌──────────────────────┐    ┌──────────────────────┐
  │  4G LTE Router       │    │  4G LTE Router       │
  │  (your hardware,     │    │  (your hardware,     │
  │   your SIM)          │    │   your SIM)          │
  │  ├── ESP32 #1        │    │  ├── ESP32 #1        │
  │  │   zones A, B, C, D│    │  │   zones A, B, C, D│
  │  └── ESP32 #2        │    │  └── ...             │
  │      zones E, F, G, H│    └──────────────────────┘
  └──────────────────────┘

  (up to 20 sites, each independently connected)
```

**Per ESP32 — zone layout:**

```
  ESP32 #1 (site_01)
  ┌─────────────────────────────────────────────┐
  │  Shared sensors (one reading for all zones)  │
  │  ├── DHT11       air temp + humidity         │
  │  ├── BH1750      light level                 │
  │  └── MLX90614    leaf temperature (IR)       │
  │                                              │
  │  Zone A  ├── moisture sensor                 │
  │          └── solenoid valve                  │
  │  Zone B  ├── moisture sensor                 │
  │          └── solenoid valve                  │
  │  Zone C  ├── moisture sensor                 │
  │          └── solenoid valve                  │
  │  Zone D  ├── moisture sensor                 │
  │          └── solenoid valve                  │
  └─────────────────────────────────────────────┘
```

---

## Wiring topology

How to wire everything to the ESP32.

### Power overview

```
  ┌─────────────────────────────────────────────────────────┐
  │  Single input supply (e.g. 12V DC wall adapter or       │
  │  LiPo/lead-acid battery)                                │
  └────────────────────┬────────────────────────────────────┘
                       │ 12V in
              ┌────────▼────────┐
              │  DC-DC Buck     │  step down to 5V
              │  Converter      │  (e.g. LM2596 module)
              └────────┬────────┘
                       │ 5V out
          ┌────────────┼──────────────────────┐
          │            │                       │
     ESP32 VIN    Relay module VCC      Solenoid valves
     (powers      (5V coil relays)      (5V, via relay contacts)
      ESP32 +
      3.3V reg)

  ESP32 3.3V pin ──┬──── DHT22 VCC        (via 1N4007)
                   ├──── BH1750 VCC        (via 1N4007)
                   ├──── MLX90614 VCC      (via 1N4007)
                   ├──── SD module VCC     (via 1N4007)
                   └──── Moisture sensors  (via 1N4007)

  GND ─────────────────── relay GND ─── solenoid GND ─── DC-DC GND
```

**1N4007 reverse polarity protection:**
Place one diode in series on the VCC wire of each sensor.
Anode toward ESP32 3.3V, cathode toward sensor VCC pin.
Note: diodes drop ~0.7V, so sensors see ~2.6V — all sensors in this build
operate correctly at this voltage.

**DHT22 pull-up:**
Place a 10kΩ resistor between the DHT22 VCC pin and its data pin.

**Relay wiring (5V coil, 5V solenoid):**
```
  ESP32 GPIO ──▶ Relay IN pin   (control side — 3.3V signal is enough
                                 for most 5V relay modules)
                 Relay VCC ──── 5V (from DC-DC converter)
                 Relay GND ──── GND
                 Relay COM ──── 5V (from DC-DC converter)
                 Relay NO  ──── Solenoid valve +ve
                                Solenoid valve -ve ──── GND
```

When ESP32 pulls the relay pin HIGH, the relay closes, 5V flows through
the solenoid, and the valve opens. When LOW, valve closes.
Use a normally-closed (NC) solenoid — fails safe (water off) if power lost.

---

### ESP32 pin assignments

```
  ┌─────────────────────────────────────────────────────────────────┐
  │  SHARED SENSORS                                                  │
  │                                                                  │
  │  DHT22 (air temp/humidity)                                       │
  │    Signal  ──────────────────────────────────── GPIO27          │
  │    VCC     ──────── 1N4007 ──────────────────── 3.3V            │
  │    GND     ──────────────────────────────────── GND             │
  │    [10kΩ resistor between VCC and Signal pin]                    │
  │                                                                  │
  │  BH1750/GY-302 (light) + MLX90614/GY-906 BAA (leaf IR temp)     │
  │                                        ← share I2C bus          │
  │    SDA     ──────────────────────────────────── GPIO21          │
  │    SCL     ──────────────────────────────────── GPIO22          │
  │    VCC     ──────── 1N4007 ──────────────────── 3.3V            │
  │    GND     ──────────────────────────────────── GND             │
  │                                                                  │
  │  MicroSD card module (SPI)                                       │
  │    CS      ──────────────────────────────────── GPIO5           │
  │    MOSI    ──────────────────────────────────── GPIO23          │
  │    MISO    ──────────────────────────────────── GPIO19          │
  │    SCK     ──────────────────────────────────── GPIO18          │
  │    VCC     ──────── 1N4007 ──────────────────── 3.3V            │
  │    GND     ──────────────────────────────────── GND             │
  ├─────────────────────────────────────────────────────────────────┤
  │  PER ZONE (repeat for each zone)                                 │
  │                                                                  │
  │  Capacitive moisture sensor                                      │
  │    Zone A signal ────────────────────────────── GPIO32 (ADC1)   │
  │    Zone B signal ────────────────────────────── GPIO33 (ADC1)   │
  │    Zone C signal ────────────────────────────── GPIO34 (ADC1)   │
  │    Zone D signal ────────────────────────────── GPIO35 (ADC1)   │
  │    VCC (all)    ──── 1N4007 (one per sensor) ── 3.3V            │
  │    GND (all)    ─────────────────────────────── GND             │
  │                                                                  │
  │  4-channel relay module (5V coil)                                │
  │    IN1 (zone A) ─────────────────────────────── GPIO25          │
  │    IN2 (zone B) ─────────────────────────────── GPIO26          │
  │    IN3 (zone C) ─────────────────────────────── GPIO13          │
  │    IN4 (zone D) ─────────────────────────────── GPIO14          │
  │    VCC          ─────────────────────────────── 5V (DC-DC out)  │
  │    GND          ─────────────────────────────── GND             │
  └─────────────────────────────────────────────────────────────────┘
```

### I2C bus — two sensors, two wires

BH1750 and MLX90614 share the same two I2C wires (SDA + SCL).
They have different addresses so they don't conflict.
Wire both sensors in parallel to GPIO21 and GPIO22.

```
  GPIO21 (SDA) ──┬──── BH1750 SDA
                 └──── MLX90614 SDA

  GPIO22 (SCL) ──┬──── BH1750 SCL
                 └──── MLX90614 SCL
```

### Relay to solenoid valve

```
  ESP32 GPIO ──▶ Relay IN pin
                 Relay VCC ──── 5V (DC-DC converter out)
                 Relay GND ──── GND
                 Relay COM ──── 5V (DC-DC converter out)
                 Relay NO  ──── Solenoid valve +ve
                                Solenoid valve -ve ──── GND
```

When ESP32 pulls the relay pin HIGH, the relay closes, 5V flows through
the solenoid, and the valve opens. When LOW, valve closes.

---

## Hardware you need

### Per ESP32 (covers up to 4 zones)
| Item | Purpose | Approx cost |
|---|---|---|
| ESP32 dev board | Reads sensors, controls valves, sends data | ~$5–8 |
| DHT22 | Air temp + humidity (shared) | ~$3 |
| BH1750 (GY-302) | Light level (shared) | ~$3 |
| MLX90614 (GY-906) | Leaf temperature IR (shared) | ~$8 |
| MicroSD card module + card | Local backup logging | ~$3 |
| 4-channel relay module | Switches up to 4 solenoid valves | ~$4 |

### Per zone
| Item | Purpose | Approx cost |
|---|---|---|
| Capacitive soil moisture sensor | Soil wetness | ~$3 |
| 5V solenoid valve (normally closed) | Controls drip line | ~$8–12 |

### Per site
| Item | Purpose | Approx cost |
|---|---|---|
| DC-DC buck converter (e.g. LM2596) | Steps input voltage down to 5V | ~$2 |
| Input power supply (12V DC or battery) | Powers DC-DC converter | ~$10–15 |
| 4G LTE router (GL.iNet or TP-Link) | Site internet, owned by you | ~$60–100 once |
| IoT SIM card | Data (~50–100MB/month per site) | ~$5–15/month |

### Cost per zone
| Configuration | Hardware cost per zone |
|---|---|
| 1 zone per ESP32 | ~$38 |
| 4 zones per ESP32 | ~$19 |

### Central server (one only)
| Option | Cost | Notes |
|---|---|---|
| Your existing Windows PC | $0 | Fine to start with |
| Raspberry Pi 4 (4GB) | ~$55 | Always-on without a PC running |
| Raspberry Pi 5 (8GB) | ~$80 | Better for adding ML later |

---

## Installation — step by step

### STEP 1 — Install Arduino IDE and upload to ESP32

1. Download Arduino IDE from **arduino.cc**
2. Open Arduino IDE → Preferences → Additional Board URLs, add:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. Tools → Board Manager → search "esp32" → install **esp32 by Espressif**
4. Install these libraries via Tools → Manage Libraries:
   - `BH1750`
   - `Adafruit MLX90614`
   - `DHT sensor library` (by Adafruit)
   - `PubSubClient` (by Nick O'Leary)
   - `ArduinoJson` (by Benoit Blanchon)
5. Open `nursery_hub\esp32_firmware\ESP32_Plant_Monitor_v4.ino`
6. At the top, configure for your ESP32:
   ```cpp
   #define NUM_ZONES 4               // 1, 2, 3, or 4
   #define SITE_ID   "northcote"     // unique name for this site

   const char* ZONE_IDS[]    = { "zone_a", "zone_b", "zone_c", "zone_d" };
   const int MOISTURE_PINS[] = { 32, 33, 34, 35 };  // match your wiring
   const int RELAY_PINS[]    = { 25, 26, 13, 14 };  // match your wiring
   ```
7. Leave `#define TEST_MODE true` for initial testing
8. Plug ESP32 into USB → Tools → Board → ESP32 Dev Module
9. Tools → Port → select your COM port → Upload
10. Open Serial Monitor (115200 baud) — confirm sensor readings appear

**To go live on a site:** set `TEST_MODE false`, add WiFi + server IP, re-upload.

---

### STEP 2 — Install Mosquitto (MQTT broker)

1. Download from **mosquitto.org/download** → run installer
2. Open Command Prompt as Administrator:
   ```
   net start mosquitto
   ```
   Mosquitto now starts automatically on every boot.

Test it works — open two Command Prompt windows:
```
mosquitto_sub -t "test" -v        ← window 1
mosquitto_pub -t "test" -m "hello" ← window 2
```
"hello" should appear in window 1.

---

### STEP 3 — Install Elixir

1. Download from **elixir-lang.org/install.html** → Windows installer
   (also installs Erlang/BEAM automatically)
2. Verify in a new Command Prompt:
   ```
   elixir --version
   ```

---

### STEP 4 — Run NurseryHub

```bash
cd C:\Users\Ramon\Downloads\nursery_hub
mix setup          # first time only — installs deps + creates database
mix run --no-halt
```

Open browser → **http://localhost:4000**

Zone cards appear automatically as each ESP32 connects for the first time.

---

## Testing order (recommended)

1. **One ESP32, TEST_MODE true** — USB only, Serial Monitor open.
   Confirm all shared sensors read. Confirm each zone's moisture reads
   independently. Watch each valve open and close. Read the VPD decision log.

2. **Flip to mesh mode** — `TEST_MODE false`, start Elixir app, confirm all zones
   appear in dashboard and update every 30 seconds.

3. **Test shared sensor fault** — unplug DHT11. All zones on that ESP32 should
   drop to `no_vpd` mode (shared sensor affects all zones on the board).

4. **Test per-zone fault** — unplug one moisture sensor. Only that zone should
   drop to `no_moisture` mode. Other zones on the same ESP32 unaffected.

5. **Add more ESP32s** — they register in the dashboard automatically.

---

## Day-to-day use

- Leave `mix run --no-halt` running (or set as a Windows service)
- Dashboard at **http://localhost:4000**
- Click **History** on any zone for moisture + VPD charts
- Click **Water now** for a manual 15-second drip on any zone
- Database at `priv/nursery_hub.db` — open with **DB Browser for SQLite**
  (free download) to query or export to Excel

---

## Security

The system controls physical valves. These are the key protections in place
and the steps required before going live.

### What's implemented

| Protection | Where |
|---|---|
| MQTT username + password | `config/config.exs` + Mosquitto password file |
| Dashboard login (BasicAuth) | `router.ex` — prompts for username/password |
| Phoenix signed sessions | `config/config.exs` secret_key_base |
| Valve safety timeout | ESP32 firmware — forces close after 60s regardless |
| Valve stuck-open detection | Elixir zone_server — sends stop command + alerts |
| ESP32 local fallback | Firmware — continues watering if server unreachable |

### Before going live — required steps

1. **Set MQTT password** in Mosquitto password file (see SECURITY_SETUP.md)
2. **Update** `mqtt_password` in `config/config.exs` to match
3. **Update** `MQTT_PASS` in ESP32 firmware to match
4. **Change** `dashboard_auth` password in `config/config.exs`
5. **Regenerate** `secret_key_base` with `mix phx.gen.secret`

### Recommended (before connecting remote sites)

6. **Set up WireGuard VPN** between each site's 4G router and your server so MQTT traffic is encrypted end-to-end and the broker is never exposed to the open internet

Full instructions: **`SECURITY_SETUP.md`**

---

## What's coming next

- **Python ML layer** — predictive watering and cross-site anomaly detection
- **Email/SMS alerts** — add to `alerting.ex`

---

## File locations

| File | Location |
|---|---|
| ESP32 firmware | `nursery_hub\esp32_firmware\ESP32_Plant_Monitor_v4.ino` |
| Elixir server app | `nursery_hub\` |
| Database (auto-created on first run) | `nursery_hub\priv\nursery_hub.db` |
| This document | `nursery_hub\NurseryHub_Overview_and_Setup.md` |
| Server setup guide | `nursery_hub\SETUP.md` |
| Security setup guide | `nursery_hub\SECURITY_SETUP.md` |
| Mosquitto config template | `nursery_hub\mosquitto_config\mosquitto.conf` |
